# echo-gate

A read is a contract with a system you do not control. Write the contract down, and a payload
that has moved stops at the step it arrived in rather than turning into something strange three
steps later. That is what `validate.schema` is: a **gate**, holding a value to a
[JSON Schema](https://winterop-com.github.io/dirigent/json-schema/) and handing it on unchanged as
`value` when it fits. This example shows the gate three times over -- tightened one line too far,
so it refuses a good answer; fixed, with the schema carried in the document; and lifted out of the
document onto the instance, which is the only form a server will store. A schema is a thing the
instance holds and a document names, so that two pipelines gating on the same shape are gating on
the same shape.

## What it calls

The **playground** is a request-and-response service every dirigent instance serves itself under
`/api/v1/playground`, unauthenticated. It answers with the request you sent it, so the gate here
holds a shape this machine produced and nothing on the public internet is involved. It does mean
an instance has to be running before any of the runs below, `--local` included: a local run builds
a throwaway database and mounts no API of its own.

In a second terminal, in this directory:

```bash
uv run dg dev
```

`dg dev` is one process holding the API, the web UI, the scheduler, one worker and a SQLite file
under `.dirigent/state/`. It keeps running; leave it. On an empty state -- which is what a fresh
clone has, because the state directory is not in the repository -- it migrates the schema, makes
its own admin `admin`, mints that admin one token, and prints the `export DG_TOKEN=` line to paste.
The UI is at `http://127.0.0.1:3333`, which is the address the `local` profile in
`.dirigent/profiles.yaml` holds and the address every document's `playground` parameter defaults
to; `dg dev --port` moves the instance, `DG_URL` is how you tell the CLI where it went, and
`-p playground=...` is how you tell a document.

## Run it

From a fresh clone, with that instance running:

```bash
uv sync
uv run dg validate echo-gate-too-tight.yaml
uv run dg validate echo-gate-carried.yaml
uv run dg validate pipelines/echo-gate.yaml
uv run dg run --local echo-gate-too-tight.yaml    # fails at the gate, on purpose
uv run dg run --local echo-gate-carried.yaml
```

The two documents at the project root are never applied: `pipelines/` is where the documents an
instance should hold live, and `dg apply` sends only what is in there. Both root documents carry
their own schema, which a local run seeds and a server refuses -- which is the next half.

Back in the first terminal, with the export line pasted:

```bash
uv run dg apply echo-gate-carried.yaml                  # refused: a server stores no carried schema
uv run dg schema create schemas/playground-answer.json
uv run dg apply
uv run dg run echo-gate --watch
uv run dg run echo-gate --watch -p station=             # fails at the gate: an empty station
```

`./verify.sh` does all of it non-interactively, on a free port of its own, points every run at that
instance's playground, and asserts that the two failures failed the way they were written to.

## What you see

*Printed as it printed, with this project's directory written as `/home/you/...` and the
temporary directory a local run makes written as `/tmp/...`.*

### Break it

```bash
uv run dg run --local echo-gate-too-tight.yaml
```

```text
2026-09-26T12:35:27.499+02:00 [info    ] started                        [run] pipeline=echo-gate-too-tight run_id=01a0dd48-bf87-7304-9e64-4d4ed42e0878 local=true scratch=file:///tmp/dirigent-local-uh9j_s4t/artifacts/runs/01a0dd48-bf87-7304-9e64-4d4ed42e0878 root=/tmp/dirigent-local-uh9j_s4t
2026-09-26T12:35:27.494+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-26T12:35:27.578+02:00 [info    ] http call                      [log ask] method=GET url=http://127.0.0.1:3333/api/v1/playground/request status=200 bytes=452 duration_ms=33
2026-09-26T12:35:27.579+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=45
2026-09-26T12:35:27.634+02:00 [info    ] failed                         [step check] block=validate.schema attempt=1 duration_ms=5
2026-09-26T12:35:27.636+02:00 [error   ] failed                         [log check] duration_ms=0 error_class=rejected error_code=base.value_refused error="at $.args.reading: '12.4' is not of type 'number'"
2026-09-26T12:35:27.687+02:00 [error   ] failed                         [run] pipeline=echo-gate-too-tight run_id=01a0dd48-bf87-7304-9e64-4d4ed42e0878 exit_code=1
steps
┏━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step          ┃ block           ┃ outcome   ┃ after ┃ duration ┃ output                          ┃
┡━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask           │ http.request    │ succeeded │ -     │ 0.0s     │ status=200  headers={5 keys}    │
│               │                 │           │       │          │ body={3 keys}  body_bytes=452   │
│               │                 │           │       │          │ duration_ms=33                  │
│ check  1 warn │ validate.schema │ failed    │ ask   │ 0.0s     │ -                               │
└───────────────┴─────────────────┴───────────┴───────┴──────────┴─────────────────────────────────┘

check failed  validate.schema, attempt 1, rejected
  at $.args.reading: '12.4' is not of type 'number'
  last log lines:
    error: failed
```

The playground answered 200. The read succeeded. The answer was simply not the answer this schema
was written against, and the gate says so in one line with the path in it: `$.args.reading`,
`'12.4' is not of type 'number'`.

The lesson under the lesson is worth keeping: **a query argument arrives as text**. There are no
numbers in a query string, so a reading that travelled that way is a string at the far end however
numeric it looks. Note the class on that failure, `rejected`: asking the same question again
cannot change the answer, so no retry is attempted whatever budget the step was given.

### Fix it

The fix is not to give up on checking the reading -- it is to check what a decimal written as text
looks like, which is one line of `pattern` and would still catch `warm`:

```bash
uv run dg run --local echo-gate-carried.yaml
```

```text
2026-09-26T12:35:29.291+02:00 [info    ] started                        [run] pipeline=echo-gate-carried run_id=01a0dd48-c685-77dd-9026-b422130282d9 local=true scratch=file:///tmp/dirigent-local-f571gc3k/artifacts/runs/01a0dd48-c685-77dd-9026-b422130282d9 root=/tmp/dirigent-local-f571gc3k
2026-09-26T12:35:29.284+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-26T12:35:29.393+02:00 [info    ] http call                      [log ask] method=GET url=http://127.0.0.1:3333/api/v1/playground/request status=200 bytes=452 duration_ms=40
2026-09-26T12:35:29.394+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=64
2026-09-26T12:35:29.450+02:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=5
2026-09-26T12:35:29.453+02:00 [info    ] finished                       [log check] duration_ms=0 output_bytes=420
2026-09-26T12:35:29.530+02:00 [info    ] succeeded                      [run] pipeline=echo-gate-carried run_id=01a0dd48-c685-77dd-9026-b422130282d9 exit_code=0
steps
┏━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step  ┃ block           ┃ outcome   ┃ after ┃ duration ┃ output                                  ┃
┡━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask   │ http.request    │ succeeded │ -     │ 0.1s     │ status=200  headers={5 keys}  body={3   │
│       │                 │           │       │          │ keys}  body_bytes=452  duration_ms=40   │
│ check │ validate.schema │ succeeded │ ask   │ 0.0s     │ value={9 keys}                          │
└───────┴─────────────────┴───────────┴───────┴──────────┴─────────────────────────────────────────┘
```

`check` produced `value={9 keys}`: `validate.schema` hands its input on unchanged, which makes the
gate a **waypoint**. Every step past it provably received the shape. The nine keys are the
playground's `request` -- the method, the url, the path, the arguments, the headers and how the
body was read -- of which the schema names two and closes the door on nothing else.

### Hand the shape to the instance

The document that passed still carries its own schema, and that is where a server draws the line:

```bash
uv run dg apply echo-gate-carried.yaml
```

```text
2026-09-26T12:35:30.906+02:00 [error   ] this document carries its own schemas (playground-answer), which an instance will not store: create them with `dg schema create` and let the document name them in requires.schemas [error] status=422 title="Unprocessable Content" code=server.document_refused params={"detail":"this document carries its own schemas (playground-answer), which an instance will not store: create them with `dg schema create` and let the document name them in requires.schemas"} instance=/api/v1/pipelines/$apply
  - this document carries its own schemas (playground-answer), which an instance will not store:
create them with `dg schema create` and let the document name them in requires.schemas
```

That refusal is the rule worth learning early: **a server stores no schema a document carries**,
exactly as it stores no connection a document carries. A carried schema is still worth having,
because a local run seeds what the document brought, and a local run is the fast loop.

So lift it out. `schemas/playground-answer.json` is the same shape as a plain JSON Schema file, and
its own keywords carry its identity: `$id` becomes the code it is addressed by, `title` its name,
`description` its body.

```bash
uv run dg schema create schemas/playground-answer.json
```

```text
stored schema playground-answer
```

```bash
uv run dg apply
```

```text
create echo-gate  version 1 (/home/you/echo-gate/pipelines/echo-gate.yaml)
```

```bash
uv run dg run echo-gate --watch
```

```text
2026-09-26T12:35:34.988+02:00 [info    ] started                        [run] pipeline=echo-gate run_id=01a0dd48-dcc7-7604-b3b6-3b75e6626e6d local=false
2026-09-26T12:35:34.985+02:00 [info    ] queued                         [step check] block=validate.schema attempt=1
2026-09-26T12:35:35.024+02:00 [info    ] http call                      [log ask] method=GET url=http://127.0.0.1:3333/api/v1/playground/request status=200 bytes=452 duration_ms=17
2026-09-26T12:35:35.028+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=32
2026-09-26T12:35:35.534+02:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=7
2026-09-26T12:35:35.538+02:00 [info    ] finished                       [log check] duration_ms=0 output_bytes=420
2026-09-26T12:35:35.571+02:00 [info    ] succeeded                      [run] pipeline=echo-gate run_id=01a0dd48-dcc7-7604-b3b6-3b75e6626e6d pipeline_version=1 triggered_by="admin (token dev)" duration_ms=539 items_total=0 items_failed=0 exit_code=0 priority=normal
run 01a0dd48-dcc7-7604-b3b6-3b75e6626e6d
pipeline      echo-gate (version 1)
status        succeeded
triggered by  admin (token dev)
duration      0.5s
items         -

steps
┏━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━┓
┃ step  ┃ block           ┃ outcome   ┃ after ┃ attempts ┃ duration ┃ error ┃
┡━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━┩
│ ask   │ http.request    │ succeeded │ -     │ 1        │ 0.0s     │ -     │
│ check │ validate.schema │ succeeded │ ask   │ 1        │ 0.0s     │ -     │
└───────┴─────────────────┴───────────┴───────┴──────────┴──────────┴───────┘

outputs
┏━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step  ┃ output                                                                      ┃
┡━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask   │ status=200  headers={5 keys}  body={3 keys}  body_bytes=452  duration_ms=17 │
│ check │ value={9 keys}                                                              │
└───────┴─────────────────────────────────────────────────────────────────────────────┘
```

The `check` step did not change between the carried form and this one: it named the schema by code
all along, and the code now resolves to the one the instance holds.

### A gate refuses what it was given

The schema is right; give it something that is not the shape. `-p` sets a parameter for one run,
and an empty station is a string the schema will not have:

```bash
uv run dg run echo-gate --watch -p station=
```

```text
2026-09-26T12:35:36.789+02:00 [info    ] started                        [run] pipeline=echo-gate run_id=01a0dd48-e3d2-71a8-8b4a-6cec46142f46 local=false
2026-09-26T12:35:36.787+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-26T12:35:36.787+02:00 [info    ] queued                         [step check] block=validate.schema attempt=1
2026-09-26T12:35:37.053+02:00 [info    ] http call                      [log ask] method=GET url=http://127.0.0.1:3333/api/v1/playground/request status=200 bytes=424 duration_ms=5
2026-09-26T12:35:37.054+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=11
2026-09-26T12:35:37.564+02:00 [info    ] failed                         [step check] block=validate.schema attempt=1 duration_ms=10
2026-09-26T12:35:37.568+02:00 [error   ] failed                         [log check] duration_ms=0 error_class=rejected error_code=base.value_refused error="at $.args.station: '' should be non-empty"
2026-09-26T12:35:38.093+02:00 [error   ] failed                         [run] pipeline=echo-gate run_id=01a0dd48-e3d2-71a8-8b4a-6cec46142f46 pipeline_version=1 triggered_by="admin (token dev)" duration_ms=521 items_total=0 items_failed=0 exit_code=1 priority=normal
run 01a0dd48-e3d2-71a8-8b4a-6cec46142f46
pipeline      echo-gate (version 1)
status        failed
triggered by  admin (token dev)
duration      0.5s
items         -

steps
┏━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━┓
┃ step          ┃ block           ┃ outcome   ┃ after ┃ attempts ┃ duration ┃ error                ┃
┡━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━┩
│ ask           │ http.request    │ succeeded │ -     │ 1        │ 0.0s     │ -                    │
│ check  1 warn │ validate.schema │ failed    │ ask   │ 1        │ 0.0s     │ at $.args.station:   │
│               │                 │           │       │          │          │ '' should be         │
│               │                 │           │       │          │          │ non-empty            │
└───────────────┴─────────────────┴───────────┴───────┴──────────┴──────────┴──────────────────────┘

outputs
┏━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step ┃ output                                                                     ┃
┡━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask  │ status=200  headers={5 keys}  body={3 keys}  body_bytes=424  duration_ms=5 │
└──────┴────────────────────────────────────────────────────────────────────────────┘

check failed  validate.schema, attempt 1, rejected
  at $.args.station: '' should be non-empty
  last log lines:
    error: failed
```

The run is `failed`, the class is `rejected`, and the message carries the path. Nothing downstream
of the gate ever saw the value -- in this document there is nothing downstream yet, and
[echo-send](../echo-send) is where a step after the gate gets skipped instead.

## The documents, hop by hop

### `schemas/playground-answer.json`

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "playground-answer",
  "title": "The reading, as the playground answers it",
  "description": "A reflected request carrying one station and one decimal reading among its query arguments. A query argument is text, so the reading is a string held to the shape of a decimal rather than a number.",
  "type": "object",
  "required": ["args", "url"],
  "properties": {
    "args": {
      "type": "object",
      "required": ["station", "reading"],
      "properties": {
        "station": { "type": "string", "minLength": 1 },
        "reading": { "type": "string", "pattern": "^-?[0-9]+(\\.[0-9]+)?$" }
      },
      "additionalProperties": false
    },
    "url": { "type": "string" }
  }
}
```

`$id` is the code, and the code is what everything else uses -- `dg schema show playground-answer`,
the Schemas screen in the UI, and every document's `requires.schemas`. `type`, `required` and
`properties` carry most of the weight: `required` is about presence, `properties` about shape, and
`additionalProperties: false` closes the door on anything you did not name. The `pattern` on
`reading` is the whole point of the example: the value is text, and text held to the shape of a
decimal is a real check, where `type: number` was a wrong one. In the pipeline editor the
`check` step's `schema` box draws a row under it that opens on this body, with a link to the
Schemas screen.

### `pipelines/echo-gate.yaml`

```yaml
format: dirigent/v1
kind: pipeline
code: echo-gate
name: Echo gate
description: Ask the playground for a reading and hold the answer to a shape the instance holds.

tags: [http, validate]

requires:
  blocks:
    - http.request
    - validate.schema
  schemas:
    - playground-answer

params:
  type: object
  properties:
    playground:
      type: string
      default: http://127.0.0.1:3333/api/v1/playground
      description: The playground routes on the instance this calls; `dg dev` serves them here.
    station:
      type: string
      default: bergen-florida
      description: The station the reading is asked for.

steps:
  ask:
    block: http.request
    config:
      url: ${params.playground}/request
      method: GET
      query:
        station: ${params.station}
        reading: "12.4"

  check:
    block: validate.schema
    depends_on: [ask]
    config:
      input: ${steps.ask.output.body.request}
      schema: playground-answer
```

`requires.schemas` is what makes a missing shape a refusal at apply rather than a failure at the
step: an instance that does not hold `playground-answer` will not take this document at all. The
`check` step names the schema by `code` and takes the envelope's `request` as its `input` -- the
part of the answer this pipeline is about -- and what it gives back is that same value, as `value`.
`playground` is a parameter like any other, and the one every URL in the document is built on, so
an instance on another port is a flag rather than an edit.

### `echo-gate-carried.yaml` and `echo-gate-too-tight.yaml`

Both are the same pipeline with a top-level `schemas:` section instead, keyed by the same code:

```yaml
schemas:
  playground-answer:
    title: The reading, as the playground answers it
    type: object
    required: [args, url]
    properties:
      args:
        type: object
        required: [station, reading]
        properties:
          station:
            type: string
            minLength: 1
          reading:
            type: string
            pattern: "^-?[0-9]+(\\.[0-9]+)?$"
        additionalProperties: false
      url:
        type: string
```

`echo-gate-too-tight.yaml` differs in exactly one place -- `reading: {type: number}` -- which is
the break at the top of this page. Both live at the project root, so `dg apply` never sends them
and the instance never sees a form it would refuse.

## Where to go next

- [`echo-send`](../echo-send/README.md) is what the gate is for: a request built out of the values
  the gate passed, and a step skipped behind a gate that refused.
- [**The basics**](https://winterop-com.github.io/dirigent/basics/) is the tutorial this example is
  cut from, and section 4 is this step of it.
- [**The examples**](../README.md): every example in order, and what you need once.
