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

## Run it

From a fresh clone, with nothing running:

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

In a second terminal, in this directory:

```bash
uv run dg dev
```

`dg dev` is one process holding the API, the web UI, the scheduler, one worker and a SQLite file
under `.dirigent/state/`. It keeps running; leave it. On an empty state -- which is what a fresh
clone has, because the state directory is not in the repository -- it migrates the schema, makes
its own admin `dev`, mints that admin one token, and prints the `export DG_TOKEN=` line to paste.
The UI is at `http://127.0.0.1:3333`, which is the address the `local` profile in
`.dirigent/profiles.yaml` holds; `dg dev --port` moves the instance and `DG_URL` is how you tell
the CLI where it went.

Back in the first terminal, with that line pasted:

```bash
uv run dg apply echo-gate-carried.yaml            # refused: a server stores no carried schema
uv run dg schema create schemas/echo-answer.json
uv run dg apply
uv run dg run echo-gate --watch
uv run dg run echo-gate --watch -p station=       # fails at the gate: an empty station
```

`./verify.sh` does all of it non-interactively, on a free port of its own, and asserts that the
two failures failed the way they were written to.

## Offline

Postman Echo is the one thing here that needs the network, and `local-echo` beside this
repository is the same service in one file of Python. Start it in another terminal:

```bash
python3 ../local-echo/echo_server.py
```

All three documents carry a `base_url` parameter that defaults to the real service, so one flag
moves any of them to the stand-in on `http://127.0.0.1:8080`:

```bash
uv run dg run --local echo-gate-too-tight.yaml -p base_url=http://127.0.0.1:8080
uv run dg run --local echo-gate-carried.yaml -p base_url=http://127.0.0.1:8080
uv run dg run echo-gate --watch -p base_url=http://127.0.0.1:8080
```

The gate is what makes that worth having: the stand-in answers the shape the real service answers,
so `echo-answer` holds against it unchanged and the too-tight document still fails on `at
$.args.reading: '12.4' is not of type 'number'` -- the same line, at the same step. Only the
address differs, in the log line

```text
2026-09-17T15:30:02.827+02:00 [info    ] http call                      [log ask] method=GET url=http://127.0.0.1:8080/get status=200 bytes=288 duration_ms=34
```

and in the value the gate handed on:

```bash
uv run dg run --local echo-gate-carried.yaml -p base_url=http://127.0.0.1:8080 --json \
  | jq -s 'map(select(.kind == "run")) | last | .steps[] | select(.step == "check") | .output.value.url'
```

```json
"http://127.0.0.1:8080/get?reading=12.4&station=bergen-florida"
```

`./verify.sh` makes every assertion on this page twice, once against each echo, whenever
`../local-echo/echo_server.py` is there; `VERIFY_OFFLINE=1 ./verify.sh` leaves the online leg
out. `OFFLINE.md` beside this repository is the rest of the story, including the `UV_OFFLINE=1`
that keeps `uv` off the network too.

## What you see

*Printed as it printed, with this project's directory written as `/home/you/...` and the
temporary directory a local run makes written as `/tmp/...`.*

### Break it

```bash
uv run dg run --local echo-gate-too-tight.yaml
```

```text
2026-09-17T15:04:55.776+02:00 [info    ] started                        [run] pipeline=echo-gate-too-tight run_id=01a0af78-5bdb-7584-95dc-bcd94d561683 local=true scratch=file:///tmp/dirigent-local-11n52321/artifacts/runs/01a0af78-5bdb-7584-95dc-bcd94d561683 root=/tmp/dirigent-local-11n52321
2026-09-17T15:04:55.770+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-17T15:04:55.863+02:00 [info    ] running                        [step ask] block=http.request attempt=1
2026-09-17T15:04:56.188+02:00 [info    ] http call                      [log ask] method=GET url=https://postman-echo.com/get status=200 bytes=273 duration_ms=316
2026-09-17T15:04:56.189+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=327
2026-09-17T15:04:56.205+02:00 [info    ] failed                         [step check] block=validate.schema attempt=1 duration_ms=4
2026-09-17T15:04:56.208+02:00 [error   ] failed                         [log check] duration_ms=0 error_class=rejected error="at $.args.reading: '12.4' is not of type 'number'"
2026-09-17T15:04:56.275+02:00 [error   ] failed                         [run] pipeline=echo-gate-too-tight run_id=01a0af78-5bdb-7584-95dc-bcd94d561683 exit_code=1
steps
┏━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step          ┃ block           ┃ outcome   ┃ after ┃ duration ┃ output                  ┃
┡━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask           │ http.request    │ succeeded │ -     │ 0.3s     │ status=200  headers={12 │
│               │                 │           │       │          │ keys}  body={3 keys}    │
│               │                 │           │       │          │ body_bytes=273          │
│               │                 │           │       │          │ duration_ms=316         │
│ check  1 warn │ validate.schema │ failed    │ ask   │ 0.0s     │ -                       │
└───────────────┴─────────────────┴───────────┴───────┴──────────┴─────────────────────────┘

check failed  validate.schema, attempt 1, rejected
  at $.args.reading: '12.4' is not of type 'number'
  last log lines:
    error: failed
```

Postman Echo answered 200. The read succeeded. The answer was simply not the answer this schema
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
2026-09-17T15:04:57.683+02:00 [info    ] started                        [run] pipeline=echo-gate-carried run_id=01a0af78-634f-7538-98fc-d65bd16efd07 local=true scratch=file:///tmp/dirigent-local-1sy6nbya/artifacts/runs/01a0af78-634f-7538-98fc-d65bd16efd07 root=/tmp/dirigent-local-1sy6nbya
2026-09-17T15:04:57.679+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-17T15:04:57.768+02:00 [info    ] running                        [step ask] block=http.request attempt=1
2026-09-17T15:04:58.008+02:00 [info    ] http call                      [log ask] method=GET url=https://postman-echo.com/get status=200 bytes=273 duration_ms=230
2026-09-17T15:04:58.010+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=242
2026-09-17T15:04:58.020+02:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=4
2026-09-17T15:04:58.024+02:00 [info    ] finished                       [log check] duration_ms=0 output_bytes=283
2026-09-17T15:04:58.151+02:00 [info    ] succeeded                      [run] pipeline=echo-gate-carried run_id=01a0af78-634f-7538-98fc-d65bd16efd07 exit_code=0
steps
┏━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step  ┃ block           ┃ outcome   ┃ after ┃ duration ┃ output                          ┃
┡━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask   │ http.request    │ succeeded │ -     │ 0.2s     │ status=200  headers={12 keys}   │
│       │                 │           │       │          │ body={3 keys}  body_bytes=273   │
│       │                 │           │       │          │ duration_ms=230                 │
│ check │ validate.schema │ succeeded │ ask   │ 0.0s     │ value={3 keys}                  │
└───────┴─────────────────┴───────────┴───────┴──────────┴─────────────────────────────────┘
```

`check` produced `value={3 keys}`: `validate.schema` hands its input on unchanged, which makes the
gate a **waypoint**. Every step past it provably received the shape.

### Hand the shape to the instance

The document that passed still carries its own schema, and that is where a server draws the line:

```bash
uv run dg apply echo-gate-carried.yaml
```

```text
2026-09-17T23:24:16.907+02:00 [error   ] this document carries its own schemas (echo-answer), which an instance will not store: create them with `dg schema create` and let the document name them in requires.schemas [error] status=422 title="Unprocessable Content" instance=/api/v1/pipelines/$apply
  - this document carries its own schemas (echo-answer), which an instance will not store: create
them with `dg schema create` and let the document name them in requires.schemas
```

That refusal is the rule worth learning early: **a server stores no schema a document carries**,
exactly as it stores no connection a document carries. A carried schema is still worth having,
because a local run seeds what the document brought, and a local run is the fast loop.

So lift it out. `schemas/echo-answer.json` is the same shape as a plain JSON Schema file, and its
own keywords carry its identity: `$id` becomes the code it is addressed by, `title` its name,
`description` its body.

```bash
uv run dg schema create schemas/echo-answer.json
```

```text
stored schema echo-answer
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
2026-09-17T23:24:20.271+02:00 [info    ] started                        [run] pipeline=echo-gate run_id=01a0b141-94ab-778c-97f7-933864f7a986 local=false
2026-09-17T23:24:20.269+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-17T23:24:20.721+02:00 [info    ] running                        [step ask] block=http.request attempt=1
2026-09-17T23:24:21.046+02:00 [info    ] http call                      [log ask] method=GET url=https://postman-echo.com/get status=200 bytes=273 duration_ms=303
2026-09-17T23:24:21.052+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=330
2026-09-17T23:24:21.290+02:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=18
2026-09-17T23:24:21.302+02:00 [info    ] finished                       [log check] duration_ms=1 output_bytes=283
2026-09-17T23:24:21.609+02:00 [info    ] succeeded                      [run] pipeline=echo-gate run_id=01a0b141-94ab-778c-97f7-933864f7a986 pipeline_version=1 triggered_by="dev (token dev)" duration_ms=569 items_total=0 items_failed=0 exit_code=0 priority=normal
run
01a0b141-94ab-778c-97f7-933864f7a986
pipeline      echo-gate (version 1)
status        succeeded
triggered by  dev (token dev)
duration      0.6s
items         -

steps
┏━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━┓
┃ step  ┃ block           ┃ outcome   ┃ after ┃ attempts ┃ duration ┃ error ┃
┡━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━┩
│ ask   │ http.request    │ succeeded │ -     │ 1        │ 0.3s     │ -     │
│ check │ validate.schema │ succeeded │ ask   │ 1        │ 0.0s     │ -     │
└───────┴─────────────────┴───────────┴───────┴──────────┴──────────┴───────┘

outputs
┏━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step  ┃ output                                                                        ┃
┡━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask   │ status=200  headers={12 keys}  body={3 keys}  body_bytes=273  duration_ms=303 │
│ check │ value={3 keys}                                                                │
└───────┴───────────────────────────────────────────────────────────────────────────────┘
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
2026-09-17T23:24:22.667+02:00 [info    ] started                        [run] pipeline=echo-gate run_id=01a0b141-9e07-70c3-aaff-0d100fe9b5aa local=false
2026-09-17T23:24:22.666+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-17T23:24:22.666+02:00 [info    ] queued                         [step check] block=validate.schema attempt=1
2026-09-17T23:24:23.035+02:00 [info    ] http call                      [log ask] method=GET url=https://postman-echo.com/get status=200 bytes=245 duration_ms=227
2026-09-17T23:24:23.041+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=239
2026-09-17T23:24:23.332+02:00 [info    ] failed                         [step check] block=validate.schema attempt=1 duration_ms=19
2026-09-17T23:24:23.342+02:00 [error   ] failed                         [log check] duration_ms=1 error_class=rejected error="at $.args.station: '' should be non-empty"
2026-09-17T23:24:24.002+02:00 [error   ] failed                         [run] pipeline=echo-gate run_id=01a0b141-9e07-70c3-aaff-0d100fe9b5aa pipeline_version=1 triggered_by="dev (token dev)" duration_ms=530 items_total=0 items_failed=0 exit_code=1 priority=normal
run
01a0b141-9e07-70c3-aaff-0d100fe9b5aa
pipeline      echo-gate (version 1)
status        failed
triggered by  dev (token dev)
duration      0.5s
items         -

steps
┏━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━┓
┃ step          ┃ block           ┃ outcome   ┃ after ┃ attempts ┃ duration ┃ error                ┃
┡━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━┩
│ ask           │ http.request    │ succeeded │ -     │ 1        │ 0.2s     │ -                    │
│ check  1 warn │ validate.schema │ failed    │ ask   │ 1        │ 0.0s     │ at $.args.station:   │
│               │                 │           │       │          │          │ '' should be         │
│               │                 │           │       │          │          │ non-empty            │
└───────────────┴─────────────────┴───────────┴───────┴──────────┴──────────┴──────────────────────┘

outputs
┏━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step ┃ output                                                                        ┃
┡━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask  │ status=200  headers={12 keys}  body={3 keys}  body_bytes=245  duration_ms=227 │
└──────┴───────────────────────────────────────────────────────────────────────────────┘

check failed  validate.schema, attempt 1, rejected
  at $.args.station: '' should be non-empty
  last log lines:
    error: failed
```

The run is `failed`, the class is `rejected`, and the message carries the path. Nothing downstream
of the gate ever saw the value -- in this document there is nothing downstream yet, and
[echo-send](../echo-send) is where a step after the gate gets skipped instead.

## The documents, hop by hop

### `schemas/echo-answer.json`

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "echo-answer",
  "title": "The answer, as Postman Echo gives it",
  "description": "A /get answer carrying one station and one decimal reading among its query arguments. A query argument is text, so the reading is a string held to the shape of a decimal rather than a number.",
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

`$id` is the code, and the code is what everything else uses -- `dg schema show echo-answer`, the
Schemas screen in the UI, and every document's `requires.schemas`. `type`, `required` and
`properties` carry most of the weight: `required` is about presence, `properties` about shape, and
`additionalProperties: false` closes the door on anything you did not name. The `pattern` on
`reading` is the whole point of the example: the value is text, and text held to the shape of a
decimal is a real check, where `type: number` was a wrong one.

### `pipelines/echo-gate.yaml`

```yaml
# The gate with its shape handed to the instance: the document names a code, and nothing else.
#
# schemas/echo-answer.json is the same shape echo-gate-carried.yaml carries, lifted out of the
# document and stored on the instance with `dg schema create`. The check step does not change at
# all: it named the schema by code all along, and the code now resolves to the one the instance
# holds. What changes is who owns the shape -- every pipeline on this instance gating on
# echo-answer is gating on the same echo-answer.
#
# requires.schemas is what makes a missing shape a refusal at apply rather than a failure at the
# step: an instance that does not hold echo-answer will not take this document.
#
#   dg schema create schemas/echo-answer.json
#   dg apply
#   dg run echo-gate --watch
#   dg run echo-gate --watch -p station=          # failed: the gate refuses an empty station

format: dirigent/v1
kind: pipeline
code: echo-gate
name: Echo gate
description: Ask Postman Echo for a reading and hold the answer to a shape the instance holds.

tags: [http, validate]

requires:
  blocks:
    - http.request
    - validate.schema
  schemas:
    - echo-answer

params:
  type: object
  properties:
    # Every URL in this document is built on this one value, so pointing the document at another
    # echo is a flag on the run rather than an edit: -p base_url=http://127.0.0.1:8080 runs it
    # against a stand-in on this machine, with no network at all.
    base_url:
      type: string
      default: https://postman-echo.com
      description: The echo service this document's requests are built on.
    station:
      type: string
      default: bergen-florida
      description: The station the reading is asked for.

steps:
  ask:
    block: http.request
    config:
      url: ${params.base_url}/get
      method: GET
      query:
        station: ${params.station}
        reading: "12.4"

  check:
    block: validate.schema
    depends_on: [ask]
    config:
      # The whole answer goes in, and the gate hands it on unchanged as value: a step past the
      # gate reads ${steps.check.output.value} and provably received the shape.
      input: ${steps.ask.output.body}
      schema: echo-answer
```

`requires.schemas` is what makes a missing shape a refusal at apply rather than a failure at the
step: an instance that does not hold `echo-answer` will not take this document at all. The `check`
step names the schema by `code` and takes the read's whole `body` as its `input`; what it gives
back is that same body, as `value`. `base_url` is a parameter like any other, and the one every
URL in the document is built on, so a run against another echo is a flag rather than an edit.

### `echo-gate-carried.yaml` and `echo-gate-too-tight.yaml`

Both are the same pipeline with a top-level `schemas:` section instead, keyed by the same code:

```yaml
schemas:
  echo-answer:
    title: The answer, as Postman Echo gives it
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
- [**All the examples**](../README.md) is the shelf they sit on, in the order the tutorials teach
  them.
