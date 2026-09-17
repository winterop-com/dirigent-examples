#!/usr/bin/env bash
# Run this example end to end and fail if anything about it has moved.
#
# A trigger only exists on an instance, so this one starts its own `dg dev`, applies the
# document, waits for the clock to fire, POSTs the webhook, and stops the instance again.
# .dirigent/state survives between runs by design, so running this twice passes twice.
#
# Every run this script starts itself is made once per echo: the real service the document
# defaults to, and the stand-in in ../local-echo, which the base_url parameter points the
# document at. VERIFY_OFFLINE=1 leaves the online leg out, so the whole of this script passes
# with no network at all -- with one thing asserted more narrowly, marked below.
set -euo pipefail

cd "$(dirname "$0")"

uv sync --quiet

uv run dg validate pipelines/echo-schedule.yaml

echo_server=../local-echo/echo_server.py
echo_pid=
dev_pid=
delivered=$(mktemp)
accepted=$(mktemp)
log=$(mktemp)

# Nothing this script started may still be listening when it returns: a dg dev that outlived
# its wrapper shares .dirigent/state with the next run, claims its steps and fails them.
port_clear() {
  local p="${1:-}" holding
  [ -n "$p" ] || return 0
  for _ in 1 2 3 4 5; do
    holding="$(lsof -nP -iTCP:"$p" -sTCP:LISTEN -t 2>/dev/null || true)"
    [ -n "$holding" ] || return 0
    sleep 0.4
  done
  kill -KILL $holding 2>/dev/null || true
}

# Whatever this script started is stopped by its pid, however this script ends -- never by
# name: a pattern matching `dg dev` matches the shell running this script too. The
# instance's wrapper has its children taken first: killing `uv run` alone leaves the dg dev
# under it on the port.
cleanup() {
  if [ -n "$dev_pid" ]; then
    pkill -TERM -P "$dev_pid" 2>/dev/null || true
    kill -TERM "$dev_pid" 2>/dev/null || true
    wait "$dev_pid" 2>/dev/null || true
  fi
  if [ -n "$echo_pid" ]; then
    kill -TERM "$echo_pid" 2>/dev/null || true
    wait "$echo_pid" 2>/dev/null || true
  fi
  port_clear "${port:-}"
  port_clear "${echo_port:-}"
  rm -f "$delivered" "$accepted" "$log"
}
trap cleanup EXIT

# Any port nothing is listening on, so two verifications never collide and neither takes
# 3333 from a dg dev somebody is watching.
free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# Every assertion goes through this: a bare `jq -e` exits 1 and says nothing, which is a
# verification that failed without telling anybody what it wanted or what it was handed.
expect() {
  local what=$1 records=$2
  shift 2
  if ! printf '%s\n' "$records" | jq -e -s "$@" >/dev/null; then
    echo "echo-schedule: expected $what" >&2
    echo "  the jq that refused: $*" >&2
    echo "  what came back:" >&2
    printf '%s\n' "$records" | sed 's/^/    /' >&2
    exit 1
  fi
}

# The echoes to run against. The empty base is the document's own default, which is the real
# service; the other is the stand-in, started here when it is beside this repository.
bases=()
legs=
online=false
if [ -z "${VERIFY_OFFLINE:-}" ]; then
  bases+=("")
  legs="postman-echo.com"
  online=true
fi
if [ -f "$echo_server" ]; then
  echo_port=$(free_port)
  # --record appends one JSON object per request, which is how the runs below are held to
  # having reached this echo rather than any other.
  python3 "$echo_server" --port "$echo_port" --record "$delivered" > /dev/null 2>&1 &
  echo_pid=$!
  if ! curl -fs --retry 60 --retry-delay 1 --retry-connrefused --retry-all-errors \
       "http://127.0.0.1:$echo_port/get" > /dev/null; then
    echo "local-echo on port $echo_port never answered /get" >&2
    exit 1
  fi
  bases+=("http://127.0.0.1:$echo_port")
  legs="${legs:+$legs and }local-echo"
fi
if [ "${#bases[@]}" -eq 0 ]; then
  echo "VERIFY_OFFLINE=1 needs $echo_server, and it is not there" >&2
  exit 1
fi

# The pipeline itself needs neither trigger, so prove it runs before anything is applied.
for base in "${bases[@]}"; do
  # Seeded empty, because an empty array is not something every bash expands under set -u.
  flags=(--json)
  if [ -n "$base" ]; then
    flags+=(-p "base_url=$base")
  fi
  records=$(uv run dg run --local pipelines/echo-schedule.yaml "${flags[@]}")
  expect "a local run against ${base:-postman-echo.com} to succeed" "$records" \
    '(map(select(.kind == "run" and has("exit_code"))) | last).message == "succeeded"'
done

# --- the instance ----------------------------------------------------------------------
port="${DG_PORT:-$(free_port)}"
export DG_URL="http://127.0.0.1:${port}"

uv run dg dev --port "$port" >"$log" 2>&1 &
dev_pid=$!

for _ in $(seq 60); do
  curl -sf "$DG_URL/health/ready" >/dev/null 2>&1 && break
  sleep 1
done
if ! curl -sf "$DG_URL/health/ready" >/dev/null; then
  echo "echo-schedule: the dg dev on $DG_URL never answered /health/ready within 60s" >&2
  echo "  its log:" >&2
  sed 's/^/    /' "$log" >&2
  exit 1
fi

# DG_URL beats the local profile, whose url is the default port; without it every command
# below would address an instance this script did not start. The token comes from dg dev's
# own admin: on an empty state that is the fixture dev / dirigent-dev, and dg auth login
# mints a token of its own from it.
DG_TOKEN=$(uv run dg auth login --username dev --password dirigent-dev --json \
  | jq -r 'select(.kind == "token.issued") | .token')
export DG_TOKEN
[ -n "$DG_TOKEN" ] || { echo "echo-schedule: dg auth login issued no token" >&2; exit 1; }

uv run dg apply

# A run somebody asks for takes the flag, so each echo gets one of those too.
for base in "${bases[@]}"; do
  flags=(--watch --json)
  if [ -n "$base" ]; then
    flags+=(-p "base_url=$base")
  fi
  records=$(uv run dg run echo-schedule "${flags[@]}")
  expect "a run against ${base:-postman-echo.com} to succeed" "$records" \
    '(map(select(.kind == "run")) | last).message == "succeeded"'
done

# --- the clock -------------------------------------------------------------------------
#
# Runs come back newest first, so the newest schedule-triggered run is the yardstick: wait
# until it is a different run than the one that was newest before the wait started. A count
# would saturate against the page size once enough verifications have run.
newest_scheduled() {
  uv run dg runs list --pipeline echo-schedule --limit 20 --json \
    | jq -rs '[.[] | select(.fields.triggered_by_kind == "schedule") | .fields.id] | (first // "")'
}

before=$(newest_scheduled)
landed=""
for left in $(seq 200 -5 5); do
  landed=$(newest_scheduled)
  [ -n "$landed" ] && [ "$landed" != "$before" ] && break
  echo "echo-schedule: no new scheduled run yet, ${left}s left of 200"
  sleep 5
done
[ -n "$landed" ] && [ "$landed" != "$before" ] || {
  echo "echo-schedule: expected the clock to start a run within 200s; the newest one is still ${before:-none}" >&2
  exit 1
}

# The schedule pins its own parameters over the pipeline's defaults, which is the whole
# reason a second schedule is a schedule rather than a second pipeline.
#
# Its status is only asserted on the online leg: base_url is not one of the parameters this
# schedule pins, so a run the clock starts reads the document's default and reaches the real
# service or nothing. What the clock is for -- that it fired, and with what -- holds either
# way.
expect "the clock's run to be pinned to oslo-blindern at 3.1" \
  "$(uv run dg runs show "$landed" --json)" --argjson online "$online" '
  .[0].fields.run as $run
  | $run.triggered_by_kind == "schedule"
    and $run.params.station == "oslo-blindern"
    and $run.params.reading == "3.1"
    and (($online | not) or $run.status == "succeeded")
'

echo "echo-schedule: the clock fired ${landed}, pinned to oslo-blindern"

# --- the webhook -----------------------------------------------------------------------
#
# An instance holds a hook's token and hands it back exactly once, when it is minted. There
# is no command that reads an existing one, so a script that has to POST rotates it and
# uses what rotation returns -- which also invalidates the token the last verification used.
hook=$(uv run dg webhook rotate-token echo-schedule upstream-reading --json | jq -r '.url')

# -f alone turns a refusal into an exit status and nothing else, so the body and the status
# line are kept and printed here rather than lost.
http=$(curl -s -o "$accepted" -w '%{http_code}' -X POST "$hook" \
  -H 'content-type: application/json' \
  -d '{"station": {"code": "tromso-langnes", "reading": "-6.8"}, "sender": "ignored"}')
if [ "${http#2}" = "$http" ]; then
  echo "echo-schedule: expected the hook to accept the POST, and it answered $http" >&2
  sed 's/^/    /' "$accepted" >&2
  exit 1
fi

expect "the hook to accept the payload and name the run it created" "$(cat "$accepted")" \
  '.[0].outcome == "accepted" and (.[0].run_id | length) > 0'
delivered_run=$(jq -r '.run_id' "$accepted")

# The run the POST created settles on its own a moment later, so wait for it -- 60s, counted
# down out loud, because a wait that prints nothing is a wait nobody can tell from a hang.
status=
for left in $(seq 60 -2 2); do
  status=$(uv run dg runs show "$delivered_run" --json | jq -rs '.[0].fields.run.status')
  case "$status" in succeeded | failed | completed_with_errors | cancelled) break ;; esac
  echo "echo-schedule: ${delivered_run} is ${status:-pending}, ${left}s left of 60"
  sleep 2
done
case "$status" in
  succeeded | failed | completed_with_errors | cancelled) ;;
  *)
    echo "echo-schedule: expected ${delivered_run} to settle within 60s, and it is ${status:-pending}" >&2
    exit 1
    ;;
esac

# The mapping put two payload fields onto two parameters and ignored the third thing the
# POST carried, because nothing in the mapping names it. The status is asserted like the
# schedule's, and for the same reason: a payload reaches only the parameters this mapping
# names, and base_url is not one of them.
expect "the payload to reach station and reading, and sender to reach nothing" \
  "$(uv run dg runs show "$delivered_run" --json)" --argjson online "$online" '
  .[0].fields.run as $run
  | $run.triggered_by_kind == "webhook"
    and $run.params.station == "tromso-langnes"
    and $run.params.reading == "-6.8"
    and ($run.params | has("sender") | not)
    and (($online | not) or $run.status == "succeeded")
'

echo "echo-schedule: the webhook started ${delivered_run}, mapped to tromso-langnes"

# What the local echo was asked, from its own record: the station of a run that was pointed
# at it. base_url reached the calls, not only the document.
if [ -s "$delivered" ]; then
  expect "the local echo to have been asked for bergen-florida at /get" "$(cat "$delivered")" '
    map(select(.method == "GET" and .path == "/get" and .args.station == "bergen-florida"))
    | length >= 1
  '
fi

echo "echo-schedule: both triggers fired, against $legs"
