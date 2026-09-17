#!/usr/bin/env bash
# Run this example end to end and fail if anything about it has moved.
#
# Nothing here needs a server: dg run --local applies and runs the document in a throwaway
# instance in a temporary directory and deletes it on the way out. Run it as often as you
# like; it leaves nothing behind but .venv/.
set -euo pipefail

cd "$(dirname "$0")"

uv sync --quiet

uv run dg validate pipelines/echo-fanout.yaml

# Stdout here is a pipe, so dg writes NDJSON whether or not --json is passed; passing it
# says out loud that the assertions below are on records rather than on rendered text.
#
# The run settles completed_with_errors by design and dg exits 0 on that with a warning, so
# the outcome is read off the final run record rather than off the exit status. That record
# carries every step and every item, which is why one jq program can check the whole run.
records=$(mktemp)
trap 'rm -f "$records"' EXIT

uv run dg run --local pipelines/echo-fanout.yaml --json >"$records"

jq -e -s '
  (map(select(.kind == "run" and has("exit_code"))) | last) as $run
  | ($run.steps | map(select(.step == "ask"))) as $items
  | ($run.steps | map(select(.step == "report")) | first) as $report
  | $run.message == "completed_with_errors"
    and ($items | map(select(.status == "succeeded")) | length) == 2
    and ($items | map(select(.status == "failed")) | length) == 1
    and $report.status == "succeeded"
    and $report.output.value.asked == 3
    and $report.output.value.answered == 2
    and $report.output.value.missing == ["oslo-blindern"]
' "$records" >/dev/null

echo "echo-fanout: completed_with_errors, two stations answered, oslo-blindern missing"
