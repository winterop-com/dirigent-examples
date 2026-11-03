#!/usr/bin/env bash
# Run this example end to end, against the real play demo, and exit non-zero the moment
# anything it claims stops being true.
#
# Every assertion below reads records rather than rendered text: --json asks for the records
# even at a terminal, and a table is only a rendering of one. Both documents run locally, so
# nothing here starts an instance or holds a port.
set -euo pipefail

cd "$(dirname "$0")"

# Somewhere to keep the streams this script asserts on, removed on the way out.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say() { printf '\n== %s\n' "$1"; }

say "the project's own environment"
uv sync --quiet

say "every document, checked offline"
uv run dg validate --json > "$WORK/validate.ndjson"
jq -se '
  map(select(.kind == "validated")) | last
  | if .documents == 2 and .invalid == 0 then true
    else error("\(.invalid) of \(.documents) document(s) refused") end
' "$WORK/validate.ndjson" > /dev/null

say "four reads, run locally against the play demo"
SINCE=2017-10-01
uv run dg run --local pipelines/dhis2-reads.yaml \
  --connections connections.yaml -p "since=$SINCE" \
  --json > "$WORK/reads.ndjson" || true

jq -se --arg since "$SINCE" '
  (map(select(.kind == "run" and has("exit_code"))) | last) as $run
  | ($run.steps | map({key: .step, value: .output}) | from_entries) as $out
  | if $run.message != "succeeded" then
      error("the run settled \($run.message): \($run.failures // [] | map("\(.step): \(.error)") | join("; "))")
    # Which DHIS2 answered: the demo addressed as 2.42 is a 2.42 release.
    elif ($out.info.version | startswith("2.42") | not) then error("system info says \($out.info.version)")
    # Two collections in one export, each counted, and the count is the rows it holds.
    elif ($out.holdings.counts | keys) != ["dataSets", "programs"] then error("the export answered \($out.holdings.counts | keys)")
    elif ($out.holdings.collections | to_entries | any(.value | length == 0)) then error("a collection came back empty")
    elif ($out.holdings.collections | to_entries | any((.value | length) != $out.holdings.counts[.key])) then error("a count does not match its rows")
    elif ($out.holdings.collections.dataSets | any(has("periodType") | not)) then error("dataSets were not read with their own fields")
    # The incremental export: values, every one of them changed at or after the date.
    elif ($out.changed.body.dataValues | length) == 0 then error("nothing changed since \($since)")
    elif ($out.changed.body.dataValues | any(.lastUpdated[0:10] < $since)) then error("a value older than \($since) was exported")
    # Every page, one list: more than one page was read, none is left, and no row twice.
    elif ($out.children.rows | length) <= $out.children.pager.page_size then error("the tracker read held one page")
    elif $out.children.pager.more then error("the tracker read left pages unread")
    elif ($out.children.rows | map(.trackedEntity) | unique | length) != ($out.children.rows | length) then error("a tracked entity was read twice")
    else true end
' "$WORK/reads.ndjson" > /dev/null

say "the same tracker read, capped below what the facility holds"
# Fails by design, so dg exits non-zero and the run record is what is read.
uv run dg run --local pipelines/dhis2-reads-capped.yaml \
  --connections connections.yaml --json > "$WORK/capped.ndjson" || true

jq -se '
  (map(select(.kind == "run" and has("exit_code"))) | last) as $run
  | ($run.failures | map(select(.step == "children"))) as $f
  | if $run.message != "failed" then error("the capped read settled \($run.message)")
    # One attempt of three: a rejected failure spends no retry, because reading again
    # would reach the same bound.
    elif ($f | length) != 1 then error("the capped read failed \($f | length) times")
    elif $f[0].error_class != "rejected" then error("the cap was classed \($f[0].error_class)")
    elif ($f[0].error | test("max_rows \\(20\\)") | not) then error("the failure does not name max_rows: \($f[0].error)")
    else true end
' "$WORK/capped.ndjson" > /dev/null

say "ok: dhis2-reads read four ways, and the capped read refused to answer part of a collection"
