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

## This one needs no network

The read is a node, not a call. `playground.generate` takes an `input` and hands it back, so
the batch is this document's own data arriving as a step's output. Nothing here reaches a
connection, a URL or a network -- only the run's own storage. Replacing `readings` with an
`http.request` whose body the write reads changes that one step and nothing under it.

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
uv run dg run echo-storage --watch
uv run dg runs report <the run id> --markdown
```

`./verify.sh` does all of that unattended, asserting that as many bytes came back as went out
and that the rendered page carries the table the template wrote. It picks a free port of its
own, mints its token with `dg auth login --username admin --password admin`, and stops
the instance it started by pid.

## What you see

*Printed as it printed, with this project's directory written as `/home/you/echo-storage` and
a local run's temporary root as `/tmp`.*

```bash
uv run dg validate pipelines/echo-storage.yaml
```

```text
2026-09-26T12:51:00.531+02:00 [info    ] valid                          [validation] code=echo-storage document=pipelines/echo-storage.yaml checked="document and installed blocks"
  each step under the last one it waits for
    readings  (playground.generate)
      save  (storage.write)
        back  (storage.read)
          summary  (transform.jq)
2026-09-26T12:51:00.535+02:00 [info    ] valid                          [validated] documents=1 invalid=0 skipped=0
```

```bash
uv run dg run --local pipelines/echo-storage.yaml
```

```text
2026-09-26T12:51:01.942+02:00 [info    ] started                        [run] pipeline=echo-storage run_id=01a0dd57-01b2-7256-9a91-4855087fcbbd local=true scratch=file:///tmp/dirigent-local-li3nb4cx/artifacts/runs/01a0dd57-01b2-7256-9a91-4855087fcbbd root=/tmp/dirigent-local-li3nb4cx
2026-09-26T12:51:01.935+02:00 [info    ] queued                         [step readings] block=playground.generate attempt=1
2026-09-26T12:51:02.006+02:00 [info    ] playground generated           [log readings] rows=4 seed=1556702461 locale=en_US drift=none
2026-09-26T12:51:02.006+02:00 [info    ] succeeded                      [step readings] block=playground.generate attempt=1 duration_ms=35
2026-09-26T12:51:02.068+02:00 [info    ] wrote                          [log save] uri=readings-2026-01-01.json bytes_written=206 content_type=application/json
2026-09-26T12:51:02.069+02:00 [info    ] succeeded                      [step save] block=storage.write attempt=1 duration_ms=10
2026-09-26T12:51:02.069+02:00 [info    ] queued                         [step back] block=storage.read attempt=1
2026-09-26T12:51:02.130+02:00 [info    ] read                           [log back] uri=readings-2026-01-01.json bytes_read=206 content_type=application/json
2026-09-26T12:51:02.132+02:00 [info    ] succeeded                      [step back] block=storage.read attempt=1 duration_ms=13
2026-09-26T12:51:02.132+02:00 [info    ] queued                         [step summary] block=transform.jq attempt=1
2026-09-26T12:51:02.218+02:00 [info    ] succeeded                      [step summary] block=transform.jq attempt=1 duration_ms=37
2026-09-26T12:51:02.223+02:00 [info    ] finished                       [log summary] duration_ms=31 output_bytes=85
2026-09-26T12:51:02.315+02:00 [info    ] succeeded                      [run] pipeline=echo-storage run_id=01a0dd57-01b2-7256-9a91-4855087fcbbd exit_code=0
steps
┏━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step     ┃ block               ┃ outcome   ┃ after    ┃ duration ┃ output                        ┃
┡━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ readings │ playground.generate │ succeeded │ -        │ 0.0s     │ records=[4 items]  rows=4     │
│          │                     │           │          │          │ seed=1556702461  locale=en_US │
│          │                     │           │          │          │ fields={3 keys}  drift=none   │
│          │                     │           │          │          │ delay_ms=0  attempt=1         │
│          │                     │           │          │          │ fail_until=0  input_rows=4    │
│ save     │ storage.write       │ succeeded │ readings │ 0.0s     │ uri=readings-2026-01-01.json  │
│          │                     │           │          │          │ bytes_written=206             │
│          │                     │           │          │          │ content_type=application/json │
│ back     │ storage.read        │ succeeded │ save     │ 0.0s     │ content_type=application/json │
│          │                     │           │          │          │ value={2 keys}                │
│          │                     │           │          │          │ bytes_read=206                │
│ summary  │ transform.jq        │ succeeded │ back     │ 0.0s     │ value={4 keys}                │
└──────────┴─────────────────────┴───────────┴──────────┴──────────┴───────────────────────────────┘
```

`bytes_written=206` and `bytes_read=206`: a value is written as canonical JSON -- sorted keys,
no spaces -- so the same value writes the same bytes every run, and what comes back is what
went out. The node's own seed is in its output and changes from run to run; it decided nothing
here, because the records came from the `input` rather than from a provider.

On an instance the same document writes into the artifact root instead of a temporary
directory, and nothing in the document changed to make that happen:

```bash
uv run dg apply
```

```text
create echo-storage  version 1 (/home/you/echo-storage/pipelines/echo-storage.yaml)
```

```bash
uv run dg run echo-storage --watch
```

```text
2026-11-01T14:20:03.253+01:00 [info    ] started                        [run] pipeline=echo-storage run_id=01a19744-6045-7382-a8a4-13818002802e local=false
2026-11-01T14:20:03.619+01:00 [info    ] playground generated           [log readings] rows=4 seed=874240655 locale=en_US drift=none
2026-11-01T14:20:03.620+01:00 [info    ] succeeded                      [step readings] block=playground.generate attempt=1 duration_ms=377
2026-11-01T14:20:03.697+01:00 [info    ] running                        [step save] block=storage.write attempt=1
2026-11-01T14:20:03.207+01:00 [info    ] queued                         [step back] block=storage.read attempt=1
2026-11-01T14:20:03.735+01:00 [info    ] wrote                          [log save] uri=file://./.dirigent/state/artifacts/runs/01a19744-6045-7382-a8a4-13818002802e/readings-2026-01-01.json bytes_written=206 content_type=application/json
2026-11-01T14:20:03.819+01:00 [info    ] succeeded                      [step save] block=storage.write attempt=1 duration_ms=122
2026-11-01T14:20:03.826+01:00 [info    ] running                        [step back] block=storage.read attempt=1
2026-11-01T14:20:03.207+01:00 [info    ] queued                         [step summary] block=transform.jq attempt=1
2026-11-01T14:20:03.843+01:00 [info    ] read                           [log back] uri=file://./.dirigent/state/artifacts/runs/01a19744-6045-7382-a8a4-13818002802e/readings-2026-01-01.json bytes_read=206 content_type=application/json
2026-11-01T14:20:03.856+01:00 [info    ] succeeded                      [step back] block=storage.read attempt=1 duration_ms=30
2026-11-01T14:20:03.861+01:00 [info    ] running                        [step summary] block=transform.jq attempt=1
2026-11-01T14:20:03.919+01:00 [info    ] succeeded                      [step summary] block=transform.jq attempt=1 duration_ms=58
2026-11-01T14:20:03.926+01:00 [info    ] finished                       [log summary] duration_ms=35 output_bytes=85
2026-11-01T14:20:04.012+01:00 [info    ] succeeded                      [run] pipeline=echo-storage run_id=01a19744-6045-7382-a8a4-13818002802e pipeline_version=1 triggered_by="admin (token dev)" duration_ms=677 items_total=0 items_failed=0 exit_code=0 priority=normal
run 01a19744-6045-7382-a8a4-13818002802e
pipeline      echo-storage (version 1)
status        succeeded
triggered by  admin (token dev)
duration      0.7s
items         -

steps
┏━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━┓
┃ step     ┃ block               ┃ outcome   ┃ after    ┃ attempts ┃ duration ┃ error ┃
┡━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━┩
│ readings │ playground.generate │ succeeded │ -        │ 1        │ 0.4s     │ -     │
│ save     │ storage.write       │ succeeded │ readings │ 1        │ 0.1s     │ -     │
│ back     │ storage.read        │ succeeded │ save     │ 1        │ 0.0s     │ -     │
│ summary  │ transform.jq        │ succeeded │ back     │ 1        │ 0.1s     │ -     │
└──────────┴─────────────────────┴───────────┴──────────┴──────────┴──────────┴───────┘

outputs
┏━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step     ┃ output                                                                                ┃
┡━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ readings │ records=[4 items]  rows=4  seed=874240655  locale=en_US  fields={3 keys}  drift=none  │
│          │ delay_ms=0  attempt=1  fail_until=0  fail_as=transient  input_rows=4                  │
│ save     │ uri=file://./.dirigent/state/artifacts/runs/01a19744-6045-7382-a8a4-13818002802e/rea… │
│          │ bytes_written=206  content_type=application/json                                      │
│ back     │ content_type=application/json  value={2 keys}  bytes_read=206                         │
│ summary  │ value={4 keys}                                                                        │
└──────────┴───────────────────────────────────────────────────────────────────────────────────────┘
```

Nobody asked for the report and it is already written: the engine rendered it in the
transaction that settled the run. Into a pipe `dg runs report --markdown` is one
`run.report_document` record carrying the whole page, so `jq -r .document` is how it comes out
as text; at a terminal the same command writes that page as-is, to go into a file or a ticket.

```bash
uv run dg runs report 01a19744-6045-7382-a8a4-13818002802e --markdown | jq -r .document
```

```text
# echo-storage on 2026-11-01T13:20:03.242885+00:00

**succeeded** in 677ms, started by admin (token dev).

The batch landed at `file://./.dirigent/state/artifacts/runs/01a19744-6045-7382-a8a4-13818002802e/readings-2026-01-01.json`, 206b of canonical JSON.

| Day | Rows | Coldest | Mean |
| --- | --- | --- | --- |
| 2026-01-01 | 4 | tromso-langnes | 2.5 |

- **readings** (playground.generate) succeeded after 1 attempt(s), 377ms
- **save** (storage.write) succeeded after 1 attempt(s), 122ms
- **back** (storage.read) succeeded after 1 attempt(s), 30ms
- **summary** (transform.jq) succeeded after 1 attempt(s), 58ms
```

`677ms` and `206b` are the `duration` and `bytes` filters: the template was handed
milliseconds and bytes and asked for them the way a person reads them.


## The document, hop by hop

`pipelines/echo-storage.yaml` opens with the two block contracts and the one rule about where
bytes land:

```yaml
# A payload out of a run and back into it, and a run that writes its own account of itself.
#
# In:  a batch of readings, carried in this document and handed over by the node.
# Out: one file in the run's scratch space, the batch read back off it, a summary, and a
#      report document the engine renders when the run settles.
#
# THE READ IS A NODE, NOT A CALL. playground.generate takes an `input` and hands it back, so
# the batch is this document's own data arriving as a step's output. Nothing here reaches a
# connection, a URL or a network -- only the run's own storage. Replacing `readings` with an
# http.request whose body the write reads changes that one step and nothing under it.
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
#   readings  the batch, as the node's records. This stands in for the read: the rows
#             arrive from somewhere else.
#   save      write the day and the rows to one file under the run's scratch prefix.
#   back      read that file again, at the uri the write reported rather than the same path
#             typed twice.
#   summary   reduce the rows as they came off storage, not as they were held upstream.
#
# EXPECT THIS RUN TO SUCCEED in well under a second, with four rows written and read back.
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
  A batch written to storage, read back, and reduced -- and a `report:` section, so every
  run of it renders its own markdown account when it settles.

  The document names a scheme-agnostic prefix; where the bytes land is an instance setting.

tags: [recipes, playground, storage, transform, report]

requires:
  blocks:
    - playground.generate
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

**`readings`** is the source. The batch is written into the node's `input`, and because no
`fields:` are named it travels through untouched and becomes the node's records:

```yaml
steps:
  readings:
    block: playground.generate
    config:
      # No fields: are named, so the list travels through untouched and each element is one
      # of the node's records.
      input:
        - { station: bergen-florida, celsius: 12.4 }
        - { station: oslo-blindern, celsius: 3.1 }
        - { station: tromso-langnes, celsius: -6.8 }
        - { station: trondheim-voll, celsius: 1.2 }
```

**`save`** writes it out, composing the file out of the day and the rows. `${run.scratch}` is a
prefix rather than a path: the same line lands in a temporary directory locally, in the
artifact root on this instance, and in a bucket on one with object storage configured:

```yaml
  save:
    block: storage.write
    depends_on: [readings]
    config:
      target: ${run.scratch}/readings-${params.day}.json
      value:
        day: ${params.day}
        readings: ${steps.readings.output.records}
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
# The template reads the run's own facts -- pipeline, run, step.<name> and steps -- and the
# filters render a value the way a person reads it: duration turns milliseconds into 1m30s,
# bytes turns bytes into 1.5mb, and iso turns a moment into a timestamp.
#
# A name the facts do not have renders as empty rather than failing, because half a run's
# facts are legitimately null depending on how it ended -- which is why the two steps below
# are guarded: a run that failed at `readings` has no `save` output to read into.
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

- [`echo-s3`](../echo-s3/README.md) is what comes next: this same round trip with a bucket
  under it, where the scheme comes off a connection rather than off the instance's filesystem.
- [**The basics**](https://winterop-com.github.io/dirigent/basics/) is the tutorial these
  examples follow: one read, a schema gate on the answer, and a send built from the value
  that passed.
- [**The examples**](../README.md): every example in order, and what you need once.
