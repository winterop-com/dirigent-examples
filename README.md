# echo-retry

Two steps, one retry policy written twice, and one row against three. A **rejected** failure spends
no budget, because the service will answer the same way in two seconds and in two hours; a
**transient** one spends all of it. The difference is not in the policy -- the two `retry:` blocks
here are identical -- it is in what the service said, and classifying that is the block's job. This
is the example that fails on purpose: both of its steps fail, the run ends `failed`, and that is
the whole point of looking at it.

## Run it

From a fresh clone, with nothing running:

```bash
uv sync
uv run dg validate pipelines/echo-retry.yaml
uv run dg run --local pipelines/echo-retry.yaml    # fails, by design
```

That run takes the better part of ten seconds, because the retried step waits two and then four
before giving up.

In a second terminal, in this directory:

```bash
uv run dg dev
```

On an empty state -- which is what a fresh clone has -- `dg dev` migrates the schema, makes its own
admin `dev`, mints that admin one token and prints the `export DG_TOKEN=` line to paste. Back in
the first terminal, with that line pasted:

```bash
uv run dg apply
uv run dg run echo-retry --watch
uv run dg runs show <run id> --json | jq -c '[.fields.attempts[] | {step: .step_name, attempt: .attempt, class: .error_class}]'
```

The contrast is worth seeing on an instance as well as locally, because there every attempt is a
row of its own with its own resolved config and its own logs -- which is what makes a retry
auditable rather than a counter.

`./verify.sh` does all of it non-interactively, on a free port of its own, and asserts that the
refusal took one attempt of the three it was allowed and the outage took all three.

## What you see

```bash
uv run dg run --local pipelines/echo-retry.yaml
```

```text
2026-09-17T15:12:16.790+02:00 [info    ] started                        [run] pipeline=echo-retry run_id=01a0af7f-1690-7074-9062-ef7945f0390e local=true scratch=file:///tmp/dirigent-local-fg87qehm/artifacts/runs/01a0af7f-1690-7074-9062-ef7945f0390e root=/tmp/dirigent-local-fg87qehm
2026-09-17T15:12:16.784+02:00 [info    ] queued                         [step refused] block=http.request attempt=1
2026-09-17T15:12:16.784+02:00 [info    ] queued                         [step unlucky] block=http.request attempt=1
2026-09-17T15:12:16.868+02:00 [info    ] running                        [step refused] block=http.request attempt=1
2026-09-17T15:12:16.979+02:00 [info    ] running                        [step unlucky] block=http.request attempt=1
2026-09-17T15:12:17.470+02:00 [info    ] http call                      [log unlucky] method=GET url=https://postman-echo.com/status/503 status=503 bytes=14 duration_ms=484
2026-09-17T15:12:17.473+02:00 [info    ] failed                         [step unlucky] block=http.request attempt=1 duration_ms=494
2026-09-17T15:12:19.776+02:00 [info    ] queued                         [step unlucky] block=http.request attempt=2
2026-09-17T15:12:19.781+02:00 [info    ] running                        [step unlucky] block=http.request attempt=2
2026-09-17T15:12:21.511+02:00 [info    ] http call                      [log unlucky] method=GET url=https://postman-echo.com/status/503 status=503 bytes=14 duration_ms=1726
2026-09-17T15:12:21.512+02:00 [info    ] failed                         [step unlucky] block=http.request attempt=2 duration_ms=1732
2026-09-17T15:12:25.433+02:00 [info    ] queued                         [step unlucky] block=http.request attempt=3
2026-09-17T15:12:22.524+02:00 [info    ] http call                      [log refused] method=GET url=https://postman-echo.com/status/404 status=404 bytes=14 duration_ms=5647
2026-09-17T15:12:22.526+02:00 [info    ] failed                         [step refused] block=http.request attempt=1 duration_ms=5659
2026-09-17T15:12:25.707+02:00 [info    ] http call                      [log unlucky] method=GET url=https://postman-echo.com/status/503 status=503 bytes=14 duration_ms=238
2026-09-17T15:12:25.708+02:00 [info    ] failed                         [step unlucky] block=http.request attempt=3 duration_ms=249
2026-09-17T15:12:25.975+02:00 [error   ] failed                         [run] pipeline=echo-retry run_id=01a0af7f-1690-7074-9062-ef7945f0390e exit_code=1
steps
┏━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━┓
┃ step    ┃ block        ┃ outcome ┃ after ┃ duration ┃ output ┃
┡━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━┩
│ refused │ http.request │ failed  │ -     │ 5.7s     │ -      │
│ unlucky │ http.request │ failed  │ -     │ 0.5s     │ -      │
│ unlucky │ http.request │ failed  │ -     │ 1.7s     │ -      │
│ unlucky │ http.request │ failed  │ -     │ 0.2s     │ -      │
└─────────┴──────────────┴─────────┴───────┴──────────┴────────┘

refused failed  http.request, attempt 1, rejected
  GET https://postman-echo.com/status/404 answered 404
  last log lines:
    info: http call

unlucky failed  http.request, attempt 1, transient
  GET https://postman-echo.com/status/503 answered 503
  last log lines:
    info: http call

unlucky failed  http.request, attempt 2, transient
  GET https://postman-echo.com/status/503 answered 503
  last log lines:
    info: http call

unlucky failed  http.request, attempt 3, transient
  GET https://postman-echo.com/status/503 answered 503
  last log lines:
    info: http call
```

Same budget, one row against three. `refused` was given `max_attempts: 3` and used one of them:
the block read 404 as `rejected`, and a rejected failure never touches the budget. `unlucky` was
given the same three and spent every one, because 503 is `transient`.

Read the timestamps rather than the durations: the second attempt starts about two seconds after
the first failed, and the third about four after that. The delay between attempts is data rather
than a sleep -- each failure writes the next attempt's time into the future and the worker moves
on, so nothing holds a worker slot for the backoff.

Now the same document on the instance:

```bash
uv run dg apply
uv run dg run echo-retry --watch
```

```text
2026-09-17T15:12:44.380+02:00 [info    ] started                        [run] pipeline=echo-retry run_id=01a0af7f-8258-75c0-b7fa-a1b6a6157428 local=false
2026-09-17T15:12:44.378+02:00 [info    ] queued                         [step refused] block=http.request attempt=1
2026-09-17T15:12:44.378+02:00 [info    ] queued                         [step unlucky] block=http.request attempt=1
2026-09-17T15:12:44.669+02:00 [info    ] running                        [step refused] block=http.request attempt=1
2026-09-17T15:12:44.689+02:00 [info    ] running                        [step unlucky] block=http.request attempt=1
2026-09-17T15:12:44.935+02:00 [info    ] http call                      [log refused] method=GET url=https://postman-echo.com/status/404 status=404 bytes=14 duration_ms=259
2026-09-17T15:12:44.937+02:00 [info    ] failed                         [step refused] block=http.request attempt=1 duration_ms=267
2026-09-17T15:12:44.944+02:00 [info    ] http call                      [log unlucky] method=GET url=https://postman-echo.com/status/503 status=503 bytes=14 duration_ms=251
2026-09-17T15:12:44.945+02:00 [info    ] failed                         [step unlucky] block=http.request attempt=1 duration_ms=256
2026-09-17T15:12:44.947+02:00 [info    ] queued                         [step unlucky] block=http.request attempt=2
2026-09-17T15:12:47.478+02:00 [info    ] http call                      [log unlucky] method=GET url=https://postman-echo.com/status/503 status=503 bytes=14 duration_ms=263
2026-09-17T15:12:47.479+02:00 [info    ] failed                         [step unlucky] block=http.request attempt=2 duration_ms=269
2026-09-17T15:12:47.481+02:00 [info    ] queued                         [step unlucky] block=http.request attempt=3
2026-09-17T15:12:52.509+02:00 [info    ] http call                      [log unlucky] method=GET url=https://postman-echo.com/status/503 status=503 bytes=14 duration_ms=258
2026-09-17T15:12:52.510+02:00 [info    ] failed                         [step unlucky] block=http.request attempt=3 duration_ms=263
2026-09-17T15:12:54.870+02:00 [error   ] failed                         [run] pipeline=echo-retry run_id=01a0af7f-8258-75c0-b7fa-a1b6a6157428 pipeline_version=1 triggered_by="dev (token cli-dev)" duration_ms=7841 items_total=0 items_failed=0 exit_code=1 priority=normal
run
01a0af7f-8258-75c0-b7fa-a1b6a6157428
pipeline      echo-retry (version 1)
status        failed
triggered by  dev (token cli-dev)
duration      7.8s
items         -

steps
┏━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step    ┃ block        ┃ outcome ┃ after ┃ attempts ┃ duration ┃ error                           ┃
┡━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ refused │ http.request │ failed  │ -     │ 1        │ 0.3s     │ GET                             │
│         │              │         │       │          │          │ https://postman-echo.com/statu… │
│         │              │         │       │          │          │ answered 404                    │
│ unlucky │ http.request │ failed  │ -     │ 1        │ 0.3s     │ GET                             │
│         │              │         │       │          │          │ https://postman-echo.com/statu… │
│         │              │         │       │          │          │ answered 503                    │
│ unlucky │ http.request │ failed  │ -     │ 2        │ 0.3s     │ GET                             │
│         │              │         │       │          │          │ https://postman-echo.com/statu… │
│         │              │         │       │          │          │ answered 503                    │
│ unlucky │ http.request │ failed  │ -     │ 3        │ 0.3s     │ GET                             │
│         │              │         │       │          │          │ https://postman-echo.com/statu… │
│         │              │         │       │          │          │ answered 503                    │
└─────────┴──────────────┴─────────┴───────┴──────────┴──────────┴─────────────────────────────────┘

refused failed  http.request, attempt 1, rejected
  GET https://postman-echo.com/status/404 answered 404
  last log lines:
    info: http call

unlucky failed  http.request, attempt 1, transient
  GET https://postman-echo.com/status/503 answered 503
  last log lines:
    info: http call
    info: http call
    info: http call

unlucky failed  http.request, attempt 2, transient
  GET https://postman-echo.com/status/503 answered 503
  last log lines:
    info: http call
    info: http call
    info: http call

unlucky failed  http.request, attempt 3, transient
  GET https://postman-echo.com/status/503 answered 503
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
uv run dg runs show 01a0af7f-8258-75c0-b7fa-a1b6a6157428 --json \
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
# Two failures with the same retry budget, to show what the budget is actually for.
#
# Neither step depends on the other, so both run in the same run and the run's table puts them side
# by side: one row against three, under identical retry: blocks. The difference is not the policy,
# it is what the service said. A rejected failure spends no budget, because the service will answer
# the same way in two seconds and in two hours; a transient one spends all of it.
#
# The delay between attempts is data rather than a sleep: each failure writes the next attempt's
# time into the future and the worker moves on, so nothing holds a worker slot for the backoff.
#
# This run is meant to fail. Both steps fail, so the run ends failed with exit code 1.
#
#   dg run --local pipelines/echo-retry.yaml     # failed, by design

format: dirigent/v1
kind: pipeline
code: echo-retry
name: Echo retry
description: One step is refused and one is unlucky, under the same retry budget, and only one of them is retried.

tags: [http, retry, failure]

requires:
  blocks:
    - http.request

steps:
  refused:
    block: http.request
    retry:
      max_attempts: 3
      backoff: 2s
    config:
      # 404 is the service saying the thing is not there. Asking again cannot change that, so the
      # block classifies it rejected and the budget above is never touched.
      url: https://postman-echo.com/status/404
      method: GET

  unlucky:
    block: http.request
    retry:
      max_attempts: 3
      backoff: 2s
    config:
      # 503 is the service saying it is unwell right now, which is a different sentence: the block
      # classifies it transient and every attempt in the budget is spent.
      url: https://postman-echo.com/status/503
      method: GET
```

Neither step names the other in `depends_on`, so neither waits: dirigent runs whatever is not
waiting on anything in parallel, and the run's table puts them side by side. `retry` is a
step-level policy, and the two fields used here are the two that matter first -- `max_attempts` is
how many attempts the step may have in total, and `backoff` is the wait before the next one.
(`multiplier`, `max_backoff` and `jitter` are the rest of it: the multiplier doubles the wait,
`max_backoff` caps it so a long budget cannot become a long sleep, and jitter spreads the retries
of a fan-out that all failed in the same instant.)

`/status/404` and `/status/503` are Postman Echo answering with a status and nothing else, which
makes them a stand-in for the two sentences a real service says: *the thing is not there*, and
*I am unwell right now*.

## Where to go next

- [**The basics**](https://winterop-com.github.io/dirigent/basics/) is the tutorial this example is
  cut from, and section 6 is this step of it.
- [**echo-send**](../echo-send) is the run that works: a read, a gate and a send, with the gate's
  refusal skipping the step behind it rather than retrying it.
