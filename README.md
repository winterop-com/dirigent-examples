# dirigent examples

Small, independent example projects for dirigent, one folder each in this repository, that
follow [The basics](https://winterop-com.github.io/dirigent/basics/) and the
[DHIS2 tutorial](https://winterop-com.github.io/dirigent-dhis2/tutorial/). Every example was
made with `dg init`, runs on dirigent 0.35, and carries a README in the tutorials' voice, its
documents commented hop by hop, a `verify.sh` that runs it end to end without asking anything,
and the `AGENTS.md` a coding agent reads before it works there.

Clone the repository once, then work inside any one example's folder; each has its own
`pyproject.toml` and environment:

```bash
git clone https://github.com/winterop-com/dirigent-examples.git
cd dirigent-examples/echo-hello
uv sync
./verify.sh
```

## What you need once

- Python 3.13 and [uv](https://docs.astral.sh/uv/), `jq`, and `curl`.
- The CLI: `uv tool install "dirigent-cli>=0.35,<0.36"`, the range every example pins, so `dg --version` says 0.35.
  A `dg` of another version refuses to work inside an example, naming both versions
  (`cli.version_mismatch`), because each project pins its own; `uv run dg` is always the pinned one.
- Docker, for `echo-s3` (a local rustfs container), for `echo-stream` (a local Redpanda container) and for the PDF document in
  `dhis2-org-units-to-markdown` (a pandoc container), and for the three pack examples below,
  which each start the outside system they talk to: `chap-prediction` a Chap stack,
  `climate-sync-and-export` an open climate service, `fhir-to-fhir` two HAPI FHIR servers,
  `fhir-search-to-summary` one.
- A network only for the six `dhis2-*` examples, which call the public DHIS2 play demo, for
  `fhir-to-dhis2` and `climate-sync-and-export`, which call it too, and for `everything`.
  No `echo-*` example calls anything on the internet: the ones that make an HTTP call make it
  against the **playground**, the request-and-response service every dirigent instance serves
  itself under `/api/v1/playground`, and the rest reach nothing at all. For a train ride, see
  [OFFLINE.md](OFFLINE.md): `prepare-offline.sh` makes every environment complete before you
  leave.

## Starting any one example

Every example starts the same way. In its directory:

```bash
uv sync                                   # the project's own environment, dirigent pinned
uv run dg validate pipelines/<name>.yaml  # the document, checked offline against the catalog
uv run dg run --local pipelines/<name>.yaml
```

`dg run --local` applies and runs the document in a throwaway instance with no server, which is
the fast loop. No document here carries a secret, and plan refuses one whose `connections:`
block holds a password, a token, a signing secret or a URL with a password in it. A document
names its connection by code instead: an instance holds it, created once with
`dg connection create`, and a local run is handed it with `--connections connections.yaml`, a
file beside the documents that holds only the public demo logins the example uses. An example
whose documents call the playground needs an instance even for that
leg, because a local run mounts no API of its own; each README says so where it applies. For
everything an instance keeps, runs, schedules, alerts, artifacts, start one in a second terminal
in the same directory:

```bash
uv run dg dev
```

On the empty state a fresh clone has, `dg dev` migrates the schema, creates its own admin `admin`
with the password `admin`, mints a token and prints the `export DG_TOKEN=` line to paste
into the first terminal. The UI is at http://127.0.0.1:3333, and `admin` / `admin` logs in
there. On a state that already holds accounts, `dg dev` prints no token; then
`uv run dg auth login --username admin --password admin` answers with the line to paste.
A state an older dirigent wrote is not readable by a newer one before 1.0, because the
schema's baseline is edited in place rather than migrated: after moving the pinned CLI,
delete `.dirigent/state/` or start once with `dg dev --wipe-state`, and `verify.sh` rebuilds
everything the example needs from the empty state.
Then:

```bash
uv run dg apply
uv run dg run <name> --watch
```

Each README shows exactly this for its own documents, with the output as it really printed,
and its `verify.sh` does all of it non-interactively, on a free port where it starts an instance,
and stops whatever it started.

## Starting all of them

```bash
./verify-all.sh
```

runs every example's `verify.sh` in turn and prints which passed. It needs the network for
the six `dhis2-*` examples, `fhir-to-dhis2`, `climate-sync-and-export` and `everything`, and Docker for
`echo-s3`, `echo-stream`, the PDF document, `chap-prediction`, `climate-sync-and-export`, `fhir-to-fhir`,
`fhir-search-to-summary` and `everything`. Expect a few
minutes: the schedule example waits for a scheduled run to land, and the DHIS2 examples talk to
the play demo. One switch makes the rest of it run with no network at all:

```bash
./prepare-offline.sh                      # once, with a network: every .venv complete, the PDFs fetched
export UV_OFFLINE=1                       # on the train: uv never reaches out
./verify-all.sh
```

The six `dhis2-*` examples, `fhir-to-dhis2`, `climate-sync-and-export` and `everything` need
the network and fail without it; everything else passes.

## The examples, in the order the tutorials teach them

| Example | What it shows |
| --- | --- |
| [`echo-hello`](echo-hello) | The smallest document: one step reading the step before it. |
| [`echo-read`](echo-read) | One HTTP request against the instance's own playground, run locally and against that instance, the answer read back. |
| [`echo-gate`](echo-gate) | A JSON Schema gate on the answer: broken on purpose, fixed, carried in the document, then lifted onto the instance. |
| [`echo-send`](echo-send) | A send built from the gate's output, and a send skipped behind a refused gate. |
| [`echo-retry`](echo-retry) | A refusal beside an outage under one retry budget: `rejected` against `transient`. |
| [`echo-fanout`](echo-fanout) | One item per station over a list, one bad item tolerated, a join. |
| [`echo-transform`](echo-transform) | A batch reshaped with the three jq verbs, and what each one may do to it. |
| [`echo-schedule`](echo-schedule) | A reading on a schedule, and another behind an endpoint source, with nothing to call. |
| [`echo-alert`](echo-alert) | Alert rules the document declares under `alerts:`, owned by it so a hand delete is refused and a pause survives an apply, a failure delivered to a webhook and to the process log, each delivery in `dg alerts queue`, the log line's fields naming the failing step and error, and the runs summary and audit trail that follow. |
| [`echo-storage`](echo-storage) | A batch written to storage, read back, and a run report. |
| [`echo-report`](echo-report) | A run's report taken from a step: a `report.render` page made the report with `report: {from: page}`, a template reading `{{ params }}`, lists, objects and booleans read as JSON inside a string, and a plan whose only change is the report saying `report_changed`. |
| [`echo-s3`](echo-s3) | The same through the `s3://` scheme against a local rustfs container. |
| [`echo-stream`](echo-stream) | A sensor waiting for a batch, a stream read whole by an HTTP step, the same batch off a real Kafka topic in a local Redpanda container, and a sensor source that keeps the batches arriving in runs that overlap, the offsets carried on from run to run. |
| [`dhis2-read-gate-send`](dhis2-read-gate-send) | The three moves against the DHIS2 play demo, with a dry-run import. |
| [`dhis2-metadata-to-storage`](dhis2-metadata-to-storage) | Organisation units exported, gated on `dhis2-uid` and `dhis2-code`, snapshotted to storage and read back. |
| [`dhis2-org-unit-sync`](dhis2-org-unit-sync) | Organisation units synchronised three ways: DHIS2 to DHIS2, DHIS2 to another system through jq, and another system into DHIS2 through jq, every import a rehearsal. |
| [`dhis2-org-units-to-markdown`](dhis2-org-units-to-markdown) | Organisation units rendered as a markdown page, an HTML page, and a PDF from a pandoc container, the markdown page the run's report, and the block catalog marking `docker.run` unsafe and enabled on that instance. |
| [`dhis2-reads`](dhis2-reads) | The DHIS2 reads side by side against the play demo: system info, two metadata collections in one export, the data values changed since a date, and every tracked entity of a program read page by page under bounds, with a capped read that fails rather than answer part of it; then a month exported as CSV and as ADX, the data store, a SQL view, and validation rules that store nothing. |
| [`dhis2-writes-rehearsed`](dhis2-writes-rehearsed) | Five DHIS2 writes as dry runs against the play demo: one data element created, one data value set (read back unchanged), one tracker event imported, a data set signed off, and a CSV file named by codes imported with the id schemes that say so, each block sending the dry run its endpoint really honours. |
| [`agent-over-mcp`](agent-over-mcp) | A coding agent on a running instance through its `/mcp`, under an operator token from a project `.mcp.json` reading `${DG_MCP_TOKEN}`: the connection kinds read with `list_connection_kinds` and `get_connection_kind`, connections created with their settings alone, one awaiting the secret an admin supplies with `dg connection set-secret`, piped in with `--stdin` as the answer's `supply_with.piped` names, a pipeline changed with `edit_pipeline`, run, and its report read with `get_run_report`. Its `verify.sh` plays the agent with `curl`, no model needed. |
| [`everything`](everything) | Every pipeline above except `echo-stream`'s, and the whole dirigent examples corpus in one project: `setup.sh` leaves one instance on 4444 with all of them applied, for a demo. |

## The packs beyond the tutorials

| Example | What it shows |
| --- | --- |
| [`chap-prediction`](chap-prediction) | A Chap forecast end to end against a local Chap the project starts: a history imported, a configured model backtested and promoted, a forecast read back at two quantiles, and the alerts it raises released once a reviewer approves them. Needs Docker and about 15 GB for the Chap images. |
| [`climate-sync-and-export`](climate-sync-and-export) | CHIRPS rainfall ingested into a local open climate service, synced forward, and exported averaged over the chiefdoms of a DHIS2 district as a dataValueSet, gated on shape. Needs Docker and the network. |
| [`fhir-to-dhis2`](fhir-to-dhis2) | A FHIR `QuestionnaireResponse` at an endpoint source, translated into a DHIS2 dataValueSet, checked against the form DHIS2 holds, and the import rehearsed against the play demo. |
| [`fhir-to-fhir`](fhir-to-fhir) | Patients and their observations copied nightly from one local HAPI FHIR server to another with the `dirigent-fhir` pack: references rewritten for the target, every write conditional on an identifier, and a second run creating nothing; then one patient updated at its id, patched, read with `$everything`, and test data deleted under a bound. Needs Docker. |
| [`fhir-search-to-summary`](fhir-search-to-summary) | Body weights searched a page at a time from a local HAPI FHIR server with the `dirigent-fhir` pack: the pages handed to a fan-out, every page validated, and the heavy ones reduced to their values and patients with FHIRPath, a limit bound as a variable. Needs Docker. |

Each example is independent: work in any one folder, in any order, without touching the others.
