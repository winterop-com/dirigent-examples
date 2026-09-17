#!/usr/bin/env bash
# Run this example end to end and assert on the records, never on the rendering: a table is
# what a terminal makes of a record, and this script has no terminal.
#
# One of the runs below fails on purpose, so its non-zero exit is the expected outcome and what is
# asserted is which step failed and which step never ran at all.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

uv sync

for document in echo-send-before.yaml pipelines/echo-send.yaml; do
  uv run dg validate "$document"
done

# 1. Without a server. A local run starts on an empty throwaway instance, so the schema the
# document requires is handed over rather than looked up.
records=$(uv run dg run --local pipelines/echo-send.yaml --schema schemas/echo-answer.json --json)
printf '%s\n' "$records" | jq -e -s '
  (map(select(.kind == "run")) | last) as $run
  | $run.message == "succeeded"
    and ($run.steps | length) == 3
    and ($run.steps | all(.status == "succeeded"))
' > /dev/null

# Postman Echo answers a POST with the body it was given, so its answer is the proof of what the
# send carried out of the gate.
printf '%s\n' "$records" | jq -e -s '
  (map(select(.kind == "run")) | last).steps
  | map(select(.step == "send"))
  | all(.output.body.json.station == "bergen-florida"
        and .output.body.json.reading == "12.4")
' > /dev/null

# 2. Against an instance this script starts and stops.
#
# $DG_PORT, or any port nothing is listening on: several instances share this machine, and two
# of them on one port is two of them failing.
port="${DG_PORT:-$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')}"
devlog=$(mktemp)
uv run dg dev --port "$port" > "$devlog" 2>&1 &
dev_pid=$!
# The instance this script started is stopped by its pid, however this script ends.
trap 'kill "$dev_pid" 2>/dev/null || true; wait "$dev_pid" 2>/dev/null || true' EXIT

# --retry-all-errors covers the moment between the socket opening and the instance answering.
if ! curl -fs --retry 60 --retry-delay 1 --retry-connrefused --retry-all-errors \
     "http://127.0.0.1:$port/health" > /dev/null; then
  echo "the instance on port $port never answered /health" >&2
  exit 1
fi

# DG_URL beats the local profile, whose url is the default port; without it every command below
# would address an instance this script did not start. The token comes from dg dev's own admin:
# on an empty state that is the fixture dev / dirigent-dev, and dg auth login mints a token from
# it, which is the same token dg dev printed at startup.
export DG_URL="http://127.0.0.1:$port"
token=$(uv run dg auth login --username dev --password dirigent-dev --json \
  | jq -r 'select(.kind == "token.issued") | .token')
export DG_TOKEN="$token"

# dg schema create refuses a code the instance already holds, so create it only the first time.
if ! uv run dg schema show echo-answer > /dev/null 2>&1; then
  uv run dg schema create schemas/echo-answer.json
fi

# The two-step form first, so that applying the real document is a version with a step in it.
uv run dg apply echo-send-before.yaml > /dev/null

uv run dg apply --json | jq -e -s '
  map(select(.kind == "apply")) | last | .fields.plan
  | .code == "echo-send"
    and .action == "update"
    and (.diff.steps_added | index("send") != null)
' > /dev/null

records=$(uv run dg run echo-send --watch --json)
printf '%s\n' "$records" | jq -e -s '
  (map(select(.kind == "run")) | last) as $run
  | $run.message == "succeeded"
    and $run.exit_code == 0
    and ($run.steps | all(.status == "succeeded"))
' > /dev/null

run_id=$(printf '%s\n' "$records" | jq -r -s 'map(select(.kind == "run")) | last | .run_id')
uv run dg runs show "$run_id" --json | jq -e '
  .fields.attempts[]
  | select(.step_name == "send")
  | .output.status == 200
    and .output.body.json.station == "bergen-florida"
    and .output.body.json.reading == "12.4"
' > /dev/null

# 3. A refused gate skips what waits on it: send never ran, so it is skipped rather than failed.
if records=$(uv run dg run echo-send --watch -p station= --json); then
  echo "an empty station was meant to be refused at the gate" >&2
  exit 1
fi
printf '%s\n' "$records" | jq -e -s '
  (map(select(.kind == "run")) | last) as $run
  | $run.message == "failed"
    and ($run.steps | map(select(.step == "check")) | all(.status == "failed"))
    and ($run.steps | map(select(.step == "send")) | all(.status == "skipped"))
' > /dev/null

echo "echo-send: documents valid, the send carried the gate's values through, a refused gate skipped the send"
