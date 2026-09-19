#!/usr/bin/env bash
# Run all three documents end to end, against the two real play demos, and exit non-zero the
# moment anything this repository claims stops being true.
#
# Every assertion below reads records rather than rendered text: --json asks for the records
# even at a terminal, and a table is only a rendering of one.
#
# The two documents that talk to a system other than DHIS2 carry a base_url parameter, so
# each of them is run once against the real Postman Echo and once against the stand-in in
# ../local-echo when it is there. VERIFY_OFFLINE=1 leaves out the online echo leg and nothing
# else: both DHIS2 instances are on the internet and have no stand-in, so this script needs
# the network either way.
set -euo pipefail

cd "$(dirname "$0")"

SOURCE_URL=https://play.im.dhis2.org/stable-2-43-1
TARGET_URL=https://play.im.dhis2.org/stable-2-42-6
SCHEMAS=(org-unit-sync-source org-unit-sync-import org-unit-sync-verdict)

# Somewhere to keep the streams this script asserts on, removed on the way out.
WORK="$(mktemp -d)"

DEV_PID=""
ECHO_PID=""

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

cleanup() {
  # Stop whatever this script started, by the pid this script holds. Never by pattern: a
  # pattern matches this shell too. The instance's wrapper has its children taken first:
  # killing `uv run` alone leaves the dg dev under it on the port.
  for pid in "$DEV_PID" "$ECHO_PID"; do
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      if [ "$pid" = "$DEV_PID" ]; then
        pkill -TERM -P "$pid" 2>/dev/null || true
      fi
      kill -TERM "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  port_clear "${PORT:-}"
  port_clear "${ECHO_PORT:-}"
  rm -rf "$WORK"
}
trap cleanup EXIT

say() { printf '\n== %s\n' "$1"; }

free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# The last run record in a stream is how the run settled.
assert_run_succeeded() {
  jq -se --arg what "$2" '
    map(select(.kind == "run")) | last
    | if . == null then error("\($what): the stream carries no run record")
      elif .message == "succeeded" then true
      else error("\($what): the run settled \(.message)") end
  ' "$1" > /dev/null
}

# What a rehearsed sync has to be able to say for itself:
#
#   the gate passed organisation units, so the run had something to sync;
#   the request carried importMode=VALIDATE, which is the one parameter that decides whether
#     the target was written to -- read off the `mode` step's own output, which is the value
#     the request's query was built from;
#   the target's report came back OK, with nothing ignored and no conflict of any class.
assert_rehearsed() {
  jq -se --arg what "$2" --arg identifier "$3" '
    map(select(.kind == "run")) | last | .steps
    | (map(select(.step == "check")) | last | .output.value.organisationUnits) as $units
    | (map(select(.step == "mode")) | last | .output.value) as $mode
    | (map(select(.step == "report")) | last | .output.value) as $report
    | if ($units | length) < 1 then error("\($what): the gate passed no organisation units")
      elif $mode.importMode != "VALIDATE" then error("\($what): the request carried importMode=\($mode.importMode), which writes to the demo")
      elif $mode.identifier != $identifier then error("\($what): the request matched on \($mode.identifier) rather than \($identifier)")
      elif $report.status != "OK" then error("\($what): the target reported \($report.status): \($report.detail)")
      elif $report.refused != 0 then error("\($what): the target refused \($report.refused): \($report.detail)")
      elif $report.ignored != 0 then error("\($what): the target ignored \($report.ignored) of \($report.total) units")
      elif $report.total < 1 then error("\($what): the import carried nothing")
      else true end
  ' "$1" > /dev/null
}

# The outbound document has no import report: what it has is the receiver's own answer, which
# carries the batch back.
assert_delivered() {
  jq -se --arg what "$2" '
    map(select(.kind == "run")) | last | .steps
    | (map(select(.step == "check")) | last | .output.value.organisationUnits | length) as $units
    | (map(select(.step == "batch")) | last | .output.value) as $batch
    | (map(select(.step == "send")) | last | .output.body.json) as $echoed
    | if $units < 1 then error("\($what): the gate passed no organisation units")
      elif $batch.synced != $units then error("\($what): \($units) units gated, \($batch.synced) sent")
      elif $echoed != $batch then error("\($what): the receiver answered with something other than the batch")
      elif ($echoed.facilities[0] | has("parent_code") | not) then error("\($what): the records carry no parent_code")
      else true end
  ' "$1" > /dev/null
}

say "the project's own environment"
uv sync --quiet

say "every document, checked offline"
# No argument: the project's own documents, which is everything under pipelines/.
uv run dg validate --json > "$WORK/validate.ndjson"
jq -se '
  map(select(.kind == "validated")) | last
  | if .invalid == 0 then true else error("\(.invalid) document(s) refused") end
' "$WORK/validate.ndjson" > /dev/null

# The receivers the two outbound-ish documents are run against. The empty base is each
# document's own default, which is the real service.
ECHO_SERVER=../local-echo/echo_server.py
BASES=()
LEGS=
if [ -z "${VERIFY_OFFLINE:-}" ]; then
  BASES+=("")
  LEGS="postman-echo.com"
fi
if [ -f "$ECHO_SERVER" ]; then
  ECHO_PORT="$(free_port)"
  python3 "$ECHO_SERVER" --port "$ECHO_PORT" > /dev/null 2>&1 &
  ECHO_PID=$!
  if ! curl -fs --retry 60 --retry-delay 1 --retry-connrefused --retry-all-errors \
       "http://127.0.0.1:$ECHO_PORT/get" > /dev/null; then
    echo "local-echo on port $ECHO_PORT never answered /get" >&2
    exit 1
  fi
  BASES+=("http://127.0.0.1:$ECHO_PORT")
  LEGS="${LEGS:+$LEGS and }local-echo"
fi
if [ "${#BASES[@]}" -eq 0 ]; then
  echo "VERIFY_OFFLINE=1 needs $ECHO_SERVER, and it is not there" >&2
  exit 1
fi

# A local run starts on a throwaway instance holding nothing, so it is handed the connections
# and the schemas the documents name.
LOCAL=(--connections connections.yaml)
for schema in "${SCHEMAS[@]}"; do
  LOCAL+=(--schema "schemas/$schema.json")
done

say "dhis2-to-dhis2, run locally against both demos"
uv run dg run --local pipelines/dhis2-to-dhis2.yaml "${LOCAL[@]}" --json > "$WORK/local-1.ndjson"
assert_run_succeeded "$WORK/local-1.ndjson" "the local dhis2-to-dhis2 run"
assert_rehearsed "$WORK/local-1.ndjson" "the local dhis2-to-dhis2 run" UID

say "dhis2-to-other, run locally against $LEGS"
for base in "${BASES[@]}"; do
  flags=("${LOCAL[@]}" --json)
  [ -n "$base" ] && flags+=(-p "base_url=$base")
  uv run dg run --local pipelines/dhis2-to-other.yaml "${flags[@]}" > "$WORK/local-2.ndjson"
  assert_run_succeeded "$WORK/local-2.ndjson" "the local dhis2-to-other run"
  assert_delivered "$WORK/local-2.ndjson" "the local dhis2-to-other run"
done

say "other-to-dhis2, run locally against $LEGS"
for base in "${BASES[@]}"; do
  flags=("${LOCAL[@]}" --json)
  [ -n "$base" ] && flags+=(-p "base_url=$base")
  uv run dg run --local pipelines/other-to-dhis2.yaml "${flags[@]}" > "$WORK/local-3.ndjson"
  assert_run_succeeded "$WORK/local-3.ndjson" "the local other-to-dhis2 run"
  assert_rehearsed "$WORK/local-3.ndjson" "the local other-to-dhis2 run" CODE
done

say "a parent the target does not hold, which must still fail"
# The one failure this repository shows on purpose. It is safe because it is a rehearsal: the
# target resolves the reference, refuses it, and writes nothing either way.
uv run dg run --local pipelines/other-to-dhis2.yaml "${LOCAL[@]}" \
  -p parent_code=OU_NOT_THERE --json > "$WORK/orphan.ndjson" || true
jq -se '
  map(select(.kind == "run")) | last | .steps
  | (map(select(.step == "report")) | last | .output.value) as $report
  | (map(select(.step == "verdict")) | last) as $verdict
  | if $report.status != "ERROR" then error("the target accepted a parent it does not hold")
    elif ($report.conflicts | map(select(.code == "E5002")) | length) < 1 then error("the target refused it without naming the reference")
    elif $verdict.status != "failed" then error("the run was allowed to succeed on a refused import")
    else true end
' "$WORK/orphan.ndjson" > /dev/null

# The instance seals a connection's secret with this key, so the key has to exist before the
# connection does. It is minted once into .env, which is not in the repository and already
# holds this instance's token, and every command below runs in this directory and reads it
# from there: an instance that changes its key cannot open what it sealed under the old one,
# so the connections this script leaves behind stay readable -- by its next run, and by a
# reader who starts a dg dev of their own on the same state.
if ! grep -q '^DIRIGENT_SECRET_KEY=' .env 2>/dev/null; then
  (umask 077; printf 'DIRIGENT_SECRET_KEY=%s\n' "$(uv run dg secret-key)" >> .env)
fi

PORT="${DG_PORT:-$(free_port)}"
export DG_URL="http://127.0.0.1:$PORT"

say "the instance, on port $PORT"
# .dirigent/state is not in the repository, so the first run here starts on nothing: dg dev
# migrates the schema and makes the development admin. Every later run reuses what is there.
uv run dg dev --port "$PORT" > "$WORK/dev.ndjson" 2>&1 &
DEV_PID=$!

for _ in $(seq 1 90); do
  if curl -fsS "$DG_URL/health" > /dev/null 2>&1; then break; fi
  kill -0 "$DEV_PID" 2>/dev/null || { echo "the instance stopped before it was ready:"; cat "$WORK/dev.ndjson"; exit 1; }
  sleep 1
done
curl -fsS "$DG_URL/health" > /dev/null

# dg auth login mints a token and writes it into a record, which is the one place it is
# readable; at a terminal the same command spells the export line out to paste.
DG_TOKEN="$(uv run dg auth login --username dev --password dirigent-dev --json \
  | jq -r 'select(.kind == "token.issued") | .token')"
export DG_TOKEN
[ -n "$DG_TOKEN" ]

say "the shapes the instance holds"
# A listing writes one record per row, with the row itself under fields.
for schema in "${SCHEMAS[@]}"; do
  if ! uv run dg schema list --json | jq -e --arg code "$schema" 'select(.fields.code == $code)' > /dev/null; then
    uv run dg schema create "schemas/$schema.json" --json > /dev/null
  fi
done

say "the two DHIS2 connections"
create_connection() {
  uv run dg connection create dhis2 "$1" \
    --name "$2" \
    --set "base_url=$3" \
    --set basic_username=admin \
    --set basic_password=district \
    --json > /dev/null
}

# Written when the instance does not hold them, and left alone when it does: the rows are
# sealed with the key in .env, which is the same key on every run, so there is nothing to
# rewrite and the state a reader inherits is the state this script asserted on.
#
# A row sealed under a key that is gone cannot be opened by this one, and the check names the
# class in its own record. Nothing recovers that secret, so the connection is written again
# under the key in hand -- which is what a reader does by hand after losing a key.
ensure_connection() {
  if ! uv run dg connection list --json | jq -e --arg code "$1" 'select(.fields.code == $code)' > /dev/null; then
    create_connection "$@"
  fi

  uv run dg connection check "$1" --json > "$WORK/check-$1.ndjson" || true
  if jq -se '
    map(select(.kind == "connection.checked")) | last
    | (.detail // "") | startswith("SecretKeyMismatch")
  ' "$WORK/check-$1.ndjson" > /dev/null; then
    say "the $1 connection, sealed again under the key in .env"
    uv run dg connection delete "$1" --json > /dev/null
    create_connection "$@"
    uv run dg connection check "$1" --json > "$WORK/check-$1.ndjson"
  fi

  jq -se --arg code "$1" '
    map(select(.kind == "connection.checked")) | last
    | if .healthy then true else error("the \($code) connection is not healthy: \(.detail)") end
  ' "$WORK/check-$1.ndjson" > /dev/null
}
ensure_connection source "DHIS2 play demo, the source" "$SOURCE_URL"
ensure_connection target "DHIS2 play demo, the target" "$TARGET_URL"

# The two instances must be two instances, or the sync is syncing a thing with itself.
jq -se '
  map(select(.kind == "connection.checked")) | last | .version
' "$WORK/check-source.ndjson" > "$WORK/source-version.json"
jq -se '
  map(select(.kind == "connection.checked")) | last | .version
' "$WORK/check-target.ndjson" > "$WORK/target-version.json"
if [ "$(cat "$WORK/source-version.json")" = "$(cat "$WORK/target-version.json")" ]; then
  echo "source and target report the same version; the two connections address one instance" >&2
  exit 1
fi

say "the documents, applied"
uv run dg apply --json > /dev/null

say "the three runs on the instance"
uv run dg run dhis2-to-dhis2 --watch --json > "$WORK/run-1.ndjson"
assert_run_succeeded "$WORK/run-1.ndjson" "the dhis2-to-dhis2 run"
assert_rehearsed "$WORK/run-1.ndjson" "the dhis2-to-dhis2 run" UID

for base in "${BASES[@]}"; do
  flags=(--watch --json)
  [ -n "$base" ] && flags+=(-p "base_url=$base")

  uv run dg run dhis2-to-other "${flags[@]}" > "$WORK/run-2.ndjson"
  assert_run_succeeded "$WORK/run-2.ndjson" "the dhis2-to-other run"
  assert_delivered "$WORK/run-2.ndjson" "the dhis2-to-other run"

  uv run dg run other-to-dhis2 "${flags[@]}" > "$WORK/run-3.ndjson"
  assert_run_succeeded "$WORK/run-3.ndjson" "the other-to-dhis2 run"
  assert_rehearsed "$WORK/run-3.ndjson" "the other-to-dhis2 run" CODE
done

say "ok: $(cat "$WORK/source-version.json" | tr -d '"') to $(cat "$WORK/target-version.json" | tr -d '"'), rehearsed and written to nothing, against $LEGS"
