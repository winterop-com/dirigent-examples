# echo-alert

A pipeline that fails at three in the morning has failed whether or not anybody is looking, so
the instance has to be the thing that notices. An **alert rule** binds an event -- `run_failed`,
`run_completed_with_errors`, `run_succeeded`, `run_stuck` -- at a scope to a **notifier**, and
the notifier delivers through a **connection**. None of those three is in the document, and
that is the design rather than an omission: a rule is operational and a connection carries a
credential, and a document that carried either would stop being portable the moment it was
applied anywhere else. So this repository is a pipeline that fails on purpose, and a README
that is the rule. The sink here is the instance's own **playground**, the request-and-response
service every dirigent instance serves under `/api/v1/playground`: it accepts anything and
answers 200, so there is a receiving endpoint without standing one up and without anything
leaving the machine.

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
schema, makes its own admin `admin`, mints that admin one token, and prints the `export
DG_TOKEN=` line to paste. The UI is at `http://127.0.0.1:3333`, which is the address the
`local` profile in `.dirigent/profiles.yaml` holds; `dg dev --port` moves the instance and
`DG_URL` is how you tell the CLI where it went.

Back in the first terminal, with that export line pasted:

```bash
uv run dg connection create webhook echo-sink \
    --name "The alert sink" \
    --description "The instance's own playground, which answers 200 to whatever is POSTed." \
    --set url=http://127.0.0.1:3333/api/v1/playground/request

uv run dg apply

uv run dg alerts rules create echo-failed \
    --name "Echo failures to the sink" \
    --event run_failed \
    --pipeline echo-alert \
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
--username admin --password admin`, writes the connection and the rule, fails a run,
waits for the notification to be delivered, and stops the instance it started by pid.

### If the key was lost

A connection is sealed with the key the instance held when it was written, so a state left over
from a key that is gone answers `uv run dg connection check echo-sink` with a record whose
`detail` begins `SecretKeyMismatch`. Nothing opens that row again, and the secret it holds is
not recoverable. Nor can it be deleted while the rule points at it: `dg connection delete` names
the rule and refuses. So write it once more, in place, under the key this instance has now:

```bash
uv run dg connection ensure webhook echo-sink \
    --name "The alert sink" \
    --description "The instance's own playground, which answers 200 to whatever is POSTed." \
    --set url=http://127.0.0.1:3333/api/v1/playground/request
```

`dg connection ensure` writes the row straight to this instance's database, reading `.env` for
the key rather than a token, and brings it whole to what the arguments say. The rule keeps
pointing at it by its code, so nothing else changes. `verify.sh` takes the other way between its
two legs, because it points the sink somewhere else: it deletes the rule, then the connection,
and creates both again.

## This one needs no network

The pipeline is a node, not a call. `playground.generate` takes an `input` and hands it back,
and its `fail_until` knob makes a step fail on cue -- so the failure this example exists to
raise an alert about is a number in the document rather than an endpoint somewhere that has to
be answering. The sink the alert is delivered to is this instance's own playground, on the port
`dg dev` is serving. Nothing here leaves the machine.

`OFFLINE.md` beside this repository is the rest of the story, including the `UV_OFFLINE=1` that
keeps `uv` off the network too.

## What you see

*Printed as it printed, with this project's directory written as `/home/you/echo-alert` and a
local run's temporary root as `/tmp`.*

```bash
uv run dg validate pipelines/echo-alert.yaml
```

```text
2026-09-26T13:09:01.001+02:00 [info    ] valid                          [validation] code=echo-alert document=pipelines/echo-alert.yaml checked="document and installed blocks"
  each step under the last one it waits for
    ask  (playground.generate)
      publish  (playground.generate)
        note  (log.write)
2026-09-26T13:09:01.005+02:00 [info    ] valid                          [validated] documents=1 invalid=0 skipped=0
```

```bash
uv run dg run --local pipelines/echo-alert.yaml
```

```text
2026-09-26T13:09:02.610+02:00 [info    ] started                        [run] pipeline=echo-alert run_id=01a0dd67-7f0d-7498-92e6-580aa1e0c4a7 local=true scratch=file:///tmp/dirigent-local-z2fbr9w1/artifacts/runs/01a0dd67-7f0d-7498-92e6-580aa1e0c4a7 root=/tmp/dirigent-local-z2fbr9w1
2026-09-26T13:09:02.605+02:00 [info    ] queued                         [step ask] block=playground.generate attempt=1
2026-09-26T13:09:02.680+02:00 [info    ] playground generated           [log ask] rows=1 seed=1596481576 locale=en_US drift=none
2026-09-26T13:09:02.680+02:00 [info    ] succeeded                      [step ask] block=playground.generate attempt=1 duration_ms=37
2026-09-26T13:09:02.737+02:00 [info    ] failed                         [step publish] block=playground.generate attempt=1 duration_ms=4
2026-09-26T13:09:02.741+02:00 [error   ] failed                         [log publish] duration_ms=0 error_class=transient error_code=playground.failed_on_purpose error="the playground failed attempt 1 on purpose, because fail_until is 3; attempt 4 will succeed"
2026-09-26T13:09:03.618+02:00 [info    ] queued                         [step publish] block=playground.generate attempt=2
2026-09-26T13:09:03.683+02:00 [info    ] failed                         [step publish] block=playground.generate attempt=2 duration_ms=10
2026-09-26T13:09:03.683+02:00 [info    ] skipped                        [step note] block=log.write attempt=1
2026-09-26T13:09:03.686+02:00 [error   ] failed                         [log publish] duration_ms=0 error_class=transient error_code=playground.failed_on_purpose error="the playground failed attempt 2 on purpose, because fail_until is 3; attempt 4 will succeed"
2026-09-26T13:09:04.139+02:00 [error   ] failed                         [run] pipeline=echo-alert run_id=01a0dd67-7f0d-7498-92e6-580aa1e0c4a7 exit_code=1
steps
┏━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step            ┃ block               ┃ outcome   ┃ after   ┃ duration ┃ output                  ┃
┡━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask             │ playground.generate │ succeeded │ -       │ 0.0s     │ records=[1 items]       │
│                 │                     │           │         │          │ rows=1  seed=1596481576 │
│                 │                     │           │         │          │ locale=en_US  fields={3 │
│                 │                     │           │         │          │ keys}  drift=none       │
│                 │                     │           │         │          │ delay_ms=0  attempt=1   │
│                 │                     │           │         │          │ fail_until=0            │
│                 │                     │           │         │          │ input_rows=1            │
│ publish  1 warn │ playground.generate │ failed    │ ask     │ 0.0s     │ -                       │
│ publish  1 warn │ playground.generate │ failed    │ ask     │ 0.0s     │ -                       │
│ note            │ log.write           │ skipped   │ publish │ -        │ -                       │
└─────────────────┴─────────────────────┴───────────┴─────────┴──────────┴─────────────────────────┘

publish failed  playground.generate, attempt 1, transient
  the playground failed attempt 1 on purpose, because fail_until is 3; attempt 4 will succeed
  last log lines:
    error: failed

publish failed  playground.generate, attempt 2, transient
  the playground failed attempt 2 on purpose, because fail_until is 3; attempt 4 will succeed
  last log lines:
    error: failed
(exit 1)
```

Two attempts, which is the budget: `fail_until: 3` is above it, so the step runs out of tries
and the run ends `failed`. The failure is classed **transient**, which is the class a budget is
for -- [echo-retry](../echo-retry) is where the other class sits beside it. `note` is
**skipped** rather than failed: it never ran, because the step it waits for did not succeed.

Now the instance. The connection is minted first, because the rule names it. Nothing is asked
for along the way: the command carries `--set`, so only a secret the kind cannot do without
would stop it, and `bearer_token` is not one:

```bash
uv run dg connection create webhook echo-sink \
    --name "The alert sink" \
    --description "The instance's own playground, which answers 200 to whatever is POSTed." \
    --set url=http://127.0.0.1:3333/api/v1/playground/request
```

```text
2026-09-26T13:09:07.973+02:00 [info    ] created                        [connection.created] code=echo-sink connection_kind=webhook name="The alert sink" description="The instance's own playground, which answers 200 to whatever is POSTed." config={"url":"http://127.0.0.1:3333/api/v1/playground/request","bearer_token":null,"headers":{},"verify_tls":true,"timeout":"15s"}
```

```bash
uv run dg apply
```

```text
create echo-alert  version 1 (/home/you/echo-alert/pipelines/echo-alert.yaml)
```

```bash
uv run dg alerts rules create echo-failed \
    --name "Echo failures to the sink" \
    --event run_failed \
    --pipeline echo-alert \
    --connection echo-sink \
    --template '{{ pipeline.code }} run {{ run.status }}' \
    --body 'Run {{ run.id }} of {{ pipeline.code }} (version {{ pipeline.version }}) ended {{ run.status }} in {{ run.duration_ms | duration }}.'
```

```text
2026-09-26T13:09:10.467+02:00 [info    ] created                        [alert_rule.created] code=echo-failed name="Echo failures to the sink" event=run_failed scope=echo-alert notifier=webhook connection=echo-sink template=true body=true throttle=0s
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
2026-09-26T13:09:11.843+02:00 [info    ] started                        [run] pipeline=echo-alert run_id=01a0dd67-a31d-7218-a27d-62c2cb13765b local=false
2026-09-26T13:09:11.839+02:00 [info    ] queued                         [step ask] block=playground.generate attempt=1
2026-09-26T13:09:11.839+02:00 [info    ] queued                         [step publish] block=playground.generate attempt=1
2026-09-26T13:09:12.011+02:00 [info    ] playground generated           [log ask] rows=1 seed=2111780573 locale=en_US drift=none
2026-09-26T13:09:12.011+02:00 [info    ] succeeded                      [step ask] block=playground.generate attempt=1 duration_ms=52
2026-09-26T13:09:12.520+02:00 [info    ] failed                         [step publish] block=playground.generate attempt=1 duration_ms=5
2026-09-26T13:09:12.524+02:00 [error   ] failed                         [log publish] duration_ms=0 error_class=transient error_code=playground.failed_on_purpose error="the playground failed attempt 1 on purpose, because fail_until is 3; attempt 4 will succeed"
2026-09-26T13:09:12.525+02:00 [info    ] queued                         [step publish] block=playground.generate attempt=2
2026-09-26T13:09:14.037+02:00 [info    ] skipped                        [step note] block=log.write attempt=1
2026-09-26T13:09:14.037+02:00 [info    ] failed                         [step publish] block=playground.generate attempt=2 duration_ms=4
2026-09-26T13:09:14.040+02:00 [error   ] failed                         [log publish] duration_ms=0 error_class=transient error_code=playground.failed_on_purpose error="the playground failed attempt 2 on purpose, because fail_until is 3; attempt 4 will succeed"
2026-09-26T13:09:14.037+02:00 [info    ] alert 'echo-failed' queued for delivery through 'webhook' [log] event=run_failed notifier=webhook
2026-09-26T13:09:14.289+02:00 [error   ] failed                         [run] pipeline=echo-alert run_id=01a0dd67-a31d-7218-a27d-62c2cb13765b pipeline_version=1 triggered_by="admin (token dev)" duration_ms=2078 items_total=0 items_failed=0 exit_code=1 priority=normal
run 01a0dd67-a31d-7218-a27d-62c2cb13765b
pipeline      echo-alert (version 1)
status        failed
triggered by  admin (token dev)
duration      2.1s
items         -

steps
┏━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━┓
┃ step            ┃ block           ┃ outcome   ┃ after   ┃ attempts ┃ duration ┃ error            ┃
┡━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━┩
│ ask             │ playground.gen… │ succeeded │ -       │ 1        │ 0.1s     │ -                │
│ publish  2 warn │ playground.gen… │ failed    │ ask     │ 1        │ 0.0s     │ the playground   │
│                 │                 │           │         │          │          │ failed attempt 1 │
│                 │                 │           │         │          │          │ on purpose,      │
│                 │                 │           │         │          │          │ because          │
│                 │                 │           │         │          │          │ fail_until is 3; │
│                 │                 │           │         │          │          │ attempt 4 will   │
│                 │                 │           │         │          │          │ succeed          │
│ publish  2 warn │ playground.gen… │ failed    │ ask     │ 2        │ 0.0s     │ the playground   │
│                 │                 │           │         │          │          │ failed attempt 2 │
│                 │                 │           │         │          │          │ on purpose,      │
│                 │                 │           │         │          │          │ because          │
│                 │                 │           │         │          │          │ fail_until is 3; │
│                 │                 │           │         │          │          │ attempt 4 will   │
│                 │                 │           │         │          │          │ succeed          │
│ note            │ log.write       │ skipped   │ publish │ 1        │ -        │ -                │
└─────────────────┴─────────────────┴───────────┴─────────┴──────────┴──────────┴──────────────────┘

outputs
┏━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step ┃ output                                                                                    ┃
┡━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask  │ records=[1 items]  rows=1  seed=2111780573  locale=en_US  fields={3 keys}  drift=none     │
│      │ delay_ms=0  attempt=1  fail_until=0  input_rows=1                                         │
└──────┴───────────────────────────────────────────────────────────────────────────────────────────┘

publish failed  playground.generate, attempt 1, transient
  the playground failed attempt 1 on purpose, because fail_until is 3; attempt 4 will succeed
  last log lines:
    error: failed
    error: failed

publish failed  playground.generate, attempt 2, transient
  the playground failed attempt 2 on purpose, because fail_until is 3; attempt 4 will succeed
  last log lines:
    error: failed
    error: failed
```

The line worth finding in that stream is `alert 'echo-failed' queued for delivery through
'webhook'`. Queued, not sent: the notification goes on a queue, is leased by a worker and is
POSTed from there, so an alert never runs inside the transaction that settles the run. The
queue says how it went afterwards:

```bash
uv run dg alerts queue
```

```text
notifications
┏━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━┳━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━┓
┃ subject               ┃ notifier ┃ status ┃ tries ┃ sent                ┃ error ┃
┡━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━╇━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━┩
│ echo-alert run failed │ webhook  │ sent   │ 1     │ 2026-09-26 13:09:14 │ -     │
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
  "url": "http://127.0.0.1:3333/api/v1/playground/request",
  "bearer_token": null,
  "headers": {},
  "verify_tls": true,
  "timeout": "15s"
}
```

That is the delivery, end to end: the run failed, the rule fired, the webhook notifier POSTed
the alert as JSON, and the instance's own playground took it. Every field the notifier declares
secret -- `bearer_token` here -- is encrypted at rest and comes back redacted from every read;
this connection has none set, so it reads as null.

`dg alerts queue` is the one place a notifier that has quietly stopped delivering is visible,
because the thing that would otherwise tell you is the notifier. `dg alerts test --connection
echo-sink` sends one message through the same queue, which is the only way to prove an endpoint
accepts an alert -- `dg connection check` sends a HEAD and proves only that it is reachable.


## The document, hop by hop

`pipelines/echo-alert.yaml` opens by saying where the other half lives:

```yaml
# A run that fails on purpose, so there is something for an alert rule to be about.
#
# In:  one station's reading.
# Out: nothing. The step that would publish it fails every attempt and the run ends failed.
#
# NOTHING HERE IS CALLED. playground.generate takes an `input` and hands it back, and its
# `fail_until` knob fails that many attempts before succeeding -- so a failure on cue is a
# number in this document rather than an endpoint somewhere that has to be answering. No
# connection, no URL, no network.
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
#   ask      the reading for this run's station, as the node's one record.
#   publish  the send. fail_until is above the budget below, so every attempt fails and the
#            step is out of tries. The failure is classed transient, which is the class a
#            budget is for; echo-retry is where the other class sits beside it.
#   note     never runs. Its edge is the default all_success, and the step it waits for did
#            not succeed, so it is skipped rather than failed.
#
# EXPECT THIS RUN TO FAIL in about a second, with publish out of attempts and note skipped
# behind it.
#
#   uv run dg run --local pipelines/echo-alert.yaml     # fails, by design
#   uv run dg run --local pipelines/echo-alert.yaml -p fail_until=0   # succeeds
```

The lines every document opens with, and a parameter that decides whether this run is the
failure or the happy path:

```yaml
format: dirigent/v1
kind: pipeline
code: echo-alert
name: A failure worth alerting on
description: |
  A read that works followed by a publish that fails every attempt, so the run ends `failed`
  and an alert rule on `run_failed` has something to fire on.

  The rule and the connection it delivers through are the instance's, never the document's.

tags: [playground, failure]

requires:
  blocks:
    - playground.generate
    - log.write

params:
  type: object
  properties:
    station:
      type: string
      default: bergen-florida
      minLength: 1
      description: The station the reading is for.
    fail_until:
      type: integer
      default: 3
      minimum: 0
      maximum: 9
      description: How many of the publish's attempts fail. Above its budget of 2, all of them do.
```

**`ask`** works. It is here so the failure below it is a failure in the middle of something
rather than the whole of it -- which is the shape a real one has:

```yaml
steps:
  ask:
    block: playground.generate
    config:
      # No fields: are named, so the input travels through untouched and becomes this run's
      # one record.
      input:
        station: ${params.station}
        reading: "12.4"
```

**`publish`** is the failure, and `fail_until` is what makes it one on cue: the knob is above
the budget, so both attempts fail and the step runs out of tries. The failure is classed
transient, which is the class a budget exists for:

```yaml
  publish:
    block: playground.generate
    depends_on: [ask]
    # Two attempts allowed, and a transient failure spends both. Where the alert itself is
    # delivered is not here: that is the sink connection's url, on the instance.
    retry:
      max_attempts: 2
      backoff: 1s
    config:
      fail_until: ${params.fail_until}
      input: ${steps.ask.output.records.0}
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

`-p fail_until=0` runs the same document green, which is the other half of what a rule is
worth: a rule that fires on every run teaches nobody anything.

## Where to go next

- [`echo-storage`](../echo-storage/README.md) is what comes next: a payload out of a run and
  back into it, and a `report:` section, so a run that nobody watched writes its own account.
- [**The basics**](https://winterop-com.github.io/dirigent/basics/) is the tutorial these
  examples follow: one read, a schema gate on the answer, and a send built from the value
  that passed.
- [**The examples**](../README.md): every example in order, and what you need once.
