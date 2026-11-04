# echo-alert

A pipeline that fails at three in the morning has failed whether or not anybody is looking, so
the instance has to be the thing that notices. An **alert rule** binds an event -- `run_failed`,
`run_completed_with_errors`, `run_succeeded`, `run_stuck` -- at a scope to a **notifier**, and
the notifier delivers through a **connection**. The rules here are the document's own, in its
`alerts:` section beside the steps they are about, so they travel with the pipeline and an
apply keeps them in step with it. The connection is not: it carries a credential, and a
document that carried one would stop being portable the moment it was applied anywhere else.
So a rule names its connection by code, and the instance holds it. The sink here is the
instance's own **playground**, the request-and-response
service every dirigent instance serves under `/api/v1/playground`: it accepts anything and
answers 200, so there is a receiving endpoint without standing one up and without anything
leaving the machine.

## Run it

The pipeline fails by design, so prove that first, with no server:

```bash
uv sync
uv run dg validate pipelines/echo-alert.yaml
uv run dg run --local pipelines/echo-alert.yaml --connections connections.yaml   # ends failed, and exits 1
```

A local run plans the document against a throwaway instance that holds nothing, and plan refuses
a rule naming a connection the instance does not hold, so the run is handed `echo-sink` in
`connections.yaml`, beside the documents; it carries a url and no secret. The throwaway instance
raises the rules' alerts like any other, and delivers them before it exits: with a `dg dev` on
3333 its playground takes the POST, and with nothing there the delivery fails and the run's
outcome is the same.

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

uv run dg apply                 # the pipeline, and with it both of its rules
uv run dg alerts rules list

uv run dg run echo-alert --watch
uv run dg alerts queue
uv run dg runs summary --since 1h
uv run dg audit --since 1h
```

At a terminal, `dg connection create` asks only for a secret the kind cannot do without, and
only when the command did not say what it wants. This one carries `--set`, and `bearer_token`
is optional, so it completes without a prompt and leaves that field unset.

The connection is created before the apply because the document's `echo-failed` rule names it,
and plan refuses a rule naming a connection the instance does not hold. `./verify.sh` does all
of this unattended: it keeps the key on a line in the gitignored `.env` so its second run can
still read what its first run stored, starts a `dg dev` on a free port of its own, mints its
token with `dg auth login --username admin --password admin`, writes the connection, applies the
document and with it both rules, proves a hand delete of a declared rule is refused and a pause
survives an apply, plans a changed rule, fails a run locally and on the instance, waits for both
notifications to be delivered, reads the log rule's line back out of `.dirigent/state/dev.log`,
reads the runs summary and the audit trail, and stops the instance it started by pid.

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
pointing at it by its code, so nothing else changes. `verify.sh` does the same on every run after
its first, because its instance is on a new port each time and the sink's url moves with it.

## This one needs no network

The pipeline is a node, not a call. `playground.generate` takes an `input` and hands it back,
and its `fail_until` knob makes a step fail on cue -- so the failure this example exists to
raise an alert about is a number in the document rather than an endpoint somewhere that has to
be answering. The sink the alert is delivered to is this instance's own playground, on the port
`dg dev` is serving. Nothing here leaves the machine.

`OFFLINE.md` at the root of this repository is the rest of the story, including the `UV_OFFLINE=1` that
keeps `uv` off the network too.

## What you see

*Printed as it printed, with this project's directory written as `/home/you/echo-alert` and a
local run's temporary root as `/tmp`.*

```bash
uv run dg validate pipelines/echo-alert.yaml
```

```text
2026-11-03T14:25:51.641+01:00 [info    ] valid                          [validation] code=echo-alert document=pipelines/echo-alert.yaml checked="document and installed blocks"
  each step under the last one it waits for
    ask  (playground.generate)
      publish  (playground.generate)
        note  (log.write)
2026-11-03T14:25:51.651+01:00 [info    ] valid                          [validated] documents=1 invalid=0 skipped=0
```

```bash
uv run dg run --local pipelines/echo-alert.yaml --connections connections.yaml
```

```text
2026-11-03T14:25:58.033+01:00 [info    ] started                        [run] pipeline=echo-alert run_id=01a1a196-8284-77c1-9e87-d01f14fada9a local=true scratch=file:///tmp/dirigent-local-gyszk9lz/artifacts/runs/01a1a196-8284-77c1-9e87-d01f14fada9a root=/tmp/dirigent-local-gyszk9lz
2026-11-03T14:25:57.908+01:00 [info    ] queued                         [step ask] block=playground.generate attempt=1
2026-11-03T14:25:58.131+01:00 [info    ] running                        [step ask] block=playground.generate attempt=1
2026-11-03T14:25:58.283+01:00 [info    ] playground generated           [log ask] rows=1 seed=1527358980 locale=en_US drift=none
2026-11-03T14:25:58.288+01:00 [info    ] succeeded                      [step ask] block=playground.generate attempt=1 duration_ms=157
2026-11-03T14:25:58.288+01:00 [info    ] queued                         [step publish] block=playground.generate attempt=1
2026-11-03T14:25:58.302+01:00 [info    ] running                        [step publish] block=playground.generate attempt=1
2026-11-03T14:25:58.324+01:00 [info    ] failed                         [step publish] block=playground.generate attempt=1 duration_ms=22
2026-11-03T14:25:58.345+01:00 [error   ] failed                         [log publish] duration_ms=0 error_class=transient error="the playground failed attempt 1 on purpose as transient, because fail_until is 3; attempt 4 is the first that would succeed"
2026-11-03T14:25:59.351+01:00 [info    ] queued                         [step publish] block=playground.generate attempt=2
2026-11-03T14:25:59.372+01:00 [info    ] running                        [step publish] block=playground.generate attempt=2
2026-11-03T14:25:59.387+01:00 [error   ] failed                         [log publish] duration_ms=0 error_class=transient error="the playground failed attempt 2 on purpose as transient, because fail_until is 3; attempt 4 is the first that would succeed"
2026-11-03T14:25:59.383+01:00 [info    ] failed                         [step publish] block=playground.generate attempt=2 duration_ms=11
2026-11-03T14:25:59.383+01:00 [info    ] skipped                        [step note] block=log.write attempt=1
2026-11-03T14:25:59.383+01:00 [info    ] alert 'echo-failed' queued for delivery through 'webhook' [log] event=run_failed notifier=webhook
2026-11-03T14:25:59.383+01:00 [info    ] alert 'echo-failed-log' queued for delivery through 'log' [log] event=run_failed notifier=log
2026-11-03T14:25:59.455+01:00 [error   ] failed                         [run] pipeline=echo-alert run_id=01a1a196-8284-77c1-9e87-d01f14fada9a exit_code=1
steps
┏━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step            ┃ block               ┃ outcome   ┃ after   ┃ duration ┃ output                  ┃
┡━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask             │ playground.generate │ succeeded │ -       │ 0.2s     │ records=[1 items]       │
│                 │                     │           │         │          │ rows=1  seed=1527358980 │
│                 │                     │           │         │          │ locale=en_US  fields={3 │
│                 │                     │           │         │          │ keys}  drift=none       │
│                 │                     │           │         │          │ delay_ms=0  attempt=1   │
│                 │                     │           │         │          │ fail_until=0            │
│                 │                     │           │         │          │ fail_as=transient       │
│                 │                     │           │         │          │ input_rows=1            │
│ publish  1 warn │ playground.generate │ failed    │ ask     │ 0.0s     │ -                       │
│ publish  1 warn │ playground.generate │ failed    │ ask     │ 0.0s     │ -                       │
│ note            │ log.write           │ skipped   │ publish │ -        │ -                       │
└─────────────────┴─────────────────────┴───────────┴─────────┴──────────┴─────────────────────────┘

publish failed  playground.generate, attempt 1, transient
  the playground failed attempt 1 on purpose as transient, because fail_until is 3; attempt 4 is the
first that would succeed
  last log lines:
    error: failed

publish failed  playground.generate, attempt 2, transient
  the playground failed attempt 2 on purpose as transient, because fail_until is 3; attempt 4 is the
first that would succeed
  last log lines:
    error: failed
(exit 1)
```

Two attempts, which is the budget: `fail_until: 3` is above it, so the step runs out of tries
and the run ends `failed`. The failure is classed **transient**, which is the class a budget is
for -- [echo-retry](../echo-retry) is where the other class sits beside it. `note` is
**skipped** rather than failed: it never ran, because the step it waits for did not succeed.
The two `alert ... queued` lines are the document's rules, raised by the throwaway instance.

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
2026-11-03T14:26:37.648+01:00 [info    ] created                        [connection.created] code=echo-sink connection_kind=webhook name="The alert sink" description="The instance's own playground, which answers 200 to whatever is POSTed." config={"url":"http://127.0.0.1:3333/api/v1/playground/request","bearer_token":null,"credential":null,"credential_header":null,"credential_query":null,"credential_scheme":null,"headers":{},"verify_tls":true,"timeout":"15s"}
```

```bash
uv run dg apply
```

```text
create echo-alert  version 1 (/home/you/echo-alert/pipelines/echo-alert.yaml)
```

The apply wrote the pipeline and the two rules its `alerts:` section declares, each scoped to
`echo-alert`. Both templates were compiled at plan, so one that does not compile is refused at
the apply with the line it broke on rather than at the failure it was written for. Neither rule
carries a `throttle`, and none means none: every failed run of `echo-alert` raises its own
notification. On a real instance a `run_failed` rule wants `throttle: 15m`, so a pipeline
failing every minute is one message rather than sixty.

`echo-failed-log` names no connection at all, and a rule with no connection delivers to the
**process log**: the `log` notifier, which needs no credential and is always there. It is the
channel that works on a fresh install, and the one a log shipper already reads. The listing's
`declared by` column names the document each rule came from, and the records say `declared`:

```bash
uv run dg alerts rules list --json | jq -c '.fields | {code, notifier, connection, declared, paused}'
```

```json
{"code":"echo-failed","notifier":"webhook","connection":"echo-sink","declared":true,"paused":false}
{"code":"echo-failed-log","notifier":"log","connection":null,"declared":true,"paused":false}
```

### The document owns its rules

A declared rule changes only by applying its document. Deleting one by hand, or changing what it
says through the API or an MCP tool, is refused with `alert.declared`, naming the pipeline:

```bash
uv run dg alerts rules delete echo-failed
```

```text
2026-11-04T08:17:57.300+01:00 [error   ] alert rule 'echo-failed' is declared by the document of pipeline 'echo-alert': edit its alerts: section and apply it again; pausing and resuming it stay allowed [error] status=409 title=Conflict code=alert.declared params={"code":"'echo-failed'","pipeline":"'echo-alert'"} instance=/api/v1/alert-rules/echo-failed
(exit 1)
```

Pausing is the exception, because it is an operator's choice on the instance rather than
something the rule declares: a paused rule ignores every event until it is resumed, nothing is
queued for it meanwhile, and the next apply leaves it paused:

```bash
uv run dg alerts rules pause echo-failed-log
uv run dg apply
uv run dg alerts rules list --json | jq -c '.fields | {code, declared, paused}'
uv run dg alerts rules resume echo-failed-log
```

```json
{"code":"echo-failed","declared":true,"paused":false}
{"code":"echo-failed-log","declared":true,"paused":true}
```

A changed rule is a changed document, and plan names it. Give `echo-failed` a throttle in a copy
and plan it:

```bash
sed 's/^    connection: echo-sink$/    connection: echo-sink\n    throttle: 15m/' pipelines/echo-alert.yaml > throttled.yaml
uv run dg apply throttled.yaml --dry-run
uv run dg apply throttled.yaml --dry-run --json | jq -c '.fields.plan.diff'
```

```text
update echo-alert  version 2 (throttled.yaml)
  alerts changed: echo-failed

steps of echo-alert  each step under the last one it waits for
  ask  (playground.generate)
    publish  (playground.generate)
      note  (log.write)
Nothing was written: this was a dry run.
```

```json
{"steps_added":[],"steps_removed":[],"steps_changed":[],"params_changed":false,"triggers_changed":false,"requires_changed":false,"report_changed":false,"alerts_added":[],"alerts_removed":[],"alerts_changed":["echo-failed"],"settings_changed":false}
```

`alerts_added`, `alerts_removed` and `alerts_changed` name the rules by code. Applying a version
whose `alerts:` no longer names a rule removes it; a rule created by hand with
`dg alerts rules create`, even one scoped to this pipeline, is never touched by an apply.

### The failure, and what it raises

On the instance this time:

```bash
uv run dg run echo-alert --watch
```

```text
2026-11-03T14:26:50.730+01:00 [info    ] started                        [run] pipeline=echo-alert run_id=01a1a197-502d-7544-978d-7e7a568d6e8a local=false
2026-11-03T14:26:50.676+01:00 [info    ] queued                         [step ask] block=playground.generate attempt=1
2026-11-03T14:26:50.837+01:00 [info    ] running                        [step ask] block=playground.generate attempt=1
2026-11-03T14:26:50.676+01:00 [info    ] queued                         [step publish] block=playground.generate attempt=1
2026-11-03T14:26:50.975+01:00 [info    ] playground generated           [log ask] rows=1 seed=1418202095 locale=en_US drift=none
2026-11-03T14:26:50.979+01:00 [info    ] succeeded                      [step ask] block=playground.generate attempt=1 duration_ms=142
2026-11-03T14:26:50.991+01:00 [info    ] running                        [step publish] block=playground.generate attempt=1
2026-11-03T14:26:51.011+01:00 [info    ] failed                         [step publish] block=playground.generate attempt=1 duration_ms=20
2026-11-03T14:26:51.030+01:00 [error   ] failed                         [log publish] duration_ms=0 error_class=transient error="the playground failed attempt 1 on purpose as transient, because fail_until is 3; attempt 4 is the first that would succeed"
2026-11-03T14:26:51.032+01:00 [info    ] queued                         [step publish] block=playground.generate attempt=2
2026-11-03T14:26:52.564+01:00 [info    ] running                        [step publish] block=playground.generate attempt=2
2026-11-03T14:26:52.573+01:00 [info    ] skipped                        [step note] block=log.write attempt=1
2026-11-03T14:26:52.573+01:00 [info    ] failed                         [step publish] block=playground.generate attempt=2 duration_ms=10
2026-11-03T14:26:52.582+01:00 [error   ] failed                         [log publish] duration_ms=0 error_class=transient error="the playground failed attempt 2 on purpose as transient, because fail_until is 3; attempt 4 is the first that would succeed"
2026-11-03T14:26:52.573+01:00 [info    ] alert 'echo-failed' queued for delivery through 'webhook' [log] event=run_failed notifier=webhook
2026-11-03T14:26:52.573+01:00 [info    ] alert 'echo-failed-log' queued for delivery through 'log' [log] event=run_failed notifier=log
2026-11-03T14:26:52.719+01:00 [error   ] failed                         [run] pipeline=echo-alert run_id=01a1a197-502d-7544-978d-7e7a568d6e8a pipeline_version=1 triggered_by="admin (token dev)" duration_ms=1737 items_total=0 items_failed=0 exit_code=1 priority=normal
run 01a1a197-502d-7544-978d-7e7a568d6e8a
pipeline      echo-alert (version 1)
status        failed
triggered by  admin (token dev)
duration      1.7s
items         -

steps
┏━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━┓
┃ step            ┃ block           ┃ outcome   ┃ after   ┃ attempts ┃ duration ┃ error            ┃
┡━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━┩
│ ask             │ playground.gen… │ succeeded │ -       │ 1        │ 0.1s     │ -                │
│ publish  2 warn │ playground.gen… │ failed    │ ask     │ 1        │ 0.0s     │ the playground   │
│                 │                 │           │         │          │          │ failed attempt 1 │
│                 │                 │           │         │          │          │ on purpose as    │
│                 │                 │           │         │          │          │ transient,       │
│                 │                 │           │         │          │          │ because          │
│                 │                 │           │         │          │          │ fail_until is 3; │
│                 │                 │           │         │          │          │ attempt 4 is the │
│                 │                 │           │         │          │          │ first that would │
│                 │                 │           │         │          │          │ succeed          │
│ publish  2 warn │ playground.gen… │ failed    │ ask     │ 2        │ 0.0s     │ the playground   │
│                 │                 │           │         │          │          │ failed attempt 2 │
│                 │                 │           │         │          │          │ on purpose as    │
│                 │                 │           │         │          │          │ transient,       │
│                 │                 │           │         │          │          │ because          │
│                 │                 │           │         │          │          │ fail_until is 3; │
│                 │                 │           │         │          │          │ attempt 4 is the │
│                 │                 │           │         │          │          │ first that would │
│                 │                 │           │         │          │          │ succeed          │
│ note            │ log.write       │ skipped   │ publish │ 1        │ -        │ -                │
└─────────────────┴─────────────────┴───────────┴─────────┴──────────┴──────────┴──────────────────┘

outputs
┏━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step ┃ output                                                                                    ┃
┡━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask  │ records=[1 items]  rows=1  seed=1418202095  locale=en_US  fields={3 keys}  drift=none     │
│      │ delay_ms=0  attempt=1  fail_until=0  fail_as=transient  input_rows=1                      │
└──────┴───────────────────────────────────────────────────────────────────────────────────────────┘

publish failed  playground.generate, attempt 1, transient
  the playground failed attempt 1 on purpose as transient, because fail_until is 3; attempt 4 is the
first that would succeed
  last log lines:
    error: failed
    error: failed

publish failed  playground.generate, attempt 2, transient
  the playground failed attempt 2 on purpose as transient, because fail_until is 3; attempt 4 is the
first that would succeed
  last log lines:
    error: failed
    error: failed
```

The lines worth finding in that stream are the two `alert ... queued for delivery` ones, one per
rule. Queued, not sent: a notification goes on a queue, is leased by a worker and is delivered
from there, so an alert never runs inside the transaction that settles the run. The queue says
how each went afterwards:

```bash
uv run dg alerts queue
```

```text
notifications
┏━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━┳━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━┓
┃ subject               ┃ notifier ┃ status ┃ tries ┃ sent                ┃ error ┃
┡━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━╇━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━┩
│ echo-alert run failed │ log      │ sent   │ 1     │ 2026-11-03 14:26:52 │ -     │
│ echo-alert run failed │ webhook  │ sent   │ 1     │ 2026-11-03 14:26:52 │ -     │
└───────────────────────┴──────────┴────────┴───────┴─────────────────────┴───────┘
```

`echo-alert run failed` is the webhook rule's subject template, rendered; the log rule has no
template of its own and says the same by default. **sent** on the first try means the POST
answered, or the line was written, and each record says which rule, notifier and connection
carried it:

```bash
uv run dg alerts queue --json | jq '.fields | {rule, notifier, connection, status, attempt, run_pipeline}'
```

```json
{
  "rule": "echo-failed-log",
  "notifier": "log",
  "connection": null,
  "status": "sent",
  "attempt": 1,
  "run_pipeline": "echo-alert"
}
{
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
  "credential": null,
  "credential_header": null,
  "credential_query": null,
  "credential_scheme": null,
  "headers": {},
  "verify_tls": true,
  "timeout": "15s"
}
```

That is the webhook delivery, end to end: the run failed, the rule fired, the webhook notifier
POSTed the alert as JSON, and the instance's own playground took it. Every field the notifier
declares secret -- `bearer_token` and `credential` here -- is encrypted at rest and comes back
redacted from every read; this connection has none set, so they read as null.

`dg alerts queue` is the one place a notifier that has quietly stopped delivering is visible,
because the thing that would otherwise tell you is the notifier. `dg alerts test --connection
echo-sink` sends one message through the same queue, which is the only way to prove an endpoint
accepts an alert -- `dg connection check` sends a HEAD and proves only that it is reachable.
Deleting a rule keeps what it already sent: each delivery names its rule by code, so the queue
still says what went out after the rule is gone.

### The log rule's line

The `log` notifier writes one structured line per alert, at `warning`, under the `dirigent.alert`
logger. The terminal running `dg dev` shows it as it happens, and `dg dev` also keeps its whole
log as NDJSON in `.dirigent/state/dev.log`, whatever the terminal is, so the line can be read
back after the fact:

```bash
grep '"logger": "dirigent.alert"' .dirigent/state/dev.log | uv run dg format
```

```text
2026-11-03T14:26:52.658+01:00 [warning ] echo-alert failed at publish   [log dirigent.alert] event_kind=run_failed run_id=01a1a197-502d-7544-978d-7e7a568d6e8a pipeline=echo-alert status=failed failing_step=publish error="the playground failed attempt 1 on purpose as transient, because fail_until is 3; attempt 4 is the first that would succeed" error_code=playground.failed_on_purpose trigger="admin (token dev)" duration_ms=1737
```

The message says what happened in a few words, and the facts are fields rather than a rendered
body: which step failed, what it failed with and under which code, and who started the run. A
log shipper or an `jq` filter selects on `failing_step` and `error_code` without parsing
English:

```bash
grep '"logger": "dirigent.alert"' .dirigent/state/dev.log | jq '{event, failing_step, error, error_code, trigger}'
```

```json
{
  "event": "echo-alert failed at publish",
  "failing_step": "publish",
  "error": "the playground failed attempt 1 on purpose as transient, because fail_until is 3; attempt 4 is the first that would succeed",
  "error_code": "playground.failed_on_purpose",
  "trigger": "admin (token dev)"
}
```

`.dirigent/state/` is not in the repository, so the file is never committed, and `dg dev
--wipe-state` clears it with everything else.

### How the pipeline has been doing

An alert is about one run. The **runs summary** is about all of them: one row per pipeline that
ran in a window, with the newest run's state, a count per state, the recent runs as a strip, and
the median duration. Run the same document green once, so there is more than one state to count:

```bash
uv run dg run echo-alert -p fail_until=0 --watch
uv run dg runs summary --since 1h
```

```text
2026-11-03T14:27:09.180+01:00 [info    ] 1 pipelines ran                [runs.summary] window_start=2026-11-03T12:27:09.175058+00:00 window_end=2026-11-03T13:27:09.175058+00:00
runs per pipeline
┏━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━┓
┃ pipeline   ┃ latest    ┃ runs                  ┃ recent ┃ last ran            ┃ median ┃
┡━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━┩
│ echo-alert │ succeeded │ 1 failed, 1 succeeded │ ●●     │ 2026-11-03 14:27:06 │ 0.1s   │
└────────────┴───────────┴───────────────────────┴────────┴─────────────────────┴────────┘
```

The table is a rendering of one `runs.summary` record, which carries every pipeline under
`pipelines`:

```bash
uv run dg runs summary --since 1h --json \
  | jq '.pipelines[0] | {pipeline, latest: .latest.status, counts, recent: [.recent[].status], median_duration_ms}'
```

```json
{
  "pipeline": "echo-alert",
  "latest": "succeeded",
  "counts": {
    "failed": 1,
    "succeeded": 1
  },
  "recent": [
    "failed",
    "succeeded"
  ],
  "median_duration_ms": 90
}
```

`--latest failed` narrows it to the pipelines whose newest run failed, which is the question a
morning starts with. The Runs screen's *By pipeline* view is the same answer, at
`/runs?group=pipeline&window=24h`.

### Who changed what

Every administrative change this walkthrough made -- the connection, the pipeline and the two
rules its apply created, the pause and the resume -- is a row in the instance's **audit
trail**, written in the same transaction as the change. It names who acted and through which
token, never a value:

```bash
uv run dg audit --since 1h
```

```text
2026-11-04T08:18:02.470+01:00 [info    ] resumed                        [audit] subject_kind=alert_rule subject=echo-failed-log actor="admin (token dev)"
2026-11-04T08:17:58.554+01:00 [info    ] paused                         [audit] subject_kind=alert_rule subject=echo-failed-log actor="admin (token dev)"
2026-11-04T08:17:54.700+01:00 [info    ] created                        [audit] subject_kind=pipeline subject=echo-alert actor="admin (token dev)"
2026-11-04T08:17:54.699+01:00 [info    ] created                        [audit] subject_kind=alert_rule subject=echo-failed-log actor="admin (token dev)"
2026-11-04T08:17:54.698+01:00 [info    ] created                        [audit] subject_kind=alert_rule subject=echo-failed actor="admin (token dev)"
2026-11-04T08:17:53.250+01:00 [info    ] created                        [audit] subject_kind=connection subject=echo-sink actor="admin (token dev)"
2026-11-04T08:17:49.816+01:00 [info    ] created                        [audit] subject_kind=token subject=admin/dev actor="dg dev"
2026-11-04T08:17:49.813+01:00 [info    ] created                        [audit] subject_kind=user subject=admin actor="dg dev"
```

Newest first. The rules were created by the apply, so they name the account that applied. The
bottom two are `dg dev` seeding its own admin and that admin's token on the empty state; a change no account made is named by the host command that made it. Each line is
an `audit` record with the row under `fields`, and `--kind`, `--subject`, `--actor` and
`--action` narrow it:

```bash
uv run dg audit --since 1h --kind connection --json \
  | jq '.fields | {action, subject_kind, subject_code, actor_label, fields}'
```

```json
{
  "action": "created",
  "subject_kind": "connection",
  "subject_code": "echo-sink",
  "actor_label": "admin (token dev)",
  "fields": []
}
```

`fields` is empty for a create; an update lists the names of the fields it changed, and still
never their values, so a rotated secret is visible as having changed without being readable
here. The audit trail is an admin's read, and the Audit screen under Admin in the UI is the same
rows.

## The document, hop by hop

`pipelines/echo-alert.yaml` opens by saying where each half lives:

```yaml
# A run that fails on purpose, so there is something for an alert rule to be about.
#
# In:  one station's reading.
# Out: nothing. The step that would publish it fails every attempt and the run ends failed.
#
# NOTHING HERE IS CALLED. playground.generate takes an `input` and hands it back, and its
# `fail_until` knob fails that many attempts before succeeding -- so a failure on cue is a
# number in this document rather than an endpoint somewhere that has to be answering. No
# step names a connection or a URL, and nothing needs a network.
#
# The alerting half is in this document too, under `alerts:` at the bottom: two rules on
# run_failed, keyed by their codes like steps. A rule binds an event to a notifier, and a
# notifier delivers through a connection, which is a record the INSTANCE holds, minted once
# with `dg connection create`: a connection carries a credential, and a portable document
# never does. So a rule names its connection by code, and `dg apply` refuses one the instance
# does not hold. The document owns its rules: an apply creates, rewrites and removes them, and
# changing or deleting one by hand is refused with alert.declared. Pausing one stays an
# operator's choice on the instance, and the next apply keeps it.
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
#   echo-failed      the failure, POSTed through the webhook connection echo-sink.
#   echo-failed-log  the same failure, written to the process log: no connection at all.
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

  The rules are the document's, under `alerts:`; the connection one delivers through is the
  instance's, named by its code.

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
    # Two attempts allowed, and a transient failure spends both.
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

**`alerts:`** is the pipeline's own rules, keyed by rule code like steps, and each takes what a
pipeline-scoped rule takes through the API: `event`, `connection`, `template`, `body`,
`importance`, `throttle`, `active`, `name` and `description`. There is no scope to write,
because a declared rule always watches the pipeline whose document declares it:

```yaml
# The pipeline's own alert rules, keyed by rule code. Each watches this pipeline alone, so
# there is no scope to write. Neither carries a throttle, which means none: every failed run
# raises its own notification. On a real instance a run_failed rule wants `throttle: 15m`, so
# a pipeline failing every minute is one message rather than sixty.
alerts:
  echo-failed:
    name: Echo failures to the sink
    event: run_failed
    # Where it is delivered is the connection's url, on the instance: here its own playground.
    connection: echo-sink
    # Both templates are compiled at plan, so one that does not compile is refused at apply
    # rather than at the failure it was written for.
    template: "{{ pipeline.code }} run {{ run.status }}"
    body: "Run {{ run.id }} of {{ pipeline.code }} (version {{ pipeline.version }}) ended {{ run.status }} in {{ run.duration_ms | duration }}."

  echo-failed-log:
    name: Echo failures to the log
    # No connection: the log notifier, which needs no credential and is always there.
    event: run_failed
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
