# fhir-to-fhir

Patients and the observations about them, copied from one FHIR server to another every night,
in one document: **a search reads every patient on the source with their observations beside
them**, **one transaction writes the lot to the target**, and **a receipt counts what the target
did**. Neither server is DHIS2. This is FHIR as a system of its own, with the `dirigent-fhir`
pack's blocks and nothing else.

Both servers are HAPI FHIR R4, started locally in Docker by `hapi/compose.yaml`: the source on
`127.0.0.1:9811`, the target on `127.0.0.1:9812`. Nothing here talks to a public FHIR server.

What you learn here:

- that a FHIR search is pages, and `fhir.search` follows `Bundle.link[next]` for you, only on the
  source's own origin and only as far as `max_pages`, failing rather than copying part of a
  source;
- that `_revinclude` puts the observations about each patient on the same page as the patient,
  so the two ends of every reference travel together;
- that `fhir.transaction` rewrites `Observation.subject` from the source's `Patient/7` to a
  `urn:uuid` the target resolves to its own copy of that patient, so the source's ids never
  reach the target;
- that every write is a conditional update on the resource's identifier, which is what makes the
  copy safe to run again: the second night creates nothing.

`pyproject.toml` pins `dirigent-cli` and the `dirigent-fhir` pack from PyPI, both at 0.29, and
`uv sync` installs them like any other pack.

## Run it

Start the two servers, empty, and wait a minute or so until both answer `/metadata`:

```bash
docker compose -p dirigent-example-fhir-to-fhir -f hapi/compose.yaml up -d
curl -s http://127.0.0.1:9811/fhir/metadata | jq .fhirVersion     # "4.0.1", once it is up
```

Give the source something to copy: a transaction Bundle of a dozen patients, two observations
about each, every one carrying an identifier.

```bash
curl -s -X POST http://127.0.0.1:9811/fhir \
  -H 'Content-Type: application/fhir+json' --data-binary @seed/source.json | jq '.entry | length'
```

Then the project:

```bash
uv sync
uv run dg validate pipelines/fhir-to-fhir.yaml
```

The fast loop, with no server. A local run starts on a throwaway instance holding nothing, so it
is handed the two connections the document names:

```bash
uv run dg run --local pipelines/fhir-to-fhir.yaml --connections connections.yaml
```

Run it a second time and nothing new is created on the target.

Then the instance. Start it in a second terminal, in this directory:

```bash
uv run dg dev
```

On an empty state `dg dev` makes its own admin `admin`, password `admin`. Back in the first
terminal, `uv run dg auth login --username admin --password admin` answers with the
`export DG_TOKEN=` line to paste. Then:

```bash
uv run dg connection create fhir fhir-source --set base_url=http://127.0.0.1:9811/fhir
uv run dg connection create fhir fhir-target --set base_url=http://127.0.0.1:9812/fhir
uv run dg connection check fhir-source
uv run dg apply
uv run dg run fhir-to-fhir --watch
```

The check reads the source's `/metadata`, its CapabilityStatement, and reports the FHIR version
it states: `4.0.1`. Applying the document registers its `nightly` schedule as well, so the
instance copies again at two in the morning, UTC, for as long as it runs.

When you are done, take the servers down; they hold everything in memory, so the next start is
empty again:

```bash
docker compose -p dirigent-example-fhir-to-fhir -f hapi/compose.yaml down -v
```

`./verify.sh` does all of it unattended -- validate, the two servers started empty under their
own compose project name, the seed, a local run, a second local run, an instance on a free port
of its own, both connections checked, the apply and a run there -- and asserts on records and on
what the target holds: a dozen patients and two dozen observations, the source's identifiers on
them, every observation's subject resolving on the target to the patient carrying the identifier
its source patient carries, the search reading three pages, and the second and third runs
creating nothing. It stops the instance it started by pid and removes both servers on the way
out, and takes two or three minutes, most of them HAPI starting.

## What you see

`receipt`, the last step's output, on the first run against the empty target:

```json
{"created": 36, "updated": 0, "by_type": {"Observation": 24, "Patient": 12}}
```

and on every run after it:

```json
{"created": 0, "updated": 36, "by_type": {"Observation": 24, "Patient": 12}}
```

`updated` counts what the target found already there and wrote over, which on an unchanged
source changes nothing on the target.

## The document, hop by hop

`pipelines/fhir-to-fhir.yaml` carries these notes as comments at the line each one is about.

**`find`.** `fhir.search` on `fhir-source`: `Patient?_revinclude=Observation:subject&_count=5&_sort=_id`.
Five patients a page, so a dozen take three pages and the paging is exercised; each page carries
those patients' observations as `include` entries. The step follows the next links on the
source's own origin, at most twenty pages, and answers one `searchset` Bundle holding every entry
of every page. A next link to another host, scheme or port fails the step instead of being
followed, so a source server can never lead the connection elsewhere. More pages than
`max_pages` fails the step too, because a copy that stopped half way would say it succeeded.

**`copy`.** `fhir.transaction` on `fhir-target`, handed that Bundle as it is. Each resource
becomes an entry with a fresh `urn:uuid`, without the id and version it had on the source, and
with the request `PUT Patient?identifier=http://example.org/fhir-to-fhir/mrn|MRN-0001`: a
conditional update, which writes over the one resource that identifier matches on the target and
creates it when none does. Every `Observation.subject`, `Patient/7` on the source, is rewritten
to the urn of that patient's entry, and the target resolves it to wherever it stores the patient.
`mode: transaction` means the target takes everything or nothing. A reference to a resource the
Bundle does not carry fails the step under `unresolved_references: fail`, because on the target it
would point at whatever holds that id there.

**`receipt`.** jq over the transaction's output: how many entries the target created, how many
it updated, and how many of each resource type the transaction carried.

`connections.yaml` is what a `--local` run is handed. Neither server takes a credential; a real
one belongs in a connection the instance holds, sealed under its key, never in a file beside the
documents.

## Where to go next

- [`fhir-to-dhis2`](../fhir-to-dhis2): FHIR arriving at an endpoint and carried into DHIS2.
- The `dirigent-fhir` pack's own `fhir` shelf: a read, a paged search, a conditional create and a
  conditional update, one document each.
