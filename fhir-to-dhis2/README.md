# fhir-to-dhis2

A filled-in FHIR form carried into DHIS2, in one document: **a `QuestionnaireResponse` arrives
at an endpoint**, **the form it answers is read from DHIS2**, **every answer is translated into a
data value and checked against a cell that form has**, and **the import is rehearsed** against
the DHIS2 play demo, which checks every value and writes none.

The dhis2 pack has no FHIR block, and needs none: FHIR is JSON, the translation is one jq
program, and the pack's own `dhis2.metadata`, `dhis2-uid` and `dhis2-period` formats and
`dhis2.data_value_set_import` do the DHIS2 half. This is the path the pack supports today, and
the mapping it follows is the one a DHIS2 FHIR facade publishes its forms with:

| FHIR | DHIS2 |
| --- | --- |
| `questionnaire`, `.../Questionnaire/<uid>` | `dataSet` |
| `subject`, `Location/<uid>` | `orgUnit` |
| the `D2Period` extension's `iso` slice | `period` |
| an answered item's `linkId`, `<dataElement>` or `<dataElement>.<categoryOptionCombo>` | one data value |

Everything below was run against the public demo at `https://play.dhis2.org/2.42`, with the
published `admin` / `district` credential. Nothing is written to it.

What you learn here:

- that a pipeline can start at an **endpoint source**, the route a FHIR server's rest-hook
  subscription POSTs to, and that a run takes the same delivery by hand with `--input`;
- that a translation is checked against the system it lands in, not trusted: the form is read
  from DHIS2 at run time, and an answer for a cell it does not have fails the run as
  `rejected`, before DHIS2 is sent anything;
- that an unanswered question is a fact of its own and never becomes a zero;
- that a dry run on `/api/dataValueSets` is `dryRun=true`, and what DHIS2's import summary says
  under it.

## Run it

```bash
uv sync
uv run dg validate pipelines/fhir-to-dhis2.yaml
```

The fast loop, with no server. A local run starts on a throwaway instance holding nothing, so
it is handed the connection and the schema the document names, and the delivery itself:

```bash
uv run dg run --local pipelines/fhir-to-dhis2.yaml \
  --connections connections.yaml \
  --schema schemas/fhir-data-value-set.json \
  --input @captures/benkeh-2025-07.json
```

A file under `captures/` is a delivery as the endpoint receives it: a `content_type` and the
`body`, which is the `QuestionnaireResponse`. Without `--input` the run takes the source's
`sample`, which is the same capture.

The second capture answers one cell the form does not have, `s46m5MS0hxu.fsFN9T4ck3E`:

```bash
uv run dg run --local pipelines/fhir-to-dhis2.yaml \
  --connections connections.yaml \
  --schema schemas/fhir-data-value-set.json \
  --input @captures/benkeh-2025-07-off-form.json
```

Then the instance. A `dhis2` connection carries a password, and a connection secret is sealed
with the instance's own key, so the instance needs one before it can hold the connection. Mint
it once into `.env`, which is not in the repository and which every command run in this
directory reads, then start the instance in a second terminal, in this directory:

```bash
grep -q '^DIRIGENT_SECRET_KEY=' .env 2>/dev/null \
  || printf 'DIRIGENT_SECRET_KEY=%s\n' "$(uv run dg secret-key)" >> .env
uv run dg dev
```

On an empty state `dg dev` makes its own admin `admin`, password `admin`. Back in the first
terminal, `uv run dg auth login --username admin --password admin` answers with the
`export DG_TOKEN=` line to paste. Then:

```bash
uv run dg schema create schemas/fhir-data-value-set.json
uv run dg connection create dhis2 play \
  --name "DHIS2 play demo" \
  --set base_url=https://play.dhis2.org/2.42 \
  --set follow_redirects_with_auth=true \
  --set basic_username=admin \
  --set basic_password=district
uv run dg apply
uv run dg run fhir-to-dhis2 --watch --input @captures/benkeh-2025-07.json
```

Once applied, the endpoint receives deliveries on the instance; `uv run dg source --help`
shows how to see where it listens and what has arrived, which is where a FHIR server's
subscription is pointed.

`./verify.sh` does all of it unattended -- validate, the good capture locally, the off-form
capture locally and refused, an instance on a free port of its own, the schema, the connection,
the apply and the run -- and asserts on the records: three values, the unanswered item named,
a rehearsal that would import all three with no conflicts, and for the off-form capture the
refusal naming the cell with the rehearsal skipped behind it. It stops the instance it started
by pid on the way out, and takes about half a minute.

## What you see

`uv run dg run --local ... --input @captures/benkeh-2025-07.json`, with a local run's temporary
root written as `/tmp/...` and the `queued` and `running` lines left out:

```text
2026-11-01T14:07:14.695+01:00 [info    ] started                        [run] pipeline=fhir-to-dhis2 run_id=01a19738-a677-75ef-8454-364144bbfeb9 local=true scratch=file:///tmp/... root=/tmp/...
2026-11-01T14:07:14.629+01:00 [info    ] succeeded                      [step capture] block=endpoint attempt=1 duration_ms=0
2026-11-01T14:07:14.688+01:00 [info    ] received by hand               [log capture] via=hand bytes=1202
2026-11-01T14:07:15.006+01:00 [info    ] succeeded                      [step read] block=transform.jq attempt=1 duration_ms=59
2026-11-01T14:07:17.273+01:00 [info    ] metadata read                  [log form] resource=dataSets duration_ms=2250
2026-11-01T14:07:17.329+01:00 [info    ] succeeded                      [step translate] block=transform.jq attempt=1 duration_ms=23
2026-11-01T14:07:17.355+01:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=15
2026-11-01T14:07:18.160+01:00 [info    ] import summary                 [log rehearse] status=SUCCESS imported=3 updated=0 ignored=0 deleted=0 conflict_count=0
2026-11-01T14:07:18.189+01:00 [info    ] succeeded                      [step receipt] block=transform.jq attempt=1 duration_ms=14
2026-11-01T14:07:18.303+01:00 [info    ] succeeded                      [run] pipeline=fhir-to-dhis2 run_id=01a19738-a677-75ef-8454-364144bbfeb9 exit_code=0
```

`receipt`, the step's output:

```json
{
  "response": "benkeh-2025-07",
  "data_set": "BfMAe6Itzgt",
  "org_unit": "wQ71REGAMet",
  "period": "202507",
  "values": 3,
  "unanswered": ["l6byfWFUGaP.Prlt0C1RF0s"],
  "status": "SUCCESS",
  "would_import": 3,
  "would_update": 0,
  "ignored": 0,
  "conflicts": 0
}
```

Three answers, three values: BCG doses given at Benkeh MCHP in July 2025, fixed and outreach
for under-ones, and measles doses, fixed. Yellow fever was asked and not answered, so it is
named under `unanswered` and is not in the import. Under `dryRun` DHIS2 resolved every value,
says it would import all three, and wrote none of them.

The off-form capture:

```text
2026-11-01T14:07:30.841+01:00 [error   ] failed                         [log translate] duration_ms=10 error_class=rejected error="answers with no cell on the form Child Health: s46m5MS0hxu.fsFN9T4ck3E"
2026-11-01T14:07:31.151+01:00 [error   ] failed                         [run] pipeline=fhir-to-dhis2 run_id=01a19738-d538-72ae-a3e0-ede0d25a7800 exit_code=1
```

`fsFN9T4ck3E` is not one of BCG's four cells on this DHIS2, so nothing is sent: `check`,
`rehearse` and `receipt` are skipped behind the failed step. `rejected` is the class that
spends no retry budget, because the same capture against the same form fails the same way every
time.

## The document, hop by hop

`pipelines/fhir-to-dhis2.yaml` carries these notes as comments at the line each one is about.

**`capture`.** An endpoint source: `POST /fhir/questionnaire-responses`, FHIR JSON or plain
JSON, up to 1 MB. Its output is the request -- method, headers, `body` -- and `body` is all a
later step reads. Its `sample` is what a run with no `--input` is handed.

**`read`.** jq that refuses what is not a completed `QuestionnaireResponse` about a `Location`,
with `error(...)`, which fails the step as `rejected`. An `in-progress` response is a form
still being filled, and a subscription may fire on one. What it hands on is the response, and
the data set, org unit and period read off it.

**`form`.** `dhis2.metadata` reads the data set the response names, projected to what the check
needs: each data element and the category option combos of its category combo. The form is
read from the instance every run, so a data element added to the data set is accepted without
an edit here.

**`translate`.** The mapping, and the check. Answered leaves are found by recursion, because
items nest; each `linkId` splits on its dot into a data element and, where there is one, a
cell; an answer whose data element is not on the form, or whose cell its category combo does
not have, fails the step naming every such `linkId`. Otherwise every answer becomes one value,
a string on the wire whatever the answer's FHIR type.

**`check`.** `validate.schema` against `schemas/fhir-data-value-set.json`, held by the instance
under `fhir-data-value-set`: the envelope DHIS2 takes, every identifier a `dhis2-uid` and the
period a `dhis2-period`. Those formats are the dhis2 pack's, and they assert because the pack
is installed.

**`rehearse`.** `dhis2.data_value_set_import` with `dry_run: true`, which is `dryRun=true` on
`/api/dataValueSets`. DHIS2 spells a rehearsal differently per endpoint: `/api/metadata` and
`/api/tracker` take `importMode=VALIDATE`, and reaching for the wrong spelling does not fail, it
imports. Dropping the line makes this a real import; do that against your own DHIS2, never the
shared demo.

**`receipt`.** What arrived, what it became and what DHIS2 would have done, in one value.

`connections.yaml` is what a `--local` run is handed. The credential in it is the play demo's
own, published so anyone may try the instance; a real one belongs in a connection the server
holds, sealed under its key, never in a file beside the documents.

## Where to go next

- [`dhis2-read-gate-send`](../dhis2-read-gate-send): the read, gate and rehearsed write this
  one is built from, without FHIR.
- `dirigent-integration`'s `fhir` shelf carries the rest of the FHIR vocabulary: a linkId
  lookup table for forms whose linkIds are not DHIS2 uids, a `Patient` to a tracked entity, an
  `Encounter` and its `Observation`s to an event, and a `ConceptMap` driving the mapping.
- [**The examples**](../README.md): every example in order, and what you need once.
