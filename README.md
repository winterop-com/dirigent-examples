# echo-read

One read, which is where every pipeline against a system you do not own begins. `http.request`
is the generic HTTP call: it takes an absolute `url`, a `method` and a `query`, and it hands back
`status`, `headers`, `body`, `body_bytes` and `duration_ms` as its output. The shape worth
noticing is that nothing in the document is written twice: the station and the reading are
`params`, a JSON Schema over the run's parameters, and `${params.station}` reads one into the
query. A parameter with a `default` may be left out, one without must be given, and a value the
schema refuses stops the run before a single call is made. Postman Echo answers a GET with the
arguments it was given, so the answer is the proof of what was asked -- and this example runs the
same document twice, once with no server at all and once against an instance that keeps the run.

## Run it

From a fresh clone:

```bash
uv sync
uv run dg validate pipelines/echo-read.yaml
uv run dg run --local pipelines/echo-read.yaml
uv run dg run --local pipelines/echo-read.yaml -p station=oslo-blindern
```

`dg run --local` applies and runs the document in a throwaway instance in a temporary directory
and deletes it on the way out: same apply, same engine, same worker loop, no server. It is the
fast loop, and `-p` sets a parameter for one run.

Then the same document on an instance that keeps what it ran. In a second terminal, in this
directory:

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

Back in the first terminal, with that export line pasted:

```bash
uv run dg apply
uv run dg run echo-read --watch
uv run dg runs show <run id> --json | jq '.fields.attempts[] | select(.step_name == "ask") | .output.body'
```

`./verify.sh` does all of it non-interactively: it picks a free port of its own, starts an
instance, applies, runs, reads the answer back out of the run, and stops the instance it started.

## Offline

Postman Echo is the one thing here that needs the network, and `local-echo` beside this
repository is the same service in one file of Python. Start it in another terminal:

```bash
python3 ../local-echo/echo_server.py
```

It listens on `http://127.0.0.1:8080`, and the document already has the parameter that points at
it:

```bash
uv run dg run --local pipelines/echo-read.yaml -p base_url=http://127.0.0.1:8080
```

```text
2026-09-17T15:26:04.931+02:00 [info    ] http call                      [log ask] method=GET url=http://127.0.0.1:8080/get status=200 bytes=288 duration_ms=31
```

That line is the whole of the difference: the `url` the call was made against. The answer is the
same answer and says the same thing about where it came from.

```bash
uv run dg run --local pipelines/echo-read.yaml -p base_url=http://127.0.0.1:8080 --json \
  | jq -s 'map(select(.kind == "run")) | last | .steps[0].output.body'
```

```json
{
  "args": {
    "reading": "12.4",
    "station": "bergen-florida"
  },
  "headers": {
    "host": "127.0.0.1:8080",
    "accept": "*/*",
    "accept-encoding": "gzip, deflate",
    "connection": "keep-alive",
    "user-agent": "python-httpx2/2.13.0"
  },
  "url": "http://127.0.0.1:8080/get?reading=12.4&station=bergen-florida"
}
```

`args` carries the parameters back exactly as the real service does, and `url` is the address it
was asked on. An instance takes the same flag:

```bash
uv run dg run echo-read --watch -p base_url=http://127.0.0.1:8080
```

`./verify.sh` makes every assertion on this page twice, once against each echo, whenever
`../local-echo/echo_server.py` is there; `VERIFY_OFFLINE=1 ./verify.sh` leaves the online leg
out. `OFFLINE.md` beside this repository is the rest of the story, including the `UV_OFFLINE=1`
that keeps `uv` off the network too.

## What you see

*Printed as it printed, with this project's directory written as `/home/you/...` and the
temporary directory a local run makes written as `/tmp/...`.*

```bash
uv run dg validate pipelines/echo-read.yaml
```

```text
2026-09-17T14:57:13.398+02:00 [info    ] valid                          [validation] code=echo-read document=pipelines/echo-read.yaml checked="document, offline"
  each step under the last one it waits for
    ask  (http.request)
2026-09-17T14:57:13.401+02:00 [info    ] valid                          [validated] documents=1 invalid=0
```

Offline, and it already knows the graph: one step, waiting on nothing.

```bash
uv run dg run --local pipelines/echo-read.yaml
```

```text
2026-09-17T14:57:21.572+02:00 [info    ] started                        [run] pipeline=echo-read run_id=01a0af71-6da0-7539-bdfb-f4995739a841 local=true scratch=file:///tmp/dirigent-local-cp29hc6y/artifacts/runs/01a0af71-6da0-7539-bdfb-f4995739a841 root=/tmp/dirigent-local-cp29hc6y
2026-09-17T14:57:21.568+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-17T14:57:21.668+02:00 [info    ] running                        [step ask] block=http.request attempt=1
2026-09-17T14:57:21.997+02:00 [info    ] http call                      [log ask] method=GET url=https://postman-echo.com/get status=200 bytes=273 duration_ms=319
2026-09-17T14:57:21.999+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=330
2026-09-17T14:57:22.047+02:00 [info    ] succeeded                      [run] pipeline=echo-read run_id=01a0af71-6da0-7539-bdfb-f4995739a841 exit_code=0
steps
┏━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step ┃ block        ┃ outcome   ┃ after ┃ duration ┃ output                              ┃
┡━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask  │ http.request │ succeeded │ -     │ 0.3s     │ status=200  headers={12 keys}       │
│      │              │           │       │          │ body={3 keys}  body_bytes=273       │
│      │              │           │       │          │ duration_ms=319                     │
└──────┴──────────────┴───────────┴───────┴──────────┴─────────────────────────────────────┘
```

That is the block's whole output, summarised. The answer itself is in the run rather than on the
screen, which is what the last command in this section is for.

```bash
uv run dg run --local pipelines/echo-read.yaml -p station=oslo-blindern
```

```text
2026-09-17T14:57:23.269+02:00 [info    ] started                        [run] pipeline=echo-read run_id=01a0af71-7441-768a-a0c6-af90d126c97e local=true scratch=file:///tmp/dirigent-local-_z7njnmd/artifacts/runs/01a0af71-7441-768a-a0c6-af90d126c97e root=/tmp/dirigent-local-_z7njnmd
2026-09-17T14:57:23.264+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-17T14:57:23.338+02:00 [info    ] running                        [step ask] block=http.request attempt=1
2026-09-17T14:57:23.560+02:00 [info    ] http call                      [log ask] method=GET url=https://postman-echo.com/get status=200 bytes=271 duration_ms=214
2026-09-17T14:57:23.562+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=224
2026-09-17T14:57:23.718+02:00 [info    ] succeeded                      [run] pipeline=echo-read run_id=01a0af71-7441-768a-a0c6-af90d126c97e exit_code=0
steps
┏━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step ┃ block        ┃ outcome   ┃ after ┃ duration ┃ output                              ┃
┡━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask  │ http.request │ succeeded │ -     │ 0.2s     │ status=200  headers={12 keys}       │
│      │              │           │       │          │ body={3 keys}  body_bytes=271       │
│      │              │           │       │          │ duration_ms=214                     │
└──────┴──────────────┴───────────┴───────┴──────────┴─────────────────────────────────────┘
```

`bytes=271` rather than `273`: `oslo-blindern` is two characters shorter than `bergen-florida`,
and the answer carries the station back. Nothing else about the document changed.

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
2026-09-17T23:22:00.070+02:00 [info    ] started                        [run] pipeline=echo-read run_id=01a0b13f-7102-7534-85da-d99b22926daa local=false
2026-09-17T23:22:00.068+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-17T23:22:00.309+02:00 [info    ] running                        [step ask] block=http.request attempt=1
2026-09-17T23:22:00.711+02:00 [info    ] http call                      [log ask] method=GET url=https://postman-echo.com/get status=200 bytes=273 duration_ms=375
2026-09-17T23:22:00.715+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=406
2026-09-17T23:22:01.425+02:00 [info    ] succeeded                      [run] pipeline=echo-read run_id=01a0b13f-7102-7534-85da-d99b22926daa pipeline_version=1 triggered_by="dev (token dev)" duration_ms=406 items_total=0 items_failed=0 exit_code=0 priority=normal
run
01a0b13f-7102-7534-85da-d99b22926daa
pipeline      echo-read (version 1)
status        succeeded
triggered by  dev (token dev)
duration      0.4s
items         -

steps
┏━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━┓
┃ step ┃ block        ┃ outcome   ┃ after ┃ attempts ┃ duration ┃ error ┃
┡━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━┩
│ ask  │ http.request │ succeeded │ -     │ 1        │ 0.4s     │ -     │
└──────┴──────────────┴───────────┴───────┴──────────┴──────────┴───────┘

outputs
┏━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step ┃ output                                                                        ┃
┡━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask  │ status=200  headers={12 keys}  body={3 keys}  body_bytes=273  duration_ms=375 │
└──────┴───────────────────────────────────────────────────────────────────────────────┘
```

Two things are here that the local run did not have: a `pipeline_version`, because the instance
stored the document and pinned the run to that version, and a `triggered by`, because a run on an
instance is something somebody asked for.

```bash
uv run dg runs show 01a0b13f-7102-7534-85da-d99b22926daa --json \
  | jq '.fields.attempts[] | select(.step_name == "ask") | .output.body'
```

```json
{
  "args": {
    "reading": "12.4",
    "station": "bergen-florida"
  },
  "headers": {
    "host": "postman-echo.com",
    "x-forwarded-proto": "https",
    "accept": "*/*",
    "user-agent": "python-httpx2/2.13.0",
    "accept-encoding": "gzip, br"
  },
  "url": "https://postman-echo.com/get?reading=12.4&station=bergen-florida"
}
```

There is the answer, whole. The query arguments came back under `args`, carrying the parameters'
defaults, and the url the call actually made is in the answer too. Every command writes records
into a pipe, so the whole of a run is one `jq` away and nothing had to be printed on screen for
it to be readable afterwards.

## The document, hop by hop

`pipelines/echo-read.yaml`:

```yaml
format: dirigent/v1
kind: pipeline
code: echo-read
name: Echo read
description: Ask Postman Echo for one station's reading, and read what it answers.

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
    base_url:
      type: string
      default: https://postman-echo.com
      description: The echo service this document's requests are built on.
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
refuses stops the run before a single call is made. `base_url` is that same mechanism doing a
structural job: every URL in the document is built on it, so one flag moves the whole run to
another echo without touching a line of the document. Note that `reading` is a **string**: there
are no numbers in a query string, so a reading that travels that way is text at the far end
however numeric it looks. The gate in [echo-gate](../echo-gate) is where that matters.

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
```

`url` is an absolute address -- assembled here from a parameter and a path, but an address, which
is all a one-off call needs. The alternative is a
**connection**: a coded record the instance holds, carrying a base URL, its credential, its TLS
setting and its timeout, which the step names with `connection:` and a `path:`. That is what you
reach for the moment two steps call the same host, or the host wants a password -- a document
naming a connection code carries no secret and applies unchanged to staging and to production.
This one calls a public endpoint once, so it needs neither.

## Where to go next

- [`echo-gate`](../echo-gate/README.md) is what comes next: the answer held to a written-down
  shape, so a payload that has moved stops at the step it arrived in.
- [**The basics**](https://winterop-com.github.io/dirigent/basics/) is the tutorial this example
  is cut from, and section 3 is this step of it.
- [**The examples**](../README.md): every example in order, and what you need once.
