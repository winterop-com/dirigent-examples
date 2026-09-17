# echo-fanout

One step, one list, one run item per element -- and one of the stations is down. This is the
shape every batch takes: you have a list of things to ask, each answer is independent of the
others, and exactly one of them will be broken on the morning it matters. `for_each` maps the
step over the list, `items: continue` decides what the broken one costs, and the step after it
reads what actually came back. The sharp edge is in that last clause: **a failed item is
absent from the step's output, not null**, so a join that counts rows is counting survivors.
This example makes the run settle `completed_with_errors` on purpose, and then names the
station that never answered.

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

```text
$ uv run dg validate pipelines/echo-fanout.yaml
2026-09-17T15:09:25.007+02:00 [info    ] valid                          [validation] code=echo-fanout document=pipelines/echo-fanout.yaml checked="document, offline"
  each step under the last one it waits for
    ask  (http.request)
      report  (transform.jq)
2026-09-17T15:09:25.011+02:00 [info    ] valid                          [validated] documents=1 invalid=0

$ uv run dg run --local pipelines/echo-fanout.yaml
2026-09-17T15:09:26.394+02:00 [info    ] started                        [run] pipeline=echo-fanout run_id=01a0af7c-7cbe-73c6-9a48-7f41c9343cb9 local=true scratch=file:///var/folders/7t/m0y6vhq508n4fsfg85vhgjkh0000gp/T/dirigent-local-i6adr05u/artifacts/runs/01a0af7c-7cbe-73c6-9a48-7f41c9343cb9 root=/var/folders/7t/m0y6vhq508n4fsfg85vhgjkh0000gp/T/dirigent-local-i6adr05u
2026-09-17T15:09:26.333+02:00 [info    ] queued                         [step ask[0]] block=http.request attempt=1
2026-09-17T15:09:26.333+02:00 [info    ] queued                         [step ask[1]] block=http.request attempt=1
2026-09-17T15:09:26.333+02:00 [info    ] queued                         [step ask[2]] block=http.request attempt=1
2026-09-17T15:09:26.426+02:00 [info    ] running                        [step ask[0]] block=http.request attempt=1
2026-09-17T15:09:26.465+02:00 [info    ] running                        [step ask[1]] block=http.request attempt=1
2026-09-17T15:09:26.470+02:00 [info    ] running                        [step ask[2]] block=http.request attempt=1
2026-09-17T15:09:26.682+02:00 [info    ] http call                      [log ask[2]] method=GET url=https://postman-echo.com/get status=200 bytes=273 duration_ms=207
2026-09-17T15:09:26.683+02:00 [info    ] succeeded                      [step ask[2]] block=http.request attempt=1 duration_ms=213
2026-09-17T15:09:26.689+02:00 [info    ] http call                      [log ask[0]] method=GET url=https://postman-echo.com/get status=200 bytes=273 duration_ms=252
2026-09-17T15:09:26.690+02:00 [info    ] succeeded                      [step ask[0]] block=http.request attempt=1 duration_ms=264
2026-09-17T15:09:26.695+02:00 [info    ] http call                      [log ask[1]] method=GET url=https://postman-echo.com/status/500 status=500 bytes=14 duration_ms=226
2026-09-17T15:09:26.698+02:00 [info    ] failed                         [step ask[1]] block=http.request attempt=1 duration_ms=233
2026-09-17T15:09:26.777+02:00 [info    ] succeeded                      [step report] block=transform.jq attempt=1 duration_ms=30
2026-09-17T15:09:26.779+02:00 [info    ] finished                       [log report] duration_ms=25 output_bytes=109
2026-09-17T15:09:26.825+02:00 [error   ] completed_with_errors          [run] pipeline=echo-fanout run_id=01a0af7c-7cbe-73c6-9a48-7f41c9343cb9 exit_code=0
steps                                                                                             
┏━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step   ┃ block        ┃ outcome   ┃ after ┃ duration ┃ output                                  ┃
┡━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask[0] │ http.request │ succeeded │ -     │ 0.3s     │ status=200  headers={12 keys}  body={3  │
│        │              │           │       │          │ keys}  body_bytes=273  duration_ms=252  │
│ ask[1] │ http.request │ failed    │ -     │ 0.2s     │ -                                       │
│ ask[2] │ http.request │ succeeded │ -     │ 0.2s     │ status=200  headers={12 keys}  body={3  │
│        │              │           │       │          │ keys}  body_bytes=273  duration_ms=207  │
│ report │ transform.jq │ succeeded │ ask   │ 0.0s     │ value={4 keys}                          │
└────────┴──────────────┴───────────┴───────┴──────────┴─────────────────────────────────────────┘

ask failed  http.request, attempt 1, transient
  GET https://postman-echo.com/status/500 answered 500
  last log lines:
    info: http call
warning the run completed with errors; --strict would fail on this
```

`ask` is one step in the document and three rows here, one per item, with the item's index in
the name. Two of them went out at once; the third was answered 500 and is the only red row.
The step below them still ran, because under `continue` the step counts as succeeded.

`completed_with_errors` is a status of its own rather than a shade of `failed`, and `dg` exits
0 on it with a warning -- `--strict` is what turns that warning into a failure in CI.

The answer itself is in the run rather than on the screen, and every command writes records
into a pipe, so the whole of it is one `jq` away:

```text
$ uv run dg run --local pipelines/echo-fanout.yaml --json \
    | jq -s 'last | .steps[] | select(.step == "report") | .output.value'
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
# One read per station, and a station that is down does not take the others with it.
#
# In:  a list of stations, each with the reading it reports and the endpoint it answers at.
# Out: one summary naming the stations that answered and the one that did not.
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
#
# Hop by hop:
#
#   ask      one http.request per station. Two are asked at /get, which answers with the
#            query arguments it was given; oslo-blindern is asked at /status/500, standing
#            in for a station whose service is down.
#   report   the join. It has no for_each of its own, which is the entire mechanism: one
#            attempt, and the batch arrives as a JSON array of the items' outputs.
#
# EXPECT THIS RUN TO END completed_with_errors, with two succeeded items, one failed item,
# a succeeded step, and oslo-blindern named under missing.
#
#   uv run dg run --local pipelines/echo-fanout.yaml
#   uv run dg run --local pipelines/echo-fanout.yaml \
#     -p stations='[{"station":"bergen-florida","reading":"12.4","endpoint":"get"}]'
```

Then the lines every document opens with, the tags a reader filters by, and what this one
needs of an instance. An instance missing a block a document requires refuses the document
rather than failing halfway through a run:

```yaml
format: dirigent/v1
kind: pipeline
code: echo-fanout
name: One read per station
description: |
  A fan-out over a list of stations, one HTTP read each, tolerating the station whose
  service is down.

  A failed item is absent from the step's output, so the join is computed from what
  answered rather than from the width that was asked for.

tags: [graph, http, transform, fan-out]

requires:
  blocks:
    - http.request
    - transform.jq
```

The grid is a parameter, so the same document runs against one station or sixteen without
being edited. Each element is an object rather than a string, because one station carries
three facts: what it is called, what it reports, and where it answers:

```yaml
params:
  type: object
  properties:
    stations:
      type: array
      description: One item, one read, per element.
      minItems: 1
      maxItems: 16
      default:
        - { station: bergen-florida, reading: "12.4", endpoint: get }
        # Postman Echo answers /status/500 with that status and nothing else, which is how
        # one element of this grid fails without anything else in the document changing.
        - { station: oslo-blindern, reading: "3.1", endpoint: status/500 }
        - { station: tromso-langnes, reading: "-6.8", endpoint: get }
      items:
        type: object
        required: [station, reading, endpoint]
        properties:
          station:
            type: string
            minLength: 1
          reading:
            type: string
          endpoint:
            type: string
        additionalProperties: false
```

**`ask`** is the fan-out. `for_each` reads the parameter, and `${item}` is the element this
run item is for, reached into with a dot exactly like a step's output. One step definition,
three run items, each with its own attempt, its own error and its own retry budget:

```yaml
steps:
  ask:
    block: http.request
    # ${item} is the element itself, so an element that is an object is reached into with a
    # dot the same way a step's output is.
    for_each: ${params.stations}
    items: continue
    config:
      url: https://postman-echo.com/${item.endpoint}
      method: GET
      query:
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
        | [.answered[].body.args.station] as $answered
        | {asked: ($asked | length),
           answered: ($answered | length),
           stations: $answered,
           missing: ($asked - $answered)}
```

Change one word in `ask` and the run changes shape. Under the default, `items: fail_fast`,
the failed item fails the step, `report` is skipped behind it, and the run ends `failed`. Run
it both ways: that pair is the decision this document is really about.

## Where to go next

- [**The basics**](https://winterop-com.github.io/dirigent/basics/) is the tutorial these
  examples follow: one read, a schema gate on the answer, and a send built from the value
  that passed.
- [**echo-retry**](../echo-retry/README.md) is the failure beside this one, told properly:
  the 500 that failed an item here is `transient` and would have been retried under a budget,
  where a 404 is `rejected` and never is.
