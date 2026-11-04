# fhir-search-to-summary

Body weights searched a page at a time from a local FHIR server, every page validated, and the
heavy ones summarised with FHIRPath, in one document: **a search hands each page on as its own
Bundle**, **a validation gate checks every page and every observation on it**, **a fan-out picks
the observations over a limit from each page**, and **the FHIRPath verbs reduce them to their
values and their patients**. A second document is the gate on its own, refusing a malformed
patient. Everything here is the `dirigent-fhir` pack's blocks.

The server is HAPI FHIR R4, started locally in Docker by `hapi/compose.yaml` on `127.0.0.1:9821`.
Nothing here talks to a public FHIR server.

What you learn here:

- that `fhir.search` with `emit: pages` hands on one searchset Bundle per page under `bundles`, and
  a `for_each` that reads it makes one item per page, so the width of the fan-out is whatever the
  search turned out to be;
- that `fhir.validate` holds every resource to FHIR's JSON rules and the engine's R4 models, and
  fails its step, `rejected`, naming every issue by the FHIRPath of its element;
- that `transform.fhirpath`, `map.fhirpath` and `filter.fhirpath` are dirigent's transform verbs
  with FHIRPath as the language: `entry.resource.ofType(Observation)` walks a Bundle the way FHIR
  names it;
- that a value reaches an expression only as a variable: the limit is a parameter, bound under
  `variables` and read as `%limit`, never spliced into the expression's text.

`pyproject.toml` pins `dirigent-cli` and the `dirigent-fhir` pack from PyPI, both at 0.35, and
`uv sync` installs them like any other pack.

## Run it

Start the server, empty, and wait a minute or so until it answers `/metadata`:

```bash
docker compose -p dirigent-example-fhir-search-to-summary -f hapi/compose.yaml up -d
curl -s http://127.0.0.1:9821/fhir/metadata | jq .fhirVersion     # "4.0.1", once it is up
```

Seed it with eight patients and two body weights each:

```bash
curl -s -X POST http://127.0.0.1:9821/fhir \
  -H 'Content-Type: application/fhir+json' --data-binary @seed/source.json | jq '.entry | length'
```

Then the project:

```bash
uv sync
uv run dg validate
uv run dg run --local pipelines/fhir-search-to-summary.yaml --connections connections.yaml
uv run dg run --local pipelines/fhir-search-to-summary.yaml --connections connections.yaml -p limit=100
uv run dg run --local pipelines/fhir-validate-gate.yaml       # fails at check, by design
```

`weights` answers the kept values and `patients` the references of the patients they are about.
At the default limit of 90 that is seven body weights and five patients.

When you are done:

```bash
docker compose -p dirigent-example-fhir-search-to-summary -f hapi/compose.yaml down -v
```

## Hop by hop

| Step | Block | What it does |
| --- | --- | --- |
| `find` | `fhir.search` | Body weights (LOINC 29463-7), four to a page, `emit: pages`: four searchset Bundles under `bundles`. |
| `check` | `fhir.validate` | Every page and every observation on it, 20 resources: FHIR's JSON rules and the engine's R4 models. An error fails the run here. |
| `heavy` | `transform.fhirpath` | One item per page: the page's observations over `%limit`. |
| `collected` | `transform.fhirpath` | The fan-in: every page's answer flattened into one list. |
| `final` | `filter.fhirpath` | Only the observations whose status is final. |
| `weights` | `map.fhirpath` | Each kept observation replaced by its value. |
| `patients` | `transform.fhirpath` | The patients those observations are about, once each. |

`fhir-validate-gate` validates an inline patient that is wrong three ways, a gender outside its
value set, an empty `birthDate` and a reference no server resolves, and fails at `check` with
`fhir.validate.invalid`, naming `Patient.gender`, `Patient.birthDate` and
`Patient.managingOrganization.reference`. The step behind it is skipped.

## Verify it

```bash
./verify.sh
```

It validates both documents offline, runs the gate and asserts its refusal, starts the server
under its own compose project name, seeds it, runs the summary at limits 90 and 100, and asserts
the pages, the validation, and the weights and patients against what the seed says each limit
keeps, reading each patient's identifier back from the server. It removes the server on the way
out. It needs Docker, `jq` and `curl`.
