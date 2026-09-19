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
not store one until it has a key to seal it with. Mint it once into `.env` -- the gitignored
file beside the state that already holds this instance's token -- and every command run in this
directory reads it from there, which is what keeps this instance on the key it sealed with: one
that changes its key cannot open the secrets it already stored. In a second terminal, in this
directory:

```bash
grep -q '^DIRIGENT_SECRET_KEY=' .env 2>/dev/null \
  || printf 'DIRIGENT_SECRET_KEY=%s\n' "$(uv run dg secret-key)" >> .env
uv run dg dev
```

`dg dev` is one process holding the API, the web UI, the scheduler, one worker and a SQLite
file under `.dirigent/state/`. It keeps running; leave it. On an empty state -- which is what
a fresh clone has, because the state directory is not in the repository -- it migrates the
schema, makes its own admin `dev`, mints that admin one token, and prints the `export
DG_TOKEN=` line to paste. The UI is at `http://127.0.0.1:3333`, which is the address the
`local` profile in `.dirigent/profiles.yaml` holds; `dg dev --port` moves the instance and
`DG_URL` is how you tell the CLI where it went.

Back in the first terminal, with that export line pasted:

```bash
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

At a terminal, `dg connection create` asks only for a secret the kind cannot do without, and
only when the command did not say what it wants. This one carries `--set`, and `bearer_token`
is optional, so it completes without a prompt and leaves that field unset.

The rule is created after the pipeline because `--pipeline` scopes it to one, and a scope
naming a pipeline no instance holds is refused. `./verify.sh` does all of this unattended: it
keeps the key on a line in the gitignored `.env` so its second run can still read what its
first run stored, starts a `dg dev` on a free port of its own, mints its token with `dg auth login
--username dev --password dirigent-dev`, writes the connection and the rule, fails a run,
waits for the notification to be delivered, and stops the instance it started by pid.

### If the key was lost

A connection is sealed with the key the instance held when it was written, so a state left over
from a key that is gone answers `uv run dg connection check echo-sink` with a record whose
`detail` begins `SecretKeyMismatch`. Nothing opens that row again -- there is no `dg connection
update`, and the secret it holds is not recoverable -- so write it once more under the key this
instance has now. The rule points at the connection and an instance refuses to delete a
connection a rule still holds, so the rule goes first and both are written again after:

```bash
uv run dg alerts rules delete echo-failed
uv run dg connection delete echo-sink
```

Then the `dg connection create` and `dg alerts rules create` above, unchanged -- which is the
same order `verify.sh` uses between its two legs.

## Offline

Postman Echo is the one thing here that needs the network, and `local-echo` beside this
repository is the same service in one file of Python. It is also where the alert goes, and a
delivery is over before you can read the terminal -- so start it with a record file, outside
this repository where nothing about it can land in git:

```bash
python3 ../local-echo/echo_server.py --record ../webhook.ndjson
```

The document takes the parameter it already carries. The sink does not: a connection is an
instance record, not a line in the document, so pointing this example at the local echo is
the same command with a different url:

```bash
uv run dg connection create webhook echo-sink \
    --name "The alert sink" \
    --description "The local echo's /post, which answers with whatever was POSTed to it." \
    --set url=http://127.0.0.1:8080/post

uv run dg run echo-alert --watch -p base_url=http://127.0.0.1:8080
```

```text
2026-09-17T15:58:08.553+02:00 [info    ] http call                      [log ask] method=GET url=http://127.0.0.1:8080/get status=200 bytes=288 duration_ms=2
2026-09-17T15:58:09.064+02:00 [info    ] http call                      [log publish] method=GET url=http://127.0.0.1:8080/status/404 status=404 bytes=15 duration_ms=3
2026-09-17T15:58:09.066+02:00 [info    ] alert 'echo-failed' queued for delivery through 'webhook' [log] event=run_failed notifier=webhook
```

An instance that already holds `echo-sink` refuses a second one, and it refuses to delete a
connection a rule still points at -- so repointing the sink is `dg alerts rules delete
echo-failed`, then `dg connection delete echo-sink`, then those two commands again. That
order is what `verify.sh` does between its two legs.

Then read what arrived. The alert is delivered as JSON, and it carries the whole of the run's
context under `context`, so this picks out the three fields the rule's own templates wrote:

```bash
jq -c 'select(.path == "/post") | {method, path, event: .json.event, subject: .json.subject, body: .json.body}' ../webhook.ndjson
```

```json
{"method":"POST","path":"/post","event":"run_failed","subject":"echo-alert run failed","body":"Run 01a0afa9-137e-7667-9bbf-391f20a122cf of echo-alert (version 1) ended failed in 519ms."}
```

That is the delivery itself rather than the instance's word for it, which is the one thing
`dg alerts queue` cannot show you.

`./verify.sh` makes every assertion on this page twice, once against each echo, whenever
`../local-echo/echo_server.py` is there; `VERIFY_OFFLINE=1 ./verify.sh` leaves the online
leg out. `OFFLINE.md` beside this repository is the rest of the story, including the
`UV_OFFLINE=1` that keeps `uv` off the network too.

## What you see

*Printed as it printed, with this project's directory written as `/home/you/echo-alert` and a
local run's temporary root as `/tmp`.*

```bash
uv run dg validate pipelines/echo-alert.yaml
```

```text
2026-09-17T15:17:04.946+02:00 [info    ] valid                          [validation] code=echo-alert document=pipelines/echo-alert.yaml checked="document, offline"
  each step under the last one it waits for
    ask  (http.request)
      publish  (http.request)
        note  (log.write)
2026-09-17T15:17:04.948+02:00 [info    ] valid                          [validated] documents=1 invalid=0
```

```bash
uv run dg run --local pipelines/echo-alert.yaml
```

```text
2026-09-17T15:17:06.188+02:00 [info    ] started                        [run] pipeline=echo-alert run_id=01a0af83-8107-76fa-93e7-3297ceaba41d local=true scratch=file:///tmp/dirigent-local-3niage83/artifacts/runs/01a0af83-8107-76fa-93e7-3297ceaba41d root=/tmp/dirigent-local-3niage83
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

Now the instance. The connection is minted first, because the rule names it. Nothing is asked
for along the way: the command carries `--set`, so only a secret the kind cannot do without
would stop it, and `bearer_token` is not one:

```bash
uv run dg connection create webhook echo-sink \
    --name "The alert sink" \
    --description "Postman Echo's /post, which answers with whatever was POSTed to it." \
    --set url=https://postman-echo.com/post
```

```text
2026-09-19T12:07:51.873+02:00 [info    ] created                        [connection.created] code=echo-sink connection_kind=webhook name="The alert sink" description="Postman Echo's /post, which answers with whatever was POSTed to it." config={"url":"https://postman-echo.com/post","bearer_token":null,"headers":{},"verify_tls":true,"timeout":"15s"}
```

```bash
uv run dg apply
```

```text
create echo-alert  version 1 
(/home/you/echo-alert/pipelines/echo-alert.yaml)
```

```bash
uv run dg alerts rules create echo-failed \
    --name "Echo failures to the sink" \
    --event run_failed \
    --pipeline echo-alert \
    --notifier webhook \
    --connection echo-sink \
    --template '{{ pipeline.code }} run {{ run.status }}' \
    --body 'Run {{ run.id }} of {{ pipeline.code }} (version {{ pipeline.version }}) ended {{ run.status }} in {{ run.duration_ms | duration }}.'
```

```text
2026-09-19T12:07:54.108+02:00 [info    ] created                        [alert_rule.created] code=echo-failed name="Echo failures to the sink" event=run_failed scope=echo-alert notifier=webhook connection=echo-sink template=true body=true throttle=0s
```

`throttle=0s` is the default and it means no throttle: every failed run of `echo-alert` raises
its own notification. On a real instance a `run_failed` rule wants `--throttle 15m`, so a
pipeline failing every minute is one message rather than sixty.

Both templates are compiled when the rule is created, so one that does not compile is refused
here with the line it broke on rather than at the failure it was written for.

Then the failure, and what it raises:

```bash
uv run dg run echo-alert --watch
```

```text
2026-09-19T12:07:55.187+02:00 [info    ] started                        [run] pipeline=echo-alert run_id=01a0b923-052e-74b6-a3c6-001186f6fee8 local=false
2026-09-19T12:07:55.184+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-19T12:07:55.639+02:00 [info    ] running                        [step ask] block=http.request attempt=1
2026-09-19T12:07:55.964+02:00 [info    ] http call                      [log ask] method=GET url=https://postman-echo.com/get status=200 bytes=273 duration_ms=292
2026-09-19T12:07:55.970+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=331
2026-09-19T12:07:56.203+02:00 [info    ] running                        [step publish] block=http.request attempt=1
2026-09-19T12:07:56.483+02:00 [info    ] http call                      [log publish] method=GET url=https://postman-echo.com/status/404 status=404 bytes=14 duration_ms=263
2026-09-19T12:07:56.485+02:00 [info    ] failed                         [step publish] block=http.request attempt=1 duration_ms=282
2026-09-19T12:07:56.485+02:00 [info    ] skipped                        [step note] block=log.write attempt=1
2026-09-19T12:07:56.485+02:00 [info    ] alert 'echo-failed' queued for delivery through 'webhook' [log] event=run_failed notifier=webhook
2026-09-19T12:07:56.657+02:00 [info    ] alert delivered through 'webhook' [log] notifier=webhook event=run_failed
2026-09-19T12:07:57.639+02:00 [error   ] failed                         [run] pipeline=echo-alert run_id=01a0b923-052e-74b6-a3c6-001186f6fee8 pipeline_version=1 triggered_by="dev (token dev)" duration_ms=845 items_total=0 items_failed=0 exit_code=1 priority=normal
run 01a0b923-052e-74b6-a3c6-001186f6fee8
pipeline      echo-alert (version 1)  
status        failed                  
triggered by  dev (token dev)         
duration      0.8s                    
items         -                       

steps
┏━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step    ┃ block        ┃ outcome   ┃ after   ┃ attempts ┃ duration ┃ error                     ┃
┡━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask     │ http.request │ succeeded │ -       │ 1        │ 0.3s     │ -                         │
│ publish │ http.request │ failed    │ ask     │ 1        │ 0.3s     │ GET                       │
│         │              │           │         │          │          │ https://postman-echo.com… │
│         │              │           │         │          │          │ answered 404              │
│ note    │ log.write    │ skipped   │ publish │ 1        │ -        │ -                         │
└─────────┴──────────────┴───────────┴─────────┴──────────┴──────────┴───────────────────────────┘

outputs
┏━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step ┃ output                                                                        ┃
┡━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask  │ status=200  headers={12 keys}  body={3 keys}  body_bytes=273  duration_ms=292 │
└──────┴───────────────────────────────────────────────────────────────────────────────┘

publish failed  http.request, attempt 1, rejected
  GET https://postman-echo.com/status/404 answered 404
  last log lines:
    info: http call
```

The line worth finding in that stream is `alert 'echo-failed' queued for delivery through
'webhook'`. Queued, not sent: the notification goes on a queue, is leased by a worker and is
POSTed from there, so an alert never runs inside the transaction that settles the run. The
`alert delivered` line half a second under it is that worker, not this command. The queue says
the same thing afterwards:

```bash
uv run dg alerts queue
```

```text
notifications
┏━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━┳━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━┓
┃ subject               ┃ notifier ┃ status ┃ tries ┃ sent                ┃ error ┃
┡━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━╇━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━┩
│ echo-alert run failed │ webhook  │ sent   │ 1     │ 2026-09-19 12:07:56 │ -     │
└───────────────────────┴──────────┴────────┴───────┴─────────────────────┴───────┘
```

`echo-alert run failed` is the subject template, rendered. **sent** on the first try means the
POST answered, and the record says which notifier and which connection carried it:

```bash
uv run dg alerts queue --json | jq '.fields | {event, rule, notifier, connection, status, attempt, run_pipeline}'
```

```json
{
  "event": "run_failed",
  "rule": "echo-failed",
  "notifier": "webhook",
  "connection": "echo-sink",
  "status": "sent",
  "attempt": 1,
  "run_pipeline": "echo-alert"
}
```

```bash
uv run dg connection show echo-sink --json | jq '.fields.config'
```

```json
{
  "url": "https://postman-echo.com/post",
  "bearer_token": null,
  "headers": {},
  "verify_tls": true,
  "timeout": "15s"
}
```

That is the delivery, end to end: the run failed, the rule fired, the webhook notifier POSTed
the alert as JSON, and `https://postman-echo.com/post` took it. Every field the notifier
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
# event to a notifier and a notifier delivers through a connection, and both are records the
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
    # Every URL in this document is built on this one value, so pointing the document at
    # another echo is a flag on the run rather than an edit: -p base_url=http://127.0.0.1:8080
    # runs it against a stand-in on this machine, with no network at all. Where the alert
    # itself is delivered is not here: that is the sink connection's url, on the instance.
    base_url:
      type: string
      default: https://postman-echo.com
      description: The echo service this document's requests are built on.
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
      url: ${params.base_url}/get
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
      url: ${params.base_url}/status/${params.publish_status}
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

- [`echo-storage`](../echo-storage/README.md) is what comes next: a payload out of a run and
  back into it, and a `report:` section, so a run that nobody watched writes its own account.
- [**The basics**](https://winterop-com.github.io/dirigent/basics/) is the tutorial these
  examples follow: one read, a schema gate on the answer, and a send built from the value
  that passed.
- [**The examples**](../README.md): every example in order, and what you need once.
