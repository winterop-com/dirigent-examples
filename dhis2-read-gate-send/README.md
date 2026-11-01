# dhis2-read-gate-send

Three hops against a real DHIS2 instance, in one document: **one read**, **a schema gate on
the answer**, and **a write built from the validated value**. The shape matters because of
the middle hop. A metadata read is a contract with a system you do not control, and
`validate.schema` is where that contract is written down: a payload that has moved stops at
the step it arrived in, naming the path that is wrong, instead of turning into something
strange three steps later. The gate is also a waypoint -- it hands its input on unchanged as
`value` -- so the write below it reads the organisation unit out of the gate rather than out
of the read, and every step past it provably received the shape. The write is rehearsed:
`dry_run: true`, against the shared play demo, so DHIS2 resolves every value, checks it
against its data element's value type, reports what it would have done, and persists nothing.

Everything below was run against the public DHIS2 demo,
`https://play.dhis2.org/2.42`, the newest 2.42 demo (**2.42.6** when this was written) -- the Sierra Leone database,
with the published `admin` / `district` credential.

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
uv run dg validate pipelines/dhis2-read-gate-send.yaml
uv run dg run --local pipelines/dhis2-read-gate-send.yaml \
  --connections connections.yaml \
  --schema schemas/read-gate-send-org-units.json
```

Then the instance. A DHIS2 connection carries a password, and a connection secret is
encrypted at rest with the instance's own key, so the instance needs a key before it can hold
one. Mint it once into `.env` -- the gitignored file beside the state that already holds this
instance's token -- and every command run in this directory reads it from there, which is what
keeps this instance on the key it sealed with: one that changes its key cannot open the secrets
it already stored. In a second terminal, in this directory:

```bash
grep -q '^DIRIGENT_SECRET_KEY=' .env 2>/dev/null \
  || printf 'DIRIGENT_SECRET_KEY=%s\n' "$(uv run dg secret-key)" >> .env
uv run dg dev
```

`dg dev` is one process holding the API, the web UI, the scheduler, one worker and a SQLite
file under `.dirigent/state/`. It keeps running; leave it. On an empty state -- which is what
a fresh clone has, because the state directory is not in the repository -- it migrates the
schema, makes its own admin `admin`, mints that admin one token, and prints the
`export DG_TOKEN=` line to paste. The UI is at `http://127.0.0.1:3333`, which is the address
the `local` profile in `.dirigent/profiles.yaml` holds; `dg dev --port` moves the instance and
`DG_URL` is how you tell the CLI where it went.

Back in the first terminal, mint a token for that admin, whose password is `admin`.
The command answers with the `export DG_TOKEN=` line to paste into this terminal, and that
line is the one output this page does not print, because it is a credential:

```bash
uv run dg auth login --username admin --password admin
```

```text
  export DG_TOKEN=<the token>

This is the only time the token is shown.
```

The instance holds the shape and the credential; the document names both by code and carries
neither, which is why it applies unchanged anywhere. Both have to exist before the document
does, because `dg apply` refuses a document whose `requires` this instance cannot satisfy:

```bash
uv run dg schema create schemas/read-gate-send-org-units.json
uv run dg connection create dhis2 play \
  --name "DHIS2 play demo" \
  --set base_url=https://play.dhis2.org/2.42 \
  --set follow_redirects_with_auth=true \
  --set basic_username=admin \
  --set basic_password=district
uv run dg connection check play
uv run dg apply
uv run dg run dhis2-read-gate-send --watch
```

`dg connection create` asks only for a secret the kind cannot do without, and only when the
command did not say what it wants. This one carries `--set`, and `api_token` is optional, so it
completes without a prompt and leaves that field unset -- which is what it has to be, because a
`dhis2` connection takes an `api_token` or basic credentials, not both.

The import summary is in the run rather than on the screen, and every command writes records
into a pipe, so the whole of it is one `jq` away:

```bash
uv run dg runs show <run id> --json \
  | jq '.fields.attempts[] | select(.step_name == "send") | .output'
```

A parameter is a JSON Schema too, and `format: dhis2-uid` is this pack's, so a run submitted
with something that is not a DHIS2 uid is refused before a single call is made:

```bash
uv run dg run dhis2-read-gate-send --watch -p parent=ImspTQPwCq
```

`./verify.sh` does all of it unattended -- validate, the local run, an instance on a free
port of its own, the schema, the connection, the apply, the run -- and asserts on the
records rather than on anything rendered. It keeps the key on that same `.env` line, and
writes the schema and the connection only when the instance does not already hold them, so its
second run inherits the state its first run left. It stops the instance it started by pid on
the way out.

### If the key was lost

A connection is sealed with the key the instance held when it was written, so a state left over
from a key that is gone answers `uv run dg connection check play` with a record whose `detail`
begins `SecretKeyMismatch`. Nothing opens that row again, and the secret it holds is not
recoverable. Nor can it be deleted once a pipeline names it: `dg connection delete` names the
pipeline and refuses. So write it once more, in place, under the key this instance has now.
`dg connection ensure` writes the row straight to this instance's database, reading `.env` for
the key rather than a token, and brings it whole to what the arguments say:

```bash
uv run dg connection ensure dhis2 play \
  --name "DHIS2 play demo" \
  --set base_url=https://play.dhis2.org/2.42 \
  --set follow_redirects_with_auth=true \
  --set basic_username=admin \
  --set basic_password=district
```

`verify.sh` does exactly that when its own check reports that class.

## What you see

*Printed as it printed, with this project's directory written as
`/home/you/dhis2-read-gate-send` and a local run's temporary root as `/tmp`.*

`uv run dg validate pipelines/dhis2-read-gate-send.yaml`:

```text
2026-09-17T15:03:01.867+02:00 [info    ] valid                          [validation] code=dhis2-read-gate-send document=pipelines/dhis2-read-gate-send.yaml checked="document and installed blocks"
  each step under the last one it waits for
    read  (dhis2.metadata)
      check  (validate.schema)
        send  (dhis2.data_value_set_import)
2026-09-17T15:03:01.870+02:00 [info    ] valid                          [validated] documents=1 invalid=0 skipped=0
```

Nothing has run and nothing has been contacted: that tree is the graph the document already
holds, each step under the last one it waits for.

`uv run dg run --local ...`:

```text
2026-09-26T15:05:42.542+02:00 [info    ] started                        [run] pipeline=dhis2-read-gate-send run_id=01a0ddd2-4e8a-727f-a11b-e7f96ef17c6f local=true scratch=file:///tmp/dirigent-local-wfem4yaq/artifacts/runs/01a0ddd2-4e8a-727f-a11b-e7f96ef17c6f root=/tmp/dirigent-local-wfem4yaq
2026-09-26T15:05:42.537+02:00 [info    ] queued                         [step read] block=dhis2.metadata attempt=1
2026-09-26T15:05:42.579+02:00 [info    ] running                        [step read] block=dhis2.metadata attempt=1
2026-09-26T15:05:43.774+02:00 [info    ] metadata read                  [log read] resource=organisationUnits duration_ms=1182
2026-09-26T15:05:43.776+02:00 [info    ] succeeded                      [step read] block=dhis2.metadata attempt=1 duration_ms=1197
2026-09-26T15:05:43.788+02:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=6
2026-09-26T15:05:43.791+02:00 [info    ] finished                       [log check] duration_ms=0 output_bytes=469
2026-09-26T15:05:43.840+02:00 [info    ] running                        [step send] block=dhis2.data_value_set_import attempt=1
2026-09-26T15:05:44.469+02:00 [info    ] import summary                 [log send] status=SUCCESS imported=0 updated=2 ignored=0 deleted=0 conflict_count=0
2026-09-26T15:05:44.471+02:00 [info    ] succeeded                      [step send] block=dhis2.data_value_set_import attempt=1 duration_ms=631
2026-09-26T15:05:44.545+02:00 [info    ] succeeded                      [run] pipeline=dhis2-read-gate-send run_id=01a0ddd2-4e8a-727f-a11b-e7f96ef17c6f exit_code=0
steps
┏━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step  ┃ block                       ┃ outcome   ┃ after ┃ duration ┃ output                      ┃
┡━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ read  │ dhis2.metadata              │ succeeded │ -     │ 1.2s     │ body={1 keys}               │
│       │                             │           │       │          │ duration_ms=1182            │
│ check │ validate.schema             │ succeeded │ read  │ 0.0s     │ value={1 keys}              │
│ send  │ dhis2.data_value_set_import │ succeeded │ check │ 0.6s     │ status=SUCCESS  imported=0  │
│       │                             │           │       │          │ updated=2  ignored=0        │
│       │                             │           │       │          │ deleted=0                   │
└───────┴─────────────────────────────┴───────────┴───────┴──────────┴─────────────────────────────┘
```

`uv run dg schema create ...` and `uv run dg connection create ...`:

```text
stored schema read-gate-send-org-units
```

```text
2026-09-17T15:03:12.605+02:00 [info    ] created                        [connection.created] code=play connection_kind=dhis2 name="DHIS2 play demo" config={"base_url":"https://play.dhis2.org/2.42","api_token":null,"basic_username":"admin","verify_tls":true,"follow_redirects_with_auth":true,"timeout":"30s","request_deadline":"10m","max_response":"64mb","basic_password":"***"}
```

The password is already withheld in the record the command answers with, and in every read
after it.

`uv run dg connection check play`:

```text
2026-09-17T15:03:14.654+02:00 [info    ] healthy                        [connection.checked] code=play healthy=true version=2.42.6
```

One line, four facts: the URL resolves, TLS is as configured, the credential is accepted,
and the instance's version is **2.42.6** -- its own word for itself, read from
`/api/system/info` rather than guessed from an `/api/N` path. That version is why
`dhis2.metadata` can refuse a collection name this instance does not publish instead of
sending a request that will 404.

`uv run dg apply`:

```text
create dhis2-read-gate-send  version 1 (/home/you/dhis2-read-gate-send/pipelines/dhis2-read-gate-send.yaml)
```

`uv run dg run dhis2-read-gate-send --watch`:

```text
2026-09-26T15:06:39.861+02:00 [info    ] started                        [run] pipeline=dhis2-read-gate-send run_id=01a0ddd3-2e71-75d5-9632-1cb6d40056ec local=false
2026-09-26T15:06:39.859+02:00 [info    ] queued                         [step read] block=dhis2.metadata attempt=1
2026-09-26T15:06:40.100+02:00 [info    ] running                        [step read] block=dhis2.metadata attempt=1
2026-09-26T15:06:41.160+02:00 [info    ] metadata read                  [log read] resource=organisationUnits duration_ms=1042
2026-09-26T15:06:41.164+02:00 [info    ] succeeded                      [step read] block=dhis2.metadata attempt=1 duration_ms=1065
2026-09-26T15:06:41.669+02:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=6
2026-09-26T15:06:41.674+02:00 [info    ] finished                       [log check] duration_ms=0 output_bytes=469
2026-09-26T15:06:42.172+02:00 [info    ] running                        [step send] block=dhis2.data_value_set_import attempt=1
2026-09-26T15:06:43.282+02:00 [info    ] import summary                 [log send] status=SUCCESS imported=0 updated=2 ignored=0 deleted=0 conflict_count=0
2026-09-26T15:06:43.285+02:00 [info    ] succeeded                      [step send] block=dhis2.data_value_set_import attempt=1 duration_ms=1113
2026-09-26T15:06:43.989+02:00 [info    ] succeeded                      [run] pipeline=dhis2-read-gate-send run_id=01a0ddd3-2e71-75d5-9632-1cb6d40056ec pipeline_version=1 triggered_by="admin (token dev)" duration_ms=3185 items_total=0 items_failed=0 exit_code=0 priority=normal
run 01a0ddd3-2e71-75d5-9632-1cb6d40056ec
pipeline      dhis2-read-gate-send (version 1)
status        succeeded
triggered by  admin (token dev)
duration      3.2s
items         -

steps
┏━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━┓
┃ step  ┃ block                       ┃ outcome   ┃ after ┃ attempts ┃ duration ┃ error ┃
┡━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━┩
│ read  │ dhis2.metadata              │ succeeded │ -     │ 1        │ 1.1s     │ -     │
│ check │ validate.schema             │ succeeded │ read  │ 1        │ 0.0s     │ -     │
│ send  │ dhis2.data_value_set_import │ succeeded │ check │ 1        │ 1.1s     │ -     │
└───────┴─────────────────────────────┴───────────┴───────┴──────────┴──────────┴───────┘

outputs
┏━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step  ┃ output                                                      ┃
┡━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ read  │ body={1 keys}  duration_ms=1042                             │
│ check │ value={1 keys}                                              │
│ send  │ status=SUCCESS  imported=0  updated=2  ignored=0  deleted=0 │
└───────┴─────────────────────────────────────────────────────────────┘
```

`uv run dg runs show ... | jq ...`:

```json
{
  "status": "SUCCESS",
  "imported": 0,
  "updated": 2,
  "ignored": 0,
  "deleted": 0,
  "conflicts": []
}
```

DHIS2's import summary is the step's output, parsed: a status, the four counts, and the
conflicts. `updated=2` means the instance resolved both values, checked each against its
data element's value type, decided it would have revised two existing values -- and then
threw the result away, because `dry_run` was on. The output above was recorded on a demo that
already held both values; 2.42.6 does not, so there the same rehearsal says `imported=2`, and
still writes nothing. A refused value would be a row in
`conflicts` in the instance's own words, and a summary whose status is `ERROR` fails the
step rather than reporting success with bad news inside it.

`uv run dg run dhis2-read-gate-send --watch -p parent=ImspTQPwCq`:

```text
2026-09-17T15:03:23.287+02:00 [error   ] parameter parent is invalid: 'ImspTQPwCq' is not a 'dhis2-uid' [error] status=422 title="Unprocessable Content" code=parameter.invalid params={"location":"parent","detail":"'ImspTQPwCq' is not a 'dhis2-uid'"} instance=/api/v1/pipelines/dhis2-read-gate-send/$run
```

Ten characters instead of eleven. Nothing ran.

## The document, hop by hop

`pipelines/dhis2-read-gate-send.yaml`, in full -- the file itself carries these notes as
comments, at the line each one is about.

The header says which document language this is and which sort of document, and then the
quartet every addressable thing carries: `code` is the key this pipeline is addressed by,
`name` a human title with no identity at all, `description` the long form.

```yaml
format: dirigent/v1
kind: pipeline
code: dhis2-read-gate-send
name: Read, gate, send
description: Read organisation units from the play demo, gate them on a schema, and rehearse an import at the first one.

tags: [dhis2, validate, references]
```

`requires` is the document saying what it needs of an instance: the block ids, the
connection code, the schema code. An instance missing one of them refuses the document
rather than failing halfway through a run, which is why the schema and the connection are
created before the apply above and not after it.

```yaml
requires:
  blocks:
    - dhis2.metadata
    - validate.schema
    - dhis2.data_value_set_import
  connections:
    - play
  schemas:
    - read-gate-send-org-units
```

`params` is a JSON Schema over the run's parameters, and a `format` this pack contributes is
enforced rather than annotated: `dg run -p parent=...` is refused at submission, before a call
is made. A parameter with a `default` may be left out.

```yaml
params:
  type: object
  properties:
    parent:
      type: string
      format: dhis2-uid
      default: jPidqyo7cpF
      description: The uid of the parent whose children are read. Bagruwa chiefdom by default.
    period:
      type: string
      format: dhis2-period
      default: "202507"
      description: The ISO period the rehearsed values belong to.
```

**Hop one, `read`.** `dhis2.metadata` reads one collection through the accessor the
instance's own version publishes, so `resource` is the collection name exactly as it appears
in the API path. `fields` is the DHIS2 projection: it decides what comes back, and what it
does not name does not arrive. `filter` is DHIS2's own syntax -- a property path, an
operator, a value. The step names the connection by code and carries no credential at all.

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
      filter: "parent.id:eq:${params.parent}"
      order: [name:asc]
```

The retry budget is for the failures worth spending it on. A connection failure on the wire,
a 5xx and a 429 are `transient` and are retried; any other 4xx, a credential the instance
refused, and a collection name this version does not publish are `rejected` and spend no
budget at all, because the instance will answer the same way in two seconds and in two
hours.

**Hop two, `check`.** The gate. It names the schema by code, and the code resolves to the one
the instance holds -- so two pipelines gating on the same shape gate on the same shape, and
it is corrected in one place. A mismatch is `rejected`: the same value against the same
schema will never pass, so it is not retried.

```yaml
  check:
    block: validate.schema
    depends_on: [read]
    config:
      input: ${steps.read.output.body}
      schema: read-gate-send-org-units
```

`depends_on` names the steps this one waits for. Those edges are the pipeline: dirigent works
out the order from them.

**Hop three, `send`.** The write, rehearsed. A reference walks a value with dots, and an
array index is a dot too, so `${steps.check.output.value.organisationUnits.0.id}` is the
first validated unit's uid -- Benkeh MCHP, because the read is ordered by name. It reads out
of the gate rather than out of the read, so the write goes where the validated answer says
and nowhere else.

```yaml
  send:
    block: dhis2.data_value_set_import
    depends_on: [check]
    config:
      connection: play
      data_values:
        dataSet: BfMAe6Itzgt
        period: ${params.period}
        orgUnit: ${steps.check.output.value.organisationUnits.0.id}
        dataValues:
          - dataElement: s46m5MS0hxu
            categoryOptionCombo: Prlt0C1RF0s
            attributeOptionCombo: HllvX50cXC0
            value: "12"
          - dataElement: s46m5MS0hxu
            categoryOptionCombo: psbwp3CQEhs
            attributeOptionCombo: HllvX50cXC0
            value: "7"
      dry_run: true
```

Every other uid here is a real one on the play demo: `BfMAe6Itzgt` is the monthly "Child
Health" data set, `s46m5MS0hxu` is "BCG doses given", `Prlt0C1RF0s` and `psbwp3CQEhs` are its
"Fixed, &lt;1y" and "Fixed, &gt;1y" cells, and `HllvX50cXC0` is the default attribute option
combo. A value is always a string on the wire, whatever the data element's value type says.

`dry_run` is the line to be suspicious of. Dropping it turns this document into a real import
of these values; do that against your own instance, never against the shared demo. DHIS2
spells a rehearsal differently per endpoint, too: `dryRun=true` on `/api/dataValueSets`, but
`importMode=VALIDATE` on `/api/metadata`. Reaching for the wrong spelling does not fail -- it
imports.

### The shape, and the credential

`schemas/read-gate-send-org-units.json` is the contract, applied on its own with
`dg schema create`. A schema reads its identity from its own keywords: `$id` becomes the code
it is addressed by, `title` its name, `description` its body.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "read-gate-send-org-units",
  "title": "Organisation units, as this project reads them",
  "description": "An organisationUnits read projected to id, code, name and level, with the identifiers held to the pack's own dhis2-uid and dhis2-code formats.",
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
          "name": { "type": "string" },
          "level": { "type": "integer", "minimum": 1 }
        }
      }
    }
  }
}
```

`required` is about presence, `properties` about shape. `dhis2-uid` and `dhis2-code` are this
pack's formats, and they assert because the pack is installed: in JSON Schema a `format`
annotates and nothing more, but dirigent always hands its validator a checker and every
installed pack's formats join it. Drop `code` from the read's `fields` line -- the kind of
edit that looks harmless -- and this gate fails with `at $.organisationUnits[0]: 'code' is a
required property`, which is the whole point of it.

`connections.yaml` is what a `--local` run is handed, because a local run starts on a
throwaway instance holding nothing. The credential in it is the play demo's own, published so
that anyone may try the instance; a real one belongs in a connection the server holds,
encrypted under its key, and never in a file beside the documents. The server refuses a
document that carries a `connections:` section for exactly that reason, which is why this is
a file of its own rather than a section of the pipeline.

## Where to go next

- [`dhis2-metadata-to-storage`](../dhis2-metadata-to-storage/README.md) is what comes next:
  what happens after the gate when the answer has to outlive the run, the same read, gated,
  written to storage, read back and counted.
- [**The DHIS2 tutorial**](https://winterop-com.github.io/dirigent-dhis2/tutorial/) is this
  example built up one section at a time, with the failures shown: a gate that refuses, a
  collection name without its `s`, and an instance that is not answering.
- [**The examples**](../README.md): every example in order, and what you need once.
