#!/usr/bin/env bash
# Run this example end to end and fail if anything about it has moved.
#
# Nothing here needs a server: dg run --local applies and runs the document in a throwaway
# instance in a temporary directory and deletes it on the way out. Run it as often as you
# like; it leaves nothing behind but .venv/.
set -euo pipefail

cd "$(dirname "$0")"

uv sync --quiet

uv run dg validate pipelines/echo-transform.yaml

# Stdout here is a pipe, so dg writes NDJSON whether or not --json is passed; passing it
# says out loud that the assertions below are on records rather than on rendered text. The
# final run record carries every step's output, so one jq program checks the whole chain.
records=$(mktemp)
trap 'rm -f "$records"' EXIT

uv run dg run --local pipelines/echo-transform.yaml --json >"$records"

# Each verb is held to its own contract: the filter dropped one of four and modified
# nothing, the map returned exactly as many as it was given, the transform turned the list
# into one object, and the send's answer is Postman Echo repeating what it received.
jq -e -s '
  (map(select(.kind == "run" and has("exit_code"))) | last) as $run
  | ($run.steps | map({key: .step, value: .}) | from_entries) as $step
  | $run.message == "succeeded"
    and ($step.active.output.value | length) == 3
    and ($step.active.output.value | map(has("celsius")) | all)
    and ($step.fahrenheit.output.value | length) == ($step.active.output.value | length)
    and $step.summary.output.value.stations == 3
    and $step.summary.output.value.warmest == "bergen-florida"
    and $step.send.output.status == 200
    and $step.send.output.body.json == $step.summary.output.value
' "$records" >/dev/null

echo "echo-transform: succeeded, 4 readings filtered to 3, mapped, reduced, and echoed back"
