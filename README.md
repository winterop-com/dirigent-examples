# echo-schedule

Everything so far has been started by somebody typing a command. Two things start a run
without anybody there: a **clock**, and a **POST**. Both are declared in the document, so one
file stays one deployable unit -- the steps, the cadence and the hook are versioned together
and `dg apply` materialises all three. What the document deliberately does not carry is the
operational half: whether a schedule is paused, when it last fired, what the hook's token is,
and every delivery it has taken. That lives on the instance, because none of it belongs in
git. This example carries one of each and proves both fire.

## Run it

The pipeline needs neither trigger, so start without a server:

```bash
uv sync
uv run dg validate pipelines/echo-schedule.yaml
uv run dg run --local pipelines/echo-schedule.yaml
```

A trigger only exists on an instance, so the rest needs one. In a second terminal, in this
directory:

```bash
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
uv run dg apply
uv run dg schedule list echo-schedule
uv run dg webhook list echo-schedule
```

The clock fires within the minute. Watch for it, then POST the hook yourself:

```bash
uv run dg runs list --pipeline echo-schedule

hook="$(uv run dg webhook rotate-token echo-schedule upstream-reading --json | jq -r .url)"
curl -s -X POST "$hook" -H 'content-type: application/json' \
    -d '{"station": {"code": "tromso-langnes", "reading": "-6.8"}, "sender": "ignored"}' | jq
```

`./verify.sh` does all of that unattended: it starts a `dg dev` on a free port of its own,
mints its token with `dg auth login --username dev --password dirigent-dev`, waits for a
scheduled run to land, POSTs the hook, asserts on the records both produced, and stops the
instance it started by pid.

## Offline

Postman Echo is the one thing here that needs the network, and `local-echo` beside this
repository is the same service in one file of Python. Start it in another terminal:

```bash
python3 ../local-echo/echo_server.py
```

It listens on `http://127.0.0.1:8080`, and the document already carries the parameter that
points at it, on a local run and on an instance alike:

```bash
uv run dg run --local pipelines/echo-schedule.yaml -p base_url=http://127.0.0.1:8080
uv run dg run echo-schedule --watch -p base_url=http://127.0.0.1:8080
```

```text
2026-09-17T15:50:42.073+02:00 [info    ] http call                      [log ask] method=GET url=http://127.0.0.1:8080/get status=200 bytes=288 duration_ms=28
```

A trigger is where that stops, and it is worth knowing why: a schedule's parameters are
pinned in the document and a webhook's come out of the payload it is POSTed, so neither can
be handed a port chosen after the document was applied. A run the clock starts reads
`base_url`'s default and goes to the real service. That is the same fact the rest of this
page is about -- what travels with the document and what does not -- seen from the other
side.

So `./verify.sh` asserts of a triggered run what a trigger decides: that it fired, what
started it, and the parameters it was given. `VERIFY_OFFLINE=1 ./verify.sh` leaves the online
leg out and holds the two triggered runs to exactly that, and every run it starts itself goes
to the local echo. `OFFLINE.md` beside this repository is the rest of the story, including
the `UV_OFFLINE=1` that keeps `uv` off the network too.

## What you see

The document is valid offline, with no server and no network:

```text
$ uv run dg validate pipelines/echo-schedule.yaml
2026-09-17T15:15:25.123+02:00 [info    ] valid                          [validation] code=echo-schedule document=pipelines/echo-schedule.yaml checked="document, offline"
  each step under the last one it waits for
    ask  (http.request)
      record  (transform.jq)
2026-09-17T15:15:25.126+02:00 [info    ] valid                          [validated] documents=1 invalid=0
```

Applying it stores the document and materialises what it declared -- one clock, one hook:

```text
$ uv run dg apply
create echo-schedule  version 1 
(/home/you/echo-schedule/pipelines/echo-schedule.yaml)

$ uv run dg schedule list echo-schedule
schedules of echo-schedule                                                                    
┏━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━┓
┃ code         ┃ name         ┃ clock ┃ timezone ┃ paused ┃ next firing         ┃ last fired ┃
┡━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━┩
│ every-minute │ Every minute │ 1m    │ UTC      │ no     │ 2026-09-17 15:50:04 │ -          │
└──────────────┴──────────────┴───────┴──────────┴────────┴─────────────────────┴────────────┘

$ uv run dg webhook list echo-schedule
webhooks of echo-schedule                                                                         
┏━━━━━━━━━━━━┳━━━━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━┳━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━┳━━━━━━━━━━━━┓
┃            ┃             ┃            ┃        ┃        ┃           ┃             ┃ last       ┃
┃ code       ┃ name        ┃ token      ┃ signed ┃ active ┃ limit/min ┃ maps        ┃ delivery   ┃
┡━━━━━━━━━━━━╇━━━━━━━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━╇━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━╇━━━━━━━━━━━━┩
│ upstream-… │ Upstream    │ jmXBMdEy.… │ no     │ yes    │ 60        │ reading,    │ -          │
│            │ reading     │            │        │        │           │ station     │            │
└────────────┴─────────────┴────────────┴────────┴────────┴───────────┴─────────────┴────────────┘
```

`next firing` and `last fired` are instance state, which is exactly why they are not in the
document. The hook's row shows a prefix of its token and never the token: an instance hands
one back once, when it is minted.

A minute later, with nobody typing anything:

```text
$ uv run dg runs list --pipeline echo-schedule
runs                                                                                              
┏━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━┓
┃ run            ┃ pipeline      ┃ status    ┃ triggered by   ┃ started         ┃ finished       ┃
┡━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━┩
│ 01a0afa1-b827… │ echo-schedule │ succeeded │ schedule       │ 2026-09-17      │ 2026-09-17     │
│                │               │           │ every-minute   │ 15:50:06        │ 15:50:07       │
└────────────────┴───────────────┴───────────┴────────────────┴─────────────────┴────────────────┘
```

Then the other trigger. There is no command that reads an existing hook token back, so a
script that has to POST rotates it and uses what the rotation returns:

```text
$ hook="$(uv run dg webhook rotate-token echo-schedule upstream-reading --json | jq -r .url)"
$ curl -s -X POST "$hook" -H 'content-type: application/json' \
    -d '{"station": {"code": "tromso-langnes", "reading": "-6.8"}, "sender": "ignored"}' | jq
{
  "run_id": "01a0afa1-f69c-7643-ae3d-a08b9b7c878b",
  "outcome": "accepted",
  "detail": null
}
```

The POST answers with the run it created, and the two runs sit side by side with what started
each one:

```text
$ uv run dg runs list --pipeline echo-schedule
runs                                                                                              
┏━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━┓
┃ run            ┃ pipeline      ┃ status    ┃ triggered by   ┃ started         ┃ finished       ┃
┡━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━┩
│ 01a0afa1-f69c… │ echo-schedule │ succeeded │ webhook        │ 2026-09-17      │ 2026-09-17     │
│                │               │           │ upstream-read… │ 15:50:22        │ 15:50:23       │
│ 01a0afa1-b827… │ echo-schedule │ succeeded │ schedule       │ 2026-09-17      │ 2026-09-17     │
│                │               │           │ every-minute   │ 15:50:06        │ 15:50:07       │
└────────────────┴───────────────┴───────────┴────────────────┴─────────────────┴────────────────┘

$ uv run dg runs show 01a0afa1-f69c-7643-ae3d-a08b9b7c878b --json | jq '.fields.run.params'
{
  "station": "tromso-langnes",
  "reading": "-6.8",
  "base_url": "https://postman-echo.com"
}
```

Two parameters out of a payload that carried three things: `sender` is not in the mapping, so
nothing reached it. The third is `base_url`, which the payload never mentioned and the mapping
does not name -- a run records every parameter it ran with, and one nobody set is its default.

## The document, hop by hop

`pipelines/echo-schedule.yaml` opens with what travels with the document and what does not:

```yaml
# The two things that start a run without anybody typing a command: a clock, and a POST.
#
# In:  a station and its reading, from a parameter, a schedule, or a webhook's payload.
# Out: the reading as Postman Echo answered it back.
#
# Both triggers travel with the document, so one file is one deployable unit and `dg apply`
# materialises the clock and mints the hook's token. What stays behind on the instance is
# the operational half -- whether a schedule is paused, when it last fired, what the token
# is, and every delivery a hook took -- and none of that belongs in git, so none of it is
# here.
#
# A trigger only fires on an instance this document has been applied to. The pipeline runs
# anywhere: `dg run --local` needs neither.
#
# Hop by hop:
#
#   ask     one GET, with the station and the reading as query arguments.
#   record  the arguments as the service handed them back, with the trigger's own label
#           beside them, so a run says out loud what started it.
#
# EXPECT THIS RUN TO SUCCEED in under a second, whichever of the three started it.
#
#   uv run dg run --local pipelines/echo-schedule.yaml
#   uv run dg apply && uv run dg run echo-schedule --watch -p station=oslo-blindern
```

The lines every document opens with, and the two parameters both triggers reach:

```yaml
format: dirigent/v1
kind: pipeline
code: echo-schedule
name: Started by a clock, and by a POST
description: |
  One read, carrying both trigger kinds: a rolling one-minute schedule, and an inbound
  webhook that maps a payload onto the pipeline's parameters.

  The document declares them; the instance holds the token, the pause flag and the history.

tags: [triggers, http, transform, webhook, schedule]

requires:
  blocks:
    - http.request
    - transform.jq

params:
  type: object
  properties:
    # Every URL in this document is built on this one value, so pointing the document at
    # another echo is a flag on the run rather than an edit: -p base_url=http://127.0.0.1:8080
    # runs it against a stand-in on this machine, with no network at all. A trigger is the
    # exception: a schedule's parameters are pinned in this document and a webhook's come out
    # of the payload, so neither can be handed a port chosen after it was applied.
    base_url:
      type: string
      default: https://postman-echo.com
      description: The echo service this document's requests are built on.
    station:
      type: string
      default: bergen-florida
      minLength: 1
      description: The station the reading is asked for.
    reading:
      type: string
      default: "12.4"
      description: The reading reported for it.
```

Every parameter carries a `default`, which is what makes the webhook mapping legal: a required
parameter nothing maps would be a hook that could never fire, and applying one is refused.

**`ask`** and **`record`** are the pipeline, and they are deliberately small -- the triggers
are what this document is about:

```yaml
steps:
  ask:
    block: http.request
    config:
      url: ${params.base_url}/get
      method: GET
      query:
        station: ${params.station}
        reading: ${params.reading}

  record:
    block: transform.jq
    depends_on: [ask]
    config:
      input:
        echoed: ${steps.ask.output.body.args}
        # run exposes exactly four names -- run.id, run.scratch, run.window.start and
        # run.window.end -- and what started the run is not one of them. Which trigger
        # fired is the instance's fact about the run, read back with `dg runs list`, not
        # something a step can reach for.
        run: ${run.id}
      program: |
        {station: .echoed.station, reading: .echoed.reading, run: .run}
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

**The hook.** The mapping is the whole declaration, and it is strict in both directions:
nothing the payload carries reaches a parameter the mapping does not name, and every name it
does use is validated against `params` like any other run's:

```yaml
  webhooks:
    # The mapping is the whole declaration: each parameter names a JSONPath into the
    # payload. Anything the payload carries that is not named here is ignored, and what is
    # named is validated against params above like any other run's -- so a caller cannot
    # reach a parameter this mapping does not mention, whatever it POSTs.
    #
    # Applying this refuses a mapping that could never fire: a path that does not parse, a
    # name params does not declare, or a required parameter with no default that nothing
    # maps. Both parameters here carry defaults, so neither is required.
    - code: upstream-reading
      name: Upstream reading
      params_from_payload:
        station: "$.station.code"
        reading: "$.station.reading"
```

A schedule you no longer want firing is paused on the instance rather than deleted from the
document: `dg schedule pause echo-schedule every-minute` holds it, and applying the document
again does not let it go.

## Where to go next

- [**The basics**](https://winterop-com.github.io/dirigent/basics/) is the tutorial these
  examples follow: one read, a schema gate on the answer, and a send built from the value
  that passed.
- [**echo-alert**](../echo-alert/README.md) is the half this one implies. A pipeline that
  fires at three in the morning is a pipeline nobody is watching, so the instance has to be
  the one that notices when it fails.
