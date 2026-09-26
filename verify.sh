#!/usr/bin/env bash
# Run this example end to end and assert on the records, never on the rendering: a table is
# what a terminal makes of a record, and this script has no terminal.
#
# It starts its own instance, which serves the playground the stream is read from, and its own
# Redpanda in a container, with the topic the third document produces to and consumes from. Each
# document is run twice -- once with no server of its own and once against the instance, where
# the fourth one's watch is resumed, left to arm a few runs, and paused -- and everything it
# started is stopped on the way out: the instance by the pid this script holds, the container by
# the name this script gave it.
#
# Needs docker and one image, the one dirigent's own infra/compose.queues.yaml uses:
#   redpandadata/redpanda:v24.2.18
set -euo pipefail

cd "$(dirname "$0")"

KAFKA_IMAGE="${DIRIGENT_KAFKA_IMAGE:-redpandadata/redpanda:v24.2.18}"

# Somewhere to keep the streams this script asserts on, removed on the way out.
WORK="$(mktemp -d)"

DEV_PID=""
KAFKA_NAME=""

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
  # The instance, by the pid this script holds, its wrapper's children first: killing
  # `uv run` alone leaves the dg dev under it on the port.
  if [ -n "$DEV_PID" ] && kill -0 "$DEV_PID" 2>/dev/null; then
    pkill -TERM -P "$DEV_PID" 2>/dev/null || true
    kill -TERM "$DEV_PID" 2>/dev/null || true
    wait "$DEV_PID" 2>/dev/null || true
  fi
  port_clear "${PORT:-}"
  # The broker, by the name this script gave it, whether or not it ever came up.
  if [ -n "$KAFKA_NAME" ]; then
    docker rm -f "$KAFKA_NAME" > /dev/null 2>&1 || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

say() { printf '\n== %s\n' "$1"; }

free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# Every assertion goes through this: the jq program is run over one file of records, and a
# refusal says what it wanted and what the stream's run record said.
expect() {
  local what=$1 file=$2
  shift 2
  if ! jq -e -s "$@" "$file" > /dev/null; then
    echo "echo-stream: expected $what" >&2
    jq -c -s 'map(select(.kind == "run")) | last | {message, steps: [.steps[]? | {step, status}], failures}' "$file" >&2 || true
    exit 1
  fi
}

step_map='(map(select(.kind == "run" and has("exit_code"))) | last) as $run | ($run.steps | map({key: .step, value: .}) | from_entries) as $step'

# What each document is for, said once and asserted on every run of it.
wait_arrived='
  | $run.message == "succeeded"
    and ([.[] | select(.step == "wait" and (.message | startswith("poke")))] | length) == 3
    and $step.summarise.output.value.count == 4
    and ($step.summarise.output.value.stations | length) == 4'
read_whole='
  | $run.message == "succeeded"
    and $step.lines.output.value.lines == 7
    and $step.lines.output.value.kinds == {"stream": 1, "stream.message": 5, "stream.closed": 1}
    and $step.lines.output.value.closed == true'
watch_once='
  | $run.message == "succeeded"
    and $step.summarise.output.value == {count: 3, first_offset: 0, last_offset: 2, next_offset: 3}'
topic_read='
  | $run.message == "succeeded"
    and $step.publish.output.produced == 4
    and $step.summarise.output.value
        == {count: 4, stations: ["bergen-florida", "oslo-blindern", "tromso-langnes", "trondheim-voll"]}'

say "the project's own environment"
uv sync --quiet

say "every document, checked offline"
uv run dg validate --json > "$WORK/validate.ndjson"
jq -se '
  map(select(.kind == "validated")) | last
  | if .invalid == 0 and .documents == 4 then true else error("\(.invalid) document(s) refused") end
' "$WORK/validate.ndjson" > /dev/null

# --- the instance, which serves the playground ------------------------------------------------
PORT="${DG_PORT:-$(free_port)}"
export DG_URL="http://127.0.0.1:$PORT"
playground="$DG_URL/api/v1/playground"

say "the instance, on port $PORT"
uv run dg dev --port "$PORT" > "$WORK/dev.ndjson" 2>&1 &
DEV_PID=$!
for _ in $(seq 1 90); do
  curl -fsS "$DG_URL/health" > /dev/null 2>&1 && break
  kill -0 "$DEV_PID" 2>/dev/null || { echo "the instance stopped before it was ready:"; cat "$WORK/dev.ndjson"; exit 1; }
  sleep 1
done
curl -fsS "$DG_URL/health" > /dev/null

# --- the broker ------------------------------------------------------------------------------
#
# A port of this script's own, advertised as itself, so a client on this machine that asks the
# broker where it lives is told the port it already used.
KAFKA_PORT="$(free_port)"
KAFKA_NAME="echo-stream-$KAFKA_PORT"
say "the broker, as $KAFKA_NAME on port $KAFKA_PORT"
docker rm -f "$KAFKA_NAME" > /dev/null 2>&1 || true
docker run -d --rm --name "$KAFKA_NAME" -p "127.0.0.1:$KAFKA_PORT:9092" "$KAFKA_IMAGE" \
  redpanda start --mode=dev-container --smp=1 --node-id=0 --check=false \
  --kafka-addr=PLAINTEXT://0.0.0.0:9092 \
  --advertise-kafka-addr="PLAINTEXT://127.0.0.1:$KAFKA_PORT" \
  --set redpanda.auto_create_topics_enabled=false > /dev/null

# Neither block declares a topic, so this makes it, from this machine rather than from inside
# the container: rpk in there would be told the advertised port, which only this side has.
# aiokafka is in this project's environment because the queue blocks bring it.
say "the topic readings"
made=false
for _ in $(seq 1 60); do
  if KAFKA_BOOTSTRAP="127.0.0.1:$KAFKA_PORT" uv run python - > /dev/null 2>&1 <<'PY'
import asyncio
import os

from aiokafka.admin import AIOKafkaAdminClient, NewTopic
from aiokafka.errors import TopicAlreadyExistsError


async def main() -> None:
    admin = AIOKafkaAdminClient(bootstrap_servers=os.environ["KAFKA_BOOTSTRAP"])
    await admin.start()
    try:
        await admin.create_topics([NewTopic("readings", num_partitions=1, replication_factor=1)])
    except TopicAlreadyExistsError:
        pass
    finally:
        await admin.close()


asyncio.run(main())
PY
  then
    made=true
    break
  fi
  sleep 1
done
[ "$made" = true ] || { echo "the topic readings could not be created on port $KAFKA_PORT" >&2; exit 1; }

# --- without a server --------------------------------------------------------------------------
say "echo-stream-wait, run locally"
uv run dg run --local pipelines/echo-stream-wait.yaml --json > "$WORK/r.ndjson"
expect "three parked pokes and a batch of four" "$WORK/r.ndjson" "$step_map$wait_arrived"

say "echo-stream-read, run locally against the instance's playground"
uv run dg run --local pipelines/echo-stream-read.yaml --json -p "playground=$playground" > "$WORK/r.ndjson"
expect "the envelope, five messages and the close, all at once" "$WORK/r.ndjson" "$step_map$read_whole"

# A local run has no watch behind it, so its batch starts from zero.
say "echo-stream-watch, run locally, once"
uv run dg run --local pipelines/echo-stream-watch.yaml --json > "$WORK/r.ndjson"
expect "one batch of three, offsets 0 to 2" "$WORK/r.ndjson" "$step_map$watch_once"

# The committed connections.yaml names port 9092, which is where the README has you start the
# broker by hand. This script picked its own port, so it writes that port into a copy.
say "echo-stream-topic, run locally against $KAFKA_NAME"
sed "s#127.0.0.1:9092#127.0.0.1:$KAFKA_PORT#" connections.yaml > "$WORK/connections.yaml"
uv run dg run --local pipelines/echo-stream-topic.yaml --connections "$WORK/connections.yaml" \
  --json > "$WORK/r.ndjson"
expect "four readings produced and read back" "$WORK/r.ndjson" "$step_map$topic_read"
expect "the first batch on the topic, offsets 0 to 3" "$WORK/r.ndjson" "$step_map"'
  | [$step.wait.output.messages[].offset] == [0, 1, 2, 3]'

# --- the instance ------------------------------------------------------------------------------
#
# DG_URL beats the local profile, whose url is the default port. The token comes from dg dev's
# own admin: on an empty state that is the fixture dev / dirigent-dev.
DG_TOKEN="$(uv run dg auth login --username dev --password dirigent-dev --json \
  | jq -r 'select(.kind == "token.issued") | .token')"
export DG_TOKEN
[ -n "$DG_TOKEN" ]

say "the connection to the broker"
# There is no `dg connection update`: a connection changes by being deleted and created, and a
# row naming last run's port names nothing, because the broker takes a free port each time.
if uv run dg connection list --json | jq -e -s 'any(.[]; .fields.code == "readings")' > /dev/null; then
  uv run dg connection delete readings --json > /dev/null
fi
uv run dg connection create kafka readings \
  --name "The readings topic's cluster" \
  --set "bootstrap_servers=[\"127.0.0.1:$KAFKA_PORT\"]" \
  --json > /dev/null
uv run dg connection check readings --json > "$WORK/check.ndjson"
jq -se '
  map(select(.kind == "connection.checked")) | last
  | if .healthy then true else error("the readings connection is not healthy: \(.detail)") end
' "$WORK/check.ndjson" > /dev/null

say "the documents, applied"
uv run dg apply --json > /dev/null

say "echo-stream-wait, on the instance"
uv run dg run echo-stream-wait --watch --json > "$WORK/r.ndjson"
expect "three parked pokes and a batch of four, watched" "$WORK/r.ndjson" "$step_map$wait_arrived"

say "echo-stream-read, on the instance"
uv run dg run echo-stream-read --watch --json -p "playground=$playground" > "$WORK/r.ndjson"
expect "the envelope, five messages and the close, all at once" "$WORK/r.ndjson" "$step_map$read_whole"

# The consumer group committed offsets 0 to 3 on the local run, so this one reads the four the
# publish before it just wrote, and nothing it read before.
say "echo-stream-topic, on the instance"
uv run dg run echo-stream-topic --watch --json > "$WORK/r.ndjson"
expect "four readings produced and read back" "$WORK/r.ndjson" "$step_map$topic_read"
expect "the second batch on the topic, offsets 4 to 7" "$WORK/r.ndjson" "$step_map"'
  | [$step.wait.output.messages[].offset] == [4, 5, 6, 7]'

# --- the watch ---------------------------------------------------------------------------------
#
# The state is kept between runs of this script, and so is the watch's cursor: this run's first
# batch starts wherever the last run's pause left it, which is the point.
watch_record='map(select(.kind == "watch")) | last | .fields'
runs_since() {
  uv run dg runs list --pipeline echo-stream-watch --limit 100 --json \
    | jq -c --slurpfile before "$WORK/before.json" \
        'select(.kind == "run") | .fields | select(.id as $id | $before[0] | index($id) | not)'
}

say "echo-stream-watch, its watch as the apply left it"
uv run dg watch show echo-stream-watch follow --json > "$WORK/w.ndjson"
# A run of this script that was cut short can leave the watch going; pausing it first makes the
# resume below the one that arms.
if ! jq -e -s "$watch_record | .paused" "$WORK/w.ndjson" > /dev/null; then
  uv run dg watch pause echo-stream-watch follow --json > /dev/null
  uv run dg watch show echo-stream-watch follow --json > "$WORK/w.ndjson"
fi
expect "the watch paused, with nothing waiting" "$WORK/w.ndjson" "$watch_record"' | .paused and .waiting_run_id == null'
start="$(jq -s "$watch_record | .cursor.offset // 0" "$WORK/w.ndjson")"

uv run dg runs list --pipeline echo-stream-watch --limit 100 --json \
  | jq -s '[.[] | select(.kind == "run") | .fields.id]' > "$WORK/before.json"

say "echo-stream-watch, resumed from offset $start"
uv run dg watch resume echo-stream-watch follow --json > "$WORK/resumed.ndjson"
expect "a run armed by the resume" "$WORK/resumed.ndjson" \
  'map(select(.kind == "watch.resumed")) | last | .waiting_run_id != null'

for _ in $(seq 1 60); do
  done_runs="$(runs_since | jq -s '[.[] | select(.status == "succeeded")] | length')"
  [ "$done_runs" -ge 3 ] && break
  sleep 1
done

say "echo-stream-watch, paused after $done_runs runs"
uv run dg watch pause echo-stream-watch follow --json > "$WORK/paused.ndjson"

# The pause cancels the run that was waiting; the runs already working a batch finish it.
for _ in $(seq 1 30); do
  runs_since > "$WORK/runs.ndjson"
  jq -e -s 'all(.status | IN("succeeded", "failed", "cancelled"))' "$WORK/runs.ndjson" > /dev/null && break
  sleep 1
done
# And nothing arms again: a paused watch stays paused.
sleep 3
runs_since > "$WORK/runs.ndjson"

# What each run's summarise read, oldest run first.
: > "$WORK/batches.ndjson"
for id in $(jq -r -s 'sort_by(.created_at) | .[] | select(.status == "succeeded") | .id' "$WORK/runs.ndjson"); do
  uv run dg runs show "$id" --json | jq -c --arg id "$id" '
    select(.kind == "run.detail") | .fields as $f
    | {run: $id, started_at: $f.run.started_at, finished_at: $f.run.finished_at,
       batch: ($f.attempts[] | select(.step_name == "summarise") | .output.value)}' \
    >> "$WORK/batches.ndjson"
done

expect "at least three batches of three" "$WORK/batches.ndjson" \
  'length >= 3 and all(.batch.count == 3 and .batch.last_offset == .batch.first_offset + 2)'
expect "the first batch starting where the last pause left the cursor" "$WORK/batches.ndjson" \
  --argjson start "$start" '.[0].batch.first_offset == $start'
expect "each batch starting where the one before it ended" "$WORK/batches.ndjson" \
  '[range(1; length) as $i | .[$i].batch.first_offset == .[$i - 1].batch.next_offset] | all'
expect "a run waiting while the run before it was still working" "$WORK/batches.ndjson" \
  '[range(1; length) as $i | .[$i].started_at < .[$i - 1].finished_at] | any'
expect "one run cancelled by the pause, and every other one succeeded" "$WORK/runs.ndjson" \
  '([.[] | select(.status == "cancelled")] | length) == 1
   and ([.[] | select(.status == "cancelled")][0].error == "its watch was paused")
   and all(.status | IN("succeeded", "cancelled"))
   and all(.triggered_by_kind == "watch")'
expect "the paused watch keeping the cursor the last batch handed on" "$WORK/paused.ndjson" \
  --argjson next "$(jq -s 'last | .batch.next_offset' "$WORK/batches.ndjson")" \
  'map(select(.kind == "watch.paused")) | last | .cursor == {offset: $next}'

say "ok: a batch that arrived, a stream read whole, the same batch off a real topic, and a batch that kept arriving"
