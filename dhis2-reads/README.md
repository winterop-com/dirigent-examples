# dhis2-reads

Four reads of a real DHIS2 instance, one per block the DHIS2 pack added or reshaped for 0.33,
in one document and side by side, because none of them waits on another:

- **`dhis2.system_info`** -- which DHIS2 answered: its version, its clock, and when its
  analytics tables were last built. A report that quotes a number should quote the instance it
  came from.
- **`dhis2.metadata_export`** -- two metadata collections in one `GET /api/metadata`, each read
  with its own `fields` and `filter`, answered under `collections.<name>` with a count per name.
- **`dhis2.data_value_set_export`, incremental** -- only the data values changed at or after a
  date, which is what a sync reads from the start of its previous run, instead of a month's
  worth every time.
- **`dhis2.tracker` with `all_pages`** -- every tracked entity of one program at one facility,
  a page at a time, answered as one list, under bounds that fail the step rather than hand on
  part of the collection.

A second document, `dhis2-reads-capped`, is the same tracker read with a bound it is sure to
reach, and it fails on purpose. A third, `dhis2-reads-more`, is five more reads with the blocks
and forms the pack added for 0.34: a data value set exported as CSV and as ADX, a data store
namespace and its first key, a stored SQL view, and validation rule analysis that stores
nothing.

Everything below was run against the public DHIS2 demo, `https://play.dhis2.org/2.42`, the
newest 2.42 demo (**2.42.7.1** when this was written) -- the Sierra Leone database, with the
published `admin` / `district` credential. Nothing here writes; for the write side, rehearsed,
see [`dhis2-writes-rehearsed`](../dhis2-writes-rehearsed).

## Run it

```bash
uv sync
uv run dg validate
uv run dg run --local pipelines/dhis2-reads.yaml --connections connections.yaml
```

`--local` applies and runs the document in a throwaway instance in a temporary directory and
deletes it on the way out. That instance holds nothing, so it is handed the connection from
`connections.yaml`: the play demo's own published credential. A real instance's credential
belongs in a connection the server holds, which is why `pipelines/` carries none and names the
connection `play` by code. On an instance of your own, `uv run dg dev` in a second terminal,
then:

```bash
uv run dg connection create dhis2 play \
  --name "DHIS2 play demo" \
  --set base_url=https://play.dhis2.org/2.42 \
  --set follow_redirects_with_auth=true \
  --set basic_username=admin \
  --set basic_password=district
uv run dg apply
uv run dg run dhis2-reads --watch
```

A `dhis2` connection needs a credential, an `api_token` or the basic pair, and the `--set`
lines name the basic pair whole, so the command asks for nothing. Leave the password off at a
terminal and it asks for it without echoing; in a script it refuses instead and names the
flags each credential needs.

`./verify.sh` runs all three documents locally and asserts on their records.

## What you see

`uv run dg validate`:

```text
2026-11-03T18:21:00.045+01:00 [info    ] valid                          [validation] code=dhis2-reads-capped document=pipelines/dhis2-reads-capped.yaml checked="document and installed blocks"
  each step under the last one it waits for
    children  (dhis2.tracker)
2026-11-03T18:21:00.051+01:00 [info    ] valid                          [validation] code=dhis2-reads-more document=pipelines/dhis2-reads-more.yaml checked="document and installed blocks"
  each step under the last one it waits for
    csv  (dhis2.data_value_set_export)
    adx  (dhis2.data_value_set_export)
    keys  (dhis2.data_store)
      first  (dhis2.data_store)
    view  (dhis2.sql_view)
    validate  (dhis2.validation_run)
2026-11-03T18:21:00.053+01:00 [info    ] valid                          [validation] code=dhis2-reads document=pipelines/dhis2-reads.yaml checked="document and installed blocks"
  each step under the last one it waits for
    info  (dhis2.system_info)
    holdings  (dhis2.metadata_export)
    changed  (dhis2.data_value_set_export)
    children  (dhis2.tracker)
2026-11-03T18:21:00.054+01:00 [info    ] valid                          [validated] documents=3 invalid=0 skipped=0
```

In `dhis2-reads`, four steps, none under another: they are queued together and run at once.

`uv run dg run --local pipelines/dhis2-reads.yaml --connections connections.yaml`:

```text
2026-11-03T14:26:15.255+01:00 [info    ] started                        [run] pipeline=dhis2-reads run_id=01a1a196-c5d0-75ce-8f7f-2b5073e58c62 local=true scratch=file:///tmp/dirigent-local-bfiwf8n1/artifacts/runs/01a1a196-c5d0-75ce-8f7f-2b5073e58c62 root=/tmp/dirigent-local-bfiwf8n1
2026-11-03T14:26:14.969+01:00 [info    ] queued                         [step info] block=dhis2.system_info attempt=1
2026-11-03T14:26:14.969+01:00 [info    ] queued                         [step holdings] block=dhis2.metadata_export attempt=1
2026-11-03T14:26:14.969+01:00 [info    ] queued                         [step changed] block=dhis2.data_value_set_export attempt=1
2026-11-03T14:26:14.969+01:00 [info    ] queued                         [step children] block=dhis2.tracker attempt=1
2026-11-03T14:26:15.373+01:00 [info    ] running                        [step changed] block=dhis2.data_value_set_export attempt=1
2026-11-03T14:26:15.464+01:00 [info    ] running                        [step children] block=dhis2.tracker attempt=1
2026-11-03T14:26:15.484+01:00 [info    ] running                        [step holdings] block=dhis2.metadata_export attempt=1
2026-11-03T14:26:15.502+01:00 [info    ] running                        [step info] block=dhis2.system_info attempt=1
2026-11-03T14:26:18.637+01:00 [info    ] system info read               [log info] version=2.42.7.1 duration_ms=3109
2026-11-03T14:26:18.649+01:00 [info    ] metadata exported              [log holdings] counts={"dataSets":26,"programs":7} duration_ms=3150
2026-11-03T14:26:18.662+01:00 [info    ] succeeded                      [step info] block=dhis2.system_info attempt=1 duration_ms=3160
2026-11-03T14:26:18.671+01:00 [info    ] succeeded                      [step holdings] block=dhis2.metadata_export attempt=1 duration_ms=3187
2026-11-03T14:26:18.780+01:00 [info    ] data value set exported        [log changed] values=10 duration_ms=3376
2026-11-03T14:26:18.804+01:00 [info    ] succeeded                      [step changed] block=dhis2.data_value_set_export attempt=1 duration_ms=3431
2026-11-03T14:26:18.956+01:00 [info    ] tracker read                   [log children] fields.kind=trackedEntities rows=36 more=false duration_ms=3473
2026-11-03T14:26:18.958+01:00 [info    ] succeeded                      [step children] block=dhis2.tracker attempt=1 duration_ms=3494
2026-11-03T14:26:19.082+01:00 [info    ] succeeded                      [run] pipeline=dhis2-reads run_id=01a1a196-c5d0-75ce-8f7f-2b5073e58c62 exit_code=0
```

The outputs are in the run's closing record. Every command writes records into a pipe, so each
one is a `jq` away:

```bash
uv run dg run --local pipelines/dhis2-reads.yaml --connections connections.yaml --json \
  | jq 'select(.kind == "run" and has("exit_code"))
        | .steps | map({key: .step, value: .output}) | from_entries'
```

### Which instance answered

`info` lifts the keys a report reads most into named fields, and keeps the rest under `other`.
A few of them:

```json
{
  "version": "2.42.7.1",
  "revision": "324e71c",
  "system_name": "DHIS 2 Demo - Sierra Leone",
  "instance_base_url": "https://play.im.dhis2.org/stable-2-42-7-1",
  "server_time_zone_id": "Etc/UTC",
  "calendar": "iso8601",
  "last_analytics_table_success": "2026-11-03T01:12:40.043",
  "interval_since_last_analytics_table_success": "12 h, 12 m, 55 s"
}
```

`instance_base_url` is where `play.dhis2.org/2.42` redirected to. The block reads through the
connection, so it follows that redirect the way the connection allows.

### Two collections in one request

`holdings` names a shared `fields` and `order`, and each collection may replace them: `dataSets`
asks for its `periodType` too, and `programs` only for the tracker programs. Each term is sent
scoped to its collection, as `dataSets:fields=` and `programs:filter=`:

```json
{
  "counts": { "dataSets": 26, "programs": 7 },
  "programs": [
    "Child Programme",
    "MNCH / PNC (Adult Woman)",
    "Malaria case diagnosis, treatment and investigation",
    "Malaria focus investigation",
    "Provider Follow-up and Support Tool",
    "TB program",
    "WHO RMNCH Tracker"
  ]
}
```

`/api/metadata` has no pager: it answers every row that matches. To count a collection without
reading it, read it with `dhis2.metadata`, `paging: true` and `page_size: 1`, and take
`pager.total`.

### What changed since

An export needs three selectors -- what, where and when -- and is refused before any request
without one of each. `last_updated` is a *when*: it stands in for a period, so the export reads every
period whose values changed at or after the date, rather than one month's. The play database
was last written in October 2017 and its dates have been shifted forward since, which is why
`since` defaults to `2017-10-01`; a sync passes the start of its previous run instead, or uses
`last_updated_duration: 1d` on a daily schedule.

```json
{
  "dataValues": [
    {
      "attributeOptionCombo": "HllvX50cXC0",
      "categoryOptionCombo": "hEFKSsPV5et",
      "created": "2022-09-05T13:06:21.000+0000",
      "dataElement": "l6byfWFUGaP",
      "followup": false,
      "lastUpdated": "2017-10-10T15:42:00.000+0000",
      "orgUnit": "DiszpKrYNg8",
      "period": "201708",
      "storedBy": "system",
      "value": "2"
    }
  ]
}
```

Ten values, across five periods from 201708 to 202608, every one with a `lastUpdated` after the
date. The body is the data value set DHIS2 wrote, the document a `dhis2.data_value_set_import`
takes whole.

### Every page, or none

`children` reads ten rows a page and follows the pages to the end:

```json
{
  "page": 4,
  "page_size": 10,
  "total": null,
  "page_count": null,
  "more": false
}
```

Thirty-six tracked entities in `rows`, four pages, and `more: false`: nothing left unread.
`total` stays null because counting is a query of its own on the instance, which `total: true`
asks for. A one-page read -- no `all_pages` -- answers the first page and says in `pager.more`
whether rows match past it, so a step never takes 50 rows for all of them.

## The bound, reached

`all_pages` is bounded three ways, by `max_rows`, `max_pages` and `max_total` (the rows' size as
JSON), and reaching any one fails the step rather than answering what it read so far.
`dhis2-reads-capped` sets `max_rows: 20` at the same facility:

```bash
uv run dg run --local pipelines/dhis2-reads-capped.yaml --connections connections.yaml
```

```text
2026-11-03T14:26:44.388+01:00 [info    ] running                        [step children] block=dhis2.tracker attempt=1
2026-11-03T14:26:48.073+01:00 [info    ] failed                         [step children] block=dhis2.tracker attempt=1 duration_ms=3685
2026-11-03T14:26:48.082+01:00 [error   ] failed                         [log children] duration_ms=3574 error_class=rejected error="reading every page of trackedEntities reached max_rows (20) with rows still to read; nothing is answered rather than a part of the collection. Raise max_rows or narrow the read"
2026-11-03T14:26:48.329+01:00 [error   ] failed                         [run] pipeline=dhis2-reads-capped run_id=01a1a197-36e9-74a4-88bd-11d24f5c43de exit_code=1
```

One attempt, though the step allows three: the failure is `rejected`, and a rejected failure
spends no retry, because reading again would reach the same bound.

## Five more reads

`dhis2-reads-more` runs six steps, five of them at once, and only `first` waits, for the key
`keys` found:

```bash
uv run dg run --local pipelines/dhis2-reads-more.yaml --connections connections.yaml
```

```text
2026-11-03T18:19:59.142+01:00 [info    ] sql view read                  [log view] sql_view=qMYMT0iUGkG rows=13 duration_ms=1808
2026-11-03T18:19:59.142+01:00 [info    ] data store keys read           [log keys] namespace=capture keys=2
2026-11-03T18:19:59.159+01:00 [info    ] data value set exported        [log adx] format=adx content_bytes=5080 duration_ms=1925
2026-11-03T18:19:59.210+01:00 [info    ] data value set exported        [log csv] format=csv content_bytes=5368 duration_ms=1912
2026-11-03T18:19:59.377+01:00 [info    ] validation rule analysis run   [log validate] violations=50 duration_ms=2056
2026-11-03T18:19:59.977+01:00 [info    ] data store key read            [log first] namespace=capture key=useNewDashboard found=true
2026-11-03T18:20:00.054+01:00 [info    ] succeeded                      [run] pipeline=dhis2-reads-more run_id=01a1a26c-bae7-71c2-b162-e536c716de4a exit_code=0
```

*The log lines alone; the queued, running and succeeded lines of each step are left out.*

### A data value set as text

`format: csv` asks `/api/dataValueSets.csv` for the selection a JSON export reads, and the
answer is not parsed: it is streamed into the run's storage, and the step answers where it went
(`uri`), how large it is (`content_bytes`), and its head inline (`text`), with `truncated`
saying whether the head was cut. `data_element_id_scheme: CODE` writes each data element by its
code; the org unit and the combos stay uids, because only the data element scheme was named:

```text
dataelement,period,orgunit,categoryoptioncombo,attributeoptioncombo,value,storedby,lastupdated,comment,followup,deleted
DE_36,202507,DiszpKrYNg8,hEFKSsPV5et,HllvX50cXC0,23,system,2014-02-28T18:06:49.000+0000,,false,null
DE_36,202507,DiszpKrYNg8,V6L425pT3A0,HllvX50cXC0,23,system,2014-02-28T18:06:48.000+0000,,false,null
DE_36,202507,DiszpKrYNg8,psbwp3CQEhs,HllvX50cXC0,23,system,2014-02-28T18:06:47.000+0000,,false,null
```

`format: adx` is the same month as ADX, which is written in codes throughout:

```xml
<adx xmlns="urn:ihe:qrph:adx:2015"><group dataSet="DS_359711" period="2025-07-01/P1M" orgUnit="OU_559"><dataValue dataElement="DE_36" EPI_NUTR_AGE="&gt;1y" LOC_FIX_OUTREACH="OUTREACH&#xa;OUTREACH" value="23"/>...
```

2.41 and 2.42 export ADX. 2.43 and later answer an ADX request with JSON, so on those the step
is refused with `dhis2.export.format_unsupported` before it asks, rather than handing on JSON
labelled ADX; every version imports it. A later step reads the whole file from `uri`, never
from `text`: [`dhis2-writes-rehearsed`](../dhis2-writes-rehearsed) sends a CSV export back as a
rehearsed import.

### The data store

`keys` lists a namespace and `first` reads the first key it found. The capture app's namespace
on the demo holds two:

```json
{ "action": "keys", "namespace": "capture", "found": true, "rows": ["useNewDashboard", "bulkDataEntry"] }
{ "action": "get", "namespace": "capture", "key": "useNewDashboard", "found": true, "value": {} }
```

`first` names the key as `${steps.keys.output.rows.0}`. A reference reads a list element as a
dotted segment; written `rows[0]` it is refused at plan with `document.reference_bracket_index`,
which names the dotted form to write instead. A key the namespace does not hold answers
`found: false` and a null value, not a failure.

### A SQL view

`view` runs the demo's one stored SQL view, *Data element by value type*, a `QUERY` view whose
`${valueType}` placeholder is filled from `variables`. Thirteen data elements are `LONG_TEXT`,
each row an object keyed by the view's 27 column names:

```json
{ "title": "Data element by value type", "rows": 13, "first names": ["Other Symptoms", "MCH Visit Comment", "MCH Delivery Comment"] }
```

*Shortened from `output.rows`, `output.columns` and `output.title`.* The block runs a view by
uid and sends no SQL of its own, and it reads every row unless `paging` asks for one page.

### Validation rules, stored nowhere

`validate` runs validation rule analysis over Ngelehun CHC for 2025 and answers each place a
rule does not hold, capped at `max_results: 50`:

```json
{
  "validation_rule": "ZoG4yXZi3c3",
  "validation_rule_description": "ANC 2 cannot be higher than ANC 1",
  "importance": "MEDIUM",
  "org_unit": "DiszpKrYNg8",
  "org_unit_name": "Ngelehun CHC",
  "period": "202501",
  "attribute_option_combo": "HllvX50cXC0",
  "left_side_value": 22.0,
  "operator": "<=",
  "right_side_value": 19.0
}
```

DHIS2 runs the analysis in the one request; there is no job to follow. `persist` and
`notification` are its two writes, storing each violation and sending each rule's
notifications, and both are off, so on a shared demo this is a read. `fail_on_violations: true`
would turn the step into a gate that fails on the first violation.

### What is not here

The pack added three more blocks for DHIS2's own jobs. `dhis2.resource_tables_run` rebuilds the
resource tables, a job that changes the shared demo for everybody on it, and
`dhis2.predictor_run` writes predicted values, with no dry run in DHIS2 for either;
`dhis2.task_wait` follows a job something else started. None is run against the play demo, and
no example here has a DHIS2 of its own for them. The pack's own shelf documents show each:
`uv run dg examples show dhis2-resource-tables` and `uv run dg examples show dhis2-task-wait`.

## Where next

- [`dhis2-writes-rehearsed`](../dhis2-writes-rehearsed): the write blocks, each as a dry run.
- [`dhis2-read-gate-send`](../dhis2-read-gate-send): a read held to a schema before a write is
  built from it.
- The [block reference](https://winterop-com.github.io/dirigent-dhis2/blocks/) for every field,
  and "How an output is shaped" for why a read answers `rows` and an export `body`.
