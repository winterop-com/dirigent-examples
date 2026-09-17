# echo-alert

A pipeline that fails at three in the morning has failed whether or not anybody is looking, so
the instance has to be the thing that notices. An **alert rule** binds an event -- `run_failed`,
`run_completed_with_errors`, `run_succeeded`, `run_stuck` -- at a scope to a **notifier**, and
the notifier delivers through a **connection**. None of those three is in the document, and
that is the design rather than an omission: a rule is operational and a connection carries a
credential, and a document that carried either would stop being portable the moment it was
applied anywhere else. So this repository is a pipeline that fails on purpose, and a README
that is the rule. The sink here is Postman Echo's `/post`, which accepts anything and answers
with it -- a receiving endpoint you do not have to stand up.

## Run it

The pipeline fails by design, so prove that first, with no server:

```bash
uv sync
uv run dg validate pipelines/echo-alert.yaml
uv run dg run --local pipelines/echo-alert.yaml     # ends failed, and exits 1
```

The alerting half needs an instance. A connection carries a credential, so the instance will
not store one until it has a key to seal it with -- and an instance that changes its key
cannot read what it stored under the old one, so mint one key and keep it. In a second
terminal, in this directory:

```bash
export DIRIGENT_SECRET_KEY="$(uv run dg secret-key)"
uv run dg dev --port 3342
```

`dg dev` is one process holding the API, the web UI, the scheduler, one worker and a SQLite
file under `.dirigent/state/`. Its first start on an empty state directory makes the instance
and mints one token, in the line it prints -- `dg init` writes that token into the project's
`.env`, where the `local` profile reads it, and a clone of this repository has neither, so
copy it out of that line. Back in the first terminal:

```bash
export DG_URL=http://127.0.0.1:3342 DG_TOKEN=<the token that line printed>

uv run dg connection create webhook echo-sink \
    --name "The alert sink" \
    --description "Postman Echo's /post, which answers with whatever was POSTed to it." \
    --set url=https://postman-echo.com/post

uv run dg apply

uv run dg alerts rules create echo-failed \
    --name "Echo failures to the sink" \
    --event run_failed \
    --pipeline echo-alert \
    --notifier webhook \
    --connection echo-sink \
    --template '{{ pipeline.code }} run {{ run.status }}' \
    --body 'Run {{ run.id }} of {{ pipeline.code }} (version {{ pipeline.version }}) ended {{ run.status }} in {{ run.duration_ms | duration }}.'

uv run dg run echo-alert --watch
uv run dg alerts queue
```

The rule is created after the pipeline because `--pipeline` scopes it to one, and a scope
naming a pipeline no instance holds is refused. `./verify.sh` does all of this unattended: it
keeps the key in a gitignored `.secret-key` so its second run can still read what its first
run stored, starts a `dg dev` on a free port of its own, creates the connection and the rule
only where they are missing, fails a run, waits for the notification to be delivered, and
stops the instance it started by pid.

## What you see

```text
$ uv run dg validate pipelines/echo-alert.yaml
2026-09-17T15:17:04.946+02:00 [info    ] valid                          [validation] code=echo-alert document=pipelines/echo-alert.yaml checked="document, offline"
  each step under the last one it waits for
    ask  (http.request)
      publish  (http.request)
        note  (log.write)
2026-09-17T15:17:04.948+02:00 [info    ] valid                          [validated] documents=1 invalid=0

$ uv run dg run --local pipelines/echo-alert.yaml
2026-09-17T15:17:06.188+02:00 [info    ] started                        [run] pipeline=echo-alert run_id=01a0af83-8107-76fa-93e7-3297ceaba41d local=true scratch=file:///var/folders/7t/m0y6vhq508n4fsfg85vhgjkh0000gp/T/dirigent-local-3niage83/artifacts/runs/01a0af83-8107-76fa-93e7-3297ceaba41d root=/var/folders/7t/m0y6vhq508n4fsfg85vhgjkh0000gp/T/dirigent-local-3niage83
2026-09-17T15:17:06.183+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-17T15:17:06.275+02:00 [info    ] running                        [step ask] block=http.request attempt=1
2026-09-17T15:17:06.502+02:00 [info    ] http call                      [log ask] method=GET url=https://postman-echo.com/get status=200 bytes=273 duration_ms=218
2026-09-17T15:17:06.504+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=229
2026-09-17T15:17:06.522+02:00 [info    ] running                        [step publish] block=http.request attempt=1
2026-09-17T15:17:06.723+02:00 [info    ] http call                      [log publish] method=GET url=https://postman-echo.com/status/404 status=404 bytes=14 duration_ms=196
2026-09-17T15:17:06.724+02:00 [info    ] failed                         [step publish] block=http.request attempt=1 duration_ms=201
2026-09-17T15:17:06.724+02:00 [info    ] skipped                        [step note] block=log.write attempt=1
2026-09-17T15:17:06.784+02:00 [error   ] failed                         [run] pipeline=echo-alert run_id=01a0af83-8107-76fa-93e7-3297ceaba41d exit_code=1
steps                                                                                             
┏━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step    ┃ block        ┃ outcome   ┃ after   ┃ duration ┃ output                               ┃
┡━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask     │ http.request │ succeeded │ -       │ 0.2s     │ status=200  headers={12 keys}        │
│         │              │           │         │          │ body={3 keys}  body_bytes=273        │
│         │              │           │         │          │ duration_ms=218                      │
│ publish │ http.request │ failed    │ ask     │ 0.2s     │ -                                    │
│ note    │ log.write    │ skipped   │ publish │ -        │ -                                    │
└─────────┴──────────────┴───────────┴─────────┴──────────┴──────────────────────────────────────┘

publish failed  http.request, attempt 1, rejected
  GET https://postman-echo.com/status/404 answered 404
  last log lines:
    info: http call
(exit 1)
```

One attempt, with three allowed. The class is what decided that: **rejected** is the service
saying the thing is not there, and asking again in two seconds or in two hours cannot change
it, so the budget is untouched. `note` is **skipped** rather than failed -- it never ran,
because the step it waits for did not succeed.

Now the instance. The connection is minted first, because the rule names it:

```text
$ uv run dg connection create webhook echo-sink \
    --name "The alert sink" \
    --description "Postman Echo's /post, which answers with whatever was POSTed to it." \
    --set url=https://postman-echo.com/post
2026-09-17T15:17:20.014+02:00 [info    ] created                        [connection.created] code=echo-sink connection_kind=webhook name="The alert sink" description="Postman Echo's /post, which answers with whatever was POSTed to it." config={"url":"https://postman-echo.com/post","bearer_token":null,"headers":{},"verify_tls":true,"timeout":"15s"}

$ uv run dg apply
create echo-alert  version 1 
(/home/you/echo-alert/pipelines/echo-alert.yaml)

$ uv run dg alerts rules create echo-failed \
    --name "Echo failures to the sink" \
    --event run_failed \
    --pipeline echo-alert \
    --notifier webhook \
    --connection echo-sink \
    --template '{{ pipeline.code }} run {{ run.status }}' \
    --body 'Run {{ run.id }} of {{ pipeline.code }} (version {{ pipeline.version }}) ended {{ run.status }} in {{ run.duration_ms | duration }}.'
2026-09-17T15:17:22.302+02:00 [info    ] created                        [alert_rule.created] code=echo-failed name="Echo failures to the sink" event=run_failed scope=echo-alert notifier=webhook connection=echo-sink template=true body=true throttle=0s
```

`throttle=0s` is the default and it means no throttle: every failed run of `echo-alert` raises
its own notification. On a real instance a `run_failed` rule wants `--throttle 15m`, so a
pipeline failing every minute is one message rather than sixty.

Both templates are compiled when the rule is created, so one that does not compile is refused
here with the line it broke on rather than at the failure it was written for.

Then the failure, and what it raises:

```text
$ uv run dg run echo-alert --watch
2026-09-17T15:17:30.658+02:00 [info    ] started                        [run] pipeline=echo-alert run_id=01a0af83-e09e-76f4-8acb-0c58f4a32073 local=false
2026-09-17T15:17:30.656+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-17T15:17:30.656+02:00 [info    ] queued                         [step publish] block=http.request attempt=1
2026-09-17T15:17:31.009+02:00 [info    ] http call                      [log ask] method=GET url=https://postman-echo.com/get status=200 bytes=273 duration_ms=226
2026-09-17T15:17:31.011+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=235
2026-09-17T15:17:31.498+02:00 [info    ] http call                      [log publish] method=GET url=https://postman-echo.com/status/404 status=404 bytes=14 duration_ms=194
2026-09-17T15:17:31.500+02:00 [info    ] failed                         [step publish] block=http.request attempt=1 duration_ms=200
2026-09-17T15:17:31.500+02:00 [info    ] skipped                        [step note] block=log.write attempt=1
2026-09-17T15:17:31.500+02:00 [info    ] alert 'echo-failed' queued for delivery through 'webhook' [log] event=run_failed notifier=webhook
2026-09-17T15:17:31.959+02:00 [error   ] failed                         [run] pipeline=echo-alert run_id=01a0af83-e09e-76f4-8acb-0c58f4a32073 pipeline_version=1 triggered_by="admin (token init)" duration_ms=723 items_total=0 items_failed=0 exit_code=1 priority=normal
run                                   
01a0af83-e09e-76f4-8acb-0c58f4a32073  
pipeline      echo-alert (version 1)  
status        failed                  
triggered by  admin (token init)      
duration      0.7s                    
items         -                       

steps                                                                                             
┏━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step    ┃ block        ┃ outcome   ┃ after   ┃ attempts ┃ duration ┃ error                     ┃
┡━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask     │ http.request │ succeeded │ -       │ 1        │ 0.2s     │ -                         │
│ publish │ http.request │ failed    │ ask     │ 1        │ 0.2s     │ GET                       │
│         │              │           │         │          │          │ https://postman-echo.com… │
│         │              │           │         │          │          │ answered 404              │
│ note    │ log.write    │ skipped   │ publish │ 1        │ -        │ -                         │
└─────────┴──────────────┴───────────┴─────────┴──────────┴──────────┴───────────────────────────┘

outputs                                                                                 
┏━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step ┃ output                                                                        ┃
┡━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask  │ status=200  headers={12 keys}  body={3 keys}  body_bytes=273  duration_ms=226 │
└──────┴───────────────────────────────────────────────────────────────────────────────┘

publish failed  http.request, attempt 1, rejected
  GET https://postman-echo.com/status/404 answered 404
  last log lines:
    info: http call
(exit 1)
```

The line worth finding in that stream is `alert 'echo-failed' queued for delivery through
'webhook'`. Queued, not sent: the notification goes on a queue, is leased by a worker and is
POSTed from there, so an alert never runs inside the transaction that settles the run. A
moment later:

```text
$ uv run dg alerts queue
notifications                                                                      
┏━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━┳━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━┓
┃ subject               ┃ notifier ┃ status ┃ tries ┃ sent                ┃ error ┃
┡━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━╇━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━┩
│ echo-alert run failed │ webhook  │ sent   │ 1     │ 2026-09-17 15:17:31 │ -     │
└───────────────────────┴──────────┴────────┴───────┴─────────────────────┴───────┘
```

`echo-alert run failed` is the subject template, rendered. **sent** on the first try means the
POST answered, and the record says which channel and which connection carried it:

```text
$ uv run dg alerts queue --json | jq '.fields | {event, rule, notifier, connection, status, attempt, run_pipeline}'
{
  "event": "run_failed",
  "rule": "echo-failed",
  "notifier": "webhook",
  "connection": "echo-sink",
  "status": "sent",
  "attempt": 1,
  "run_pipeline": "echo-alert"
}

$ uv run dg connection show echo-sink --json | jq '.fields.config'
{
  "url": "https://postman-echo.com/post",
  "bearer_token": null,
  "headers": {},
  "verify_tls": true,
  "timeout": "15s"
}
```

That is the delivery, end to end: the run failed, the rule fired, the webhook notifier POSTed
the alert as JSON, and `https://postman-echo.com/post` took it. Every field the channel
declares secret -- `bearer_token` here -- is encrypted at rest and comes back redacted from
every read; this connection has none set, so it reads as null.

`dg alerts queue` is the one place a notifier that has quietly stopped delivering is visible,
because the thing that would otherwise tell you is the notifier. `dg alerts test webhook
--connection echo-sink` sends one message through the same queue, which is the only way to
prove an endpoint accepts an alert -- `dg connection check` sends a HEAD and proves only that
it is reachable.

## The document, hop by hop

`pipelines/echo-alert.yaml` opens by saying where the other half lives:

```yaml
# A run that fails on purpose, so there is something for an alert rule to be about.
#
# In:  one station's reading, read back from Postman Echo.
# Out: nothing. The step that would publish it is answered 404 and the run ends failed.
#
# The alerting half of this example is not in this document and cannot be: a rule binds an
# event to a channel and a channel delivers through a connection, and both are records the
# INSTANCE holds, minted with `dg connection create` and `dg alerts rules create`. A
# document that carried either would be a document that carried a credential, which is the
# one thing a portable document must never do. So this file is only the failure, and
# README.md is the rule.
#
# Hop by hop:
#
#   ask      one GET at /get, which answers with the query arguments it was given.
#   publish  the send, pointed at /status/404. A 404 is the service saying the thing is not
#            there, so the block classes it rejected and spends no retry budget on it: one
#            attempt, whatever max_attempts allows. The step fails, so the run fails, and a
#            failed run is what raises run_failed.
#   note     never runs. Its edge is the default all_success, and the step it waits for did
#            not succeed, so it is skipped rather than failed.
#
# EXPECT THIS RUN TO FAIL in under a second, with publish rejected on one attempt and note
# skipped behind it.
#
#   uv run dg run --local pipelines/echo-alert.yaml     # fails, by design
#   uv run dg run --local pipelines/echo-alert.yaml -p publish_status=200   # succeeds
```

The lines every document opens with, and a parameter that decides whether this run is the
failure or the happy path:

```yaml
format: dirigent/v1
kind: pipeline
code: echo-alert
name: A failure worth alerting on
description: |
  A read that works followed by a publish that is answered 404, so the run ends `failed`
  and an alert rule on `run_failed` has something to fire on.

  The rule and the connection it delivers through are the instance's, never the document's.

tags: [http, failure]

requires:
  blocks:
    - http.request
    - log.write

params:
  type: object
  properties:
    station:
      type: string
      default: bergen-florida
      minLength: 1
      description: The station the reading is asked for.
    publish_status:
      type: integer
      default: 404
      enum: [200, 404, 500]
      description: What the publish endpoint answers. 404 is the failure this example is for.
```

**`ask`** works. It is here so the failure below it is a failure in the middle of something
rather than the whole of it -- which is the shape a real one has:

```yaml
steps:
  ask:
    block: http.request
    config:
      url: https://postman-echo.com/get
      method: GET
      query:
        station: ${params.station}
        reading: "12.4"
```

**`publish`** is the failure, and the retry budget on it is the lesson: three attempts
allowed, one taken. What decides is the class of what came back, never the number in the
document:

```yaml
  publish:
    block: http.request
    depends_on: [ask]
    # Three attempts allowed, and a rejected failure takes one. The budget is here to show
    # that it is the class of the failure that decides, not the number in the document: a
    # 500 under this same budget would be retried three times.
    retry:
      max_attempts: 3
      backoff: 2s
    config:
      url: https://postman-echo.com/status/${params.publish_status}
      method: GET
```

**`note`** never runs, and the run's table says `skipped` rather than `failed` so that the
difference stays visible: a step that was refused its turn is not a step that went wrong.

```yaml
  note:
    block: log.write
    depends_on: [publish]
    config:
      message: "published the reading for ${params.station}"
```

`-p publish_status=200` runs the same document green, which is the other half of what a rule
is worth: a rule that fires on every run teaches nobody anything.

## Where to go next

- [**The basics**](https://winterop-com.github.io/dirigent/basics/) is the tutorial these
  examples follow: one read, a schema gate on the answer, and a send built from the value
  that passed.
- [**echo-schedule**](../echo-schedule/README.md) is why this matters. A run somebody started
  is a run somebody is watching; a run a clock started at three in the morning is not, and an
  alert rule is the difference.
