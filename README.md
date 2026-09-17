# echo-storage

A value travels between steps as a step's output, and that has a ceiling. `storage.write` is
the only way one leaves the run and `storage.read` the only way one comes back in -- so a
payload too large to carry in an output is handed along as a pair of steps naming a URI, and
the document never says whether that URI is a directory, an artifact root or a bucket. Where
the bytes land is an instance setting. The other half of this example is the `report:`
section: declare one and every run of the pipeline renders its own markdown account of itself
when it settles, written by the engine rather than by a step -- which is the point, because
the run whose worker died has no step left to write anything and is the run whose account is
worth the most.

## Run it

The storage round trip runs anywhere:

```bash
uv sync
uv run dg validate pipelines/echo-storage.yaml
uv run dg run --local pipelines/echo-storage.yaml
```

The report is the half that needs an instance: a local run's throwaway instance is deleted on
the way out with the run in it, so there is nothing left to read the page back from. In a
second terminal, in this directory:

```bash
uv run dg dev --port 3343
```

`dg dev` is one process holding the API, the web UI, the scheduler, one worker and a SQLite
file under `.dirigent/state/`. Its first start on an empty state directory makes the instance
and mints one token, in the line it prints -- `dg init` writes that token into the project's
`.env`, where the `local` profile reads it, and a clone of this repository has neither, so
copy it out of that line. Back in the first terminal:

```bash
export DG_URL=http://127.0.0.1:3343 DG_TOKEN=<the token that line printed>

uv run dg apply
uv run dg run echo-storage --watch
uv run dg runs report <the run id> --markdown
```

`./verify.sh` does all of that unattended, asserting that as many bytes came back as went out
and that the rendered page carries the table the template wrote.

## What you see

```text
$ uv run dg validate pipelines/echo-storage.yaml
2026-09-17T15:19:43.364+02:00 [info    ] valid                          [validation] code=echo-storage document=pipelines/echo-storage.yaml checked="document, offline"
  each step under the last one it waits for
    ask  (http.request)
      save  (storage.write)
        back  (storage.read)
          summary  (transform.jq)
2026-09-17T15:19:43.366+02:00 [info    ] valid                          [validated] documents=1 invalid=0

$ uv run dg run --local pipelines/echo-storage.yaml
2026-09-17T15:19:44.618+02:00 [info    ] started                        [run] pipeline=echo-storage run_id=01a0af85-ebe6-71db-959c-6addd6f78a80 local=true scratch=file:///var/folders/7t/m0y6vhq508n4fsfg85vhgjkh0000gp/T/dirigent-local-btz4qu7f/artifacts/runs/01a0af85-ebe6-71db-959c-6addd6f78a80 root=/var/folders/7t/m0y6vhq508n4fsfg85vhgjkh0000gp/T/dirigent-local-btz4qu7f
2026-09-17T15:19:44.611+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-17T15:19:44.687+02:00 [info    ] running                        [step ask] block=http.request attempt=1
2026-09-17T15:19:44.956+02:00 [info    ] http call                      [log ask] method=POST url=https://postman-echo.com/post status=200 bytes=701 duration_ms=257
2026-09-17T15:19:44.959+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=271
2026-09-17T15:19:45.008+02:00 [info    ] wrote                          [log save] uri=readings-2026-01-01.json bytes_written=206 content_type=application/json
2026-09-17T15:19:45.010+02:00 [info    ] succeeded                      [step save] block=storage.write attempt=1 duration_ms=16
2026-09-17T15:19:45.073+02:00 [info    ] read                           [log back] uri=readings-2026-01-01.json bytes_read=206 content_type=application/json
2026-09-17T15:19:45.074+02:00 [info    ] succeeded                      [step back] block=storage.read attempt=1 duration_ms=15
2026-09-17T15:19:45.074+02:00 [info    ] queued                         [step summary] block=transform.jq attempt=1
2026-09-17T15:19:45.168+02:00 [info    ] succeeded                      [step summary] block=transform.jq attempt=1 duration_ms=43
2026-09-17T15:19:45.173+02:00 [info    ] finished                       [log summary] duration_ms=33 output_bytes=85
2026-09-17T15:19:45.220+02:00 [info    ] succeeded                      [run] pipeline=echo-storage run_id=01a0af85-ebe6-71db-959c-6addd6f78a80 exit_code=0
steps                                                                                             
┏━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step    ┃ block         ┃ outcome   ┃ after ┃ duration ┃ output                                ┃
┡━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask     │ http.request  │ succeeded │ -     │ 0.3s     │ status=200  headers={12 keys}         │
│         │               │           │       │          │ body={7 keys}  body_bytes=701         │
│         │               │           │       │          │ duration_ms=257                       │
│ save    │ storage.write │ succeeded │ ask   │ 0.0s     │ uri=readings-2026-01-01.json          │
│         │               │           │       │          │ bytes_written=206                     │
│         │               │           │       │          │ content_type=application/json         │
│ back    │ storage.read  │ succeeded │ save  │ 0.0s     │ content_type=application/json         │
│         │               │           │       │          │ value={2 keys}  bytes_read=206        │
│ summary │ transform.jq  │ succeeded │ back  │ 0.0s     │ value={4 keys}                        │
└─────────┴───────────────┴───────────┴───────┴──────────┴───────────────────────────────────────┘
```

`bytes_written=206` and `bytes_read=206`: a value is written as canonical JSON -- sorted keys,
no spaces -- so the same value writes the same bytes every run, and what comes back is what
went out.

On an instance the same document writes into the artifact root instead of a temporary
directory, and nothing in the document changed to make that happen:

```text
$ uv run dg apply
create echo-storage  version 1 
(/home/you/echo-storage/pipelines/echo-storage.yaml)

$ uv run dg run echo-storage --watch
2026-09-17T15:19:58.619+02:00 [info    ] started                        [run] pipeline=echo-storage run_id=01a0af86-2297-775a-9d46-cbddfb1fcf3a local=false
2026-09-17T15:19:58.617+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-17T15:19:59.024+02:00 [info    ] running                        [step ask] block=http.request attempt=1
2026-09-17T15:19:58.617+02:00 [info    ] queued                         [step back] block=storage.read attempt=1
2026-09-17T15:19:59.226+02:00 [info    ] http call                      [log ask] method=POST url=https://postman-echo.com/post status=200 bytes=701 duration_ms=192
2026-09-17T15:19:59.228+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=205
2026-09-17T15:19:59.558+02:00 [info    ] wrote                          [log save] uri=file://./.dirigent/state/artifacts/runs/01a0af86-2297-775a-9d46-cbddfb1fcf3a/readings-2026-01-01.json bytes_written=206 content_type=application/json
2026-09-17T15:19:59.559+02:00 [info    ] succeeded                      [step save] block=storage.write attempt=1 duration_ms=9
2026-09-17T15:20:00.068+02:00 [info    ] read                           [log back] uri=file://./.dirigent/state/artifacts/runs/01a0af86-2297-775a-9d46-cbddfb1fcf3a/readings-2026-01-01.json bytes_read=206 content_type=application/json
2026-09-17T15:20:00.070+02:00 [info    ] succeeded                      [step back] block=storage.read attempt=1 duration_ms=11
2026-09-17T15:20:00.600+02:00 [info    ] succeeded                      [step summary] block=transform.jq attempt=1 duration_ms=31
2026-09-17T15:20:00.605+02:00 [info    ] finished                       [log summary] duration_ms=25 output_bytes=85
2026-09-17T15:20:01.075+02:00 [info    ] succeeded                      [run] pipeline=echo-storage run_id=01a0af86-2297-775a-9d46-cbddfb1fcf3a pipeline_version=1 triggered_by="admin (token init)" duration_ms=1577 items_total=0 items_failed=0 exit_code=0 priority=normal
run 01a0af86-2297-775a-9d46-cbddfb1fcf3a
pipeline      echo-storage (version 1)  
status        succeeded                 
triggered by  admin (token init)        
duration      1.6s                      
items         -                         

steps                                                                        
┏━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━┓
┃ step    ┃ block         ┃ outcome   ┃ after ┃ attempts ┃ duration ┃ error ┃
┡━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━┩
│ ask     │ http.request  │ succeeded │ -     │ 1        │ 0.2s     │ -     │
│ save    │ storage.write │ succeeded │ ask   │ 1        │ 0.0s     │ -     │
│ back    │ storage.read  │ succeeded │ save  │ 1        │ 0.0s     │ -     │
│ summary │ transform.jq  │ succeeded │ back  │ 1        │ 0.0s     │ -     │
└─────────┴───────────────┴───────────┴───────┴──────────┴──────────┴───────┘

outputs                                                                                           
┏━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step    ┃ output                                                                               ┃
┡━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask     │ status=200  headers={12 keys}  body={7 keys}  body_bytes=701  duration_ms=192        │
│ save    │ uri=file://./.dirigent/state/artifacts/runs/01a0af86-2297-775a-9d46-cbddfb1fcf3a/re… │
│         │ bytes_written=206  content_type=application/json                                     │
│ back    │ content_type=application/json  value={2 keys}  bytes_read=206                        │
│ summary │ value={4 keys}                                                                       │
└─────────┴──────────────────────────────────────────────────────────────────────────────────────┘
```

Nobody asked for the report and it is already written: the engine rendered it in the
transaction that settled the run. Into a pipe `dg runs report --markdown` is one
`run.report_document` record carrying the whole page, so `jq -r .document` is how it comes out
as text; at a terminal the same command writes that page as-is, to go into a file or a ticket.

```text
$ uv run dg runs report 01a0af86-2297-775a-9d46-cbddfb1fcf3a --markdown | jq -r .document
# echo-storage on 2026-09-17T13:19:59.024016+00:00

**succeeded** in 1s577ms, started by admin (token init).

The batch landed at `file://./.dirigent/state/artifacts/runs/01a0af86-2297-775a-9d46-cbddfb1fcf3a/readings-2026-01-01.json`, 206b of canonical JSON.

| Day | Rows | Coldest | Mean |
| --- | --- | --- | --- |
| 2026-01-01 | 4 | tromso-langnes | 2.5 |

- **ask** (http.request) succeeded after 1 attempt(s), 205ms
- **save** (storage.write) succeeded after 1 attempt(s), 9ms
- **back** (storage.read) succeeded after 1 attempt(s), 11ms
- **summary** (transform.jq) succeeded after 1 attempt(s), 31ms
```

`1s577ms` and `206b` are the `duration` and `bytes` filters: the template was handed
milliseconds and bytes and asked for them the way a person reads them.

## The document, hop by hop

`pipelines/echo-storage.yaml` opens with the two block contracts and the one rule about where
bytes land:

```yaml
# A payload out of a run and back into it, and a run that writes its own account of itself.
#
# In:  a batch of readings, POSTed to Postman Echo and read back out of its answer.
# Out: one file in the run's scratch space, the batch read back off it, a summary, and a
#      report document the engine renders when the run settles.
#
# A value travels between steps as a step's output. storage.write is the only way one
# leaves the run and storage.read the only way one comes back in, which is how a payload
# too large to carry in a step's output is handed along:
#
#   storage.write  target, and exactly one of text or value. A value is written as
#                  canonical JSON -- sorted keys, no spaces -- so the same value writes the
#                  same bytes every run. Out come uri, bytes_written and content_type.
#   storage.read   source, and max_size: how much of an object this step will hold, 1mb
#                  unless it says otherwise. An object above the cap is refused rather than
#                  truncated, because half a document is not a smaller one, it is a wrong
#                  one. JSON comes back as value and anything else as text.
#
# ${run.scratch} is this run's own prefix in whatever storage the instance is configured
# with: a temporary directory under a --local run, the artifact root under `dg dev`, and a
# bucket where an s3 connection serves the scheme. The document says none of that -- it
# names a scheme-agnostic prefix, and where the bytes land is an instance setting.
#
# The `report:` section at the bottom is the other half. A document with no report section
# renders nothing; one with a section renders a markdown document every time a run of it
# settles -- succeeded, failed, completed with errors or cancelled. The engine renders it in
# the transaction that settles the run rather than a step doing it, which is the point: a
# run whose worker died has no step left to write anything, and that is the run whose
# account is worth the most. `report: {}` would render the built-in page instead.
#
# Hop by hop:
#
#   ask      POST the batch to /post, which answers with the body it was given.
#   save     write the echoed batch to one file under the run's scratch prefix.
#   back     read that file again, at the uri the write reported rather than the same path
#            typed twice.
#   summary  reduce the rows as they came off storage, not as they were held upstream.
#
# EXPECT THIS RUN TO SUCCEED in about a second, with four rows written and read back.
#
#   uv run dg run --local pipelines/echo-storage.yaml
#   uv run dg apply && uv run dg run echo-storage --watch && uv run dg runs report RUN_ID --markdown
```

The lines every document opens with, and the four block ids it needs of an instance:

```yaml
format: dirigent/v1
kind: pipeline
code: echo-storage
name: Through storage, with a report
description: |
  The answer to one read written to storage, read back, and reduced -- and a `report:`
  section, so every run of it renders its own markdown account when it settles.

  The document names a scheme-agnostic prefix; where the bytes land is an instance setting.

tags: [recipes, http, storage, transform, report]

requires:
  blocks:
    - http.request
    - storage.write
    - storage.read
    - transform.jq

params:
  type: object
  properties:
    day:
      type: string
      format: date
      default: "2026-01-01"
      description: The day the written file is named for.
```

**`ask`** is the read. The batch is written into the request so the example needs nothing
standing up, and Postman Echo hands it straight back under `json`:

```yaml
steps:
  ask:
    block: http.request
    config:
      url: https://postman-echo.com/post
      method: POST
      body:
        day: ${params.day}
        readings:
          - { station: bergen-florida, celsius: 12.4 }
          - { station: oslo-blindern, celsius: 3.1 }
          - { station: tromso-langnes, celsius: -6.8 }
          - { station: trondheim-voll, celsius: 1.2 }
```

**`save`** writes it out. `${run.scratch}` is a prefix rather than a path: the same line lands
in a temporary directory locally, in the artifact root on this instance, and in a bucket on
one with object storage configured:

```yaml
  save:
    block: storage.write
    depends_on: [ask]
    config:
      target: ${run.scratch}/readings-${params.day}.json
      value: ${steps.ask.output.body.json}
```

**`back`** reads it in again, at the URI the write reported. One place decides where a file
went, so renaming it is a one-line change rather than a hunt:

```yaml
  back:
    block: storage.read
    depends_on: [save]
    config:
      # Where the write said the object landed. One place decides the path, so renaming the
      # file is a one-line change.
      source: ${steps.save.output.uri}
      max_size: 8mb
```

**`summary`** reduces the rows as they came off storage rather than as they were held
upstream, which is what makes this a round trip and not a detour:

```yaml
  summary:
    block: transform.jq
    depends_on: [back]
    config:
      input: ${steps.back.output.value}
      program: |
        {day: .day,
         rows: (.readings | length),
         coldest: (.readings | min_by(.celsius) | .station),
         mean_celsius: ((.readings | map(.celsius) | add) / (.readings | length) * 10
                        | round / 10)}
```

**The report** is a section of the document rather than a step, and it reads the run's own
facts -- the same ones `dg runs report` summarises. A name the facts do not have renders as
empty rather than failing the document, because half a run's facts are legitimately null
depending on how it ended, which is why the two steps read into below are guarded:

```yaml
# Every fact this template reads is in docs/reports.md. The filters render a value the way
# a person reads it: duration turns milliseconds into 1m30s, bytes turns bytes into 1.5mb,
# and iso turns a moment into a timestamp.
#
# A name the facts do not have renders as empty rather than failing, because half a run's
# facts are legitimately null depending on how it ended -- which is why the two steps below
# are guarded: a run that failed at `ask` has no `save` output to read into.
report:
  template: |
    # {{ pipeline.code }} on {{ run.started_at | iso }}

    **{{ run.status }}** in {{ run.duration_ms | duration }}, started by {{ run.trigger }}.

    {% if step.save.output %}
    The batch landed at `{{ step.save.output.uri }}`, {{ step.save.output.bytes_written | bytes }} of canonical JSON.
    {% endif %}

    {% if step.summary.output %}
    | Day | Rows | Coldest | Mean |
    | --- | --- | --- | --- |
    | {{ step.summary.output.value.day }} | {{ step.summary.output.value.rows }} | {{ step.summary.output.value.coldest }} | {{ step.summary.output.value.mean_celsius }} |
    {% endif %}

    {% for s in steps %}
    - **{{ s.step }}** ({{ s.block }}) {{ s.outcome }} after {{ s.attempts }} attempt(s), {{ s.duration_ms | duration }}
    {% endfor %}
```

Replace the whole section with `report: {}` and the engine renders its own page instead: the
title, the run's facts, a row per step, the items that failed, and the run's error. A template
is worth writing when somebody other than an operator is going to read the page.

## Where to go next

- [**The basics**](https://winterop-com.github.io/dirigent/basics/) is the tutorial these
  examples follow: one read, a schema gate on the answer, and a send built from the value
  that passed.
- [**echo-transform**](../echo-transform/README.md) is the step that usually sits between the
  read and the write: `filter.jq`, `map.jq` and `transform.jq`, and what each one is allowed
  to do to a list.
