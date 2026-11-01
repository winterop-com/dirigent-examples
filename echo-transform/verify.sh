#!/usr/bin/env bash
# Run this example end to end and fail if anything about it has moved.
#
# Nothing here needs a server or a network: dg run --local applies and runs the document in a
# throwaway instance in a temporary directory and deletes it on the way out, and the document
# reaches nothing. Run it as often as you like; it leaves nothing behind but .venv/.
set -euo pipefail

cd "$(dirname "$0")"

uv sync --quiet

uv run dg validate pipelines/echo-transform.yaml

records=$(mktemp)
trap 'rm -f "$records"' EXIT

# Stdout here is a pipe, so dg writes NDJSON whether or not --json is passed; passing it
# says out loud that the assertions below are on records rather than on rendered text. The
# final run record carries every step's output, so one jq program checks the whole chain.
#
# Each verb is held to its own contract: the filter dropped one of four and modified
# nothing, the map returned exactly as many as it was given, the transform turned the list
# into one object, and the sink handed that object on unchanged.
uv run dg run --local pipelines/echo-transform.yaml --json >"$records"

jq -e -s '
  (map(select(.kind == "run" and has("exit_code"))) | last) as $run
  | ($run.steps | map({key: .step, value: .}) | from_entries) as $step
  | $run.message == "succeeded"
    and ($step.readings.output.records | length) == 4
    and ($step.active.output.value | length) == 3
    and ($step.active.output.value | map(has("celsius")) | all)
    and ($step.fahrenheit.output.value | length) == ($step.active.output.value | length)
    and $step.summary.output.value.stations == 3
    and $step.summary.output.value.warmest == "bergen-florida"
    and $step.say.output.value == $step.summary.output.value
' "$records" >/dev/null

# The summary reached the run's own timeline, which is where this document's sink is.
jq -e -s '
  any(.[]; .kind == "log"
      and .step == "say"
      and .message == "the three verbs are done"
      and .fields.value.stations == 3)
' "$records" >/dev/null

echo "echo-transform: succeeded, 4 readings filtered to 3, mapped, reduced, and logged, with nothing called"
