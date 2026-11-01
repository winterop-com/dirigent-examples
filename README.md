# echo-fanout

One step, one list, one run item per element -- and one of the stations is down. This is the
shape every batch takes: you have a list of things to ask, each answer is independent of the
others, and exactly one of them will be broken on the morning it matters. `for_each` maps the
step over the list, `items: continue` decides what the broken one costs, and the step after it
reads what actually came back. The sharp edge is in that last clause: **a failed item is
absent from the step's output, not null**, so a join that counts rows is counting survivors.
This example makes the run settle `completed_with_errors` on purpose, and then names the
station that never answered.

## This one needs no network

The read is a node, not a call. `playground.generate` takes an `input` and hands it back, and
its `fail_until` knob makes a step fail on cue -- so the station that is down is a number on an
element rather than an endpoint somewhere that has to be answering. The document reaches
nothing: no connection, no URL, no network, no file. Replacing `ask` with an `http.request`
whose answer the join reads changes that one step and nothing under it.

## Run it

Everything here runs without a server. `dg run --local` applies and runs the document in a
throwaway instance in a temporary directory and deletes it on the way out -- the same apply,
the same engine, the same worker loop.

```bash
uv sync
uv run dg validate pipelines/echo-fanout.yaml
uv run dg run --local pipelines/echo-fanout.yaml
```

`./verify.sh` does exactly that and asserts on the records it gets back.

## What you see

*Printed as it printed, with this project's directory written as `/home/you/echo-fanout` and a
local run's temporary root as `/tmp`.*

```bash
uv run dg validate pipelines/echo-fanout.yaml
```

```text
2026-09-26T12:45:48.060+02:00 [info    ] valid                          [validation] code=echo-fanout document=pipelines/echo-fanout.yaml checked="document and installed blocks"
  each step under the last one it waits for
    ask  (playground.generate)
      report  (transform.jq)
2026-09-26T12:45:48.064+02:00 [info    ] valid                          [validated] documents=1 invalid=0 skipped=0
```

```bash
uv run dg run --local pipelines/echo-fanout.yaml
```

```text
2026-09-26T12:45:49.392+02:00 [info    ] started                        [run] pipeline=echo-fanout run_id=01a0dd52-3cc8-7555-a4a3-7d581d8846ae local=true scratch=file:///tmp/dirigent-local-gt5qblom/artifacts/runs/01a0dd52-3cc8-7555-a4a3-7d581d8846ae root=/tmp/dirigent-local-gt5qblom
2026-09-26T12:45:49.383+02:00 [info    ] queued                         [step ask[0]] block=playground.generate attempt=1
2026-09-26T12:45:49.383+02:00 [info    ] queued                         [step ask[1]] block=playground.generate attempt=1
2026-09-26T12:45:49.383+02:00 [info    ] queued                         [step ask[2]] block=playground.generate attempt=1
2026-09-26T12:45:49.457+02:00 [info    ] playground generated           [log ask[0]] rows=1 seed=852630996 locale=en_US drift=none
2026-09-26T12:45:49.457+02:00 [info    ] succeeded                      [step ask[0]] block=playground.generate attempt=1 duration_ms=34
2026-09-26T12:45:49.461+02:00 [info    ] failed                         [step ask[1]] block=playground.generate attempt=1 duration_ms=4
2026-09-26T12:45:49.461+02:00 [info    ] queued                         [step report] block=transform.jq attempt=1
2026-09-26T12:45:49.471+02:00 [info    ] playground generated           [log ask[2]] rows=1 seed=491364487 locale=en_US drift=none
2026-09-26T12:45:49.471+02:00 [info    ] succeeded                      [step ask[2]] block=playground.generate attempt=1 duration_ms=10
2026-09-26T12:45:49.486+02:00 [error   ] failed                         [log ask[1]] duration_ms=0 error_class=transient error_code=playground.failed_on_purpose error="the playground failed attempt 1 on purpose, because fail_until is 1; attempt 2 will succeed"
2026-09-26T12:45:49.551+02:00 [info    ] succeeded                      [step report] block=transform.jq attempt=1 duration_ms=28
2026-09-26T12:45:49.553+02:00 [info    ] finished                       [log report] duration_ms=25 output_bytes=109
2026-09-26T12:45:49.659+02:00 [error   ] completed_with_errors          [run] pipeline=echo-fanout run_id=01a0dd52-3cc8-7555-a4a3-7d581d8846ae exit_code=0
steps
┏━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step           ┃ block               ┃ outcome   ┃ after ┃ duration ┃ output                     ┃
┡━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask[0]         │ playground.generate │ succeeded │ -     │ 0.0s     │ records=[1 items]  rows=1  │
│                │                     │           │       │          │ seed=852630996             │
│                │                     │           │       │          │ locale=en_US  fields={3    │
│                │                     │           │       │          │ keys}  drift=none          │
│                │                     │           │       │          │ delay_ms=0  attempt=1      │
│                │                     │           │       │          │ fail_until=0  input_rows=1 │
│ ask[1]  1 warn │ playground.generate │ failed    │ -     │ 0.0s     │ -                          │
│ ask[2]         │ playground.generate │ succeeded │ -     │ 0.0s     │ records=[1 items]  rows=1  │
│                │                     │           │       │          │ seed=491364487             │
│                │                     │           │       │          │ locale=en_US  fields={3    │
│                │                     │           │       │          │ keys}  drift=none          │
│                │                     │           │       │          │ delay_ms=0  attempt=1      │
│                │                     │           │       │          │ fail_until=0  input_rows=1 │
│ report         │ transform.jq        │ succeeded │ ask   │ 0.0s     │ value={4 keys}             │
└────────────────┴─────────────────────┴───────────┴───────┴──────────┴────────────────────────────┘

ask failed  playground.generate, attempt 1, transient
  the playground failed attempt 1 on purpose, because fail_until is 1; attempt 2 will succeed
  last log lines:
    error: failed
warning the run completed with errors; --strict would fail on this
```

`ask` is one step in the document and three rows here, one per item, with the item's index in
the name. Two of them generated their reading; the third had `fail_until: 1` on its element and
is the only red row. The step below them still ran, because under `continue` the step counts as
succeeded. The failure is classified `transient`, which is what a retry budget is for -- there
is none on this step, so one attempt is all it gets.

`completed_with_errors` is a status of its own rather than a shade of `failed`, and `dg` exits
0 on it with a warning -- `--strict` is what turns that warning into a failure in CI.

The answer itself is in the run rather than on the screen, and every command writes records
into a pipe, so the whole of it is one `jq` away:

```bash
uv run dg run --local pipelines/echo-fanout.yaml --json \
  | jq -s 'last | .steps[] | select(.step == "report") | .output.value'
```

```json
{
  "asked": 3,
  "answered": 2,
  "stations": [
    "bergen-florida",
    "tromso-langnes"
  ],
  "missing": [
    "oslo-blindern"
  ]
}
```

Three asked, two answered, and the one that did not is named. That is what handing the join
both lists buys.

## The document, hop by hop

`pipelines/echo-fanout.yaml` opens by saying what to expect before you run it, which is worth
having on a document that ends red on purpose:

```yaml
# One reading per station, and a station that is down does not take the others with it.
#
# In:  a list of stations, each with the reading it reports and how many of its attempts fail.
# Out: one summary naming the stations that answered and the one that did not.
#
# THE READ IS A NODE, NOT A CALL. playground.generate takes an `input` and hands it back, and
# `fail_until` makes it fail on cue -- so this document reaches nothing: no connection, no
# URL, no network. Replacing `ask` with an http.request whose answer the join reads changes
# that one step and nothing under it.
#
# for_each maps one step over a list, with one run item per element. The grid is expanded
# when the run is created, so it may read params, run and item -- never another step's
# output, because the width has to be known before anything executes.
#
# items: continue is the whole lesson. Under the default, fail_fast, the first item that
# fails fails the step and every station after it is abandoned. Under continue the failure
# is recorded against its own item, the other stations finish, the step still counts as
# succeeded, and the run settles completed_with_errors -- a third status, not a shade of
# failed.
#
# The sharp edge comes with it: a failed item is ABSENT from the step's output list, not
# null. So the list the join reads is shorter than the grid that was asked for, index 0 is
# the first station that answered rather than the first one asked, and a join that counts
# rows is counting survivors. That is why the join below is handed the grid as well as the
# answers, and computes the difference instead of assuming three.
```

Then the lines every document opens with, the tags a reader filters by, and what this one
needs of an instance. An instance missing a block a document requires refuses the document
rather than failing halfway through a run:

```yaml
format: dirigent/v1
kind: pipeline
code: echo-fanout
name: One reading per station
description: |
  A fan-out over a list of stations, one generated reading each, tolerating the station
  whose service is down.

  A failed item is absent from the step's output, so the join is computed from what
  answered rather than from the width that was asked for.

tags: [graph, playground, transform, fan-out]

requires:
  blocks:
    - playground.generate
    - transform.jq
```

The grid is a parameter, so the same document runs against one station or sixteen without
being edited. Each element is an object rather than a string, because one station carries
three facts: what it is called, what it reports, and whether it is answering:

```yaml
params:
  type: object
  properties:
    stations:
      type: array
      description: One item, one reading, per element.
      minItems: 1
      maxItems: 16
      default:
        - { station: bergen-florida, reading: "12.4", fail_until: 0 }
        # fail_until above this item's attempt count is how one element of the grid fails
        # without anything else in the document changing. There is no retry policy here,
        # so 1 is enough.
        - { station: oslo-blindern, reading: "3.1", fail_until: 1 }
        - { station: tromso-langnes, reading: "-6.8", fail_until: 0 }
      items:
        type: object
        required: [station, reading, fail_until]
        properties:
          station:
            type: string
            minLength: 1
          reading:
            type: string
          fail_until:
            type: integer
            minimum: 0
            maximum: 9
        additionalProperties: false
```

**`ask`** is the fan-out. `for_each` reads the parameter, and `${item}` is the element this
run item is for, reached into with a dot exactly like a step's output. One step definition,
three run items, each with its own attempt, its own error and its own retry budget:

```yaml
steps:
  ask:
    block: playground.generate
    # ${item} is the element itself, so an element that is an object is reached into with a
    # dot the same way a step's output is.
    for_each: ${params.stations}
    items: continue
    config:
      fail_until: ${item.fail_until}
      # No fields: are named, so the input travels through untouched and becomes this item's
      # one record.
      input:
        station: ${item.station}
        reading: ${item.reading}
```

**`report`** is the join, and there is no keyword for it: a step joins a fan-out by depending
on it and having no `for_each` of its own. One attempt, and the batch arrives as a JSON array
of the items' outputs -- the ones that succeeded:

```yaml
  report:
    block: transform.jq
    depends_on: [ask]
    config:
      # Both the grid and the answers, because the difference between them is the point.
      input:
        asked: ${params.stations}
        answered: ${steps.ask.output}
      program: |
        (.asked | map(.station)) as $asked
        | [.answered[].records[].station] as $answered
        | {asked: ($asked | length),
           answered: ($answered | length),
           stations: $answered,
           missing: ($asked - $answered)}
```

Change one word in `ask` and the run changes shape. Under the default, `items: fail_fast`,
the failed item fails the step, `report` is skipped behind it, and the run ends `failed`. Run
it both ways: that pair is the decision this document is really about.

## Where to go next

- [`echo-transform`](../echo-transform/README.md) is what comes next: the three jq verbs, and
  what each one is allowed to do to a list on its way past.
- [**The basics**](https://winterop-com.github.io/dirigent/basics/) is the tutorial these
  examples follow: one read, a schema gate on the answer, and a send built from the value
  that passed.
- [**The examples**](../README.md): every example in order, and what you need once.
