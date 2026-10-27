# echo-hello

The smallest document dirigent will run, and the one thing worth learning from it: a step reads
what the step before it produced. `value.const` emits a value and touches nothing; `log.write`
writes one line into the run's log, and it builds that line out of `${steps.make.output.value}`
rather than out of a constant written twice. That reference, and the `depends_on` edge under it,
are what make this a pipeline rather than two commands in a shell -- dirigent works the order out
from the edges, and resolves the reference the moment the step is about to run. Nothing here
needs a server, a network or a credential, so it is the fastest loop you have while you are
learning the shape of a document.

## Run it

From a fresh clone:

```bash
uv sync
uv run dg validate pipelines/echo-hello.yaml
uv run dg run --local pipelines/echo-hello.yaml
```

`uv sync` builds this project's own environment from `pyproject.toml`, which pins the dirigent
runtime, so every `uv run dg` is that pinned `dg` rather than whatever is on your path.
`dg validate` checks the document offline -- no server, no network. `dg run --local` applies and
runs it in a throwaway instance in a temporary directory and deletes that instance on the way
out: same apply, same engine, same worker loop, no server.

`./verify.sh` runs exactly that sequence and asserts on the records it gets back.

## What you see

*Printed as it printed, with this project's directory written as `/home/you/...` and the
temporary directory a local run makes written as `/tmp/...`.*

```bash
uv run dg validate pipelines/echo-hello.yaml
```

```text
2026-09-17T14:53:17.014+02:00 [info    ] valid                          [validation] code=echo-hello document=pipelines/echo-hello.yaml checked="document and installed blocks"
  each step under the last one it waits for
    make  (value.const)
      say  (log.write)
2026-09-17T14:53:17.016+02:00 [info    ] valid                          [validated] documents=1 invalid=0
```

The tree is the graph the document described, drawn before anything ran: each step under the
last step it waits for.

```bash
uv run dg run --local pipelines/echo-hello.yaml
```

```text
2026-09-17T14:53:36.815+02:00 [info    ] started                        [run] pipeline=echo-hello run_id=01a0af6d-ffaa-763d-b3e3-df56a3a17700 local=true scratch=file:///tmp/dirigent-local-fjpjd_u9/artifacts/runs/01a0af6d-ffaa-763d-b3e3-df56a3a17700 root=/tmp/dirigent-local-fjpjd_u9
2026-09-17T14:53:36.810+02:00 [info    ] queued                         [step make] block=value.const attempt=1
2026-09-17T14:53:36.905+02:00 [info    ] succeeded                      [step make] block=value.const attempt=1 duration_ms=11
2026-09-17T14:53:36.909+02:00 [info    ] finished                       [log make] duration_ms=0 output_bytes=31
2026-09-17T14:53:36.919+02:00 [info    ] the step before me said: hello from dirigent [log say]
2026-09-17T14:53:36.919+02:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=14
2026-09-17T14:53:37.027+02:00 [info    ] succeeded                      [run] pipeline=echo-hello run_id=01a0af6d-ffaa-763d-b3e3-df56a3a17700 exit_code=0
steps
┏━━━━━━┳━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step ┃ block       ┃ outcome   ┃ after ┃ duration ┃ output                    ┃
┡━━━━━━╇━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ make │ value.const │ succeeded │ -     │ 0.0s     │ value=hello from dirigent │
│ say  │ log.write   │ succeeded │ make  │ 0.0s     │ -                         │
└──────┴─────────────┴───────────┴───────┴──────────┴───────────────────────────┘
```

There is the reference, resolved, in the middle of the stream: `the step before me said: hello
from dirigent`. Nobody wrote that sentence anywhere; `say` built it from what `make` produced.

The table is a rendering, not the output. Every command writes tables and colour when its stdout
is a terminal, and NDJSON -- one record per line -- when it is a pipe, a container's log or a CI
job. `--json` asks for the records at a terminal and `dg format` renders a stream that was piped
or kept, so nothing is lost either way. That is why `verify.sh` asserts on records and never on
the table above.

## The document, hop by hop

`pipelines/echo-hello.yaml`:

```yaml
format: dirigent/v1
kind: pipeline
code: echo-hello
name: Echo hello
description: One step emits a value, and the step after it writes that value into the run's log.
```

`format` says which document language this is and `kind` which sort of document; every document
dirigent reads opens with those two lines. `code` is the key the pipeline is addressed by:
constrained, unique on the instance, and what every command and every URL uses. `name` is a human
title with no identity at all, and `description` is long-form and markdown-capable.

```yaml
tags: [references]

requires:
  blocks:
    - value.const
    - log.write
```

`requires` is the document saying what it needs of an instance -- here, two block ids. An
instance missing something a document requires refuses the document rather than failing halfway
through a run. `tags` is the vocabulary a reader filters by, and `references` is what this one
teaches.

```yaml
steps:
  make:
    block: value.const
    config:
      value: hello from dirigent
```

`steps` is a map, and each key is a step's name -- `make` here, and the name is how everything
else refers to it. A step names a **block**, one unit of work the instance knows how to do, and
hands it a `config`. `value.const` emits its configured value as its output, unchanged.

```yaml
  say:
    block: log.write
    depends_on: [make]
    config:
      message: "the step before me said: ${steps.make.output.value}"
```

`depends_on` names the steps this one waits for, and those edges are the pipeline: dirigent works
the order out from them, and runs whatever is not waiting on anything in parallel.
`${steps.make.output.value}` is a **reference**: at the moment `say` is about to run it is
replaced by what `make` actually produced. `steps.<name>.output` is that step's output object and
every dot after it walks into it -- an array index is a dot too, so `...output.value.rows.0.id`
is the first row's id.

## Where to go next

- [`echo-read`](../echo-read/README.md) is the next step: one `http.request` against the
  playground an instance serves itself, run locally and then against that instance.
- [**The basics**](https://winterop-com.github.io/dirigent/basics/) is the tutorial this example
  is cut from: this document, and then a real read, a schema gate and a send after it.
- [**The examples**](../README.md): every example in order, and what you need once.
