# echo-retry

Two steps, one retry policy written twice, and one row against three. A **rejected** failure spends
no budget, because the service will answer the same way in two seconds and in two hours; a
**transient** one spends all of it. The difference is not in the policy -- the two `retry:` blocks
here are identical -- it is in what the service said, and classifying that is the block's job. This
is the example that fails on purpose: both of its steps fail, the run ends `failed`, and that is
the whole point of looking at it.

## What it calls

The **playground** is a request-and-response service every dirigent instance serves itself under
`/api/v1/playground`, unauthenticated, and it answers with whatever status it is asked for. That is
what lets one document show both classes of failure without calling anything on the public
internet: `?status=404` is the thing not being there, `?status=503` is the service being unwell.
An instance has to be running before any of the runs below, `--local` included, because a local run
builds a throwaway database and mounts no API of its own.

In a second terminal, in this directory:

```bash
uv run dg dev
```

`dg dev` is one process holding the API, the web UI, the scheduler, one worker and a SQLite file
under `.dirigent/state/`. It keeps running; leave it. On an empty state -- which is what a fresh
clone has, because the state directory is not in the repository -- it migrates the schema, makes
its own admin `admin`, mints that admin one token, and prints the `export DG_TOKEN=` line to paste.
The UI is at `http://127.0.0.1:3333`, which is the address the `local` profile in
`.dirigent/profiles.yaml` holds and the address the document's `playground` parameter defaults to;
`dg dev --port` moves the instance, `DG_URL` is how you tell the CLI where it went, and
`-p playground=...` is how you tell the document.

## Run it

From a fresh clone, with that instance running:

```bash
uv sync
uv run dg validate pipelines/echo-retry.yaml
uv run dg run --local pipelines/echo-retry.yaml    # fails, by design
```

That run takes the better part of six seconds, because the retried step waits two and then four
before giving up.

Back in the first terminal, with the export line pasted:

```bash
uv run dg apply
uv run dg run echo-retry --watch
uv run dg runs show <run id> --json | jq -c '[.fields.attempts[] | {step: .step_name, attempt: .attempt, class: .error_class}]'
```

The contrast is worth seeing on an instance as well as locally, because there every attempt is a
row of its own with its own resolved config and its own logs -- which is what makes a retry
auditable rather than a counter.

`./verify.sh` does all of it non-interactively, on a free port of its own, points both runs at that
instance's playground, and asserts that the refusal took one attempt of the three it was allowed
and the outage took all three.

## What you see

*Printed as it printed, with this project's directory written as `/home/you/...` and the
temporary directory a local run makes written as `/tmp/...`.*

```bash
uv run dg run --local pipelines/echo-retry.yaml
```

```text
2026-09-26T12:42:38.406+02:00 [info    ] started                        [run] pipeline=echo-retry run_id=01a0dd4f-52c1-70b8-8c32-a57f8729e4e1 local=true scratch=file:///tmp/dirigent-local-2p7q2x62/artifacts/runs/01a0dd4f-52c1-70b8-8c32-a57f8729e4e1 root=/tmp/dirigent-local-2p7q2x62
2026-09-26T12:42:38.401+02:00 [info    ] queued                         [step refused] block=http.request attempt=1
2026-09-26T12:42:38.401+02:00 [info    ] queued                         [step unlucky] block=http.request attempt=1
2026-09-26T12:42:38.475+02:00 [info    ] http call                      [log refused] method=GET url=http://127.0.0.1:3333/api/v1/playground/request status=404 bytes=398 duration_ms=30
2026-09-26T12:42:38.480+02:00 [info    ] failed                         [step refused] block=http.request attempt=1 duration_ms=46
2026-09-26T12:42:38.482+02:00 [info    ] http call                      [log unlucky] method=GET url=http://127.0.0.1:3333/api/v1/playground/request status=503 bytes=398 duration_ms=4
2026-09-26T12:42:38.487+02:00 [info    ] failed                         [step unlucky] block=http.request attempt=1 duration_ms=16
2026-09-26T12:42:40.167+02:00 [info    ] queued                         [step unlucky] block=http.request attempt=2
2026-09-26T12:42:40.180+02:00 [info    ] http call                      [log unlucky] method=GET url=http://127.0.0.1:3333/api/v1/playground/request status=503 bytes=398 duration_ms=4
2026-09-26T12:42:40.181+02:00 [info    ] failed                         [step unlucky] block=http.request attempt=2 duration_ms=8
2026-09-26T12:42:43.595+02:00 [info    ] queued                         [step unlucky] block=http.request attempt=3
2026-09-26T12:42:43.632+02:00 [info    ] http call                      [log unlucky] method=GET url=http://127.0.0.1:3333/api/v1/playground/request status=503 bytes=398 duration_ms=3
2026-09-26T12:42:43.633+02:00 [info    ] failed                         [step unlucky] block=http.request attempt=3 duration_ms=9
2026-09-26T12:42:43.834+02:00 [error   ] failed                         [run] pipeline=echo-retry run_id=01a0dd4f-52c1-70b8-8c32-a57f8729e4e1 exit_code=1
steps
┏━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━┓
┃ step    ┃ block        ┃ outcome ┃ after ┃ duration ┃ output ┃
┡━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━┩
│ refused │ http.request │ failed  │ -     │ 0.0s     │ -      │
│ unlucky │ http.request │ failed  │ -     │ 0.0s     │ -      │
│ unlucky │ http.request │ failed  │ -     │ 0.0s     │ -      │
│ unlucky │ http.request │ failed  │ -     │ 0.0s     │ -      │
└─────────┴──────────────┴─────────┴───────┴──────────┴────────┘

refused failed  http.request, attempt 1, rejected
  GET http://127.0.0.1:3333/api/v1/playground/request answered 404
  last log lines:
    info: http call

unlucky failed  http.request, attempt 1, transient
  GET http://127.0.0.1:3333/api/v1/playground/request answered 503
  last log lines:
    info: http call

unlucky failed  http.request, attempt 2, transient
  GET http://127.0.0.1:3333/api/v1/playground/request answered 503
  last log lines:
    info: http call

unlucky failed  http.request, attempt 3, transient
  GET http://127.0.0.1:3333/api/v1/playground/request answered 503
  last log lines:
    info: http call
```

Same budget, one row against three. `refused` was given `max_attempts: 3` and used one of them:
the block read 404 as `rejected`, and a rejected failure never touches the budget. `unlucky` was
given the same three and spent every one, because 503 is `transient`.

Read the timestamps rather than the durations: the second attempt starts about two seconds after
the first failed, and the third about four after that. The delay between attempts is data rather
than a sleep -- each failure writes the next attempt's time into the future and the worker moves
on, so nothing holds a worker slot for the backoff. The call itself takes single-digit
milliseconds, because the service answering is the instance on this machine.

Now the same document on the instance:

```bash
uv run dg apply
uv run dg run echo-retry --watch
```

```text
2026-09-26T12:42:46.250+02:00 [info    ] started                        [run] pipeline=echo-retry run_id=01a0dd4f-7165-72f5-8ad8-41544b361d1f local=false
2026-09-26T12:42:46.247+02:00 [info    ] queued                         [step refused] block=http.request attempt=1
2026-09-26T12:42:46.247+02:00 [info    ] queued                         [step unlucky] block=http.request attempt=1
2026-09-26T12:42:46.464+02:00 [info    ] http call                      [log refused] method=GET url=http://127.0.0.1:3333/api/v1/playground/request status=404 bytes=398 duration_ms=17
2026-09-26T12:42:46.470+02:00 [info    ] failed                         [step refused] block=http.request attempt=1 duration_ms=30
2026-09-26T12:42:46.470+02:00 [info    ] http call                      [log unlucky] method=GET url=http://127.0.0.1:3333/api/v1/playground/request status=503 bytes=398 duration_ms=4
2026-09-26T12:42:46.475+02:00 [info    ] failed                         [step unlucky] block=http.request attempt=1 duration_ms=14
2026-09-26T12:42:46.476+02:00 [info    ] queued                         [step unlucky] block=http.request attempt=2
2026-09-26T12:42:48.511+02:00 [info    ] http call                      [log unlucky] method=GET url=http://127.0.0.1:3333/api/v1/playground/request status=503 bytes=398 duration_ms=4
2026-09-26T12:42:48.511+02:00 [info    ] failed                         [step unlucky] block=http.request attempt=2 duration_ms=10
2026-09-26T12:42:48.513+02:00 [info    ] queued                         [step unlucky] block=http.request attempt=3
2026-09-26T12:42:53.570+02:00 [info    ] http call                      [log unlucky] method=GET url=http://127.0.0.1:3333/api/v1/playground/request status=503 bytes=398 duration_ms=4
2026-09-26T12:42:53.571+02:00 [info    ] failed                         [step unlucky] block=http.request attempt=3 duration_ms=15
2026-09-26T12:42:56.765+02:00 [error   ] failed                         [run] pipeline=echo-retry run_id=01a0dd4f-7165-72f5-8ad8-41544b361d1f pipeline_version=1 triggered_by="admin (token dev)" duration_ms=7131 items_total=0 items_failed=0 exit_code=1 priority=normal
run 01a0dd4f-7165-72f5-8ad8-41544b361d1f
pipeline      echo-retry (version 1)
status        failed
triggered by  admin (token dev)
duration      7.1s
items         -

steps
┏━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step    ┃ block        ┃ outcome ┃ after ┃ attempts ┃ duration ┃ error                           ┃
┡━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ refused │ http.request │ failed  │ -     │ 1        │ 0.0s     │ GET                             │
│         │              │         │       │          │          │ http://127.0.0.1:3333/api/v1/p… │
│         │              │         │       │          │          │ answered 404                    │
│ unlucky │ http.request │ failed  │ -     │ 1        │ 0.0s     │ GET                             │
│         │              │         │       │          │          │ http://127.0.0.1:3333/api/v1/p… │
│         │              │         │       │          │          │ answered 503                    │
│ unlucky │ http.request │ failed  │ -     │ 2        │ 0.0s     │ GET                             │
│         │              │         │       │          │          │ http://127.0.0.1:3333/api/v1/p… │
│         │              │         │       │          │          │ answered 503                    │
│ unlucky │ http.request │ failed  │ -     │ 3        │ 0.0s     │ GET                             │
│         │              │         │       │          │          │ http://127.0.0.1:3333/api/v1/p… │
│         │              │         │       │          │          │ answered 503                    │
└─────────┴──────────────┴─────────┴───────┴──────────┴──────────┴─────────────────────────────────┘

refused failed  http.request, attempt 1, rejected
  GET http://127.0.0.1:3333/api/v1/playground/request answered 404
  last log lines:
    info: http call

unlucky failed  http.request, attempt 1, transient
  GET http://127.0.0.1:3333/api/v1/playground/request answered 503
  last log lines:
    info: http call
    info: http call
    info: http call

unlucky failed  http.request, attempt 2, transient
  GET http://127.0.0.1:3333/api/v1/playground/request answered 503
  last log lines:
    info: http call
    info: http call
    info: http call

unlucky failed  http.request, attempt 3, transient
  GET http://127.0.0.1:3333/api/v1/playground/request answered 503
  last log lines:
    info: http call
    info: http call
    info: http call
```

The `attempts` column is the one to look at: `1` beside `refused`, and `1`, `2`, `3` beside
`unlucky`. Each is its own row, with its own error, and the run is `failed` because a step in it
failed with nothing tolerating it. The error column is narrowed to the terminal's width here; the
failure detail under the table carries each message whole.

```bash
uv run dg runs show 01a0dd4f-7165-72f5-8ad8-41544b361d1f --json \
  | jq -c '[.fields.attempts[] | {step: .step_name, attempt: .attempt, class: .error_class}]'
```

```json
[{"step":"refused","attempt":1,"class":"rejected"},{"step":"unlucky","attempt":1,"class":"transient"},{"step":"unlucky","attempt":2,"class":"transient"},{"step":"unlucky","attempt":3,"class":"transient"}]
```

Four attempts across two steps, each carrying the class the block decided on. That is what
`verify.sh` asserts, and it is the only honest thing to assert: a table is a rendering, and the
class is a fact the record carries.

## Why the classes differ

That classification is a block's job, and every block makes it the same way:

| What happened | Class | Retried |
| --- | --- | --- |
| A connection or read failure on the wire | `transient` | yes |
| The service answered 5xx | `transient` | yes |
| The service answered 429, rate limiting | `transient` | yes |
| The service answered any other 4xx | `rejected` | no |
| A gate refused the value | `rejected` | no |
| A config or reference that will not resolve | `rejected` | no |

429 is the one client error worth retrying: the service is asking you to come back, and the same
call succeeds once the window has passed. That is why `max_attempts` above 1 is worth writing on a
step that calls anything over a network at all -- and why it costs nothing on the step that was
simply wrong.

## The document, hop by hop

`pipelines/echo-retry.yaml`:

```yaml
format: dirigent/v1
kind: pipeline
code: echo-retry
name: Echo retry
description: One step is refused and one is unlucky, under the same retry budget, and only one of them is retried.

tags: [http, retry, failure]

requires:
  blocks:
    - http.request

params:
  type: object
  properties:
    playground:
      type: string
      default: http://127.0.0.1:3333/api/v1/playground
      description: The playground routes on the instance this calls; `dg dev` serves them here.

steps:
  refused:
    block: http.request
    retry:
      max_attempts: 3
      backoff: 2s
    config:
      # 404 is the service saying the thing is not there. Asking again cannot change that, so the
      # block classifies it rejected and the budget above is never touched.
      url: ${params.playground}/request
      method: GET
      query:
        status: 404

  unlucky:
    block: http.request
    retry:
      max_attempts: 3
      backoff: 2s
    config:
      # 503 is the service saying it is unwell right now, which is a different sentence: the block
      # classifies it transient and every attempt in the budget is spent.
      url: ${params.playground}/request
      method: GET
      query:
        status: 503
```

Neither step names the other in `depends_on`, so neither waits: dirigent runs whatever is not
waiting on anything in parallel, and the run's table puts them side by side. `retry` is a
step-level policy, and the two fields used here are the two that matter first -- `max_attempts` is
how many attempts the step may have in total, and `backoff` is the wait before the next one.
(`multiplier`, `max_backoff` and `jitter` are the rest of it: the multiplier doubles the wait,
`max_backoff` caps it so a long budget cannot become a long sleep, and jitter spreads the retries
of a fan-out that all failed in the same instant.)

`status` is a query argument the playground reads as a knob rather than as data: it answers with
that status, and reflects the request under it either way. So the two steps differ in one number,
and that number is the two sentences a real service says: *the thing is not there*, and *I am
unwell right now*. Both are built on `playground`, the document's one parameter.

## Where to go next

- [`echo-fanout`](../echo-fanout/README.md) is the same two classes over a list: one item per
  station, one station down, and a join that counts the survivors rather than the rows asked for.
- [**The basics**](https://winterop-com.github.io/dirigent/basics/) is the tutorial this example is
  cut from, and section 6 is this step of it.
- [**The examples**](../README.md): every example in order, and what you need once.
