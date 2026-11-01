#!/usr/bin/env bash
# Run this example end to end and fail if anything about it has moved.
#
# The storage round trip runs anywhere, so it is checked with dg run --local first. The
# report is the half that needs an instance: the engine renders it in the transaction that
# settles the run, and a local run's instance is deleted on the way out with the run in it.
# So this one starts its own `dg dev`, applies, runs, reads the report back, and stops the
# instance again. .dirigent/state survives between runs, so running this twice passes twice.
#
# The document itself reaches nothing, so no network is needed for either half.
set -euo pipefail

cd "$(dirname "$0")"

uv sync --quiet

uv run dg validate pipelines/echo-storage.yaml

dev_pid=
records=$(mktemp)
log=$(mktemp)

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

# Whatever this script started is stopped by its pid, however this script ends -- never by
# name: a pattern matching `dg dev` matches the shell running this script too. The
# instance's wrapper has its children taken first: killing `uv run` alone leaves the dg dev
# under it on the port.
cleanup() {
  if [ -n "$dev_pid" ]; then
    pkill -TERM -P "$dev_pid" 2>/dev/null || true
    kill -TERM "$dev_pid" 2>/dev/null || true
    wait "$dev_pid" 2>/dev/null || true
  fi
  port_clear "${port:-}"
  rm -f "$records" "$log"
}
trap cleanup EXIT

# Any port nothing is listening on, so two verifications never collide and neither takes
# 3333 from a dg dev somebody is watching.
free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# --- the round trip, without a server at all -----------------------------------------------
#
# Stdout here is a pipe, so dg writes NDJSON whether or not --json is passed; passing it
# says out loud that the assertions below are on records rather than on rendered text.
#
# What came off storage is what went on: the same four rows, and as many bytes read as were
# written, because a value is written as canonical JSON and read back the same way.
uv run dg run --local pipelines/echo-storage.yaml --json >"$records"

jq -e -s '
  (map(select(.kind == "run" and has("exit_code"))) | last) as $run
  | ($run.steps | map({key: .step, value: .}) | from_entries) as $step
  | $run.message == "succeeded"
    and ($step.save.output.uri | endswith("/readings-2026-01-01.json"))
    and $step.save.output.content_type == "application/json"
    and $step.back.output.bytes_read == $step.save.output.bytes_written
    and $step.back.output.value.readings == $step.readings.output.records
    and $step.summary.output.value.rows == 4
    and $step.summary.output.value.coldest == "tromso-langnes"
' "$records" >/dev/null

echo "echo-storage: the batch made the round trip through the run's scratch space"

# --- the instance ------------------------------------------------------------------------
port="${DG_PORT:-$(free_port)}"
uv run dg dev --port "$port" >"$log" 2>&1 &
dev_pid=$!

for _ in $(seq 60); do
  curl -sf "http://127.0.0.1:$port/health/ready" >/dev/null 2>&1 && break
  sleep 1
done
curl -sf "http://127.0.0.1:$port/health/ready" >/dev/null

# DG_URL beats the local profile, whose url is the default port; without it every command
# below would address an instance this script did not start. The token comes from dg dev's
# own admin: on an empty state that is the fixture admin / admin, and dg auth login
# mints a token of its own from it.
export DG_URL="http://127.0.0.1:$port"
DG_TOKEN=$(uv run dg auth login --username admin --password admin --json \
  | jq -r 'select(.kind == "token.issued") | .token')
export DG_TOKEN
[ -n "$DG_TOKEN" ]

# Applying an unchanged document again is not a new version, so this passes on every run.
uv run dg apply

# --- the report ---------------------------------------------------------------------------
#
# Into a pipe `dg runs report --markdown` is one run.report_document record carrying the
# whole page; at a terminal the same command writes that page as-is, so it goes into a file
# or a ticket. The template's own lines are what is asserted on, filters and all: 206b came
# through the bytes filter, and the table came through the summary step's output.
uv run dg run echo-storage --watch --json >"$records"
run=$(jq -rs '[.[] | select(.kind == "run") | .run_id] | first' "$records")
jq -e -s '(map(select(.kind == "run")) | last).message == "succeeded"' "$records" >/dev/null

uv run dg runs report "$run" --markdown --json | jq -e -s --arg run "$run" '
  ([.[] | select(.kind == "run.report_document")] | first) as $report
  | $report.run_id == $run
    and ($report.document | test("# echo-storage on "))
    and ($report.document | test("\\*\\*succeeded\\*\\* in "))
    and ($report.document | test("readings-2026-01-01.json`, 206b of canonical JSON"))
    and ($report.document | test("\\| 2026-01-01 \\| 4 \\| tromso-langnes \\| 2.5 \\|"))
    and ($report.document | test("- \\*\\*save\\*\\* \\(storage.write\\) succeeded"))
' >/dev/null

echo "echo-storage: run ${run} settled and rendered its own report, with nothing called"
