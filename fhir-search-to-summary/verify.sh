#!/usr/bin/env bash
# Run this example end to end against a local HAPI FHIR server it starts itself, and exit non-zero
# the moment anything it claims stops being true. Nothing it does reaches the internet once the
# image is pulled: the server is a container on 127.0.0.1.
#
# Every assertion below reads records or FHIR JSON rather than rendered text: --json asks for the
# records even at a terminal, and a table is only a rendering of one.
set -euo pipefail

cd "$(dirname "$0")"

CODE=fhir-search-to-summary
GATE=fhir-validate-gate
COMPOSE=(docker compose -p dirigent-example-fhir-search-to-summary -f hapi/compose.yaml)
export FHIR_PORT="${FHIR_PORT:-9821}"
FHIR="http://127.0.0.1:$FHIR_PORT/fhir"

WORK="$(mktemp -d)"

cleanup() {
  # The server, by its own project name, so the next run starts from an empty one.
  "${COMPOSE[@]}" down -v --remove-orphans > /dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

say() { printf '\n== %s\n' "$1"; }

# The last run record in a stream is how the run settled.
assert_run_succeeded() {
  jq -se --arg what "$2" '
    map(select(.kind == "run")) | last
    | if . == null then error("\($what): the stream carries no run record")
      elif .message == "succeeded" then true
      else error("\($what): the run settled \(.message): \(.failures // [] | map("\(.step): \(.error)") | join("; "))") end
  ' "$1" > /dev/null
}

# One step's output in a run's stream.
output_of() {
  jq -se --arg step "$2" 'map(select(.kind == "run")) | last | .steps | map(select(.step == $step)) | last | .output' "$1"
}

# What the seed says a limit should keep: every observation's identifier and value over it, and
# the identifiers of the patients they are about.
expected() {
  jq --argjson limit "$1" '
    [.entry[].resource] as $all
    | ($all | map(select(.resourceType == "Patient"))) as $patients
    | [.entry[] | {url: .fullUrl, r: .resource}] as $entries
    | ($entries | map(select(.r.resourceType == "Patient")) | map({key: .url, value: .r.identifier[0].value}) | from_entries) as $mrn
    | $all | map(select(.resourceType == "Observation" and .valueQuantity.value > $limit))
    | {weights: (map(.valueQuantity.value) | sort), patients: (map($mrn[.subject.reference]) | unique)}
  ' seed/source.json
}

# What a run kept: the values `weights` read, and the identifiers of the patients `patients`
# named, each read back from the server it searched.
kept() {
  local weights patients
  weights="$(output_of "$1" weights | jq -c '.value | sort')"
  patients="$(output_of "$1" patients | jq -r '.value[]' | while read -r ref; do
    curl -fsS -H 'Cache-Control: no-cache' "$FHIR/$ref" | jq -r '.identifier[0].value'
  done | jq -R . | jq -sc 'sort')"
  jq -n --argjson w "$weights" --argjson p "$patients" '{weights: $w, patients: $p}'
}

say "the project's own environment"
uv sync --quiet

say "every document, checked offline"
uv run dg validate --json > "$WORK/validate.ndjson"
jq -se '
  map(select(.kind == "validated")) | last
  | if .invalid == 0 and .documents == 2 then true else error("\(.invalid) document(s) refused") end
' "$WORK/validate.ndjson" > /dev/null

say "the gate: a malformed patient refused, every issue named"
if uv run dg run --local "pipelines/$GATE.yaml" --json > "$WORK/gate.ndjson"; then
  echo "the gate let a malformed patient through"; exit 1
fi
jq -se '
  map(select(.kind == "run")) | last
  | if .message != "failed" then error("the gate run settled \(.message)") else . end
  | (.failures | map(select(.step == "check")) | first) as $f
  | if $f == null then error("check did not fail")
    elif $f.error_class != "rejected" then error("check failed as \($f.error_class)")
    elif ($f.error | test("^3 issues were found in the 1 resources checked") | not) then error("check said: \($f.error)")
    elif ([("at Patient.gender"), ("at Patient.birthDate"), ("at Patient.managingOrganization.reference")]
          | all(. as $at | $f.error | contains($at)) | not) then error("check did not name every element: \($f.error)")
    else . end
  | if (.steps | map(select(.step == "name")) | first | .status) != "skipped" then error("the step behind the gate ran")
    else true end
' "$WORK/gate.ndjson" > /dev/null

say "a HAPI FHIR server on port $FHIR_PORT, empty"
"${COMPOSE[@]}" down -v --remove-orphans > /dev/null 2>&1 || true
"${COMPOSE[@]}" up -d > "$WORK/compose.log" 2>&1 \
  || { echo "the server did not start:"; cat "$WORK/compose.log"; exit 1; }
for _ in $(seq 1 180); do
  if curl -fsS "$FHIR/metadata" 2>/dev/null | jq -e '.resourceType == "CapabilityStatement"' > /dev/null 2>&1; then break; fi
  sleep 1
done
curl -fsS "$FHIR/metadata" | jq -e '.fhirVersion == "4.0.1"' > /dev/null

say "the server, seeded with 8 patients and 16 body weights"
curl -fsS -X POST "$FHIR" -H 'Content-Type: application/fhir+json' --data-binary @seed/source.json \
  | jq -e '[.entry[].response.status | startswith("201")] | all and length == 24' > /dev/null

for limit in 90 100; do
  say "the document, run locally with limit $limit"
  uv run dg run --local "pipelines/$CODE.yaml" --connections connections.yaml -p "limit=$limit" --json \
    > "$WORK/run-$limit.ndjson"
  assert_run_succeeded "$WORK/run-$limit.ndjson" "the run with limit $limit"

  # Sixteen observations, four to a page: four pages, each its own Bundle, and one item of
  # `heavy` per page.
  output_of "$WORK/run-$limit.ndjson" find \
    | jq -e '.bundle == null and .pages == 4 and .count == 16 and (.bundles | length) == 4
             and all(.bundles[]; .type == "searchset" and (.entry | length) == 4)' > /dev/null \
    || { echo "the search did not hand on four pages of four"; exit 1; }
  jq -se 'map(select(.kind == "run")) | last | .steps | map(select(.step == "heavy" and .status == "succeeded")) | length == 4' \
    "$WORK/run-$limit.ndjson" > /dev/null || { echo "heavy did not fan out over four pages"; exit 1; }

  # Every page and every observation on it, valid.
  output_of "$WORK/run-$limit.ndjson" check \
    | jq -e '.valid and .checked == 20 and .issues == [] and .outcome.resourceType == "OperationOutcome"' > /dev/null \
    || { echo "the pages did not validate"; exit 1; }

  kept "$WORK/run-$limit.ndjson" > "$WORK/kept-$limit.json"
  expected "$limit" > "$WORK/expected-$limit.json"
  diff <(jq -S . "$WORK/expected-$limit.json") <(jq -S . "$WORK/kept-$limit.json") > /dev/null \
    || { echo "with limit $limit the run kept something else:"; diff -u <(jq -S . "$WORK/expected-$limit.json") <(jq -S . "$WORK/kept-$limit.json"); exit 1; }
done

say "ok: $CODE searched four pages, validated 20 resources, and kept the heavy body weights and their patients at two limits; $GATE refused a malformed patient"
