#!/usr/bin/env bash
# Run this example end to end and assert on the records, never on the rendering: a table is
# what a terminal makes of a record, and this script has no terminal.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

uv sync

uv run dg validate pipelines/echo-hello.yaml

records=$(uv run dg run --local pipelines/echo-hello.yaml --json)

# The last run record carries the whole settled run: its message, its exit code, and one entry
# per step with that step's own status.
printf '%s\n' "$records" | jq -e -s '
  (map(select(.kind == "run")) | last) as $run
  | $run.message == "succeeded"
    and $run.exit_code == 0
    and ($run.steps | length) == 2
    and ($run.steps | all(.status == "succeeded"))
' > /dev/null

# The reference resolved: the line say wrote carries what make produced.
printf '%s\n' "$records" | jq -e -s '
  any(.[]; .kind == "log"
      and .step == "say"
      and .message == "the step before me said: hello from dirigent")
' > /dev/null

echo "echo-hello: document valid, local run succeeded, reference resolved"
