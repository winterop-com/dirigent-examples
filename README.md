# echo-read

One read, which is where every pipeline against a system you do not own begins. `http.request`
is the generic HTTP call: it takes an absolute `url`, a `method` and a `query`, and it hands back
`status`, `headers`, `body`, `body_bytes` and `duration_ms` as its output. The shape worth
noticing is that nothing in the document is written twice: the station and the reading are
`params`, a JSON Schema over the run's parameters, and `${params.station}` reads one into the
query. A parameter with a `default` may be left out, one without must be given, and a value the
schema refuses stops the run before a single call is made. The playground answers a GET with the
request it was given, so the answer is the proof of what was asked -- and this example runs the
same document twice, once with no server of its own and once against an instance that keeps the
run.

## What it calls

The **playground** is a request-and-response service every dirigent instance serves itself under
`/api/v1/playground`, unauthenticated. It answers with the request you sent it: the query
arguments, the body, the headers, and whatever status you asked for. So this example needs no
account anywhere and nothing it calls leaves the machine -- but it does need an instance, because
`dg run --local` builds a throwaway database and mounts no API of its own. Start one first, in
this directory:

```bash
uv run dg dev
```

`dg dev` is one process holding the API, the web UI, the scheduler, one worker and a SQLite file
under `.dirigent/state/`. It keeps running; leave it. On an empty state -- which is what a fresh
clone has, because the state directory is not in the repository -- it migrates the schema, makes
its own admin `dev`, mints that admin one token, and prints the `export DG_TOKEN=` line to paste.
The UI is at `http://127.0.0.1:3333`, which is the address the `local` profile in
`.dirigent/profiles.yaml` holds and the address the document's `playground` parameter defaults to;
`dg dev --port` moves the instance, `DG_URL` is how you tell the CLI where it went, and
`-p playground=...` is how you tell the document.

## Run it

From a fresh clone, with that instance running in a second terminal:

```bash
uv sync
uv run dg validate pipelines/echo-read.yaml
uv run dg run --local pipelines/echo-read.yaml
uv run dg run --local pipelines/echo-read.yaml -p station=oslo-blindern
```

`dg run --local` applies and runs the document in a throwaway instance in a temporary directory
and deletes it on the way out: same apply, same engine, same worker loop, no server of its own.
It is the fast loop, and `-p` sets a parameter for one run.

Then the same document on the instance that keeps what it ran, with the export line pasted:

```bash
uv run dg apply
uv run dg run echo-read --watch
uv run dg runs show <run id> --json | jq '.fields.attempts[] | select(.step_name == "ask") | .output.body'
```

`./verify.sh` does all of it non-interactively: it picks a free port of its own, starts an
instance, points both runs at that instance's playground, applies, runs, reads the answer back out
of the run, and stops the instance it started.

## What you see

*Printed as it printed, with this project's directory written as `/home/you/...` and the
temporary directory a local run makes written as `/tmp/...`.*

```bash
uv run dg validate pipelines/echo-read.yaml
```

```text
2026-09-26T12:29:45.000+02:00 [info    ] valid                          [validation] code=echo-read document=pipelines/echo-read.yaml checked="document, offline"
  each step under the last one it waits for
    ask  (http.request)
2026-09-26T12:29:45.002+02:00 [info    ] valid                          [validated] documents=1 invalid=0
```

Offline, and it already knows the graph: one step, waiting on nothing.

```bash
uv run dg run --local pipelines/echo-read.yaml
```

```text
2026-09-26T12:30:20.878+02:00 [info    ] started                        [run] pipeline=echo-read run_id=01a0dd44-11ca-763a-8f77-927b553fdd88 local=true scratch=file:///tmp/dirigent-local-l1ee6zq7/artifacts/runs/01a0dd44-11ca-763a-8f77-927b553fdd88 root=/tmp/dirigent-local-l1ee6zq7
2026-09-26T12:30:20.873+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-26T12:30:20.952+02:00 [info    ] http call                      [log ask] method=GET url=http://127.0.0.1:3333/api/v1/playground/request status=200 bytes=452 duration_ms=31
2026-09-26T12:30:20.953+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=45
2026-09-26T12:30:21.046+02:00 [info    ] succeeded                      [run] pipeline=echo-read run_id=01a0dd44-11ca-763a-8f77-927b553fdd88 exit_code=0
steps
┏━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step ┃ block        ┃ outcome   ┃ after ┃ duration ┃ output                                      ┃
┡━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask  │ http.request │ succeeded │ -     │ 0.0s     │ status=200  headers={5 keys}  body={3 keys} │
│      │              │           │       │          │ body_bytes=452  duration_ms=31              │
└──────┴──────────────┴───────────┴───────┴──────────┴─────────────────────────────────────────────┘
```

That is the block's whole output, summarised. The answer itself is in the run rather than on the
screen, which is what the last command in this section is for.

```bash
uv run dg run --local pipelines/echo-read.yaml -p station=oslo-blindern
```

```text
2026-09-26T12:30:22.616+02:00 [info    ] started                        [run] pipeline=echo-read run_id=01a0dd44-1894-7796-b760-00a9d5973ba3 local=true scratch=file:///tmp/dirigent-local-4kcs932r/artifacts/runs/01a0dd44-1894-7796-b760-00a9d5973ba3 root=/tmp/dirigent-local-4kcs932r
2026-09-26T12:30:22.611+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-26T12:30:22.708+02:00 [info    ] http call                      [log ask] method=GET url=http://127.0.0.1:3333/api/v1/playground/request status=200 bytes=450 duration_ms=36
2026-09-26T12:30:22.712+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=59
2026-09-26T12:30:22.848+02:00 [info    ] succeeded                      [run] pipeline=echo-read run_id=01a0dd44-1894-7796-b760-00a9d5973ba3 exit_code=0
steps
┏━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step ┃ block        ┃ outcome   ┃ after ┃ duration ┃ output                                      ┃
┡━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask  │ http.request │ succeeded │ -     │ 0.1s     │ status=200  headers={5 keys}  body={3 keys} │
│      │              │           │       │          │ body_bytes=450  duration_ms=36              │
└──────┴──────────────┴───────────┴───────┴──────────┴─────────────────────────────────────────────┘
```

`bytes=450` rather than `452`: `oslo-blindern` is one character shorter than `bergen-florida` and
the answer carries the station back twice, in the url and in the arguments. Nothing else about the
document changed.

Now the same document against the instance:

```bash
uv run dg apply
```

```text
create echo-read  version 1 (/home/you/echo-read/pipelines/echo-read.yaml)
```

`dg apply` sends every document under `pipelines/` and stores each as an immutable version;
applying an unchanged document again is not a new version, which is why `verify.sh` may be run as
many times as you like.

```bash
uv run dg run echo-read --watch
```

```text
2026-09-26T12:30:24.216+02:00 [info    ] started                        [run] pipeline=echo-read run_id=01a0dd44-1ed3-7286-a467-d65a57da6cd2 local=false
2026-09-26T12:30:24.213+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-26T12:30:24.489+02:00 [info    ] http call                      [log ask] method=GET url=http://127.0.0.1:3333/api/v1/playground/request status=200 bytes=452 duration_ms=22
2026-09-26T12:30:24.491+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=39
2026-09-26T12:30:24.808+02:00 [info    ] succeeded                      [run] pipeline=echo-read run_id=01a0dd44-1ed3-7286-a467-d65a57da6cd2 pipeline_version=1 triggered_by="dev (token cli-dev)" duration_ms=39 items_total=0 items_failed=0 exit_code=0 priority=normal
run 01a0dd44-1ed3-7286-a467-d65a57da6cd2
pipeline      echo-read (version 1)
status        succeeded
triggered by  dev (token cli-dev)
duration      0.0s
items         -

steps
┏━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━┓
┃ step ┃ block        ┃ outcome   ┃ after ┃ attempts ┃ duration ┃ error ┃
┡━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━┩
│ ask  │ http.request │ succeeded │ -     │ 1        │ 0.0s     │ -     │
└──────┴──────────────┴───────────┴───────┴──────────┴──────────┴───────┘

outputs
┏━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step ┃ output                                                                      ┃
┡━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask  │ status=200  headers={5 keys}  body={3 keys}  body_bytes=452  duration_ms=22 │
└──────┴─────────────────────────────────────────────────────────────────────────────┘
```

Two things are here that the local run did not have: a `pipeline_version`, because the instance
stored the document and pinned the run to that version, and a `triggered by`, because a run on an
instance is something somebody asked for.

```bash
uv run dg runs show 01a0dd44-1ed3-7286-a467-d65a57da6cd2 --json \
  | jq '.fields.attempts[] | select(.step_name == "ask") | .output.body'
```

```json
{
  "kind": "request",
  "request": {
    "method": "GET",
    "url": "http://127.0.0.1:3333/api/v1/playground/request?reading=12.4&station=bergen-florida",
    "path": "/api/v1/playground/request",
    "args": {
      "reading": "12.4",
      "station": "bergen-florida"
    },
    "headers": {
      "host": "127.0.0.1:3333",
      "accept": "*/*",
      "accept-encoding": "gzip, deflate",
      "connection": "keep-alive",
      "user-agent": "python-httpx2/2.13.0"
    },
    "body": null,
    "body_kind": "none",
    "body_bytes": 0,
    "content_type": null
  },
  "status": 200
}
```

There is the answer, whole, and every playground answer has that shape: `kind` says which route
answered, `request` is what arrived verbatim, and anything beside them is what the route decided.
So the query arguments came back under `request.args`, carrying the parameters' defaults, and the
url the call actually made is in the answer too. Every command writes records into a pipe, so the
whole of a run is one `jq` away and nothing had to be printed on screen for it to be readable
afterwards.

## The document, hop by hop

`pipelines/echo-read.yaml`:

```yaml
format: dirigent/v1
kind: pipeline
code: echo-read
name: Echo read
description: Ask the playground for one station's reading, and read what it answers.

tags: [http, params]

requires:
  blocks:
    - http.request
```

`requires` is the document saying what it needs of an instance. An instance missing a block named
here refuses the document at apply, with the list of what is missing, rather than failing halfway
through a run.

```yaml
params:
  type: object
  properties:
    playground:
      type: string
      default: http://127.0.0.1:3333/api/v1/playground
      description: The playground routes on the instance this calls; `dg dev` serves them here.
    station:
      type: string
      default: bergen-florida
      description: The station the reading is asked for.
    reading:
      type: string
      default: "12.4"
      description: The reading to send along with it.
```

`params` is a JSON Schema over the run's parameters, so the schema is the form: `dg run -p
station=oslo-blindern` overrides one, the UI's run form is drawn from it, and a value the schema
refuses stops the run before a single call is made. `playground` is that same mechanism doing a
structural job: every URL in the document is built on it, so an instance on another port is one
flag rather than an edit. Note that `reading` is a **string**: there are no numbers in a query
string, so a reading that travels that way is text at the far end however numeric it looks. The
gate in [echo-gate](../echo-gate) is where that matters.

```yaml
steps:
  ask:
    block: http.request
    config:
      url: ${params.playground}/request
      method: GET
      query:
        station: ${params.station}
        reading: ${params.reading}
```

`url` is an absolute address -- assembled here from a parameter and a path, but an address, which
is all a one-off call needs. The alternative is a
**connection**: a coded record the instance holds, carrying a base URL, its credential, its TLS
setting and its timeout, which the step names with `connection:` and a `path:`. That is what you
reach for the moment two steps call the same host, or the host wants a password -- a document
naming a connection code carries no secret and applies unchanged to staging and to production.
This one calls a single endpoint once, so it needs neither.

## Where to go next

- [`echo-gate`](../echo-gate/README.md) is what comes next: the answer held to a written-down
  shape, so a payload that has moved stops at the step it arrived in.
- [**The basics**](https://winterop-com.github.io/dirigent/basics/) is the tutorial this example
  is cut from, and section 3 is this step of it.
- [**The examples**](../README.md): every example in order, and what you need once.
