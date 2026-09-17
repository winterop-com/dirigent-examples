#!/usr/bin/env bash
# Run this example end to end and fail if anything about it has moved.
#
# An alert rule is a record the instance holds, so this one starts its own `dg dev`, writes
# the connection and the rule, fails a run on purpose, waits for the notification to be
# delivered, and stops the instance again. .dirigent/state survives between runs by design,
# so running this twice passes twice.
#
# Everything is done once per echo: the real service the document defaults to, and the
# stand-in in ../local-echo, which the base_url parameter points the document at and the sink
# connection is pointed at in turn. VERIFY_OFFLINE=1 leaves the online leg out, so the whole
# of this script passes with no network at all.
set -euo pipefail

cd "$(dirname "$0")"

uv sync --quiet

uv run dg validate pipelines/echo-alert.yaml

echo_server=../local-echo/echo_server.py
echo_pid=
dev_pid=
records=$(mktemp)
delivered=$(mktemp)
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
  rm -f "$records" "$delivered" "$log"
}
trap cleanup EXIT

# Any port nothing is listening on, so two verifications never collide and neither takes
# 3333 from a dg dev somebody is watching.
free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# The echoes to run against. The empty base is the document's own default, which is the real
# service; the other is the stand-in, started here when it is beside this repository. It is
# started with --record, so what a webhook was delivered can be read back out of a file --
# the run is over long before anything reaches the terminal.
bases=()
legs=
if [ -z "${VERIFY_OFFLINE:-}" ]; then
  bases+=("")
  legs="postman-echo.com"
fi
if [ -f "$echo_server" ]; then
  echo_port=$(free_port)
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

# --- the failure, without a server at all -------------------------------------------------
#
# The pipeline fails by design, so dg exits non-zero and the run record is what is read.
for base in "${bases[@]}"; do
  # Seeded empty, because an empty array is not something every bash expands under set -u.
  flags=(--json)
  if [ -n "$base" ]; then
    flags+=(-p "base_url=$base")
  fi

  uv run dg run --local pipelines/echo-alert.yaml "${flags[@]}" >"$records" || true
  jq -e -s '
    (map(select(.kind == "run" and has("exit_code"))) | last) as $run
    | ($run.steps | map({key: .step, value: .}) | from_entries) as $step
    | $run.message == "failed"
      and $step.ask.status == "succeeded"
      and $step.publish.status == "failed"
      and $step.note.status == "skipped"
      and ($run.failures | map(.error_class)) == ["rejected"]
  ' "$records" >/dev/null
done

# --- the instance ----------------------------------------------------------------------
#
# A connection carries a credential, so the instance will not store one until it has a key
# to seal it with. The key is minted once and kept, because an instance that changes its
# key cannot read what it stored under the old one -- and this script has to read, on its
# second run, the connection its first run stored.
if [ ! -f .secret-key ]; then
  (umask 077; uv run dg secret-key >.secret-key)
fi
export DIRIGENT_SECRET_KEY="$(cat .secret-key)"

port="${DG_PORT:-$(free_port)}"
export DG_URL="http://127.0.0.1:${port}"

uv run dg dev --port "$port" >"$log" 2>&1 &
dev_pid=$!

for _ in $(seq 60); do
  curl -sf "$DG_URL/health/ready" >/dev/null 2>&1 && break
  sleep 1
done
curl -sf "$DG_URL/health/ready" >/dev/null

# DG_URL beats the local profile, whose url is the default port; without it every command
# below would address an instance this script did not start. The token comes from dg dev's
# own admin: on an empty state that is the fixture dev / dirigent-dev, and dg auth login
# mints a token of its own from it.
DG_TOKEN=$(uv run dg auth login --username dev --password dirigent-dev --json \
  | jq -r 'select(.kind == "token.issued") | .token')
export DG_TOKEN
[ -n "$DG_TOKEN" ]

uv run dg apply

# --- the notifier, and the rule that uses it ----------------------------------------------
#
# The sink is an instance record, so pointing this example at another echo is a command
# rather than a flag. An instance refuses to delete a connection something still points at,
# which is why the rule goes first and is written again after: one leg, one sink.
#
# The rule carries no --throttle, which means no throttle: every failed run of echo-alert
# raises its own notification. One with a throttle would suppress the second leg's alert.
point_sink_at() {
  if uv run dg alerts rules list --json | jq -e -s 'any(.[]; .fields.code == "echo-failed")' >/dev/null; then
    uv run dg alerts rules delete echo-failed --json >/dev/null
  fi
  if uv run dg connection list --json | jq -e -s 'any(.[]; .fields.code == "echo-sink")' >/dev/null; then
    uv run dg connection delete echo-sink --json >/dev/null
  fi
  uv run dg connection create webhook echo-sink \
    --name "The alert sink" \
    --description "An echo's /post, which answers with whatever was POSTed to it." \
    --set url="$1" \
    --json >/dev/null
  uv run dg alerts rules create echo-failed \
    --name "Echo failures to the sink" \
    --event run_failed \
    --pipeline echo-alert \
    --notifier webhook \
    --connection echo-sink \
    --template '{{ pipeline.code }} run {{ run.status }}' \
    --body 'Run {{ run.id }} of {{ pipeline.code }} (version {{ pipeline.version }}) ended {{ run.status }} in {{ run.duration_ms | duration }}.' \
    --json >/dev/null
}

# --- the failure on the instance, and what it raises --------------------------------------
for base in "${bases[@]}"; do
  sink="${base:-https://postman-echo.com}/post"
  point_sink_at "$sink"

  flags=(--watch --json)
  if [ -n "$base" ]; then
    flags+=(-p "base_url=$base")
  fi

  uv run dg run echo-alert "${flags[@]}" >"$records" || true
  run=$(jq -rs '[.[] | select(.kind == "run") | .run_id] | first' "$records")
  jq -e -s '(map(select(.kind == "run")) | last).message == "failed"' "$records" >/dev/null

  # The notification goes on a queue, is leased by a worker, and is POSTed from there -- so
  # it is delivered a moment after the run settles rather than in the same breath.
  sent=""
  for _ in $(seq 30); do
    sent=$(uv run dg alerts queue --json \
      | jq -rs --arg run "$run" '[.[] | select(.fields.run_id == $run and .fields.status == "sent") | .fields.id] | (first // "")')
    [ -n "$sent" ] && break
    sleep 2
  done
  [ -n "$sent" ] || { echo "no notification was delivered for run ${run}" >&2; exit 1; }

  # Delivered where: the rule named a notifier, the notifier named a connection, and that
  # connection's url is the sink. `dg alerts queue` says sent once the POST answered 2xx.
  uv run dg alerts queue --json | jq -e -s --arg run "$run" '
    ([.[] | select(.fields.run_id == $run)] | first).fields as $n
    | $n.status == "sent"
      and $n.event == "run_failed"
      and $n.rule == "echo-failed"
      and $n.notifier == "webhook"
      and $n.connection == "echo-sink"
      and $n.attempt == 1
  ' >/dev/null

  uv run dg connection show echo-sink --json | jq -e -s --arg sink "$sink" '
    .[0].fields.config.url == $sink
  ' >/dev/null

  # What the sink received, from the echo's own record: sent is the instance's word for it,
  # and this is the delivery itself, body and all.
  if [ -n "$base" ]; then
    jq -e -s --arg run "$run" '
      map(select(.method == "POST" and .path == "/post" and .json.run_id == $run))
      | length == 1
      and (first | .json.event == "run_failed"
            and .json.pipeline == "echo-alert"
            and .json.subject == "echo-alert run failed"
            and (.json.body | startswith("Run \($run) of echo-alert")))
    ' "$delivered" >/dev/null
  fi

  echo "echo-alert: run ${run} failed, and its alert reached ${sink}"
done

echo "echo-alert: delivered against $legs"
