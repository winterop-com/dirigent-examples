# echo-transform

Between a read and a send, something almost always has to be reshaped -- and dirigent gives
you three verbs to do it with rather than one. `filter.jq` narrows a list without touching
what stays, `map.jq` replaces every element with one thing, and `transform.jq` reshapes the
whole value at once. One jq program could do all three jobs in a line; three steps say which
job was done. That matters when somebody reads the document a year later and wants to know
whether it dropped rows, added rows, or edited them in place -- so this example does one
thing per step, on a batch it reads back out of Postman Echo's own answer, and POSTs the
result onward.

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
given, and that what Postman Echo received is what the transform built.

## What you see

```text
$ uv run dg validate pipelines/echo-transform.yaml
2026-09-17T15:11:59.021+02:00 [info    ] valid                          [validation] code=echo-transform document=pipelines/echo-transform.yaml checked="document, offline"
  each step under the last one it waits for
    ask  (http.request)
      active  (filter.jq)
        fahrenheit  (map.jq)
          summary  (transform.jq)
            send  (http.request)
2026-09-17T15:11:59.024+02:00 [info    ] valid                          [validated] documents=1 invalid=0

$ uv run dg run --local pipelines/echo-transform.yaml
2026-09-17T15:12:00.293+02:00 [info    ] started                        [run] pipeline=echo-transform run_id=01a0af7e-d621-7056-a3be-84ed3d786eca local=true scratch=file:///var/folders/7t/m0y6vhq508n4fsfg85vhgjkh0000gp/T/dirigent-local-aa42ai_y/artifacts/runs/01a0af7e-d621-7056-a3be-84ed3d786eca root=/var/folders/7t/m0y6vhq508n4fsfg85vhgjkh0000gp/T/dirigent-local-aa42ai_y
2026-09-17T15:12:00.289+02:00 [info    ] queued                         [step ask] block=http.request attempt=1
2026-09-17T15:12:00.372+02:00 [info    ] running                        [step ask] block=http.request attempt=1
2026-09-17T15:12:00.632+02:00 [info    ] http call                      [log ask] method=POST url=https://postman-echo.com/post status=200 bytes=941 duration_ms=226
2026-09-17T15:12:00.634+02:00 [info    ] succeeded                      [step ask] block=http.request attempt=1 duration_ms=262
2026-09-17T15:12:00.678+02:00 [info    ] succeeded                      [step active] block=filter.jq attempt=1 duration_ms=29
2026-09-17T15:12:00.681+02:00 [info    ] finished                       [log active] duration_ms=25 output_bytes=243
2026-09-17T15:12:00.721+02:00 [info    ] succeeded                      [step fahrenheit] block=map.jq attempt=1 duration_ms=8
2026-09-17T15:12:00.721+02:00 [info    ] queued                         [step summary] block=transform.jq attempt=1
2026-09-17T15:12:00.722+02:00 [info    ] finished                       [log fahrenheit] duration_ms=4 output_bytes=194
2026-09-17T15:12:00.780+02:00 [info    ] succeeded                      [step summary] block=transform.jq attempt=1 duration_ms=8
2026-09-17T15:12:00.781+02:00 [info    ] finished                       [log summary] duration_ms=4 output_bytes=106
2026-09-17T15:12:00.831+02:00 [info    ] running                        [step send] block=http.request attempt=1
2026-09-17T15:12:01.271+02:00 [info    ] http call                      [log send] method=POST url=https://postman-echo.com/post status=200 bytes=480 duration_ms=436
2026-09-17T15:12:01.273+02:00 [info    ] succeeded                      [step send] block=http.request attempt=1 duration_ms=442
2026-09-17T15:12:01.349+02:00 [info    ] succeeded                      [run] pipeline=echo-transform run_id=01a0af7e-d621-7056-a3be-84ed3d786eca exit_code=0
steps                                                                                             
┏━━━━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step       ┃ block        ┃ outcome   ┃ after      ┃ duration ┃ output                         ┃
┡━━━━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask        │ http.request │ succeeded │ -          │ 0.3s     │ status=200  headers={12 keys}  │
│            │              │           │            │          │ body={7 keys}  body_bytes=941  │
│            │              │           │            │          │ duration_ms=226                │
│ active     │ filter.jq    │ succeeded │ ask        │ 0.0s     │ value=[3 items]                │
│ fahrenheit │ map.jq       │ succeeded │ active     │ 0.0s     │ value=[3 items]                │
│ summary    │ transform.jq │ succeeded │ fahrenheit │ 0.0s     │ value={4 keys}                 │
│ send       │ http.request │ succeeded │ summary    │ 0.4s     │ status=200  headers={12 keys}  │
│            │              │           │            │          │ body={7 keys}  body_bytes=480  │
│            │              │           │            │          │ duration_ms=436                │
└────────────┴──────────────┴───────────┴────────────┴──────────┴────────────────────────────────┘
```

Read the two middle rows together: `active` answered with three items where four went in, and
`fahrenheit` answered with three where three went in. Those two numbers are the verbs' whole
contract, visible without reading a single jq program.

Postman Echo answers a POST with the body it was given, so its answer to `send` is the proof
of what was sent:

```text
$ uv run dg run --local pipelines/echo-transform.yaml --json \
    | jq -s 'last | .steps[] | select(.step == "send") | .output.body.json'
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
# The three jq verbs, in the order a reshape usually wants them, between a read and a send.
#
# In:  a batch of station readings, POSTed to Postman Echo and read back out of its answer.
# Out: a summary POSTed onward, and the echo of that send as the proof of what was sent.
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
#
# Every program is compiled when the document is applied, so a syntax error is refused at
# steps.<name>.config rather than at three in the morning.
#
# Hop by hop:
#
#   ask          POST the batch to /post, which answers with the body it was given under
#                json. This stands in for the read: the list arrives from somewhere else.
#   active       keep the stations still reporting. Four in, three out.
#   fahrenheit   convert each survivor. Three in, three out, by the verb's contract.
#   summary      one program over the whole list: a count, the regions, the warmest.
#   send         POST the summary onward, built from the value the transform produced.
#
# EXPECT THIS RUN TO SUCCEED in about a second, with send's answer echoing the summary.
#
#   uv run dg run --local pipelines/echo-transform.yaml
#   uv run dg run --local pipelines/echo-transform.yaml -p keep=retired
```

The lines every document opens with, the tags a reader filters by, and the four block ids
this one needs of an instance:

```yaml
format: dirigent/v1
kind: pipeline
code: echo-transform
name: Filter, map, transform, send
description: |
  A batch read back out of Postman Echo's answer, narrowed with `filter.jq`, converted
  element by element with `map.jq`, reduced with `transform.jq`, and POSTed onward.

  Each verb carries its own contract: a filter cannot modify, a map cannot change the
  length, and only the transform reshapes the whole value.

tags: [transform, http, filter, map, jq]

requires:
  blocks:
    - http.request
    - filter.jq
    - map.jq
    - transform.jq

params:
  type: object
  properties:
    keep:
      type: string
      default: active
      description: The status the filter keeps. Set it to retired to narrow to the other one.
```

**`ask`** is the read. The batch is written into the request so the example needs nothing
standing up, and Postman Echo hands it straight back -- which means every step after this one
is working on an answer that arrived over the wire, exactly as it would against a real
service:

```yaml
steps:
  ask:
    block: http.request
    config:
      url: https://postman-echo.com/post
      method: POST
      # /post answers with the body it was given, so the batch below comes back under
      # .body.json and every step after this one reads the answer rather than the literal.
      body:
        readings:
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
    depends_on: [ask]
    config:
      input: ${steps.ask.output.body.json.readings}
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

**`send`** reads out of `summary` rather than out of `ask`. Every value that leaves this
pipeline went through all three verbs, and nothing can take a shortcut past them:

```yaml
  send:
    block: http.request
    depends_on: [summary]
    config:
      url: https://postman-echo.com/post
      method: POST
      # Built from the transform's output rather than from the read's, so the send carries
      # what the three verbs made and nothing that skipped them.
      body: ${steps.summary.output.value}
```

`-p keep=retired` runs the same document against the other half of the batch: one station
survives the filter, one is converted, and the summary is over one row. Nothing else changes,
because nothing in the document was written for three.

## Where to go next

- [**The basics**](https://winterop-com.github.io/dirigent/basics/) is the tutorial these
  examples follow: one read, a schema gate on the answer, and a send built from the value
  that passed.
- [**echo-gate**](../echo-gate/README.md) is the step that belongs in front of a reshape: a
  schema the answer is held to, so a payload that has moved stops where it arrived rather
  than reaching a jq program written for the shape it used to have.
