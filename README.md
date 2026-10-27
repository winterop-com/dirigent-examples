# echo-transform

Between a source and a sink, something almost always has to be reshaped -- and dirigent gives
you three verbs to do it with rather than one. `filter.jq` narrows a list without touching
what stays, `map.jq` replaces every element with one thing, and `transform.jq` reshapes the
whole value at once. One jq program could do all three jobs in a line; three steps say which
job was done. That matters when somebody reads the document a year later and wants to know
whether it dropped rows, added rows, or edited them in place -- so this example does one
thing per step, on a batch a node hands over, and writes the result onto the run's own
timeline.

## This one needs no network

The read is a node, not a call. `playground.generate` takes an `input` and hands it back, so
the batch is this document's own data arriving as a step's output rather than a round trip
that pretends to fetch what it just sent. The sink is `log.write`, the smallest one there is:
it puts the summary on the run's timeline and hands it on unchanged. The document reaches
nothing: no connection, no URL, no network, no file. Replace `readings` with an `http.request`
whose body the filter reads, or `say` with an `http.request` that POSTs the summary onward,
and the three verbs between them do not move.

## Run it

Everything here runs without a server. `dg run --local` applies and runs the document in a
throwaway instance in a temporary directory and deletes it on the way out -- the same apply,
the same engine, the same worker loop.

```bash
uv sync
uv run dg validate pipelines/echo-transform.yaml
uv run dg run --local pipelines/echo-transform.yaml
```

`./verify.sh` does exactly that and asserts on the records it gets back: that the filter
dropped one of four and modified nothing, that the map returned exactly as many as it was
given, and that what reached the run's timeline is what the transform built.

## What you see

*Printed as it printed, with this project's directory written as `/home/you/echo-transform`
and a local run's temporary root as `/tmp`.*

```bash
uv run dg validate pipelines/echo-transform.yaml
```

```text
2026-09-26T12:48:10.093+02:00 [info    ] valid                          [validation] code=echo-transform document=pipelines/echo-transform.yaml checked="document and installed blocks"
  each step under the last one it waits for
    readings  (playground.generate)
      active  (filter.jq)
        fahrenheit  (map.jq)
          summary  (transform.jq)
            say  (log.write)
2026-09-26T12:48:10.097+02:00 [info    ] valid                          [validated] documents=1 invalid=0
```

```bash
uv run dg run --local pipelines/echo-transform.yaml
```

```text
2026-09-26T12:48:11.456+02:00 [info    ] started                        [run] pipeline=echo-transform run_id=01a0dd54-67bc-733e-a811-7fab12e52dcc local=true scratch=file:///tmp/dirigent-local-1zvmdg6a/artifacts/runs/01a0dd54-67bc-733e-a811-7fab12e52dcc root=/tmp/dirigent-local-1zvmdg6a
2026-09-26T12:48:11.451+02:00 [info    ] queued                         [step readings] block=playground.generate attempt=1
2026-09-26T12:48:11.517+02:00 [info    ] playground generated           [log readings] rows=4 seed=384415594 locale=en_US drift=none
2026-09-26T12:48:11.517+02:00 [info    ] succeeded                      [step readings] block=playground.generate attempt=1 duration_ms=31
2026-09-26T12:48:11.570+02:00 [info    ] running                        [step active] block=filter.jq attempt=1
2026-09-26T12:48:11.599+02:00 [info    ] succeeded                      [step active] block=filter.jq attempt=1 duration_ms=29
2026-09-26T12:48:11.602+02:00 [info    ] finished                       [log active] duration_ms=25 output_bytes=243
2026-09-26T12:48:11.637+02:00 [info    ] succeeded                      [step fahrenheit] block=map.jq attempt=1 duration_ms=5
2026-09-26T12:48:11.637+02:00 [info    ] queued                         [step summary] block=transform.jq attempt=1
2026-09-26T12:48:11.639+02:00 [info    ] finished                       [log fahrenheit] duration_ms=2 output_bytes=194
2026-09-26T12:48:11.695+02:00 [info    ] succeeded                      [step summary] block=transform.jq attempt=1 duration_ms=8
2026-09-26T12:48:11.698+02:00 [info    ] finished                       [log summary] duration_ms=2 output_bytes=106
2026-09-26T12:48:11.751+02:00 [info    ] the three verbs are done       [log say] value={"stations":3,"regions":["east","north","west"],"warmest":"bergen-florida","mean_fahrenheit":42}
2026-09-26T12:48:11.751+02:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=5
2026-09-26T12:48:11.822+02:00 [info    ] succeeded                      [run] pipeline=echo-transform run_id=01a0dd54-67bc-733e-a811-7fab12e52dcc exit_code=0
steps
┏━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step       ┃ block               ┃ outcome   ┃ after      ┃ duration ┃ output                    ┃
┡━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ readings   │ playground.generate │ succeeded │ -          │ 0.0s     │ records=[4 items]  rows=4 │
│            │                     │           │            │          │ seed=384415594            │
│            │                     │           │            │          │ locale=en_US  fields={3   │
│            │                     │           │            │          │ keys}  drift=none         │
│            │                     │           │            │          │ delay_ms=0  attempt=1     │
│            │                     │           │            │          │ fail_until=0              │
│            │                     │           │            │          │ input_rows=4              │
│ active     │ filter.jq           │ succeeded │ readings   │ 0.0s     │ value=[3 items]           │
│ fahrenheit │ map.jq              │ succeeded │ active     │ 0.0s     │ value=[3 items]           │
│ summary    │ transform.jq        │ succeeded │ fahrenheit │ 0.0s     │ value={4 keys}            │
│ say        │ log.write           │ succeeded │ summary    │ 0.0s     │ value={4 keys}            │
└────────────┴─────────────────────┴───────────┴────────────┴──────────┴───────────────────────────┘
```

Read the two middle rows together: `active` answered with three items where four went in, and
`fahrenheit` answered with three where three went in. Those two numbers are the verbs' whole
contract, visible without reading a single jq program.

`log.write` hands its value on as its own output, so the sink is a pass-through rather than a
dead end and the summary is in the run as well as in the log line:

```bash
uv run dg run --local pipelines/echo-transform.yaml --json \
  | jq -s 'last | .steps[] | select(.step == "say") | .output.value'
```

```json
{
  "stations": 3,
  "regions": [
    "east",
    "north",
    "west"
  ],
  "warmest": "bergen-florida",
  "mean_fahrenheit": 42
}
```

## The document, hop by hop

`pipelines/echo-transform.yaml` opens with the three contracts, because they are what the
document is for:

```yaml
# The three jq verbs, in the order a reshape usually wants them, between a source and a sink.
#
# In:  a batch of station readings, carried in this document and handed over by the node.
# Out: one summary, written onto the run's own timeline.
#
# THE READ IS A NODE, NOT A CALL. playground.generate takes an `input` and hands it back, so
# the batch below is this document's own data arriving as a step's output rather than a round
# trip that pretends to fetch what it just sent. Nothing here reaches a connection, a URL, a
# network or a file. Replace `readings` with an http.request whose body the filter reads, or
# `say` with an http.request that POSTs the summary onward, and the three verbs between them
# do not move.
#
# One jq program could do all of this in a line. Three steps say what happened instead, and
# each verb has a contract the others do not:
#
#   filter.jq     runs its program once per element and keeps the elements it answers true
#                 for. The frame keeps the element, so nothing is modified and the list can
#                 only get shorter. jq's truthiness is not applied: a program answering 0 or
#                 "" is refused rather than read as false, so "has readings" is .count > 0.
#   map.jq        runs its program once per element and keeps what the program returns. One
#                 output per element, so the list is exactly as long as the one that went
#                 in; a program emitting nothing, or two things, for one element is refused.
#   transform.jq  runs one program over one whole value. This is the verb for a change of
#                 shape rather than an element-wise edit.
```

The lines every document opens with, the tags a reader filters by, and the five block ids
this one needs of an instance:

```yaml
format: dirigent/v1
kind: pipeline
code: echo-transform
name: Filter, map, transform
description: |
  A batch narrowed with `filter.jq`, converted element by element with `map.jq`, reduced
  with `transform.jq`, and written onto the run's timeline.

  Each verb carries its own contract: a filter cannot modify, a map cannot change the
  length, and only the transform reshapes the whole value.

tags: [transform, playground, filter, map, jq]

requires:
  blocks:
    - playground.generate
    - filter.jq
    - map.jq
    - transform.jq
    - log.write

params:
  type: object
  properties:
    keep:
      type: string
      default: active
      description: The status the filter keeps. Set it to retired to narrow to the other one.
```

**`readings`** is the source. The batch is written into the node's `input`, and because no
`fields:` are named it travels through untouched and becomes the node's records -- so every
step after this one is working on a step's output, exactly as it would against a real service:

```yaml
steps:
  readings:
    block: playground.generate
    config:
      # No fields: are named, so the list travels through untouched and each element is one
      # of the node's records.
      input:
        - { station: bergen-florida, region: west, status: active, celsius: 12.4 }
        - { station: oslo-blindern, region: east, status: active, celsius: 3.1 }
        - { station: tromso-langnes, region: north, status: retired, celsius: -6.8 }
        - { station: trondheim-voll, region: north, status: active, celsius: 1.2 }
```

**`active`** narrows. The program is a predicate and nothing else: whatever it answers true
for comes out unchanged, which is why a filter can never quietly edit a row on its way past:

```yaml
  active:
    block: filter.jq
    depends_on: [readings]
    config:
      input: ${steps.readings.output.records}
      # The program's answer is the verdict and nothing else. The element that comes out is
      # the element that went in, which is why a filter can never quietly edit a row.
      program: |
        .status == "${params.keep}"
```

**`fahrenheit`** converts. One output per element, so this list is exactly as long as the one
above it -- and a program that emitted nothing for an element would be refused rather than
silently shortening the batch:

```yaml
  fahrenheit:
    block: map.jq
    depends_on: [active]
    config:
      input: ${steps.active.output.value}
      # One output per element, so this list is exactly as long as the one above it.
      program: |
        {station, region, fahrenheit: (.celsius * 9 / 5 + 32 | round)}
```

**`summary`** is the one that could not have been either of the others: a list goes in and one
object comes out:

```yaml
  summary:
    block: transform.jq
    depends_on: [fahrenheit]
    config:
      input: ${steps.fahrenheit.output.value}
      # A whole-value reshape: the list goes in and one object comes out, which is the one
      # thing neither of the other two verbs can do.
      program: |
        {stations: length,
         regions: (map(.region) | unique),
         warmest: (max_by(.fahrenheit) | .station),
         mean_fahrenheit: ((map(.fahrenheit) | add) / length | round)}
```

**`say`** reads out of `summary` rather than out of `readings`. Every value that leaves this
pipeline went through all three verbs, and nothing can take a shortcut past them:

```yaml
  say:
    block: log.write
    depends_on: [summary]
    config:
      message: the three verbs are done
      # Built from the transform's output rather than from the source, so what lands carries
      # what the three verbs made and nothing that skipped them.
      value: ${steps.summary.output.value}
```

`-p keep=retired` runs the same document against the other half of the batch: one station
survives the filter, one is converted, and the summary is over one row. Nothing else changes,
because nothing in the document was written for three.

## Where to go next

- [`echo-schedule`](../echo-schedule/README.md) is what comes next: the two things that start
  a run with nobody typing a command, a clock and a POST, both declared in the document.
- [**The basics**](https://winterop-com.github.io/dirigent/basics/) is the tutorial these
  examples follow: one read, a schema gate on the answer, and a send built from the value
  that passed.
- [**The examples**](../README.md): every example in order, and what you need once.
