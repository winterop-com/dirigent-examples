# dhis2-writes-rehearsed

Five kinds of write to a real DHIS2 instance, in one document, **every one of them a dry run**:
DHIS2 resolves what each would write, checks it the way it checks a real write, reports what it
would have done, and stores nothing. The play demo is shared, so this is the only way to write
to it; against your own instance, the same document with `dry_run` off is the real thing.

- **`dhis2.metadata_import`** -- one new data element, sent as a bundle of one.
- **`dhis2.data_value`** -- one cell set to a new value, read before and after so the run itself
  shows the cell did not move.
- **`dhis2.tracker_import`** -- one event, validated by the tracker importer as a job the engine
  follows.
- **`dhis2.data_set_completion`** -- a data set signed off for a month at a facility.
- **`dhis2.data_value_set_import`, `format: csv`** -- a month of values exported as a CSV file
  that names data elements and org units by code, and sent back as it is, the id schemes saying
  how the file names things.

A dry run is not one flag on the wire. Each block sends the one its endpoint really honours, and
that is the reason to use the blocks rather than five HTTP calls:

| Block | What `dry_run: true` sends | Why not the obvious flag |
| --- | --- | --- |
| `dhis2.metadata_import` | `POST /api/metadata?importMode=VALIDATE` | The metadata importer accepts `dryRun=true` without a word and commits the bundle. |
| `dhis2.data_value` | A one-value `POST /api/dataValueSets?dryRun=true` | `/api/dataValues` accepts `dryRun` and writes the value anyway, so a dry run never calls it. |
| `dhis2.tracker_import` | `POST /api/tracker?importMode=VALIDATE` | |
| `dhis2.data_set_completion` | `POST /api/completeDataSetRegistrations?dryRun=true` | |
| `dhis2.data_value_set_import` | `POST /api/dataValueSets?dryRun=true`, the file as `application/csv` | |

Everything below was run against the public DHIS2 demo, `https://play.dhis2.org/2.42`, the
newest 2.42 demo (**2.42.7.1** when this was written) -- the Sierra Leone database, with the
published `admin` / `district` credential. For the read side, see
[`dhis2-reads`](../dhis2-reads).

## Run it

```bash
uv sync
uv run dg validate
uv run dg run --local pipelines/dhis2-writes-rehearsed.yaml --connections connections.yaml
```

`--local` applies and runs the document in a throwaway instance and deletes it on the way out,
so it is handed the connection from `connections.yaml`: the play demo's own published
credential. On an instance of your own, create the `play` connection as
[`dhis2-reads`](../dhis2-reads#run-it) does, then `uv run dg apply` and
`uv run dg run dhis2-writes-rehearsed --watch`.

`./verify.sh` refuses the document before anything is sent if a write step lacks
`dry_run: true`, then runs it locally and asserts on the records: every write answered as a
rehearsal, and the cell read back holding what it held before.

## What you see

`uv run dg validate`:

```text
2026-11-03T18:21:25.591+01:00 [info    ] valid                          [validation] code=dhis2-writes-rehearsed document=pipelines/dhis2-writes-rehearsed.yaml checked="document and installed blocks"
  each step under the last one it waits for
    element  (dhis2.metadata_import)
    before  (dhis2.data_value)
      value  (dhis2.data_value)
        after  (dhis2.data_value)
    visit  (dhis2.tracker_import)
    sign_off  (dhis2.data_set_completion)
    export  (dhis2.data_value_set_export)
      csv  (dhis2.data_value_set_import)
2026-11-03T18:21:25.604+01:00 [info    ] valid                          [validated] documents=1 invalid=0 skipped=0
```

The cell's three steps are a chain, and the CSV import waits for its export; the other three rehearsals wait on nothing and run beside them.

`uv run dg run --local pipelines/dhis2-writes-rehearsed.yaml --connections connections.yaml`:

```text
2026-11-03T18:21:28.269+01:00 [info    ] started                        [run] pipeline=dhis2-writes-rehearsed run_id=01a1a26e-1ec6-7646-a7af-c27cbdc10f3f local=true scratch=file:///tmp/dirigent-local-9m0qmw_p/artifacts/runs/01a1a26e-1ec6-7646-a7af-c27cbdc10f3f root=/tmp/dirigent-local-9m0qmw_p
2026-11-03T18:21:28.221+01:00 [info    ] queued                         [step element] block=dhis2.metadata_import attempt=1
2026-11-03T18:21:28.221+01:00 [info    ] queued                         [step before] block=dhis2.data_value attempt=1
2026-11-03T18:21:28.221+01:00 [info    ] queued                         [step visit] block=dhis2.tracker_import attempt=1
2026-11-03T18:21:28.221+01:00 [info    ] queued                         [step sign_off] block=dhis2.data_set_completion attempt=1
2026-11-03T18:21:28.221+01:00 [info    ] queued                         [step export] block=dhis2.data_value_set_export attempt=1
2026-11-03T18:21:28.322+01:00 [info    ] running                        [step before] block=dhis2.data_value attempt=1
2026-11-03T18:21:28.389+01:00 [info    ] running                        [step element] block=dhis2.metadata_import attempt=1
2026-11-03T18:21:28.409+01:00 [info    ] running                        [step export] block=dhis2.data_value_set_export attempt=1
2026-11-03T18:21:28.429+01:00 [info    ] running                        [step sign_off] block=dhis2.data_set_completion attempt=1
2026-11-03T18:21:28.439+01:00 [info    ] running                        [step visit] block=dhis2.tracker_import attempt=1
2026-11-03T18:21:30.192+01:00 [info    ] succeeded                      [step before] block=dhis2.data_value attempt=1 duration_ms=1870
2026-11-03T18:21:30.192+01:00 [info    ] queued                         [step value] block=dhis2.data_value attempt=1
2026-11-03T18:21:30.198+01:00 [info    ] finished                       [log before] duration_ms=1852 output_bytes=198
2026-11-03T18:21:30.194+01:00 [info    ] completion registration        [log sign_off] status=SUCCESS completed=true imported=0 updated=1 ignored=0 deleted=0
2026-11-03T18:21:30.206+01:00 [info    ] succeeded                      [step sign_off] block=dhis2.data_set_completion attempt=1 duration_ms=1777
2026-11-03T18:21:28.439+01:00 [info    ] waiting                        [step visit] block=dhis2.tracker_import attempt=1
2026-11-03T18:21:30.207+01:00 [info    ] metadata import report         [log element] status=OK dry_run=true imported=1 updated=0 ignored=0 deleted=0 conflicts=0
2026-11-03T18:21:30.218+01:00 [info    ] tracker import job submitted   [log visit] job=pGpkPvOzyjn dry_run=true
2026-11-03T18:21:30.219+01:00 [info    ] succeeded                      [step element] block=dhis2.metadata_import attempt=1 duration_ms=1830
2026-11-03T18:21:30.201+01:00 [info    ] running                        [step value] block=dhis2.data_value attempt=1
2026-11-03T18:21:30.286+01:00 [info    ] data value set exported        [log export] format=csv content_bytes=5113 duration_ms=1859
2026-11-03T18:21:30.287+01:00 [info    ] succeeded                      [step export] block=dhis2.data_value_set_export attempt=1 duration_ms=1879
2026-11-03T18:21:30.287+01:00 [info    ] queued                         [step csv] block=dhis2.data_value_set_import attempt=1
2026-11-03T18:21:30.292+01:00 [info    ] running                        [step csv] block=dhis2.data_value_set_import attempt=1
2026-11-03T18:21:30.989+01:00 [info    ] data value rehearsed           [log value] action=set
2026-11-03T18:21:30.991+01:00 [info    ] succeeded                      [step value] block=dhis2.data_value attempt=1 duration_ms=790
2026-11-03T18:21:30.991+01:00 [info    ] queued                         [step after] block=dhis2.data_value attempt=1
2026-11-03T18:21:30.996+01:00 [info    ] running                        [step after] block=dhis2.data_value attempt=1
2026-11-03T18:21:31.139+01:00 [info    ] import summary                 [log csv] status=SUCCESS imported=0 updated=0 ignored=51 deleted=0 conflict_count=0
2026-11-03T18:21:31.142+01:00 [info    ] succeeded                      [step csv] block=dhis2.data_value_set_import attempt=1 duration_ms=850
2026-11-03T18:21:28.439+01:00 [info    ] running                        [step visit] block=dhis2.tracker_import attempt=1
2026-11-03T18:21:31.702+01:00 [info    ] succeeded                      [step after] block=dhis2.data_value attempt=1 duration_ms=706
2026-11-03T18:21:31.705+01:00 [info    ] finished                       [log after] duration_ms=696 output_bytes=198
2026-11-03T18:21:32.665+01:00 [info    ] tracker import report          [log visit] status=OK dry_run=true imported=0 updated=0 ignored=0 deleted=0 conflicts=0
2026-11-03T18:21:32.668+01:00 [info    ] succeeded                      [step visit] block=dhis2.tracker_import attempt=1 duration_ms=4229
2026-11-03T18:21:32.736+01:00 [info    ] succeeded                      [run] pipeline=dhis2-writes-rehearsed run_id=01a1a26e-1ec6-7646-a7af-c27cbdc10f3f exit_code=0
```

`visit` goes `waiting` once its job is submitted: the tracker importer runs the bundle as a job
on the instance, and the engine probes `/api/tracker/jobs/{id}` every `poll: 5s` instead of
holding a worker for the wait. The outputs are in the run's closing record:

```bash
uv run dg run --local pipelines/dhis2-writes-rehearsed.yaml --connections connections.yaml --json \
  | jq 'select(.kind == "run" and has("exit_code"))
        | .steps | map({key: .step, value: .output}) | from_entries'
```

### The data element

```json
{
  "status": "OK",
  "dry_run": true,
  "sent": 1,
  "counts": { "imported": 1, "updated": 0, "ignored": 0, "deleted": 0 },
  "by_class": {
    "DataElement": { "imported": 1, "updated": 0, "ignored": 0, "deleted": 0 }
  },
  "objects": [],
  "conflicts": []
}
```

One object sent, one the instance would have created -- DHIS2's `created`, answered as
`imported` -- and nothing refused. `objects` stays empty under a validation: the uids it names
are the ones a real import assigned. `import_strategy: CREATE` is there so an element that
already exists is refused rather than quietly updated. One object is a bundle of one,
`{dataElements: [...]}`, and there is no single-object block: the same bundle holding only an
`id` deletes it under `import_strategy: DELETE`, and `UPDATE` with `merge_mode: MERGE` changes
the fields it names and keeps the rest.

### The cell, before and after

`before` read `value: "23"`, `value` rehearsed `"24"`, and `after` read `"23"` again: the
rehearsal resolved the cell, checked the value against the data element's type and left it as
it was. A read of an empty cell is not a failure either; it answers `found: false`.

### The event

```json
{
  "status": "OK",
  "dry_run": true,
  "job_id": "U0i8anG94da",
  "sent": 1,
  "counts": { "imported": 0, "updated": 0, "ignored": 0, "deleted": 0 },
  "conflicts": [],
  "warnings": []
}
```

The counts are all zero because a validation imports nothing; the report says so by having no
errors. The event carries five data values where the pack's own shelf example carries one: the
stage makes four of its data elements compulsory -- admission and discharge dates, the mode of
discharge, the diagnosis -- and DHIS2 2.42 refuses an event without them, rehearsal or not.

### The sign-off

```json
{
  "status": "SUCCESS",
  "completed": true,
  "dry_run": true,
  "sent": 1,
  "counts": { "imported": 0, "updated": 1, "ignored": 0, "deleted": 0 },
  "conflicts": [
    {
      "object": "dataElementOperand",
      "value": "OPV1 doses given Fixed, >1y needs to be filled. It is compulsory.",
      "error_code": null,
      "indexes": []
    },
    {
      "object": "dataElementOperand",
      "value": "Penta2 doses given Fixed, >1y needs to be filled. It is compulsory.",
      "error_code": null,
      "indexes": []
    }
  ]
}
```

`updated: 1`: July 2025 at Ngelehun CHC is already registered complete on the demo, so the
rehearsal would have replaced that registration. The two conflicts are DHIS2 naming compulsory
cells the month leaves empty; it would still take the registration, so the step succeeds and
hands them on. A summary that ignored the registration, or came back `ERROR`, fails the step
with the instance's reason. `completed: false` reopens a window instead.

### The CSV file, named by codes

`export` writes the month as CSV with `data_element_id_scheme: CODE` and
`org_unit_id_scheme: CODE`, the way a file from another system names things, and `csv` sends
that file back from the export's `uri`:

```json
{
  "export": {
    "format": "csv",
    "text": "dataelement,period,orgunit,categoryoptioncombo,attributeoptioncombo,value,storedby,lastupdated,comment,followup,deleted\nDE_36,202507,OU_559,hEFKSsPV5et,HllvX50cXC0,23,system,2014-02-28T18:06:49.000+0000,,false,null\n...",
    "uri": "file:///tmp/dirigent-local-.../artifacts/runs/<run id>/export/attempt-1-data-value-set.csv",
    "content_bytes": 5113,
    "truncated": false
  },
  "csv": {
    "status": "SUCCESS",
    "sent": 51,
    "counts": { "imported": 0, "updated": 0, "ignored": 51, "deleted": 0 },
    "conflicts": []
  }
}
```

*`text` and `uri` shortened.* Fifty-one rows sent and every one resolved: the import names the
same two id schemes, so `DE_36` and `OU_559` are read as codes. All fifty-one are ignored because
the demo already holds each value as it is, and a rehearsal of a value equal to the stored one
changes nothing. Leave the id schemes off the import and the same file comes back `WARNING`,
every row a conflict:

```json
{ "object": "DE_36", "value": "Data element not found or not accessible: `DE_36`", "error_code": "E7610", "indexes": [0, 1, 2, 3] }
```

`atomic_mode: NONE` is what lets a rehearsal report that, rather than refuse the whole file on
the first row. The import reads the file from `data_values_uri`, never the inline `text`, which
is only the head of the file and may be cut.

## Where next

- [`dhis2-reads`](../dhis2-reads): the read side, four blocks side by side and five more,
  the CSV and ADX exports among them.
- [`dhis2-read-gate-send`](../dhis2-read-gate-send): a data value set import, rehearsed, built
  from a read held to a schema.
- The [block reference](https://winterop-com.github.io/dirigent-dhis2/blocks/) for every field
  and refusal.
