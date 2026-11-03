# echo-schedule

Everything so far has been started by somebody typing a command. Two things start a run
without anybody there: a **clock**, and a **POST**. Each is declared in a document, so the
steps and what starts them are versioned together and `dg apply` materialises both: the
schedule in `pipelines/echo-schedule.yaml`, and the endpoint in `pipelines/echo-endpoint.yaml`.
They are two documents because a pipeline that starts at a source carries no schedule. What
the documents deliberately do not carry is the operational half: whether a schedule is paused,
when it last fired, what the endpoint's token is, and every input it has taken. That lives on
the instance, because none of it belongs in git. This example carries one of each and proves
both fire.

## Run it

Neither pipeline needs its trigger, so start without a server:

```bash
uv sync
uv run dg validate pipelines/
uv run dg run --local pipelines/echo-schedule.yaml
uv run dg run --local pipelines/echo-endpoint.yaml
```

The endpoint's local run enters with the `sample` its source carries, because nothing called
it. A schedule and an endpoint only exist on an instance, so the rest needs one. In a second
terminal, in this directory:

```bash
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
uv run dg apply
uv run dg schedule list echo-schedule
uv run dg source list --json | jq '.fields | {pipeline, code, state, url_path, auth}'
```

The clock fires within the minute. Watch for it, then POST the endpoint yourself:

```bash
uv run dg runs list --pipeline echo-schedule

token="$(uv run dg source rotate-token echo-endpoint upstream --json | jq -r .token)"
curl -s -X POST http://127.0.0.1:3333/endpoints/readings \
    -H "authorization: Bearer $token" -H 'content-type: application/json' \
    -d '{"station": {"code": "tromso-langnes", "reading": "-6.8"}, "sender": "ignored"}' | jq
```

`./verify.sh` does all of that unattended: it starts a `dg dev` on a free port of its own,
mints its token with `dg auth login --username admin --password admin`, waits for a
scheduled run to land, POSTs the endpoint, asserts on the records both produced, and stops the
instance it started by pid.

## This one needs no network

The read is a node, not a call. `playground.generate` takes an `input` and hands it back, so
`echo-schedule` reaches nothing: no connection, no URL, no network, and `echo-endpoint` reaches
nothing either, since its input is the request. That matters more here than anywhere else,
because a schedule cannot be handed anything after it was applied -- its parameters are pinned
in the document, so a document with an address in it is a document whose scheduled runs are
stuck with the address it was written with. Replacing `ask` with an `http.request` whose answer
`record` reads changes that one step and nothing under it.

`OFFLINE.md` at the root of this repository is the rest of the story, including the `UV_OFFLINE=1` that
keeps `uv` off the network too.

## What you see

*Printed as it printed, with this project's directory written as `/home/you/echo-schedule`.*

Both documents are valid offline, with no server and no network. The endpoint's, for one:

```bash
uv run dg validate pipelines/echo-endpoint.yaml
```

```text
2026-11-01T13:52:36.282+01:00 [info    ] valid                          [validation] code=echo-endpoint document=pipelines/echo-endpoint.yaml checked="document and installed blocks"
  each step under the last one it waits for
    upstream  (endpoint)
      record  (transform.jq)
2026-11-01T13:52:36.359+01:00 [info    ] valid                          [validated] documents=1 invalid=0 skipped=0
```

Applying stores both documents and materialises what they declared -- one clock, one endpoint.
The endpoint's token is in the apply's answer, and only there:

```bash
uv run dg apply
```

```text
create echo-endpoint  version 1 (/home/you/echo-schedule/pipelines/echo-endpoint.yaml)
create echo-schedule  version 1 (/home/you/echo-schedule/pipelines/echo-schedule.yaml)

  source upstream  http://127.0.0.1:3333/endpoints/readings
  Authorization: Bearer Veld2ddzpsID5XtfFROyH7_kU5d58e9FeX_8KGSl6gQ

Each token and signing secret is shown once.
```

```bash
uv run dg schedule list echo-schedule
```

```text
schedules of echo-schedule
┏━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━┳━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━┓
┃ code         ┃ name         ┃ clock ┃ timezone ┃ paused ┃ next firing       ┃ last fired         ┃
┡━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━╇━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━┩
│ every-minute │ Every minute │ 1m    │ UTC      │ no     │ 2026-11-01        │ 2026-11-01         │
│              │              │       │          │        │ 13:44:58          │ 13:44:00           │
└──────────────┴──────────────┴───────┴──────────┴────────┴───────────────────┴────────────────────┘
```

```bash
uv run dg source list --json | jq '.fields | {pipeline, code, kind, state, url_path, auth, accepted, failed, refused}'
```

```json
{
  "pipeline": "echo-endpoint",
  "code": "upstream",
  "kind": "endpoint",
  "state": "listening",
  "url_path": "/endpoints/readings",
  "auth": "token",
  "accepted": 1,
  "failed": 0,
  "refused": 0
}
```

Three counts, one per way a call can end. `accepted` is a call that started a run and was not
answered with that run's failure; `failed` is one whose caller was held for the run and got its
failure back; `refused` is one turned away before any run, a missing or wrong token included,
and a refused call is in the source's journal too, without its headers or body.

`next firing`, `last fired` and what the source has accepted are instance state, which is
exactly why they are not in the documents. A source's row carries a prefix of its token and
never the token: an instance hands one back once, when it is minted.

A minute later, with nobody typing anything:

```bash
uv run dg runs list --pipeline echo-schedule
```

```text
runs
┏━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━┓
┃ run             ┃ pipeline      ┃ status    ┃ triggered by    ┃ started         ┃ finished       ┃
┡━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━┩
│ 01a19723-5edf-… │ echo-schedule │ succeeded │ schedule        │ 2026-11-01      │ 2026-11-01     │
│                 │               │           │ every-minute    │ 13:44:00        │ 13:44:00       │
└─────────────────┴───────────────┴───────────┴─────────────────┴─────────────────┴────────────────┘
```

Then the other way in. There is no command that reads an existing source token back, so a
script that has to POST rotates it and uses what the rotation returns:

```bash
token="$(uv run dg source rotate-token echo-endpoint upstream --json | jq -r .token)"
curl -s -X POST http://127.0.0.1:3333/endpoints/readings \
    -H "authorization: Bearer $token" -H 'content-type: application/json' \
    -d '{"station": {"code": "tromso-langnes", "reading": "-6.8"}, "sender": "ignored"}' | jq
```

```json
{
  "run_id": "01a1972b-c70d-7482-a055-55bf60b98634",
  "status": "queued",
  "run_url": "/api/v1/runs/01a1972b-c70d-7482-a055-55bf60b98634"
}
```

No reply step follows the source, so the caller is answered 202 at once with where to read the
run. A POST without the token never makes one:

```json
{"status":401,"title":"Unauthorized","detail":"this endpoint takes the bearer token minted for it, in an Authorization header","code":"source.token_refused","params":{},"problems":[],"instance":"/endpoints/readings"}
```

`uv run dg source call echo-endpoint upstream --source-token "$token" --body '...'` makes the
same call and writes down what it answered. The run the POST started sits in the list with
what started it:

```bash
uv run dg runs list --pipeline echo-endpoint
```

```text
runs
┏━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━┓
┃ run             ┃ pipeline      ┃ status    ┃ triggered by    ┃ started         ┃ finished       ┃
┡━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━┩
│ 01a19723-0372-… │ echo-endpoint │ succeeded │ source upstream │ 2026-11-01      │ 2026-11-01     │
│                 │               │           │                 │ 13:43:36        │ 13:43:36       │
└─────────────────┴───────────────┴───────────┴─────────────────┴─────────────────┴────────────────┘
```

```bash
uv run dg runs show 01a19723-0372-70ca-9b66-ab833fbb2db2 --json \
  | jq '.fields.attempts[] | select(.step_name == "record") | .output'
```

```json
{
  "value": {
    "station": "tromso-langnes",
    "reading": "-6.8",
    "run": "01a19723-0372-70ca-9b66-ab833fbb2db2"
  }
}
```

Two fields out of a body that carried three things: `sender` is in no path `record` names, so
nothing after the source sees it.

## The clock, hop by hop

`pipelines/echo-schedule.yaml` opens with what travels with the document and what does not:

```yaml
# The thing that starts a run without anybody typing a command: a clock.
#
# In:  a station and its reading, from a parameter or a schedule.
# Out: the reading, with the run it arrived in beside it.
#
# THE READ IS A NODE, NOT A CALL. playground.generate takes an `input` and hands it back, so
# this document reaches nothing: no connection, no URL, no network. That matters more here
# than anywhere else, because a schedule cannot be handed anything after it was applied -- its
# parameters are pinned in this document, so a document with an address in it is a document
# whose scheduled runs are stuck with the address it was written with.
#
# The schedule travels with the document, so one file is one deployable unit and `dg apply`
# materialises the clock. What stays behind on the instance is the operational half --
# whether the schedule is paused and when it last fired -- and none of that belongs in git,
# so none of it is here.
#
# The other way a run starts unattended, a POST, is pipelines/echo-endpoint.yaml: a pipeline
# that starts at a source carries no schedule, so the two are two documents.
#
# A schedule only fires on an instance this document has been applied to. The pipeline runs
# anywhere: `dg run --local` needs none.
#
# Hop by hop:
#
#   ask     the reading for this run's station, as the node's one record.
#   record  that record, with the run's own id beside it, so a run says out loud what it
#           was asked for.
#
# EXPECT THIS RUN TO SUCCEED in under a second, whether the clock or a person started it.
#
#   uv run dg run --local pipelines/echo-schedule.yaml
#   uv run dg apply && uv run dg run echo-schedule --watch -p station=oslo-blindern
```

The lines every document opens with, and the two parameters the schedule pins:

```yaml
format: dirigent/v1
kind: pipeline
code: echo-schedule
name: Started by a clock
description: |
  One reading on a rolling one-minute schedule, which pins its own parameters over the
  pipeline's defaults.

  The document declares the schedule; the instance holds the pause flag and the history.

tags: [triggers, playground, transform, schedule]

requires:
  blocks:
    - playground.generate
    - transform.jq

params:
  type: object
  properties:
    station:
      type: string
      default: bergen-florida
      minLength: 1
      description: The station the reading is for.
    reading:
      type: string
      default: "12.4"
      description: The reading reported for it.
```

**`ask`** and **`record`** are the pipeline, and they are deliberately small -- the triggers
are what this example is about:

```yaml
steps:
  ask:
    block: playground.generate
    config:
      # No fields: are named, so the input travels through untouched and becomes this run's
      # one record.
      input:
        station: ${params.station}
        reading: ${params.reading}

  record:
    block: transform.jq
    depends_on: [ask]
    config:
      input:
        reported: ${steps.ask.output.records.0}
        # run exposes exactly four names -- run.id, run.scratch, run.window.start and
        # run.window.end -- and what started the run is not one of them. Which trigger
        # fired is the instance's fact about the run, read back with `dg runs list`, not
        # something a step can reach for.
        run: ${run.id}
      program: |
        {station: .reported.station, reading: .reported.reading, run: .run}
```

**The clock.** An interval is a cadence with no calendar moment behind it; a cron is the other
clock, for the nightly load somebody downstream is waiting for. The schedule pins its own
parameters over the pipeline's defaults, which is why nightly against production and hourly
against staging is two schedules on one pipeline rather than two pipelines:

```yaml
triggers:
  schedules:
    # An interval is a cadence: every minute from whenever it was declared, with no
    # calendar moment anybody downstream is waiting for. A cron is the other clock, for
    # "at 05:00 Oslo" -- write each as what it is and neither has to fake the other.
    #
    # A duration is the same length in every zone, so an interval never consults the
    # calendar and the zone here is read by nothing. cron and at are the clocks that need
    # one.
    - code: every-minute
      name: Every minute
      description: A cadence fast enough to watch, which is the only reason it is a minute.
      interval: 1m
      timezone: UTC
      # Parameters pinned here override the pipeline's defaults for this schedule's firings
      # only, which is what makes a second schedule a schedule rather than a second
      # pipeline.
      params:
        station: oslo-blindern
        reading: "3.1"
```

A schedule you no longer want firing is paused on the instance rather than deleted from the
document: `dg schedule pause echo-schedule every-minute` holds it, and applying the document
again does not let it go.

## The endpoint, hop by hop

`pipelines/echo-endpoint.yaml` starts at a source rather than a parameter:

```yaml
# The other thing that starts a run without anybody typing a command: a POST.
#
# In:  a POST to /endpoints/readings, whose JSON body carries a station and its reading.
# Out: the reading, with the run it arrived in beside it.
#
# THE FIRST STEP IS A SOURCE. `upstream` is where an input enters: an endpoint the instance
# answers at /endpoints/readings once this document is applied. A run it starts begins with
# `upstream` already settled, its output the request -- method, path, query, headers and body
# -- and every step after it reads that output like any upstream step's.
#
# The source travels with the document, so `dg apply` opens the route and mints its token.
# What stays behind on the instance is the operational half -- the token, whether the source
# is paused, and every input it took or refused -- and none of that belongs in git, so none of
# it is here.
#
# A pipeline that starts at a source carries no schedule, so the clock is
# pipelines/echo-schedule.yaml.
#
# Hop by hop:
#
#   upstream  the request, as it arrived: a POST with a JSON body of at most 4KB, from a caller
#             holding the token the apply minted.
#   record    the two fields the body names under `station`, with the run's own id beside them.
#             Nothing else the body carries reaches a step, and a body without a station code
#             fails this step.
#
# A source with no instance runs by hand: with no --input, the run enters with the `sample`.
#
# EXPECT THIS RUN TO SUCCEED in under a second, whether a POST or a person started it.
#
#   uv run dg run --local pipelines/echo-endpoint.yaml
#   uv run dg run --local pipelines/echo-endpoint.yaml \
#       --input '{body: {station: {code: bergen-florida, reading: "12.4"}}}'
#   uv run dg apply && uv run dg source call echo-endpoint upstream --source-token "$TOKEN" \
#       --body '{"station": {"code": "tromso-langnes", "reading": "-6.8"}}'
```

It has no `params`: what a run is about arrives in the request, and a step reads it there.

```yaml
format: dirigent/v1
kind: pipeline
code: echo-endpoint
name: Started by a POST
description: |
  One reading, taken from the body of a POST to an endpoint source. Only the fields a step
  names reach it.

  The document declares the endpoint; the instance holds the token, the pause flag and every
  input it took.

tags: [triggers, sources, transform]

requires:
  blocks:
    - transform.jq
```

**`upstream`** is the source and **`record`** the one step after it. A run the POST started
begins with `upstream` settled, its output the request; `record` names the two fields it
wants by path, so nothing else the body carries goes further, and a body without a station
code fails the step rather than recording nothing:

```yaml
steps:
  upstream:
    source:
      kind: endpoint
      path: /readings
      methods: [POST]
      max_body: 4KB
    # What a hand run enters with when it is given no --input, in the shape of the source's
    # output. The endpoint kind fills in the method, the path and the body's type and size.
    sample:
      body:
        station: {code: bergen-florida, reading: "12.4"}
        sender: ignored

  record:
    block: transform.jq
    depends_on: [upstream]
    config:
      input:
        reported: ${steps.upstream.output.body}
        # run exposes exactly four names -- run.id, run.scratch, run.window.start and
        # run.window.end -- and what started the run is not one of them. Which source
        # started it is the instance's fact about the run, read back with `dg runs list`.
        run: ${run.id}
      # One path per field: `sender`, or anything else a caller adds, goes no further.
      program: |
        if (.reported.station.code | type) != "string" or .reported.station.code == ""
        then error("the body names no station.code")
        else {station: .reported.station.code, reading: .reported.station.reading, run: .run}
        end
```

The endpoint takes `Authorization: Bearer` with the token its apply minted unless the source
says otherwise: `auth: {kind: hmac}` takes a signed body instead, and `auth: {kind: public}`
takes anything. A source you no longer want taking input is paused on the instance:
`dg source pause echo-endpoint upstream` answers every caller 503 and keeps the token.

## Where to go next

- [`echo-alert`](../echo-alert/README.md) is the half this one implies. A pipeline that
  fires at three in the morning is a pipeline nobody is watching, so the instance has to be
  the one that notices when it fails.
- [**The basics**](https://winterop-com.github.io/dirigent/basics/) is the tutorial these
  examples follow: one read, a schema gate on the answer, and a send built from the value
  that passed.
- [**The examples**](../README.md): every example in order, and what you need once.
