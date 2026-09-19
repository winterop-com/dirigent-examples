# dhis2-metadata-to-storage

One level of a DHIS2 organisation unit hierarchy, read, gated, written to storage as a
snapshot, read back and counted. The shape matters because of what storage is in dirigent: a
value moves from step to step as an output, and storage has exactly two doors --
`storage.write` puts a value out at a URI, `storage.read` brings one back in -- and no
`dhis2.*` block opens either. So a read that has to leave a file behind is a read step and a
write step, and reading it back is a third. Writing the file out of the gate rather than out
of the read is the other half of the lesson: what is stored is what passed, and the count at
the end is the count of what came back out of storage, which is what makes the round trip a
proof rather than a hope.

Metadata drifts: a facility is renamed, a district is closed, a hierarchy is rearranged
underneath a data set, and the pipeline that was correct last quarter starts posting into a
cell nobody reads. A snapshot costs one read and one file, and turns "when did this change?"
into a diff.

Everything below was run against the public DHIS2 demo,
`https://play.im.dhis2.org/stable-2-43-1`, version **2.43.1** -- the Sierra Leone database,
with the published `admin` / `district` credential. Nothing here writes to it.

## Run it

`.dirigent/state/` is not in the repository: it is one instance's own database and its
artifacts, disposable, and a clone makes its own. `.dirigent/profiles.yaml` beside it is
committed, because it is addressing rather than state -- which server, and how to get a token
for it. Everything else here is committed too.

```bash
uv sync
```

The fast loop first, with no server anywhere. `--local` applies and runs the document in a
throwaway instance in a temporary directory and deletes it on the way out, so it is handed
the connection and the schema this document names:

```bash
uv run dg validate pipelines/dhis2-metadata-to-storage.yaml
uv run dg run --local pipelines/dhis2-metadata-to-storage.yaml \
  --connections connections.yaml \
  --schema schemas/metadata-snapshot-org-units.json
```

A local run deletes its artifacts on the way out, so add `--keep` to leave the snapshot
behind and be told where it landed.

Then the instance. A DHIS2 connection carries a password, and a connection secret is
encrypted at rest with the instance's own key, so mint one and start the instance with it in
a second terminal, in this directory. Keep the key: an instance that changes it cannot read
what it stored under the old one.

```bash
export DIRIGENT_SECRET_KEY="$(uv run dg secret-key)"
uv run dg dev
```

`dg dev` is one process holding the API, the web UI, the scheduler, one worker and a SQLite
file under `.dirigent/state/`. It keeps running; leave it. On an empty state -- which is what
a fresh clone has, because the state directory is not in the repository -- it migrates the
schema, makes its own admin `dev`, mints that admin one token, and prints the
`export DG_TOKEN=` line to paste. The UI is at `http://127.0.0.1:3333`, which is the address
the `local` profile in `.dirigent/profiles.yaml` holds; `dg dev --port` moves the instance and
`DG_URL` is how you tell the CLI where it went.

Back in the first terminal, mint a token for that admin, whose password is `dirigent-dev`.
The command answers with the `export DG_TOKEN=` line to paste into this terminal, and that
line is the one output this page does not print, because it is a credential:

```bash
uv run dg auth login --username dev --password dirigent-dev
```

```text
  export DG_TOKEN=<the token>

This is the only time the token is shown.
```

The instance holds the shape and the credential; the document names both by code and carries
neither, which is why it applies unchanged anywhere. Both have to exist before the document
does, because `dg apply` refuses a document whose `requires` this instance cannot satisfy:

```bash
uv run dg schema create schemas/metadata-snapshot-org-units.json
uv run dg connection create dhis2 play \
  --name "DHIS2 play demo" \
  --set base_url=https://play.im.dhis2.org/stable-2-43-1 \
  --set basic_username=admin \
  --set basic_password=district
uv run dg connection check play
uv run dg apply
uv run dg run dhis2-metadata-to-storage --watch
```

`dg connection create` asks only for a secret the kind cannot do without, and only when the
command did not say what it wants. This one carries `--set`, and `api_token` is optional, so it
completes without a prompt and leaves that field unset -- which is what it has to be, because a
`dhis2` connection takes an `api_token` or basic credentials, not both.

The snapshot's URI and the count are in the run rather than on the screen, and every command
writes records into a pipe, so each of them is one `jq` away:

```bash
uv run dg runs show <run id> --json \
  | jq '.fields.attempts[] | select(.step_name == "save") | .output'
uv run dg runs show <run id> --json \
  | jq '.fields.attempts[] | select(.step_name == "count") | .output.value'
```

A parameter is a JSON Schema, so a level this hierarchy does not have is refused before a
single call is made:

```bash
uv run dg run dhis2-metadata-to-storage --watch -p level=9
```

`./verify.sh` does all of it unattended -- validate, the local run, an instance on a free
port of its own, the schema, the connection, the apply, the run -- and asserts on the
records rather than on anything rendered: that the bytes written are the bytes read, that
what came back out of storage is what went in, and that the count is the count of what the
gate passed. It stops the instance it started by pid on the way out.

## What you see

*Printed as it printed, with this project's directory written as
`/home/you/dhis2-metadata-to-storage` and a local run's temporary root as `/tmp`.*

`uv run dg validate pipelines/dhis2-metadata-to-storage.yaml`:

```text
2026-09-17T15:08:41.999+02:00 [info    ] valid                          [validation] code=dhis2-metadata-to-storage document=pipelines/dhis2-metadata-to-storage.yaml checked="document, offline"
  each step under the last one it waits for
    read  (dhis2.metadata)
      check  (validate.schema)
        save  (storage.write)
          load  (storage.read)
            count  (transform.jq)
              say  (log.write)  also after save
2026-09-17T15:08:42.010+02:00 [info    ] valid                          [validated] documents=1 invalid=0
```

Nothing has run and nothing has been contacted: that tree is the graph the document already
holds, each step under the last one it waits for, and `also after save` is the second edge
`say` carries.

`uv run dg run --local ...`:

```text
2026-09-17T15:08:43.693+02:00 [info    ] started                        [run] pipeline=dhis2-metadata-to-storage run_id=01a0af7b-d62a-775c-96bd-b86dbb6c338d local=true scratch=file:///tmp/dirigent-local-8ax8yhd7/artifacts/runs/01a0af7b-d62a-775c-96bd-b86dbb6c338d root=/tmp/dirigent-local-8ax8yhd7
2026-09-17T15:08:43.689+02:00 [info    ] queued                         [step read] block=dhis2.metadata attempt=1
2026-09-17T15:08:43.726+02:00 [info    ] running                        [step read] block=dhis2.metadata attempt=1
2026-09-17T15:08:44.950+02:00 [info    ] metadata read                  [log read] resource=organisationUnits duration_ms=1215
2026-09-17T15:08:44.951+02:00 [info    ] succeeded                      [step read] block=dhis2.metadata attempt=1 duration_ms=1226
2026-09-17T15:08:44.963+02:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=7
2026-09-17T15:08:44.967+02:00 [info    ] finished                       [log check] duration_ms=1 output_bytes=902
2026-09-17T15:08:45.025+02:00 [info    ] wrote                          [log save] uri=dhis2/organisation-units-level-2.json bytes_written=892 content_type=application/json
2026-09-17T15:08:45.026+02:00 [info    ] succeeded                      [step save] block=storage.write attempt=1 duration_ms=10
2026-09-17T15:08:45.087+02:00 [info    ] read                           [log load] uri=dhis2/organisation-units-level-2.json bytes_read=892 content_type=application/json
2026-09-17T15:08:45.089+02:00 [info    ] succeeded                      [step load] block=storage.read attempt=1 duration_ms=14
2026-09-17T15:08:45.189+02:00 [info    ] succeeded                      [step count] block=transform.jq attempt=1 duration_ms=51
2026-09-17T15:08:45.192+02:00 [info    ] finished                       [log count] duration_ms=42 output_bytes=67
2026-09-17T15:08:45.223+02:00 [info    ] the snapshot at file:///tmp/dirigent-local-8ax8yhd7/artifacts/runs/01a0af7b-d62a-775c-96bd-b86dbb6c338d/dhis2/organisation-units-level-2.json holds 13 organisation units, Bo to Western Area [log say]
2026-09-17T15:08:45.223+02:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=6
2026-09-17T15:08:45.425+02:00 [info    ] succeeded                      [run] pipeline=dhis2-metadata-to-storage run_id=01a0af7b-d62a-775c-96bd-b86dbb6c338d exit_code=0
steps
┏━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step  ┃ block           ┃ outcome   ┃ after       ┃ duration ┃ output                            ┃
┡━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ read  │ dhis2.metadata  │ succeeded │ -           │ 1.2s     │ body={1 keys}  duration_ms=1215   │
│ check │ validate.schema │ succeeded │ read        │ 0.0s     │ value={1 keys}                    │
│ save  │ storage.write   │ succeeded │ check       │ 0.0s     │ uri=dhis2/organisation-units-lev… │
│       │                 │           │             │          │ bytes_written=892                 │
│       │                 │           │             │          │ content_type=application/json     │
│ load  │ storage.read    │ succeeded │ save        │ 0.0s     │ content_type=application/json     │
│       │                 │           │             │          │ value={1 keys}  bytes_read=892    │
│ count │ transform.jq    │ succeeded │ load        │ 0.1s     │ value={4 keys}                    │
│ say   │ log.write       │ succeeded │ count, save │ 0.0s     │ -                                 │
└───────┴─────────────────┴───────────┴─────────────┴──────────┴───────────────────────────────────┘
```

892 bytes written and 892 bytes read: the file is the proof, and the line `say` wrote is the
count of what came back out of it.

`uv run dg schema create ...` and `uv run dg connection create ...`:

```text
stored schema metadata-snapshot-org-units
```

```text
2026-09-17T15:08:52.544+02:00 [info    ] created                        [connection.created] code=play connection_kind=dhis2 name="DHIS2 play demo" config={"base_url":"https://play.im.dhis2.org/stable-2-43-1","api_token":null,"basic_username":"admin","verify_tls":true,"timeout":"30s","basic_password":"***"}
```

The password is already withheld in the record the command answers with, and in every read
after it.

`uv run dg connection check play`:

```text
2026-09-17T15:08:54.742+02:00 [info    ] healthy                        [connection.checked] code=play healthy=true version=2.43.1
```

One line, four facts: the URL resolves, TLS is as configured, the credential is accepted, and
the instance's version is **2.43.1** -- its own word for itself, read from `/api/system/info`
rather than guessed from an `/api/N` path.

`uv run dg apply`:

```text
create dhis2-metadata-to-storage  version 1 (/home/you/dhis2-metadata-to-storage/pipelines/dhis2-metadata-to-storage.yaml)
```

`uv run dg run dhis2-metadata-to-storage --watch`:

```text
2026-09-17T15:08:57.181+02:00 [info    ] started                        [run] pipeline=dhis2-metadata-to-storage run_id=01a0af7c-0ad9-75db-a3c9-f2bdff5fdc52 local=false
2026-09-17T15:08:57.179+02:00 [info    ] queued                         [step read] block=dhis2.metadata attempt=1
2026-09-17T15:08:57.247+02:00 [info    ] running                        [step read] block=dhis2.metadata attempt=1
2026-09-17T15:08:57.179+02:00 [info    ] queued                         [step save] block=storage.write attempt=1
2026-09-17T15:08:57.863+02:00 [info    ] metadata read                  [log read] resource=organisationUnits duration_ms=607
2026-09-17T15:08:57.865+02:00 [info    ] succeeded                      [step read] block=dhis2.metadata attempt=1 duration_ms=618
2026-09-17T15:08:58.267+02:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=5
2026-09-17T15:08:58.270+02:00 [info    ] finished                       [log check] duration_ms=0 output_bytes=902
2026-09-17T15:08:57.179+02:00 [info    ] queued                         [step count] block=transform.jq attempt=1
2026-09-17T15:08:58.775+02:00 [info    ] wrote                          [log save] uri=file://./.dirigent/state/artifacts/runs/01a0af7c-0ad9-75db-a3c9-f2bdff5fdc52/dhis2/organisation-units-level-2.json bytes_written=892 content_type=application/json
2026-09-17T15:08:58.776+02:00 [info    ] succeeded                      [step save] block=storage.write attempt=1 duration_ms=7
2026-09-17T15:08:59.283+02:00 [info    ] read                           [log load] uri=file://./.dirigent/state/artifacts/runs/01a0af7c-0ad9-75db-a3c9-f2bdff5fdc52/dhis2/organisation-units-level-2.json bytes_read=892 content_type=application/json
2026-09-17T15:08:59.284+02:00 [info    ] succeeded                      [step load] block=storage.read attempt=1 duration_ms=8
2026-09-17T15:08:59.842+02:00 [info    ] succeeded                      [step count] block=transform.jq attempt=1 duration_ms=57
2026-09-17T15:08:59.844+02:00 [info    ] finished                       [log count] duration_ms=43 output_bytes=67
2026-09-17T15:09:00.325+02:00 [info    ] the snapshot at file://./.dirigent/state/artifacts/runs/01a0af7c-0ad9-75db-a3c9-f2bdff5fdc52/dhis2/organisation-units-level-2.json holds 13 organisation units, Bo to Western Area [log say]
2026-09-17T15:09:00.325+02:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=5
2026-09-17T15:09:01.318+02:00 [info    ] succeeded                      [run] pipeline=dhis2-metadata-to-storage run_id=01a0af7c-0ad9-75db-a3c9-f2bdff5fdc52 pipeline_version=1 triggered_by="dev (token cli-dev)" duration_ms=3079 items_total=0 items_failed=0 exit_code=0 priority=normal
run 01a0af7c-0ad9-75db-a3c9-f2bdff5fdc52
pipeline      dhis2-metadata-to-storage (version 1)
status        succeeded
triggered by  dev (token cli-dev)
duration      3.1s
items         -

steps
┏━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━┓
┃ step  ┃ block           ┃ outcome   ┃ after       ┃ attempts ┃ duration ┃ error ┃
┡━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━┩
│ read  │ dhis2.metadata  │ succeeded │ -           │ 1        │ 0.6s     │ -     │
│ check │ validate.schema │ succeeded │ read        │ 1        │ 0.0s     │ -     │
│ save  │ storage.write   │ succeeded │ check       │ 1        │ 0.0s     │ -     │
│ load  │ storage.read    │ succeeded │ save        │ 1        │ 0.0s     │ -     │
│ count │ transform.jq    │ succeeded │ load        │ 1        │ 0.1s     │ -     │
│ say   │ log.write       │ succeeded │ count, save │ 1        │ 0.0s     │ -     │
└───────┴─────────────────┴───────────┴─────────────┴──────────┴──────────┴───────┘

outputs
┏━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step  ┃ output                                                                                   ┃
┡━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ read  │ body={1 keys}  duration_ms=607                                                           │
│ check │ value={1 keys}                                                                           │
│ save  │ uri=file://./.dirigent/state/artifacts/runs/01a0af7c-0ad9-75db-a3c9-f2bdff5fdc52/dhis2/… │
│       │ bytes_written=892  content_type=application/json                                         │
│ load  │ content_type=application/json  value={1 keys}  bytes_read=892                            │
│ count │ value={4 keys}                                                                           │
│ say   │ -                                                                                        │
└───────┴──────────────────────────────────────────────────────────────────────────────────────────┘
```

Same document, same five hops, and the only difference is where the file landed: on the
instance `${run.scratch}` is this run's own directory under the artifact root rather than a
temporary one that is about to be deleted.

`uv run dg runs show ... | jq ...`, the write and the count:

```json
{
  "uri": "file://./.dirigent/state/artifacts/runs/01a0af7c-0ad9-75db-a3c9-f2bdff5fdc52/dhis2/organisation-units-level-2.json",
  "bytes_written": 892,
  "content_type": "application/json"
}
```

```json
{
  "level": 2,
  "units": 13,
  "first": "Bo",
  "last": "Western Area"
}
```

Thirteen districts, Bo to Western Area -- read back out of the file, not counted on the way
in.

`uv run dg run dhis2-metadata-to-storage --watch -p level=9`:

```text
2026-09-17T15:09:04.877+02:00 [error   ] parameter level is invalid: 9 is greater than the maximum of 4 [error] status=422 title="Unprocessable Content" instance=/api/v1/pipelines/dhis2-metadata-to-storage/$run
```

Nothing ran. A parameter's schema is checked when the run is submitted, not when the call is
made.

## The document, hop by hop

`pipelines/dhis2-metadata-to-storage.yaml`, in full -- the file itself carries these notes as
comments, at the line each one is about.

The header says which document language this is and which sort of document, and then the
quartet every addressable thing carries: `code` is the key this pipeline is addressed by,
`name` a human title with no identity at all, `description` the long form.

```yaml
format: dirigent/v1
kind: pipeline
code: dhis2-metadata-to-storage
name: Organisation units, snapshotted
description: Read one level of the organisation unit hierarchy, gate it, write it to storage, read it back and count it.

tags: [dhis2, metadata, validate, storage, transform]
```

`requires` is the document saying what it needs of an instance: every block id, the
connection code, the schema code. An instance missing one of them refuses the document rather
than failing halfway through a run.

```yaml
requires:
  blocks:
    - dhis2.metadata
    - validate.schema
    - storage.write
    - storage.read
    - transform.jq
    - log.write
  connections:
    - play
  schemas:
    - metadata-snapshot-org-units
```

`params` is a JSON Schema over the run's parameters. `minimum` and `maximum` are why
`-p level=9` above never reached DHIS2.

```yaml
params:
  type: object
  properties:
    level:
      type: integer
      minimum: 1
      maximum: 4
      default: 2
      description: The hierarchy level to snapshot. 2 is the districts of the play demo.
```

**Hop one, `read`.** `dhis2.metadata` reads one collection through the accessor the
instance's own version publishes, so `resource` is the collection name exactly as it appears
in the API path. `fields` is the DHIS2 projection, and it is what keeps a snapshot small:
ask for the columns a diff is about, not for `:owner`. The step names the connection by code
and carries no credential at all.

```yaml
steps:
  read:
    block: dhis2.metadata
    retry:
      max_attempts: 3
      backoff: 2s
    config:
      connection: play
      resource: organisationUnits
      fields: id,code,name,level
      filter: "level:eq:${params.level}"
      order: [name:asc]
```

A reference that is the whole value resolves to the typed value; one inside a larger string
interpolates as text, which is what `filter:` wants. The retry budget is for the failures
worth spending it on: a connection failure on the wire, a 5xx and a 429 are `transient` and
are retried, while any other 4xx and a collection name this version does not publish are
`rejected` and spend no budget at all.

**Hop two, `check`.** The gate, naming a schema by code -- the one the instance holds, so
two pipelines gating on the same shape gate on the same shape. A mismatch is `rejected`: the
same value against the same schema will never pass, so it is not retried.

```yaml
  check:
    block: validate.schema
    depends_on: [read]
    config:
      input: ${steps.read.output.body}
      schema: metadata-snapshot-org-units
```

**Hop three, `save`.** The first of storage's two doors. `${run.scratch}` is this run's own
directory under the artifact root; a target naming a bucket URI writes there instead and
outlives the run, and nothing above it changes, because the scheme is the only difference.
The level is in the file name, so a run per level leaves one file per level rather than each
overwriting the last.

```yaml
  save:
    block: storage.write
    depends_on: [check]
    config:
      target: "${run.scratch}/dhis2/organisation-units-level-${params.level}.json"
      value: ${steps.check.output.value}
      content_type: application/json
```

`value:` is written out of the gate rather than out of the read. `validate.schema` hands its
input on unchanged as `value`, which makes the gate a waypoint: what is in the file provably
passed the shape.

**Hop four, `load`.** The other door. It names `${steps.save.output.uri}` rather than
repeating the path, so the write decides where the file is and the read simply follows it --
change the target to a bucket and this step needs no edit.

```yaml
  load:
    block: storage.read
    depends_on: [save]
    config:
      source: ${steps.save.output.uri}
```

**Hop five, `count`.** The proof. `transform.jq` runs a jq program over a value, and this one
reduces the snapshot that came *back* to four facts. Counting the read's own output instead
would prove nothing about the file.

```yaml
  count:
    block: transform.jq
    depends_on: [load]
    config:
      input: ${steps.load.output.value}
      program: |
        {
          level: (.organisationUnits[0].level),
          units: (.organisationUnits | length),
          first: (.organisationUnits[0].name),
          last: (.organisationUnits[-1].name)
        }
```

And one line in the run's log, so the count is on the screen as well as in the record. `say`
waits for two steps, which is the one place in this document where the graph is not a line.

```yaml
  say:
    block: log.write
    depends_on: [count, save]
    config:
      message: "the snapshot at ${steps.save.output.uri} holds ${steps.count.output.value.units} organisation units, ${steps.count.output.value.first} to ${steps.count.output.value.last}"
```

### The shape, and the credential

`schemas/metadata-snapshot-org-units.json` is the contract, applied on its own with
`dg schema create`. A schema reads its identity from its own keywords: `$id` becomes the code
it is addressed by, `title` its name, `description` its body.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "metadata-snapshot-org-units",
  "title": "Organisation units, as a snapshot keeps them",
  "description": "An organisationUnits read projected to id, code, name and level, with every identifier held to the pack's own dhis2-uid format and every code to dhis2-code.",
  "type": "object",
  "required": ["organisationUnits"],
  "properties": {
    "organisationUnits": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "required": ["id", "code", "name", "level"],
        "properties": {
          "id": { "type": "string", "format": "dhis2-uid" },
          "code": { "type": "string", "format": "dhis2-code" },
          "name": { "type": "string", "minLength": 1 },
          "level": { "type": "integer", "minimum": 1 }
        },
        "additionalProperties": false
      }
    }
  }
}
```

`required` is about presence, `properties` about shape, and `additionalProperties: false`
closes the door on anything the projection did not ask for -- which is what makes this gate
notice a `fields=` line somebody widened. `dhis2-uid` and `dhis2-code` are this pack's
formats, and they assert because the pack is installed: in JSON Schema a `format` annotates
and nothing more, but dirigent always hands its validator a checker and every installed
pack's formats join it. A uid that is ten characters instead of eleven fails here, in one
line with the path in it.

`connections.yaml` is what a `--local` run is handed, because a local run starts on a
throwaway instance holding nothing. The credential in it is the play demo's own, published so
that anyone may try the instance; a real one belongs in a connection the server holds,
encrypted under its key, and never in a file beside the documents. The server refuses a
document that carries a `connections:` section for exactly that reason, which is why this is
a file of its own rather than a section of the pipeline.

## Where to go next

- [`dhis2-org-unit-sync`](../dhis2-org-unit-sync/README.md) is what comes next: the same
  three moves in each of the three directions a sync is ever asked for, against two DHIS2
  instances named by code, with the reshape in the middle written where a reviewer can read
  it.
- [**The DHIS2 tutorial**](https://winterop-com.github.io/dirigent-dhis2/tutorial/) is the
  same three moves -- read, gate, send -- against the same play demo, with the failures
  shown.
- [**The examples**](../README.md): every example in order, and what you need once.
