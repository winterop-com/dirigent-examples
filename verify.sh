#!/usr/bin/env bash
# Run this example end to end and assert on the records, never on the rendering: a table is
# what a terminal makes of a record, and this script has no terminal.
#
# Two of the runs below fail on purpose, so their non-zero exit is the expected outcome and what
# is asserted is the error the records carry.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

uv sync

for document in echo-gate-too-tight.yaml echo-gate-carried.yaml pipelines/echo-gate.yaml; do
  uv run dg validate "$document"
done

# 1. The gate refuses what it was given, because a query argument is text.
if records=$(uv run dg run --local echo-gate-too-tight.yaml --json); then
  echo "echo-gate-too-tight was meant to fail at the gate" >&2
  exit 1
fi
printf '%s\n' "$records" | jq -e -s '
  (map(select(.kind == "run")) | last) as $run
  | $run.message == "failed"
    and $run.exit_code == 1
    and ($run.steps | map(select(.step == "ask")) | all(.status == "succeeded"))
    and ($run.steps | map(select(.step == "check")) | all(.status == "failed"))
' > /dev/null
printf '%s\n' "$records" | jq -e -s '
  (map(select(.kind == "run")) | last).failures
  | any(.step == "check"
        and .error_class == "rejected"
        and (.error | test("\\$\\.args\\.reading")))
' > /dev/null

# 2. The same gate with the line fixed, and its schema still carried in the document.
records=$(uv run dg run --local echo-gate-carried.yaml --json)
printf '%s\n' "$records" | jq -e -s '
  (map(select(.kind == "run")) | last) as $run
  | $run.message == "succeeded" and ($run.steps | all(.status == "succeeded"))
' > /dev/null

# 3. Against an instance this script starts and stops.
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

# 4. A server stores no schema a document carries.
if refusal=$(uv run dg apply echo-gate-carried.yaml --json); then
  echo "a document carrying its own schemas was meant to be refused" >&2
  exit 1
fi
printf '%s\n' "$refusal" | jq -e -s '
  any(.[]; .kind == "error"
      and .status == 422
      and (.message | test("carries its own schemas")))
' > /dev/null

# 5. So the instance holds the shape instead. dg schema create refuses a code the instance
# already has, which is why this asks first.
if ! uv run dg schema show echo-answer > /dev/null 2>&1; then
  uv run dg schema create schemas/echo-answer.json
fi

uv run dg apply

records=$(uv run dg run echo-gate --watch --json)
printf '%s\n' "$records" | jq -e -s '
  (map(select(.kind == "run")) | last) as $run
  | $run.message == "succeeded"
    and $run.exit_code == 0
    and ($run.steps | all(.status == "succeeded"))
' > /dev/null

# The gate hands its input on unchanged, which is what makes it a waypoint.
run_id=$(printf '%s\n' "$records" | jq -r -s 'map(select(.kind == "run")) | last | .run_id')
uv run dg runs show "$run_id" --json | jq -e '
  .fields.attempts[]
  | select(.step_name == "check")
  | .output.value.args.station == "bergen-florida"
    and .output.value.args.reading == "12.4"
' > /dev/null

# 6. An empty station is a string the schema will not have, and nothing downstream sees it.
if records=$(uv run dg run echo-gate --watch -p station= --json); then
  echo "an empty station was meant to be refused at the gate" >&2
  exit 1
fi
printf '%s\n' "$records" | jq -e -s '
  (map(select(.kind == "run")) | last) as $run
  | $run.message == "failed"
    and ($run.steps | map(select(.step == "check")) | all(.status == "failed"))
' > /dev/null
printf '%s\n' "$records" | jq -e -s '
  (map(select(.kind == "run")) | last).failures
  | any(.step == "check"
        and .error_class == "rejected"
        and (.error | test("\\$\\.args\\.station")))
' > /dev/null

echo "echo-gate: documents valid, the gate refused twice as written, the carried schema refused at apply, the lifted schema gated a run"
