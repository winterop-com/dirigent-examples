#!/usr/bin/env bash
# Run this example end to end against two local HAPI FHIR servers it starts itself, and exit
# non-zero the moment anything it claims stops being true. Nothing it does reaches the internet
# once the image is pulled: both servers are containers on 127.0.0.1.
#
# Every assertion below reads records or FHIR JSON rather than rendered text: --json asks for
# the records even at a terminal, and a table is only a rendering of one.
set -euo pipefail

cd "$(dirname "$0")"

CODE=fhir-to-fhir
COMPOSE=(docker compose -p dirigent-example-fhir-to-fhir -f hapi/compose.yaml)
export FHIR_SOURCE_PORT="${FHIR_SOURCE_PORT:-9811}" FHIR_TARGET_PORT="${FHIR_TARGET_PORT:-9812}"
SOURCE="http://127.0.0.1:$FHIR_SOURCE_PORT/fhir"
TARGET="http://127.0.0.1:$FHIR_TARGET_PORT/fhir"

# What the seed holds: a dozen patients, two observations about each.
PATIENTS=12
OBSERVATIONS=24

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
  # Stop the instance this script started, by the pid it holds, and both servers by their own
  # project name, so the next run starts from two empty servers.
  if [ -n "$DEV_PID" ] && kill -0 "$DEV_PID" 2>/dev/null; then
    pkill -TERM -P "$DEV_PID" 2>/dev/null || true
    kill -TERM "$DEV_PID" 2>/dev/null || true
    wait "$DEV_PID" 2>/dev/null || true
  fi
  port_clear "${PORT:-}"
  "${COMPOSE[@]}" down -v --remove-orphans > /dev/null 2>&1 || true
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

# What the target did, as the receipt step counted it: how many created, how many updated.
assert_receipt() {
  jq -se --argjson created "$2" --argjson updated "$3" --argjson p "$PATIENTS" --argjson o "$OBSERVATIONS" '
    map(select(.kind == "run")) | last | .steps
    | (map(select(.step == "receipt")) | last | .output.value) as $r
    | if $r == null then error("the run carries no receipt")
      elif $r.by_type != {Observation: $o, Patient: $p} then error("the transaction carried \($r.by_type)")
      elif $r.created != $created then error("the target created \($r.created), not \($created)")
      elif $r.updated != $updated then error("the target updated \($r.updated), not \($updated)")
      else true end
  ' "$1" > /dev/null
}

# HAPI answers a search it ran in the last minute from its cache unless told not to, which would
# read a target as empty after the copy filled it.
fresh() {
  curl -fsS -H 'Cache-Control: no-cache' "$@"
}

# How many resources of one type a server holds.
count() {
  fresh "$1/$2?_summary=count" | jq -r '.total'
}

# Every resource of one type, with what an observation refers to, as one JSON array.
everything() {
  fresh "$1/$2?_count=200${3:-}" | jq '[.entry[]?.resource]'
}

# The copy, as the target holds it: the counts, the identifiers, and every observation's
# subject a patient on the target carrying the identifier its source patient carries.
assert_copy() {
  [ "$(count "$TARGET" Patient)" = "$PATIENTS" ] || { echo "the target holds $(count "$TARGET" Patient) patients"; exit 1; }
  [ "$(count "$TARGET" Observation)" = "$OBSERVATIONS" ] \
    || { echo "the target holds $(count "$TARGET" Observation) observations"; exit 1; }
  for server in source target; do
    url="$SOURCE"; [ "$server" = target ] && url="$TARGET"
    everything "$url" Observation "&_include=Observation:subject" > "$WORK/$server.json"
    # Each observation's identifier, paired with the identifier of the patient its subject
    # resolves to on the same server. A subject that resolves to nothing pairs with null.
    jq -S '
      (map(select(.resourceType == "Patient")) | map({key: "Patient/\(.id)", value: .identifier[0].value}) | from_entries) as $patients
      | map(select(.resourceType == "Observation"))
      | map({observation: .identifier[0].value, patient: $patients[.subject.reference]})
      | sort_by(.observation)
    ' "$WORK/$server.json" > "$WORK/$server.pairs.json"
  done
  jq -e 'all(.[]; .patient != null)' "$WORK/target.pairs.json" > /dev/null \
    || { echo "an observation on the target refers to no patient there"; exit 1; }
  diff -u "$WORK/source.pairs.json" "$WORK/target.pairs.json" > /dev/null \
    || { echo "the target's observations do not refer to the patients the source's do:"; diff -u "$WORK/source.pairs.json" "$WORK/target.pairs.json"; exit 1; }
  diff <(everything "$SOURCE" Patient | jq -S 'map(.identifier) | sort') \
       <(everything "$TARGET" Patient | jq -S 'map(.identifier) | sort') > /dev/null \
    || { echo "the target's patients do not carry the source's identifiers"; exit 1; }
}

say "the project's own environment"
uv sync --quiet

say "every document, checked offline"
uv run dg validate --json > "$WORK/validate.ndjson"
jq -se '
  map(select(.kind == "validated")) | last
  | if .invalid == 0 then true else error("\(.invalid) document(s) refused") end
' "$WORK/validate.ndjson" > /dev/null

say "two HAPI FHIR servers, on ports $FHIR_SOURCE_PORT and $FHIR_TARGET_PORT, empty"
"${COMPOSE[@]}" down -v --remove-orphans > /dev/null 2>&1 || true
"${COMPOSE[@]}" up -d > "$WORK/compose.log" 2>&1 \
  || { echo "the servers did not start:"; cat "$WORK/compose.log"; exit 1; }
for url in "$SOURCE" "$TARGET"; do
  for _ in $(seq 1 180); do
    if curl -fsS "$url/metadata" 2>/dev/null | jq -e '.resourceType == "CapabilityStatement"' > /dev/null 2>&1; then break; fi
    sleep 1
  done
  curl -fsS "$url/metadata" | jq -e '.fhirVersion == "4.0.1"' > /dev/null
done
[ "$(count "$TARGET" Patient)" = 0 ]

say "the source, seeded with $PATIENTS patients and $OBSERVATIONS observations"
curl -fsS -X POST "$SOURCE" -H 'Content-Type: application/fhir+json' --data-binary @seed/source.json \
  | jq -e '[.entry[].response.status | startswith("201")] | all and length == 36' > /dev/null
[ "$(count "$SOURCE" Patient)" = "$PATIENTS" ]

say "the document, run locally: everything created on the target"
uv run dg run --local "pipelines/$CODE.yaml" --connections connections.yaml --json > "$WORK/local.ndjson"
assert_run_succeeded "$WORK/local.ndjson" "the first local run"
assert_receipt "$WORK/local.ndjson" 36 0
jq -se 'map(select(.kind == "run")) | last | .steps | map(select(.step == "find")) | last | .output.pages == 3' \
  "$WORK/local.ndjson" > /dev/null || { echo "the search did not read three pages"; exit 1; }
assert_copy

say "the document, run again: nothing new"
uv run dg run --local "pipelines/$CODE.yaml" --connections connections.yaml --json > "$WORK/again.ndjson"
assert_run_succeeded "$WORK/again.ndjson" "the second local run"
assert_receipt "$WORK/again.ndjson" 0 36
assert_copy

PORT="${DG_PORT:-$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')}"
export DG_URL="http://127.0.0.1:$PORT"

say "the instance, on port $PORT"
uv run dg dev --port "$PORT" > "$WORK/dev.ndjson" 2>&1 &
DEV_PID=$!

for _ in $(seq 1 90); do
  if curl -fsS "$DG_URL/health" > /dev/null 2>&1; then break; fi
  kill -0 "$DEV_PID" 2>/dev/null || { echo "the instance stopped before it was ready:"; cat "$WORK/dev.ndjson"; exit 1; }
  sleep 1
done
curl -fsS "$DG_URL/health" > /dev/null

DG_TOKEN="$(uv run dg auth login --username admin --password admin --json \
  | jq -r 'select(.kind == "token.issued") | .token')"
export DG_TOKEN
[ -n "$DG_TOKEN" ]

say "the connections, checked: each reads /metadata and reports FHIR 4.0.1"
# Neither carries a secret, and each names the port this run started its server on, so both
# are written again on every run, in place: a connection an applied pipeline names cannot be
# deleted, and ensure creates it or brings what is stored to what is given.
for pair in "fhir-source=$SOURCE" "fhir-target=$TARGET"; do
  code="${pair%%=*}"
  uv run dg connection ensure fhir "$code" --set base_url="${pair#*=}" --set timeout=1m --json > /dev/null
  uv run dg connection check "$code" --json > "$WORK/check.ndjson"
  jq -se --arg code "$code" '
    map(select(.kind == "connection.checked")) | last
    | if .healthy != true then error("the \($code) connection is not healthy: \(.detail)")
      elif .version != "4.0.1" then error("the \($code) connection reports FHIR \(.version)")
      else true end
  ' "$WORK/check.ndjson" > /dev/null
done

say "the document, applied"
uv run dg apply --json > /dev/null

say "the run, on the instance: nothing new"
uv run dg run "$CODE" --watch --json > "$WORK/run.ndjson"
assert_run_succeeded "$WORK/run.ndjson" "the server run"
assert_receipt "$WORK/run.ndjson" 0 36
assert_copy

say "ok: $CODE copied $PATIENTS patients and $OBSERVATIONS observations between two HAPI FHIR servers, and a second and third run created nothing"
