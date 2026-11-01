#!/usr/bin/env bash
# Run this example end to end against a local open climate service it starts itself, and exit
# non-zero the moment anything it claims stops being true. The service downloads CHIRPS from
# data.chc.ucsb.edu and the chiefdoms come from the DHIS2 play demo, so it needs the network.
#
# Every assertion below reads records rather than rendered text: --json asks for the records
# even at a terminal, and a table is only a rendering of one.
set -euo pipefail

cd "$(dirname "$0")"

CODE=climate-sync-and-export
SCHEMA=rainfall-data-value-set
COMPOSE=(docker compose -p dirigent-example-climate-sync-and-export -f ocs/compose.yaml)
export OCS_PORT="${OCS_PORT:-9710}"
OCS="http://127.0.0.1:$OCS_PORT"

WORK="$(mktemp -d)"
DEV_PID=""

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
  # Stop the instance this script started, by the pid it holds, and the service by its own
  # project name, its data volume included, so the next run ingests from nothing.
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

assert_run_succeeded() {
  jq -se --arg what "$2" '
    map(select(.kind == "run")) | last
    | if . == null then error("\($what): the stream carries no run record")
      elif .message == "succeeded" then true
      else error("\($what): the run settled \(.message): \(.failures // [] | map("\(.step): \(.error)") | join("; "))") end
  ' "$1" > /dev/null
}

# What one run must have done: the ingestion and the sync each ran a job to the end, and the
# export holds one value per chiefdom and day, 2025-01-01 to 2025-01-10, past the gate.
assert_export() {
  jq -se '
    map(select(.kind == "run")) | last | .steps
    | (map({key: .step, value: .output}) | from_entries) as $out
    | ($out.check.value.dataValues) as $values
    | ($out.shapes.value.features | length) as $units
    | if ($out.ingest.status | IN("successful", "completed") | not) then error("the ingestion ended \($out.ingest.status)")
      elif ($out.sync.status | IN("successful", "completed", "up_to_date") | not) then error("the sync ended \($out.sync.status)")
      elif $units < 1 then error("the play demo answered with no chiefdoms")
      elif ([$values[].period] | unique) != [range(1; 11) | "202501\(if . < 10 then "0" else "" end)\(.)"]
        then error("the export covers \([$values[].period] | unique)")
      elif ([$values[].orgUnit] | unique | length) != $units then error("not every chiefdom has values")
      elif ($values | length) != ($units * 10) then error("\($values | length) values, not \($units * 10)")
      else true end
  ' "$1" > /dev/null
}

say "the project's own environment"
uv sync --quiet

say "every document, checked offline"
uv run dg validate --json > "$WORK/validate.ndjson"
jq -se '
  map(select(.kind == "validated")) | last
  | if .invalid == 0 then true else error("\(.invalid) document(s) refused") end
' "$WORK/validate.ndjson" > /dev/null

say "the open climate service, on port $OCS_PORT, empty"
"${COMPOSE[@]}" down -v --remove-orphans > /dev/null 2>&1 || true
"${COMPOSE[@]}" up -d --wait > "$WORK/compose.log" 2>&1 \
  || { echo "the service did not come up:"; cat "$WORK/compose.log"; exit 1; }
curl -fsS "$OCS/datasets" | jq -e '.items == []' > /dev/null

say "the document, run locally"
uv run dg run --local "pipelines/$CODE.yaml" \
  --connections connections.yaml \
  --schema "schemas/$SCHEMA.json" \
  --json > "$WORK/local.ndjson"
assert_run_succeeded "$WORK/local.ndjson" "the local run"
assert_export "$WORK/local.ndjson"

say "the service holds the dataset, synced to 2025-01-10"
curl -fsS "$OCS/datasets" | jq -e '
  [.items[] | select(.dataset_id == "chirps3_precipitation_daily")][0].extent.temporal.end == "2025-01-10"
' > /dev/null

if ! grep -q '^DIRIGENT_SECRET_KEY=' .env 2>/dev/null; then
  (umask 077; printf 'DIRIGENT_SECRET_KEY=%s\n' "$(uv run dg secret-key)" >> .env)
fi

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

say "the shape the instance holds"
if ! uv run dg schema list --json | jq -e --arg code "$SCHEMA" 'select(.fields.code == $code)' > /dev/null; then
  uv run dg schema create "schemas/$SCHEMA.json" --json > /dev/null
fi

say "the connections"
# climate-local carries no secret and names the port this run started the service on. play is
# written once and kept, sealed under the key in .env, and written again only when that key
# changed. Each is created on the first run; on a later one, whose instance still holds it in
# .dirigent/state with the pipeline that names it, it is updated in place.
has_connection() {
  uv run dg connection list --json | jq -e --arg code "$1" 'select(.fields.code == $code)' > /dev/null
}
update_connection() {
  curl -fsS -X PATCH "$DG_URL/api/v1/connections/$1" \
    -H "Authorization: Bearer $DG_TOKEN" \
    -H 'content-type: application/json' \
    -d "{\"config\": $2}" > /dev/null
}

if has_connection climate-local; then
  update_connection climate-local "{\"base_url\": \"$OCS\", \"timeout\": \"2m\"}"
else
  uv run dg connection create climate climate-local \
    --name "Local open climate service" \
    --set base_url="$OCS" \
    --set timeout=2m \
    --json > /dev/null
fi

if ! has_connection play; then
  uv run dg connection create dhis2 play \
    --name "DHIS2 play demo" \
    --set base_url=https://play.dhis2.org/2.42 \
    --set follow_redirects_with_auth=true \
    --set basic_username=admin \
    --set basic_password=district \
    --json > /dev/null
fi
uv run dg connection check play --json > "$WORK/check-play.ndjson" || true
if jq -se 'map(select(.kind == "connection.checked")) | last | (.detail // "") | startswith("SecretKeyMismatch")' \
  "$WORK/check-play.ndjson" > /dev/null; then
  update_connection play '{"base_url": "https://play.dhis2.org/2.42", "follow_redirects_with_auth": true,
    "basic_username": "admin", "basic_password": "district"}'
fi

for code in climate-local play; do
  uv run dg connection check "$code" --json > "$WORK/check.ndjson"
  jq -se --arg code "$code" '
    map(select(.kind == "connection.checked")) | last
    | if .healthy then true else error("the \($code) connection is not healthy: \(.detail)") end
  ' "$WORK/check.ndjson" > /dev/null
done

say "the document, applied"
uv run dg apply --json > /dev/null

say "the run, on a service that already holds the dataset"
uv run dg run "$CODE" --watch --json > "$WORK/run.ndjson"
assert_run_succeeded "$WORK/run.ndjson" "the server run"
assert_export "$WORK/run.ndjson"

say "ok: $CODE ingested, synced and exported rainfall per chiefdom against a local open climate service"
