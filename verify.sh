#!/usr/bin/env bash
# Run this example end to end, against the real play demo, and exit non-zero the moment
# anything it claims stops being true.
#
# Every assertion below reads records rather than rendered text: --json asks for the records
# even at a terminal, and a table is only a rendering of one.
set -euo pipefail

cd "$(dirname "$0")"

CODE=dhis2-metadata-to-storage
SCHEMA=metadata-snapshot-org-units

# Somewhere to keep the streams this script asserts on, removed on the way out.
WORK="$(mktemp -d)"

DEV_PID=""

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
  # Stop the instance this script started, by the pid this script holds. Never by pattern:
  # a pattern matches this shell too. Its wrapper has its children taken first: killing
  # `uv run` alone leaves the dg dev under it on the port.
  if [ -n "$DEV_PID" ] && kill -0 "$DEV_PID" 2>/dev/null; then
    pkill -TERM -P "$DEV_PID" 2>/dev/null || true
    kill -TERM "$DEV_PID" 2>/dev/null || true
    wait "$DEV_PID" 2>/dev/null || true
  fi
  port_clear "${PORT:-}"
  rm -rf "$WORK"
}
trap cleanup EXIT

say() { printf '\n== %s\n' "$1"; }

# The last run record in a stream is how the run settled.
assert_run_succeeded() {
  jq -se --arg what "$2" '
    map(select(.kind == "run")) | last
    | if . == null then error("\($what): the stream carries no run record")
      elif .message == "succeeded" then true
      else error("\($what): the run settled \(.message)") end
  ' "$1" > /dev/null
}

# What the five hops are for: the file holds what the gate passed, byte for byte and value
# for value, and the count is the count of what came back rather than of what went out.
assert_round_trip() {
  jq -se --arg what "$2" '
    map(select(.kind == "run")) | last | .steps
    | (map(select(.step == "check")) | last | .output.value) as $gated
    | (map(select(.step == "save")) | last | .output) as $save
    | (map(select(.step == "load")) | last | .output) as $load
    | (map(select(.step == "count")) | last | .output.value) as $count
    | if ($gated.organisationUnits | length) < 1 then error("\($what): the gate passed no organisation units")
      elif $save.bytes_written < 1 then error("\($what): nothing was written to storage")
      elif $load.bytes_read != $save.bytes_written then error("\($what): \($save.bytes_written) bytes written, \($load.bytes_read) read back")
      elif $load.value != $gated then error("\($what): what came back out of storage is not what went in")
      elif $count.units != ($gated.organisationUnits | length) then error("\($what): the count says \($count.units) of \($gated.organisationUnits | length)")
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

say "the document, run locally against the play demo"
# A local run starts on a throwaway instance holding nothing, so it is handed the connection
# and the schema this document names.
uv run dg run --local "pipelines/$CODE.yaml" \
  --connections connections.yaml \
  --schema "schemas/$SCHEMA.json" \
  --json > "$WORK/local.ndjson"
assert_run_succeeded "$WORK/local.ndjson" "the local run"
assert_round_trip "$WORK/local.ndjson" "the local run"

# The instance seals a connection's secret with this key, so the key has to exist before the
# connection does. It is minted once into .env, which is not in the repository and already
# holds this instance's token, and every command below runs in this directory and reads it
# from there: an instance that changes its key cannot open what it sealed under the old one,
# so the connection this script leaves behind stays readable -- by its next run, and by a
# reader who starts a dg dev of their own on the same state.
if ! grep -q '^DIRIGENT_SECRET_KEY=' .env 2>/dev/null; then
  (umask 077; printf 'DIRIGENT_SECRET_KEY=%s\n' "$(uv run dg secret-key)" >> .env)
fi

PORT="${DG_PORT:-$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')}"
export DG_URL="http://127.0.0.1:$PORT"

say "the instance, on port $PORT"
# .dirigent/state/ is not in the repository, so the first run here starts on nothing: dg dev
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

say "the shape the instance holds"
# A read writes the row under fields, so the stored body is fields.body. There is no
# `dg schema update`: a schema changes by being deleted and created, so a body that no longer
# matches the file on disk is replaced rather than left as a gate nobody edited.
if ! uv run dg schema show "$SCHEMA" --json 2>/dev/null \
     | jq -se --slurpfile want "schemas/$SCHEMA.json" \
         'map(select(.kind == "schema")) | last | .fields.body == $want[0]' > /dev/null; then
  uv run dg schema delete "$SCHEMA" --json > /dev/null 2>&1 || true
  uv run dg schema create "schemas/$SCHEMA.json" --json > /dev/null
fi

say "the connection to the play demo"
# Written when the instance does not hold it, and left alone when it does: the row is sealed
# with the key in .env, which is the same key on every run, so there is nothing to rewrite and
# the state a reader inherits is the state this script asserted on.
create_play() {
  uv run dg connection create dhis2 play \
    --name "DHIS2 play demo" \
    --set base_url=https://play.dhis2.org/2.42 \
    --set follow_redirects_with_auth=true \
    --set basic_username=admin \
    --set basic_password=district \
    --json > /dev/null
}

if ! uv run dg connection list --json | jq -e 'select(.fields.code == "play")' > /dev/null; then
  create_play
fi

# A row sealed under a key that is gone cannot be opened by this one, and the check names the
# class in its own record. Nothing recovers that secret, so the connection is written again
# under the key in hand -- which is what a reader does by hand after losing a key.
uv run dg connection check play --json > "$WORK/check.ndjson" || true
if jq -se '
  map(select(.kind == "connection.checked")) | last
  | (.detail // "") | startswith("SecretKeyMismatch")
' "$WORK/check.ndjson" > /dev/null; then
  say "the connection, sealed again under the key in .env"
  uv run dg connection delete play --json > /dev/null
  create_play
  uv run dg connection check play --json > "$WORK/check.ndjson"
fi

jq -se '
  map(select(.kind == "connection.checked")) | last
  | if .healthy then true else error("the play connection is not healthy: \(.detail)") end
' "$WORK/check.ndjson" > /dev/null

say "the document, applied"
uv run dg apply --json > /dev/null

say "the run"
uv run dg run "$CODE" --watch --json > "$WORK/run.ndjson"
assert_run_succeeded "$WORK/run.ndjson" "the server run"
assert_round_trip "$WORK/run.ndjson" "the server run"

say "ok: $CODE snapshotted the play demo's organisation units and read them back"
