#!/usr/bin/env bash
# Run this example end to end, against the real play demo, and exit non-zero the moment
# anything it claims stops being true.
#
# Every assertion below reads records rather than rendered text: --json asks for the records
# even at a terminal, and a table is only a rendering of one. The document runs locally, so
# nothing here starts an instance or holds a port.
set -euo pipefail

cd "$(dirname "$0")"

CODE=dhis2-writes-rehearsed

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
  | if .invalid == 0 then true else error("\(.invalid) document(s) refused") end
' "$WORK/validate.ndjson" > /dev/null

say "every write in the document is a rehearsal"
# Before anything is sent: the play demo is shared, and a write step without dry_run: true
# would really write. A data_value get reads, and is the one write block allowed without it.
uv run python - "pipelines/$CODE.yaml" <<'PY'
import sys

import yaml

writes = {
    "dhis2.metadata_import",
    "dhis2.data_value",
    "dhis2.tracker_import",
    "dhis2.data_set_completion",
    "dhis2.data_value_set_import",
}
steps = yaml.safe_load(open(sys.argv[1]))["steps"]
live = [
    name
    for name, step in steps.items()
    if step.get("block") in writes
    and step["config"].get("action", "set") != "get"
    and step["config"].get("dry_run") is not True
]
if live:
    sys.exit(f"these steps would write to the play demo: {', '.join(live)}")
PY

say "five writes, rehearsed against the play demo"
uv run dg run --local "pipelines/$CODE.yaml" \
  --connections connections.yaml --json > "$WORK/run.ndjson" || true

jq -se '
  (map(select(.kind == "run" and has("exit_code"))) | last) as $run
  | ($run.steps | map({key: .step, value: .output}) | from_entries) as $out
  | if $run.message != "succeeded" then
      error("the run settled \($run.message): \($run.failures // [] | map("\(.step): \(.error)") | join("; "))")
    # Every write answered as a rehearsal.
    elif ([$out.element, $out.value, $out.visit, $out.sign_off] | any(.dry_run != true)) then error("a write did not run as a dry run")
    # The data element: one object sent, one the instance would have created, nothing refused.
    elif $out.element.status != "OK" then error("the metadata rehearsal came back \($out.element.status)")
    elif $out.element.sent != 1 or $out.element.counts.imported != 1 then error("the metadata rehearsal would not create the one element")
    elif ($out.element.conflicts | length) != 0 then error("the metadata rehearsal reported conflicts")
    # The cell: rehearsed at the new value, and read back holding what it held before.
    elif $out.value.value == $out.before.value then error("the rehearsed value is the stored one, which proves nothing")
    elif $out.after.value != $out.before.value then error("the cell moved from \($out.before.value) to \($out.after.value)")
    # The event: the tracker importer validated it as a job and refused nothing.
    elif $out.visit.status != "OK" or $out.visit.job_id == null then error("the tracker rehearsal came back \($out.visit.status)")
    elif ($out.visit.conflicts | length) != 0 then error("the tracker rehearsal reported conflicts")
    # The sign-off: one registration, taken.
    elif $out.sign_off.status != "SUCCESS" or $out.sign_off.completed != true then error("the sign-off came back \($out.sign_off.status)")
    elif $out.sign_off.counts.ignored != 0 then error("the sign-off was ignored")
    # The CSV: a file of codes, every row sent, and every code resolved. The demo already
    # holds each value, so DHIS2 ignores them as unchanged; a code it could not resolve would
    # be a conflict (E7610), and the import a WARNING.
    elif ($out.export.text | split("\n") | .[1] | test("^DE_[^,]*,[^,]*,OU_") | not) then error("the export does not name things by code")
    elif $out.csv.sent == 0 then error("the CSV rehearsal sent nothing")
    elif $out.csv.status != "SUCCESS" or ($out.csv.conflicts | length) != 0 then error("the CSV rehearsal came back \($out.csv.status): \($out.csv.conflicts[0:3])")
    elif ($out.csv.counts | .imported + .updated + .ignored) != $out.csv.sent then error("the CSV rehearsal lost rows")
    else true end
' "$WORK/run.ndjson" > /dev/null

say "ok: $CODE rehearsed five writes and the play demo kept what it held"
