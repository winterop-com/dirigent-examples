#!/usr/bin/env bash
# Run this example end to end, against the real play demo, and exit non-zero the moment
# anything it claims stops being true.
#
# Every assertion below reads records rather than rendered text: --json asks for the records
# even at a terminal, and a table is only a rendering of one. Every document runs locally, so
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
  | if .documents == 3 and .invalid == 0 then true
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

say "five more reads: CSV and ADX, the data store, a SQL view, validation rules"
uv run dg run --local pipelines/dhis2-reads-more.yaml \
  --connections connections.yaml --json > "$WORK/more.ndjson" || true

jq -se '
  (map(select(.kind == "run" and has("exit_code"))) | last) as $run
  | ($run.steps | map({key: .step, value: .output}) | from_entries) as $out
  | if $run.message != "succeeded" then
      error("the run settled \($run.message): \($run.failures // [] | map("\(.step): \(.error)") | join("; "))")
    # A text export is not parsed: it is in storage at uri, its head inline, and no body.
    elif [$out.csv, $out.adx] | any(.body != null or .uri == null or .content_bytes == 0) then error("a text export left no file")
    elif ($out.csv.text | split("\n") | first | startswith("dataelement,period,orgunit") | not) then error("the CSV has no header row")
    # data_element_id_scheme: CODE writes codes, not the uid s46m5MS0hxu of BCG doses given.
    elif ($out.csv.text | split("\n") | .[1] | startswith("DE_") | not) then error("the CSV names data elements by uid")
    elif ($out.adx.text | startswith("<adx ") | not) then error("the ADX export is not ADX")
    # The data store: a namespace listed, and its first key read back by a dotted index.
    elif ($out.keys.rows | length) == 0 then error("the namespace holds no key")
    elif $out.first.key != $out.keys.rows[0] or $out.first.found != true then error("the first key was not read")
    # The SQL view: rows keyed by column, every one of the value type asked for.
    elif ($out.view.rows | length) == 0 then error("the SQL view answered no rows")
    elif ($out.view.rows | any(.valuetype != "LONG_TEXT")) then error("the SQL view ignored its variable")
    # Validation rules: violations named, at most max_results.
    elif $out.validate.count != ($out.validate.violations | length) or $out.validate.count > 50 then error("the analysis count is off")
    elif ($out.validate.violations | any(.validation_rule == null or .period == null)) then error("a violation names no rule or period")
    else true end
' "$WORK/more.ndjson" > /dev/null

say "ok: dhis2-reads read four ways and five more, and the capped read refused to answer part of a collection"
