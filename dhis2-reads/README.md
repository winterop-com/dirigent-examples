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
reach, and it fails on purpose.

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

`./verify.sh` runs both documents locally and asserts on their records.

## What you see

`uv run dg validate`:

```text
2026-11-03T14:25:16.466+01:00 [info    ] valid                          [validation] code=dhis2-reads-capped document=pipelines/dhis2-reads-capped.yaml checked="document and installed blocks"
  each step under the last one it waits for
    children  (dhis2.tracker)
2026-11-03T14:25:16.480+01:00 [info    ] valid                          [validation] code=dhis2-reads document=pipelines/dhis2-reads.yaml checked="document and installed blocks"
  each step under the last one it waits for
    info  (dhis2.system_info)
    holdings  (dhis2.metadata_export)
    changed  (dhis2.data_value_set_export)
    children  (dhis2.tracker)
2026-11-03T14:25:16.481+01:00 [info    ] valid                          [validated] documents=2 invalid=0 skipped=0
```

Four steps, none under another: they are queued together and run at once.

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

The step names two data sets where one would do. With exactly one data set and no period,
DHIS2's answer names no data set, and dirigent-dhis2 0.33 reads that as an org unit outside the
account's data scope and refuses the export as `dhis2.export.empty_answer`.

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

## Where next

- [`dhis2-writes-rehearsed`](../dhis2-writes-rehearsed): the write blocks, each as a dry run.
- [`dhis2-read-gate-send`](../dhis2-read-gate-send): a read held to a schema before a write is
  built from it.
- The [block reference](https://winterop-com.github.io/dirigent-dhis2/blocks/) for every field,
  and "How an output is shaped" for why a read answers `rows` and an export `body`.
