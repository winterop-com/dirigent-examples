#!/usr/bin/env bash
# Run this example end to end and assert on the records, never on the rendering: a table is
# what a terminal makes of a record, and this script has no terminal.
#
# One of the runs below fails on purpose, so its non-zero exit is the expected outcome and what is
# asserted is which step failed and which step never ran at all.
#
# The documents call the playground, which an instance serves under /api/v1/playground, so the
# instance is started first and every run below is pointed at it. A --local run mounts no API of
# its own, which is why even that leg needs the instance this script starts.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

uv sync

for document in echo-send-before.yaml pipelines/echo-send.yaml; do
  uv run dg validate "$document"
done

dev_pid=

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

# Whatever this script started is stopped by its pid, however this script ends. The
# instance's wrapper has its children taken first: killing `uv run` alone leaves the dg dev
# under it on the port.
cleanup() {
  if [ -n "$dev_pid" ]; then
    pkill -TERM -P "$dev_pid" 2>/dev/null || true
    kill -TERM "$dev_pid" 2>/dev/null || true
    wait "$dev_pid" 2>/dev/null || true
  fi
  port_clear "${port:-}"
}
trap cleanup EXIT

# Any port nothing is listening on: several instances share this machine, and two of them on one
# port is two of them failing.
free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# The instance: what the documents call, and what holds the shape from the apply on.
port="${DG_PORT:-$(free_port)}"
devlog=$(mktemp)
uv run dg dev --port "$port" > "$devlog" 2>&1 &
dev_pid=$!

# --retry-all-errors covers the moment between the socket opening and the instance answering.
if ! curl -fs --retry 60 --retry-delay 1 --retry-connrefused --retry-all-errors \
     "http://127.0.0.1:$port/health" > /dev/null; then
  echo "the instance on port $port never answered /health" >&2
  exit 1
fi

# The port is chosen here rather than in the documents, so every run below is handed it.
playground="http://127.0.0.1:$port/api/v1/playground"

# 1. Without a server of its own. A local run starts on an empty throwaway instance, so the schema
# the document requires is handed over rather than looked up.
records=$(uv run dg run --local pipelines/echo-send.yaml \
  --schema schemas/playground-answer.json --json -p "playground=$playground")
printf '%s\n' "$records" | jq -e -s '
  (map(select(.kind == "run")) | last) as $run
  | $run.message == "succeeded"
    and ($run.steps | length) == 3
    and ($run.steps | all(.status == "succeeded"))
' > /dev/null

# The playground answers a POST with the body it was given, under request.body, so its answer is
# the proof of what the send carried out of the gate. The url is the proof of where it was sent.
printf '%s\n' "$records" | jq -e -s --arg pg "$playground" '
  (map(select(.kind == "run")) | last).steps
  | map(select(.step == "send"))
  | all(.output.body.request.body.station == "bergen-florida"
        and .output.body.request.body.reading == "12.4"
        and (.output.body.request.url | startswith($pg + "/request")))
' > /dev/null

# 2. Against the instance, as stored documents.
#
# DG_URL beats the local profile, whose url is the default port; without it every command below
# would address an instance this script did not start. The token comes from dg dev's own admin:
# on an empty state that is the fixture dev / dirigent-dev, and dg auth login mints a token from
# it.
export DG_URL="http://127.0.0.1:$port"
token=$(uv run dg auth login --username dev --password dirigent-dev --json \
  | jq -r 'select(.kind == "token.issued") | .token')
export DG_TOKEN="$token"

# dg schema create refuses a code the instance already holds, so create it only the first time.
if ! uv run dg schema show playground-answer > /dev/null 2>&1; then
  uv run dg schema create schemas/playground-answer.json
fi

# The two-step form first, so that applying the real document is a version with a step in it.
uv run dg apply echo-send-before.yaml > /dev/null

uv run dg apply --json | jq -e -s '
  map(select(.kind == "apply")) | last | .fields.plan
  | .code == "echo-send"
    and .action == "update"
    and (.diff.steps_added | index("send") != null)
' > /dev/null

records=$(uv run dg run echo-send --watch --json -p "playground=$playground")
printf '%s\n' "$records" | jq -e -s '
  (map(select(.kind == "run")) | last) as $run
  | $run.message == "succeeded"
    and $run.exit_code == 0
    and ($run.steps | all(.status == "succeeded"))
' > /dev/null

run_id=$(printf '%s\n' "$records" | jq -r -s 'map(select(.kind == "run")) | last | .run_id')
uv run dg runs show "$run_id" --json | jq -e --arg pg "$playground" '
  .fields.attempts[]
  | select(.step_name == "send")
  | .output.status == 200
    and .output.body.request.body.station == "bergen-florida"
    and .output.body.request.body.reading == "12.4"
    and (.output.body.request.url | startswith($pg + "/request"))
' > /dev/null

# 3. A refused gate skips what waits on it: send never ran, so it is skipped rather than failed.
if records=$(uv run dg run echo-send --watch --json -p "playground=$playground" -p station=); then
  echo "an empty station was meant to be refused at the gate" >&2
  exit 1
fi
printf '%s\n' "$records" | jq -e -s '
  (map(select(.kind == "run")) | last) as $run
  | $run.message == "failed"
    and ($run.steps | map(select(.step == "check")) | all(.status == "failed"))
    and ($run.steps | map(select(.step == "send")) | all(.status == "skipped"))
' > /dev/null

echo "echo-send: documents valid, the send carried the gate's values through to the playground, a refused gate skipped the send"
