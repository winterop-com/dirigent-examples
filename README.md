# echo-send

The third move: a request built out of the values a gate passed. `validate.schema` hands its input
on unchanged as `value`, which makes a gate a **waypoint** -- so the send does not read the
request's answer again, it reads `${steps.check.output.value...}`, and every step past the gate
provably received the shape. That is also what makes a refusal cheap: when the gate says no, `send`
is **skipped** rather than failed, because it never ran at all. The repository holds the pipeline
twice, one step apart, so that applying the real document is a version you can see: `dg apply`
stores each document as an immutable version and says what changed between the last one and this
one.

## Run it

From a fresh clone, with nothing running:

```bash
uv sync
uv run dg validate echo-send-before.yaml
uv run dg validate pipelines/echo-send.yaml
uv run dg run --local pipelines/echo-send.yaml --schema schemas/echo-answer.json
```

A local run starts on an empty throwaway instance, so the schema this document requires has to be
handed over: `--schema` is how a file becomes a shape that instance holds for the length of one
run.

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
uv run dg schema create schemas/echo-answer.json
uv run dg apply echo-send-before.yaml           # the pipeline one step short
uv run dg apply                                 # ... and the step added
uv run dg run echo-send --watch
uv run dg runs show <run id> --json | jq '.fields.attempts[] | select(.step_name == "send") | .output.body.json'
uv run dg run echo-send --watch -p station=     # the gate refuses, and send is skipped
```

`./verify.sh` does all of it non-interactively, on a free port of its own, and asserts that what
arrived at `/post` is what the gate passed.

## Offline

Postman Echo is the one thing here that needs the network, and `local-echo` beside this
repository is the same service in one file of Python. Start it in another terminal:

```bash
python3 ../local-echo/echo_server.py
```

Both documents carry a `base_url` parameter that defaults to the real service, and both the read
and the send are built on it, so one flag moves the whole run to the stand-in:

```bash
uv run dg run --local pipelines/echo-send.yaml --schema schemas/echo-answer.json \
  -p base_url=http://127.0.0.1:8080
uv run dg run echo-send --watch -p base_url=http://127.0.0.1:8080
```

```text
2026-09-17T15:33:20.461+02:00 [info    ] http call                      [log ask] method=GET url=http://127.0.0.1:8080/get status=200 bytes=288 duration_ms=28
2026-09-17T15:33:20.580+02:00 [info    ] http call                      [log send] method=POST url=http://127.0.0.1:8080/post status=200 bytes=408 duration_ms=4
```

Two lines differ, and only in the address. The stand-in answers a POST with the body it was given
exactly as the real service does, so the proof of what was sent reads the same:

```bash
uv run dg run --local pipelines/echo-send.yaml --schema schemas/echo-answer.json \
  -p base_url=http://127.0.0.1:8080 --json \
  | jq -s 'map(select(.kind == "run")) | last | .steps[] | select(.step == "send") | .output.body.json'
```

```json
{
  "reading": "12.4",
  "station": "bergen-florida"
}
```

`./verify.sh` makes every assertion on this page twice, once against each echo, whenever
`../local-echo/echo_server.py` is there; `VERIFY_OFFLINE=1 ./verify.sh` leaves the online leg
out. `OFFLINE.md` beside this repository is the rest of the story, including the `UV_OFFLINE=1`
that keeps `uv` off the network too.

## What you see

*Printed as it printed, with this project's directory written as `/home/you/...` and the
temporary directory a local run makes written as `/tmp/...`.*

```bash
uv run dg run --local pipelines/echo-send.yaml --schema schemas/echo-answer.json
```

```text
2026-09-17T15:09:46.624+02:00 [info    ] started                        [run] pipeline=echo-send run_id=01a0af7c-cbfa-74f5-966d-963b6d6ad1d7 local=true scratch=file:///tmp/dirigent-local-le_s7b3_/artifacts/runs/01a0af7c-cbfa-74f5-966d-963b6d6ad1d7 root=/tmp/dirigent-local-le_s7b3_
2026-09-17T15:09:46.618+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-17T15:09:46.708+02:00 [info    ] running                        [step ask] block=http.request attempt=1
2026-09-17T15:09:47.041+02:00 [info    ] http call                      [log ask] method=GET url=https://postman-echo.com/get status=200 bytes=273 duration_ms=322
2026-09-17T15:09:47.043+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=335
2026-09-17T15:09:47.052+02:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=8
2026-09-17T15:09:47.052+02:00 [info    ] queued                         [step send] block=http.request attempt=1
2026-09-17T15:09:47.055+02:00 [info    ] finished                       [log check] duration_ms=0 output_bytes=283
2026-09-17T15:09:47.104+02:00 [info    ] running                        [step send] block=http.request attempt=1
2026-09-17T15:09:47.303+02:00 [info    ] http call                      [log send] method=POST url=https://postman-echo.com/post status=200 bytes=378 duration_ms=195
2026-09-17T15:09:47.306+02:00 [info    ] succeeded                      [step send] block=http.request attempt=1 duration_ms=202
2026-09-17T15:09:47.457+02:00 [info    ] succeeded                      [run] pipeline=echo-send run_id=01a0af7c-cbfa-74f5-966d-963b6d6ad1d7 exit_code=0
steps
┏━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step  ┃ block           ┃ outcome   ┃ after ┃ duration ┃ output                          ┃
┡━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask   │ http.request    │ succeeded │ -     │ 0.3s     │ status=200  headers={12 keys}   │
│       │                 │           │       │          │ body={3 keys}  body_bytes=273   │
│       │                 │           │       │          │ duration_ms=322                 │
│ check │ validate.schema │ succeeded │ ask   │ 0.0s     │ value={3 keys}                  │
│ send  │ http.request    │ succeeded │ check │ 0.2s     │ status=200  headers={12 keys}   │
│       │                 │           │       │          │ body={7 keys}  body_bytes=378   │
│       │                 │           │       │          │ duration_ms=195                 │
└───────┴─────────────────┴───────────┴───────┴──────────┴─────────────────────────────────┘
```

Three steps, in the order the edges said: the read, the gate, the send. `send` answered
`body={7 keys}` where the read answered `body={3 keys}` -- `/post` gives back rather more about a
request than `/get` does.

### The version

```bash
uv run dg schema create schemas/echo-answer.json
```

```text
stored schema echo-answer
```

```bash
uv run dg apply echo-send-before.yaml
```

```text
create echo-send  version 1 (echo-send-before.yaml)
```

```bash
uv run dg apply
```

```text
update echo-send  version 2 (/home/you/echo-send/pipelines/echo-send.yaml)
  steps added: send
```

`create` and then `update`, with the step that appeared named. `dg apply` sends every document
under `pipelines/` and stores each as an immutable version; `echo-send-before.yaml` sits at the
project root, so it is sent only when it is named. Both files carry `code: echo-send`, which is why
the second apply is a new version of one pipeline rather than a second pipeline -- the `code` is
the identity, and the file name is not.

```bash
uv run dg run echo-send --watch
```

```text
2026-09-17T23:26:05.057+02:00 [info    ] started                        [run] pipeline=echo-send run_id=01a0b143-2dfd-7571-bf1b-2be98f2b644b local=false
2026-09-17T23:26:05.055+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-17T23:26:05.456+02:00 [info    ] running                        [step ask] block=http.request attempt=1
2026-09-17T23:26:05.055+02:00 [info    ] queued                         [step send] block=http.request attempt=1
2026-09-17T23:26:05.712+02:00 [info    ] http call                      [log ask] method=GET url=https://postman-echo.com/get status=200 bytes=273 duration_ms=248
2026-09-17T23:26:05.714+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=258
2026-09-17T23:26:05.990+02:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=7
2026-09-17T23:26:05.997+02:00 [info    ] finished                       [log check] duration_ms=0 output_bytes=283
2026-09-17T23:26:06.722+02:00 [info    ] http call                      [log send] method=POST url=https://postman-echo.com/post status=200 bytes=378 duration_ms=224
2026-09-17T23:26:06.723+02:00 [info    ] succeeded                      [step send] block=http.request attempt=1 duration_ms=230
2026-09-17T23:26:07.516+02:00 [info    ] succeeded                      [run] pipeline=echo-send run_id=01a0b143-2dfd-7571-bf1b-2be98f2b644b pipeline_version=2 triggered_by="dev (token dev)" duration_ms=1267 items_total=0 items_failed=0 exit_code=0 priority=normal
run
01a0b143-2dfd-7571-bf1b-2be98f2b644b
pipeline      echo-send (version 2)
status        succeeded
triggered by  dev (token dev)
duration      1.3s
items         -

steps
┏━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━┓
┃ step  ┃ block           ┃ outcome   ┃ after ┃ attempts ┃ duration ┃ error ┃
┡━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━┩
│ ask   │ http.request    │ succeeded │ -     │ 1        │ 0.3s     │ -     │
│ check │ validate.schema │ succeeded │ ask   │ 1        │ 0.0s     │ -     │
│ send  │ http.request    │ succeeded │ check │ 1        │ 0.2s     │ -     │
└───────┴─────────────────┴───────────┴───────┴──────────┴──────────┴───────┘

outputs
┏━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step  ┃ output                                                                        ┃
┡━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask   │ status=200  headers={12 keys}  body={3 keys}  body_bytes=273  duration_ms=248 │
│ check │ value={3 keys}                                                                │
│ send  │ status=200  headers={12 keys}  body={7 keys}  body_bytes=378  duration_ms=224 │
└───────┴───────────────────────────────────────────────────────────────────────────────┘
```

```bash
uv run dg runs show 01a0b143-2dfd-7571-bf1b-2be98f2b644b --json \
  | jq '.fields.attempts[] | select(.step_name == "send") | .output.body.json'
```

```json
{
  "reading": "12.4",
  "station": "bergen-florida"
}
```

Postman Echo answers a POST with the body it was given, so that is the proof of what was sent. The
station and the reading made it from the first step's answer, through the gate, into the second
request -- and neither value was written twice in the document.

### When the gate says no

```bash
uv run dg run echo-send --watch -p station=
```

```text
2026-09-17T23:26:09.720+02:00 [info    ] started                        [run] pipeline=echo-send run_id=01a0b143-4036-76b0-afb6-330c7095f207 local=false
2026-09-17T23:26:09.719+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-17T23:26:10.041+02:00 [info    ] running                        [step ask] block=http.request attempt=1
2026-09-17T23:26:10.298+02:00 [info    ] http call                      [log ask] method=GET url=https://postman-echo.com/get status=200 bytes=245 duration_ms=244
2026-09-17T23:26:10.300+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=259
2026-09-17T23:26:10.577+02:00 [info    ] failed                         [step check] block=validate.schema attempt=1 duration_ms=14
2026-09-17T23:26:10.577+02:00 [info    ] skipped                        [step send] block=http.request attempt=1
2026-09-17T23:26:10.584+02:00 [error   ] failed                         [log check] duration_ms=0 error_class=rejected error="at $.args.station: '' should be non-empty"
2026-09-17T23:26:11.019+02:00 [error   ] failed                         [run] pipeline=echo-send run_id=01a0b143-4036-76b0-afb6-330c7095f207 pipeline_version=2 triggered_by="dev (token dev)" duration_ms=536 items_total=0 items_failed=0 exit_code=1 priority=normal
run
01a0b143-4036-76b0-afb6-330c7095f207
pipeline      echo-send (version 2)
status        failed
triggered by  dev (token dev)
duration      0.5s
items         -

steps
┏━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━┓
┃ step          ┃ block           ┃ outcome   ┃ after ┃ attempts ┃ duration ┃ error                ┃
┡━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━┩
│ ask           │ http.request    │ succeeded │ -     │ 1        │ 0.3s     │ -                    │
│ check  1 warn │ validate.schema │ failed    │ ask   │ 1        │ 0.0s     │ at $.args.station:   │
│               │                 │           │       │          │          │ '' should be         │
│               │                 │           │       │          │          │ non-empty            │
│ send          │ http.request    │ skipped   │ check │ 1        │ -        │ -                    │
└───────────────┴─────────────────┴───────────┴───────┴──────────┴──────────┴──────────────────────┘

outputs
┏━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step ┃ output                                                                        ┃
┡━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask  │ status=200  headers={12 keys}  body={3 keys}  body_bytes=245  duration_ms=244 │
└──────┴───────────────────────────────────────────────────────────────────────────────┘

check failed  validate.schema, attempt 1, rejected
  at $.args.station: '' should be non-empty
  last log lines:
    error: failed
```

`send` is **skipped**, not failed: it never ran, because the step it waits for did not succeed.
That is the point of a gate -- nothing downstream of it ever sees a value it refused. The run is
`failed` because a step in it failed, and the failure carries the class `rejected`, so no attempt
was spent asking again.

## The documents, hop by hop

### `pipelines/echo-send.yaml`

```yaml
# Read, gate, send: the three moves, with the send built out of what the gate passed.
#
# validate.schema hands its input on unchanged as value, which makes the gate a waypoint: the send
# does not read the request's answer again, it reads the gate's output, and every step past the
# gate provably received the shape. That is also why send is skipped rather than failed when the
# gate refuses -- it never ran, because the step it waits for did not succeed.
#
# Postman Echo answers a POST with the body it was given, so the send's own answer is the proof of
# what was sent.
#
#   dg schema create schemas/echo-answer.json
#   dg apply
#   dg run echo-send --watch
#   dg run echo-send --watch -p station=          # the gate refuses, and send is skipped

format: dirigent/v1
kind: pipeline
code: echo-send
name: Echo send
description: Ask Postman Echo for one station's reading, hold the answer to a shape, and send the validated values back.

tags: [http, validate, references]

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
      input: ${steps.ask.output.body}
      schema: echo-answer

  send:
    block: http.request
    depends_on: [check]
    config:
      url: ${params.base_url}/post
      method: POST
      # Read out of the gate rather than out of the read: every step past a gate provably
      # received the shape the gate passed. Neither value is written twice in this document.
      body:
        station: ${steps.check.output.value.args.station}
        reading: ${steps.check.output.value.args.reading}
```

`requires` names both blocks and the schema code, so an instance missing any of them refuses the
document at apply rather than failing at the step. `base_url` is the one value both requests are
built on, so a run against another echo is a flag rather than an edit. `ask` is the read from
[echo-read](../echo-read) and `check` the gate from [echo-gate](../echo-gate); what is new is
`send`, and the only thing worth staring at is where its body comes from:

```yaml
      body:
        station: ${steps.check.output.value.args.station}
        reading: ${steps.check.output.value.args.reading}
```

`steps.check.output.value` is what the gate handed on, and every dot after it walks into that
value. Reading out of the gate rather than out of the read is what makes the graph mean something:
`ask -> check -> send` says that nothing reaches `/post` that the schema has not seen.

### `echo-send-before.yaml`

The same document with `send` left out and the same `code`. It is at the project root so that
`dg apply` never sends it on its own; naming it explicitly is what puts version 1 on the instance,
and the apply after it is the one with a step in its diff.

### `schemas/echo-answer.json`

The shape the gate holds the answer to, stored on the instance with `dg schema create` and named by
`requires.schemas`. It is the same file as in [echo-gate](../echo-gate), where the break-it/fix-it
pair explains every line of it.

## Where to go next

- [`echo-retry`](../echo-retry/README.md) is the other half of what a failure means: a refusal that
  no budget can help, beside an outage that a retry is exactly for.
- [**The basics**](https://winterop-com.github.io/dirigent/basics/) is the tutorial this example is
  cut from, and section 5 is this step of it.
- [**The examples**](../README.md): every example in order, and what you need once.
