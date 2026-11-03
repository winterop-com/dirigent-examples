#!/usr/bin/env bash
# Run this example end to end and fail if anything about it has moved.
#
# Both documents run anywhere, so they are checked with dg run --local first: the page the
# report.render step wrote, the log line whose list, object and boolean arrived as JSON, and
# what plan says about a `report:` pointing at the wrong step. The reports themselves need an
# instance: the engine stores one in the transaction that settles the run, and a local run's
# instance is deleted on the way out with the run in it. So this starts its own `dg dev`,
# applies, runs both, reads each report back, and stops the instance again. .dirigent/state
# survives between runs, so running this twice passes twice.
#
# Neither document reaches anything, so no network is needed.
set -euo pipefail

cd "$(dirname "$0")"

uv sync --quiet

uv run dg validate pipelines/

dev_pid=
records=$(mktemp)
log=$(mktemp)
scratch=$(mktemp -d)

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
  rm -f "$records" "$log" "$scratch"/*.yaml "$scratch"/*.ndjson
  rmdir "$scratch" 2>/dev/null || true
}
trap cleanup EXIT

# Any port nothing is listening on, so two verifications never collide and neither takes
# 3333 from a dg dev somebody is watching.
free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# --- what plan says, without a server -----------------------------------------------------
#
# `from` naming a step whose block hands on no text is refused at report.from; a
# report.render step with no `report:` at all is valid, with a warning naming the line that
# would make it the run's report.
sed 's/^  from: page$/  from: summary/' pipelines/echo-report.yaml >"$scratch/wrong-step.yaml"
grep -v -e '^report:$' -e '^  from: page$' pipelines/echo-report.yaml >"$scratch/no-report.yaml"

# An invalid document exits non-zero, so the records are kept and read rather than piped.
uv run dg validate "$scratch/wrong-step.yaml" --json >"$records" || true
jq -e -s '
  ([.[] | select(.kind == "validation")] | first) as $v
  | $v.message == "invalid"
    and ($v.problems | any(.code == "document.report_step_no_text" and .location == "report.from"))
' "$records" >/dev/null

uv run dg validate "$scratch/no-report.yaml" --json | jq -e -s '
  ([.[] | select(.kind == "validation")] | first) as $v
  | $v.message == "valid"
    and ($v.warnings | any(.code == "document.report_render_unseen" and .location == "steps.page"))
' >/dev/null

echo "echo-report: plan refuses a report from a step with no text, and warns about a page nobody reads"

# --- the runs, without a server -----------------------------------------------------------
#
# Stdout here is a pipe, so dg writes NDJSON whether or not --json is passed; passing it
# says out loud that the assertions below are on records rather than on rendered text.
uv run dg run --local pipelines/echo-report.yaml -p day=2026-01-02 --json >"$records"

jq -e -s '
  (map(select(.kind == "run" and has("exit_code"))) | last) as $run
  | ($run.steps | map({key: .step, value: .}) | from_entries) as $step
  | $run.message == "succeeded"
    and $step.summary.output.value.all_above_freezing == false
    and ($step.page.output.text | startswith("# Readings for 2026-01-02\n"))
    and ($step.page.output.text | test("\\| tromso-langnes \\|"))
    and $step.page.output.content_type == "text/markdown"
' "$records" >/dev/null

# Inside a longer string a list and an object are compact JSON and a boolean is `false`.
jq -e -s '
  any(.[]; .kind == "log" and .step == "say"
      and .message == "stations [\"bergen-florida\",\"oslo-blindern\",\"tromso-langnes\",\"trondheim-voll\"], coldest {\"station\":\"tromso-langnes\",\"celsius\":-6.8}, all above freezing: false")
' "$records" >/dev/null

echo "echo-report: the page rendered, and the log line read its values as JSON"

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

# Applying unchanged documents again is not a new version, so this passes on every run.
uv run dg apply

# --- what plan says about a changed report -----------------------------------------------
#
# A version whose only change is its report is planned as an update with report_changed and
# nothing else, and a dry run writes nothing.
sed 's/: readings above/: stations above/' pipelines/echo-report-params.yaml >"$scratch/heading.yaml"
uv run dg apply "$scratch/heading.yaml" --dry-run --json | jq -e -s '
  ([.[] | select(.kind == "apply")] | first).fields as $f
  | $f.dry_run == true and $f.plan.action == "update"
    and $f.plan.diff == {steps_added: [], steps_removed: [], steps_changed: [],
                         params_changed: false, triggers_changed: false,
                         requires_changed: false, report_changed: true, settings_changed: false}
' >/dev/null

echo "echo-report: a version changing its report alone is planned as report_changed"

# --- the report a step wrote ----------------------------------------------------------------
#
# The run's report is the page step's text as it was, rendered no further.
uv run dg run echo-report -p day=2026-01-02 --watch --json >"$records"
run=$(jq -rs '[.[] | select(.kind == "run") | .run_id] | first' "$records")
jq -e -s '(map(select(.kind == "run")) | last).message == "succeeded"' "$records" >/dev/null

uv run dg runs report "$run" --markdown --json >"$scratch/report.ndjson"
jq -e -n --arg run "$run" --slurpfile watched "$records" --slurpfile report "$scratch/report.ndjson" '
  ($watched | map(select(.kind == "run" and has("exit_code"))) | last
     | .steps[] | select(.step == "page") | .output.text) as $page
  | ($report | map(select(.kind == "run.report_document")) | first) as $doc
  | $doc.run_id == $run
    and $doc.document == $page
    and ($page | test("\n\n\\| Station \\|\n\\| --- \\|\n"))
' >/dev/null

echo "echo-report: run ${run}'s report is the text its page step rendered"

# --- the report a template wrote, reading params -------------------------------------------
uv run dg run echo-report-params -p threshold=0 --watch --json >"$records"
run=$(jq -rs '[.[] | select(.kind == "run") | .run_id] | first' "$records")
jq -e -s '(map(select(.kind == "run")) | last).message == "succeeded"' "$records" >/dev/null

uv run dg runs report "$run" --markdown --json | jq -e -s '
  ([.[] | select(.kind == "run.report_document")] | first).document as $doc
  | ($doc | test("# echo-report-params: readings above 0 C"))
    and ($doc | test("strict: false"))
    and ($doc | test("3 stations: bergen-florida, oslo-blindern, trondheim-voll"))
    and ($doc | test("Asked with `\\{\"threshold\":0,\"strict\":false\\}`"))
' >/dev/null

echo "echo-report: run ${run}'s report named the parameters it was asked with"
