#!/usr/bin/env bash
# Run this example end to end and fail if anything about it has moved.
#
# The storage round trip runs anywhere, so it is checked with dg run --local first. The
# report is the half that needs an instance: the engine renders it in the transaction that
# settles the run, and a local run's instance is deleted on the way out with the run in it.
# So this one starts its own `dg dev`, applies, runs, reads the report back, and stops the
# instance again. .dirigent/state survives between runs, so running this twice passes twice.
set -euo pipefail

cd "$(dirname "$0")"

uv sync --quiet

uv run dg validate pipelines/echo-storage.yaml

records=$(mktemp)

# Stdout here is a pipe, so dg writes NDJSON whether or not --json is passed; passing it
# says out loud that the assertions below are on records rather than on rendered text.
uv run dg run --local pipelines/echo-storage.yaml --json >"$records"

# What came off storage is what went on: the same four rows, and as many bytes read as were
# written, because a value is written as canonical JSON and read back the same way.
jq -e -s '
  (map(select(.kind == "run" and has("exit_code"))) | last) as $run
  | ($run.steps | map({key: .step, value: .}) | from_entries) as $step
  | $run.message == "succeeded"
    and ($step.save.output.uri | endswith("/readings-2026-01-01.json"))
    and $step.save.output.content_type == "application/json"
    and $step.back.output.bytes_read == $step.save.output.bytes_written
    and $step.back.output.value.readings == $step.ask.output.body.json.readings
    and $step.summary.output.value.rows == 4
    and $step.summary.output.value.coldest == "tromso-langnes"
' "$records" >/dev/null

echo "echo-storage: the batch made the round trip through the run's scratch space"

# --- the instance ------------------------------------------------------------------------
#
# A port of this script's own, so two verifications never collide and neither takes 3333
# from a dg dev somebody is watching. DG_URL has to name the same port: --port moves the
# server, and the `local` profile dg init wrote still says 3333.
port="${DG_PORT:-$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')}"
export DG_URL="http://127.0.0.1:${port}"

log=$(mktemp)
uv run dg dev --port "$port" >"$log" 2>&1 &
dev=$!
# Stop what this script started, by pid, on whatever it exits on -- never by name: a
# pattern matching `dg dev` matches the shell running this script too.
trap 'kill "$dev" 2>/dev/null || true; wait "$dev" 2>/dev/null || true; rm -f "$log" "$records"' EXIT

for _ in $(seq 60); do
  curl -sf "$DG_URL/health/ready" >/dev/null 2>&1 && break
  sleep 1
done
curl -sf "$DG_URL/health/ready" >/dev/null

# dg init minted this instance's first token and wrote it into .env, where the `local`
# profile reads it. A clone has neither -- no .env, and no instance either -- so dg dev made
# one just now and minted a token into its starting record, once. Whichever it is, it is
# exported here: the CLI reads --url/--token first, then DG_URL/DG_TOKEN, then a profile.
if [ -z "${DG_TOKEN:-}" ] && [ -f .env ]; then
  DG_TOKEN=$(sed -n 's/^DG_TOKEN=//p' .env | head -1)
fi
if [ -z "${DG_TOKEN:-}" ]; then
  DG_TOKEN=$(jq -r 'select(.kind == "process") | .token // empty' "$log" | head -1)
  if [ -n "$DG_TOKEN" ]; then (umask 077; printf 'DG_TOKEN=%s\n' "$DG_TOKEN" >.env); fi
fi
[ -n "${DG_TOKEN:-}" ] || { echo "no token in .env and none minted at startup" >&2; exit 1; }
export DG_TOKEN

uv run dg apply

uv run dg run echo-storage --watch --json >"$records"
run=$(jq -rs '[.[] | select(.kind == "run") | .run_id] | first' "$records")
jq -e -s '(map(select(.kind == "run")) | last).message == "succeeded"' "$records" >/dev/null

# --- the report ---------------------------------------------------------------------------
#
# Into a pipe `dg runs report --markdown` is one run.report_document record carrying the
# whole page; at a terminal the same command writes that page as-is, so it goes into a file
# or a ticket. The template's own lines are what is asserted on, filters and all: 206b came
# through the bytes filter, and the table came through the summary step's output.
uv run dg runs report "$run" --markdown --json | jq -e -s --arg run "$run" '
  ([.[] | select(.kind == "run.report_document")] | first) as $report
  | $report.run_id == $run
    and ($report.document | test("# echo-storage on "))
    and ($report.document | test("\\*\\*succeeded\\*\\* in "))
    and ($report.document | test("readings-2026-01-01.json`, 206b of canonical JSON"))
    and ($report.document | test("\\| 2026-01-01 \\| 4 \\| tromso-langnes \\| 2.5 \\|"))
    and ($report.document | test("- \\*\\*save\\*\\* \\(storage.write\\) succeeded"))
' >/dev/null

echo "echo-storage: run ${run} settled and rendered its own report"
