#!/usr/bin/env bash
# Run this example end to end against a local Chap it starts itself, and exit non-zero the moment
# anything it claims stops being true. It plays the reviewer too: every alert a forecast raises is
# approved in Chap while the run waits on it.
#
# Every assertion below reads records rather than rendered text: --json asks for the records
# even at a terminal, and a table is only a rendering of one.
set -euo pipefail

cd "$(dirname "$0")"

CODE=chap-prediction
POLICY=chap-alert-policy
COMPOSE=(docker compose -p dirigent-example-chap-prediction -f chap/compose.yaml)
export CHAP_PORT="${CHAP_PORT:-8710}"
CHAP="http://127.0.0.1:$CHAP_PORT"

WORK="$(mktemp -d)"
DEV_PID=""
RUN_PID=""

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

stop_pid() {
  local pid="${1:-}"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    pkill -TERM -P "$pid" 2>/dev/null || true
    kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
}

cleanup() {
  # Stop what this script started, by the pid it holds, and the Chap stack by its own project
  # name, volumes included, so the next run starts on an empty Chap.
  stop_pid "$RUN_PID"
  stop_pid "$DEV_PID"
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
      else error("\($what): the run settled \(.message)") end
  ' "$1" > /dev/null
}

# Approve every pending alert in Chap until the process named by the first argument exits.
review_while() {
  local pid="$1" pending
  while kill -0 "$pid" 2>/dev/null; do
    pending="$(curl -fsS "$CHAP/v1/crud/alerts?approved=pending" | jq -c '[.[].id]')"
    if [ "$pending" != "[]" ]; then
      curl -fsS -X POST "$CHAP/v1/crud/alerts/\$approve" \
        -H 'content-type: application/json' \
        -d "{\"alertIds\": $pending, \"approved\": \"approved\", \"approvedBy\": \"verify.sh\"}" > /dev/null
    fi
    sleep 2
  done
}

# What one forecast run must have done: three org units imported, a backtest, nine forecast
# cells at two quantiles, and every alert it recorded released.
assert_forecast() {
  jq -se '
    map(select(.kind == "run")) | last | .steps
    | (map({key: .step, value: .output}) | from_entries) as $out
    | if $out.dataset.imported_count != 3 then error("the import took \($out.dataset.imported_count) locations, not 3")
      elif $out.dataset.rejected_count != 0 then error("Chap rejected \($out.dataset.rejected_count) observations")
      elif ($out.backtest.backtest_id | type) != "number" then error("the backtest stored nothing")
      elif ($out.quantiles.count) != 18 then error("the forecast read \($out.quantiles.count) entries, not 18")
      elif $out.record.count < 1 then error("the forecast raised no alerts")
      elif ($out.release.value.released | length) != $out.record.count then error("not every recorded alert was released")
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

say "Chap, on port $CHAP_PORT"
"${COMPOSE[@]}" down -v --remove-orphans > /dev/null 2>&1 || true
"${COMPOSE[@]}" up -d --wait > "$WORK/compose.log" 2>&1 \
  || { echo "Chap did not come up:"; cat "$WORK/compose.log"; exit 1; }
curl -fsS "$CHAP/system/info" | jq -e '.auth_required == false' > /dev/null

say "the alert policy, defined locally"
uv run dg run --local "pipelines/$POLICY.yaml" --connections connections.yaml --json > "$WORK/policy.ndjson"
assert_run_succeeded "$WORK/policy.ndjson" "the policy run"
POLICY_ID="$(jq -rs 'map(select(.kind == "run")) | last | .steps[0].output.body.id' "$WORK/policy.ndjson")"
[ "$POLICY_ID" -ge 1 ]

say "the forecast, run locally, its alerts approved as they arrive"
uv run dg run --local "pipelines/$CODE.yaml" --connections connections.yaml \
  -P data/laos-dengue.yaml -p alert_policy_id="$POLICY_ID" \
  --json > "$WORK/local.ndjson" &
RUN_PID=$!
review_while "$RUN_PID"
wait "$RUN_PID"
RUN_PID=""
assert_run_succeeded "$WORK/local.ndjson" "the local run"
assert_forecast "$WORK/local.ndjson"

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

say "the connection to Chap"
# The connection carries no secret, so it is written again on every run: the port is the one
# this run started Chap on.
if uv run dg connection list --json | jq -e 'select(.fields.code == "chap-local")' > /dev/null; then
  uv run dg connection delete chap-local --json > /dev/null
fi
uv run dg connection create chap chap-local \
  --name "Local Chap" \
  --set base_url="$CHAP" \
  --json > /dev/null
uv run dg connection check chap-local --json > "$WORK/check.ndjson"
jq -se '
  map(select(.kind == "connection.checked")) | last
  | if .healthy then true else error("the chap-local connection is not healthy: \(.detail)") end
' "$WORK/check.ndjson" > /dev/null

say "the documents, applied"
uv run dg apply --json > /dev/null

say "the forecast, run on the instance, its alerts approved as they arrive"
uv run dg run "$CODE" --watch -P data/laos-dengue.yaml -p alert_policy_id="$POLICY_ID" \
  --json > "$WORK/run.ndjson" &
RUN_PID=$!
review_while "$RUN_PID"
wait "$RUN_PID"
RUN_PID=""
assert_run_succeeded "$WORK/run.ndjson" "the server run"
assert_forecast "$WORK/run.ndjson"

say "ok: $CODE imported, backtested, forecast, read back and released against a local Chap"
