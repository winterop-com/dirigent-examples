# echo-stream

Data that turns up over time, four ways, reading forward from the simplest. A **sensor** that
waits for a batch and is handed it when it arrives; a **stream** read by an ordinary HTTP step;
the same wait against a **real Kafka topic**; and the first wait again as a **source**, which a
worker keeps poking outside any run, so batch after batch arrives in runs that overlap. The first and the third are the point of the
repository: `playground.arrive` hands over its batch in exactly the shape `kafka.consume` does --
`messages`, each with an `offset` and a `value`, and a `count` -- so the step that reads it is
the same text in both documents. Swapping the playground for a real topic changes the wait and
nothing downstream of it.

| Document | What it shows |
| --- | --- |
| `pipelines/echo-stream-wait.yaml` | `playground.arrive` parks for three pokes, then hands over a batch of four; `summarise` reads `.messages[].value`. |
| `pipelines/echo-stream-read.yaml` | `http.request` against `/api/v1/playground/stream`, and `transform.jq` splitting the NDJSON lines back into records. |
| `pipelines/echo-stream-topic.yaml` | `kafka.produce` four readings onto a Redpanda topic, `kafka.consume` them back as one batch, and the same `summarise`. |
| `pipelines/echo-stream-source.yaml` | A sensor source on `playground.arrive`: a worker pokes it outside any run, each batch that arrives becomes a run, the offsets carried on from run to run, steered with `dg source`. |

## What it needs

An instance, for the playground the stream is read from, and a broker for the third document.
Start the instance in a second terminal, in this directory:

```bash
uv run dg dev
```

On the empty state a fresh clone has, `dg dev` migrates the schema, makes its own admin `admin`,
and prints the `export DG_TOKEN=` line to paste into the first terminal. The UI is at
`http://127.0.0.1:3333`, which is where the documents' `playground` parameter points.

The broker is one Redpanda node in a container -- the image dirigent's own
`infra/compose.queues.yaml` runs -- and the topic the third document writes to. Neither block
declares a topic, so it is made by hand:

```bash
docker run -d --rm --name echo-stream-kafka -p 127.0.0.1:9092:9092 \
  redpandadata/redpanda:v24.2.18 redpanda start --mode=dev-container --smp=1 --node-id=0 \
  --check=false --kafka-addr=PLAINTEXT://0.0.0.0:9092 \
  --advertise-kafka-addr=PLAINTEXT://127.0.0.1:9092 \
  --set redpanda.auto_create_topics_enabled=false
docker exec echo-stream-kafka rpk topic create readings
```

`connections.yaml` names that broker for a local run. On the instance the connection is a
record of its own, and it carries no credential, because this broker takes none:

```bash
uv run dg connection create kafka readings --set 'bootstrap_servers=["127.0.0.1:9092"]'
```

A broker on another port is the same connection with another `bootstrap_servers`. Once
`echo-stream-topic` is applied the connection cannot be deleted, because that pipeline uses it,
so it is rewritten in place instead, straight to this instance's database:

```bash
uv run dg connection ensure kafka readings --set 'bootstrap_servers=["127.0.0.1:19092"]'
```

## Run it

```bash
uv sync
uv run dg validate
uv run dg run --local pipelines/echo-stream-wait.yaml
uv run dg run --local pipelines/echo-stream-read.yaml
uv run dg run --local pipelines/echo-stream-topic.yaml --connections connections.yaml
uv run dg run --local pipelines/echo-stream-source.yaml
```

Then on the instance, with the export line pasted:

```bash
uv run dg apply --paused
uv run dg run echo-stream-wait --watch
uv run dg run echo-stream-read --watch
uv run dg run echo-stream-topic --watch
uv run dg source resume echo-stream-source arrive
uv run dg runs list --pipeline echo-stream-source
uv run dg source pause echo-stream-source arrive
```

`--paused` creates `echo-stream-source`'s source paused, so nothing is poked until the resume; a
plain `dg apply` sets it going at once. `dg run --watch` follows one run.

`./verify.sh` does all of it non-interactively: its own instance on a free port, its own
Redpanda container on another, the topic made from this machine, every document run locally
and then on the instance, the source resumed until three runs have succeeded and then paused, and
assertions on the records each run writes: every batch starting where the one before it ended,
the first where the last pause left the cursor, a run starting while the one before it was still
working, and no run after the pause. It stops what it started.

## What you see

*Printed as it printed, with this project's directory written as `/home/you/echo-stream` and a
local run's temporary root as `/tmp`.*

### A batch that arrives

`uv run dg run --local pipelines/echo-stream-wait.yaml`:

```text
2026-09-26T19:37:08.737+02:00 [info    ] started                        [run] pipeline=echo-stream-wait run_id=01a0deca-d07d-7612-a258-802df58a8e35 local=true scratch=file:///tmp/dirigent-local-_vbfgzej/artifacts/runs/01a0deca-d07d-7612-a258-802df58a8e35 root=/tmp/dirigent-local-_vbfgzej
2026-09-26T19:37:08.733+02:00 [info    ] queued                         [step wait] block=playground.arrive attempt=1
2026-09-26T19:37:08.771+02:00 [info    ] waiting                        [step wait] block=playground.arrive attempt=1
2026-09-26T19:37:08.786+02:00 [info    ] poke 1 of 4                    [log wait]
2026-09-26T19:37:09.805+02:00 [info    ] poke 2 of 4                    [log wait]
2026-09-26T19:37:10.816+02:00 [info    ] poke 3 of 4                    [log wait]
2026-09-26T19:37:11.862+02:00 [info    ] a batch arrived                [log wait] count=4 pokes=4 seed=7
2026-09-26T19:37:11.862+02:00 [info    ] succeeded                      [step wait] block=playground.arrive attempt=1 duration_ms=3091
2026-09-26T19:37:11.862+02:00 [info    ] queued                         [step summarise] block=transform.jq attempt=1
2026-09-26T19:37:11.905+02:00 [info    ] succeeded                      [step summarise] block=transform.jq attempt=1 duration_ms=42
2026-09-26T19:37:11.908+02:00 [info    ] finished                       [log summarise] duration_ms=29 output_bytes=100
2026-09-26T19:37:12.027+02:00 [info    ] succeeded                      [run] pipeline=echo-stream-wait run_id=01a0deca-d07d-7612-a258-802df58a8e35 exit_code=0
steps
┏━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step      ┃ block             ┃ outcome   ┃ after ┃ duration ┃ output                            ┃
┡━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ wait      │ playground.arrive │ succeeded │ -     │ 3.1s     │ messages=[4 items]  count=4       │
│           │                   │           │       │          │ pokes=4  waited_ms=3061  seed=7   │
│           │                   │           │       │          │ locale=en_US  fields={2 keys}     │
│           │                   │           │       │          │ drift=none                        │
│ summarise │ transform.jq      │ succeeded │ wait  │ 0.0s     │ value={2 keys}                    │
└───────────┴───────────────────┴───────────┴───────┴──────────┴───────────────────────────────────┘
```

Three pokes park, a second apart, and the fourth hands the batch over. Between pokes the run
holds no worker slot: a sensor's wait is the engine asking again later, not a step sitting on a
thread. `uv run dg run echo-stream-wait --watch` on the instance prints the same parks as they
happen. In the UI, open the run and select the `wait` node on its graph: the step panel shows
the waiting attempt's message, `poke 1 of 4` and on, updating live as the run's events arrive:

```text
2026-09-26T19:38:05.618+02:00 [info    ] started                        [run] pipeline=echo-stream-wait run_id=01a0decb-ae98-760f-a909-aaca6b552afc local=false
2026-09-26T19:38:05.600+02:00 [info    ] queued                         [step wait] block=playground.arrive attempt=1
2026-09-26T19:38:05.927+02:00 [info    ] waiting                        [step wait] block=playground.arrive attempt=1
2026-09-26T19:38:05.966+02:00 [info    ] poke 1 of 4                    [log wait]
2026-09-26T19:38:07.012+02:00 [info    ] poke 2 of 4                    [log wait]
2026-09-26T19:38:08.041+02:00 [info    ] poke 3 of 4                    [log wait]
2026-09-26T19:38:09.110+02:00 [info    ] a batch arrived                [log wait] count=4 pokes=4 seed=7
2026-09-26T19:38:09.111+02:00 [info    ] succeeded                      [step wait] block=playground.arrive attempt=1 duration_ms=3183
2026-09-26T19:38:09.230+02:00 [info    ] succeeded                      [step summarise] block=transform.jq attempt=1 duration_ms=119
2026-09-26T19:38:09.241+02:00 [info    ] finished                       [log summarise] duration_ms=58 output_bytes=100
2026-09-26T19:38:09.939+02:00 [info    ] succeeded                      [run] pipeline=echo-stream-wait run_id=01a0decb-ae98-760f-a909-aaca6b552afc pipeline_version=1 triggered_by="admin (token dev)" duration_ms=3303 items_total=0 items_failed=0 exit_code=0 priority=normal
run 01a0decb-ae98-760f-a909-aaca6b552afc
pipeline      echo-stream-wait (version 1)
status        succeeded
triggered by  admin (token dev)
duration      3.3s
items         -

steps
┏━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━┓
┃ step      ┃ block             ┃ outcome   ┃ after ┃ attempts ┃ duration ┃ error ┃
┡━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━┩
│ wait      │ playground.arrive │ succeeded │ -     │ 1        │ 3.2s     │ -     │
│ summarise │ transform.jq      │ succeeded │ wait  │ 1        │ 0.1s     │ -     │
└───────────┴───────────────────┴───────────┴───────┴──────────┴──────────┴───────┘

outputs
┏━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step      ┃ output                                                                               ┃
┡━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ wait      │ messages=[4 items]  count=4  pokes=4  waited_ms=3137  seed=7  locale=en_US           │
│           │ fields={2 keys}  drift=none                                                          │
│ summarise │ value={2 keys}                                                                       │
└───────────┴──────────────────────────────────────────────────────────────────────────────────────┘
```

What `summarise` read out of the batch, from `uv run dg runs show <run id> --json`:

```json
{"count":4,"stations":["North Loriville","North Christopher","Brownshire","North Angela"]}
```

The stations are Faker cities, seeded, so they are these four on every machine.

### A stream, read whole

The playground's streaming route, watched live from a terminal -- the lines turn up half a second
apart:

```bash
curl -N 'http://127.0.0.1:3333/api/v1/playground/stream?messages=5&every=500ms'
```

```text
{"kind":"stream","request":{"method":"GET","url":"http://127.0.0.1:3333/api/v1/playground/stream?messages=5&every=500ms","path":"/api/v1/playground/stream","args":{"messages":"5","every":"500ms"},"headers":{"host":"127.0.0.1:3333","user-agent":"curl/8.7.1","accept":"*/*"},"body":null,"body_kind":"none","body_bytes":0,"content_type":null},"messages":5,"gap_ms":500,"payload_bytes":null}
{"kind":"stream.message","offset":0,"sent_at":"2026-09-26T17:37:12.792652Z","elapsed_ms":501,"payload":null}
{"kind":"stream.message","offset":1,"sent_at":"2026-09-26T17:37:13.293830Z","elapsed_ms":1002,"payload":null}
{"kind":"stream.message","offset":2,"sent_at":"2026-09-26T17:37:13.794966Z","elapsed_ms":1504,"payload":null}
{"kind":"stream.message","offset":3,"sent_at":"2026-09-26T17:37:14.295240Z","elapsed_ms":2004,"payload":null}
{"kind":"stream.message","offset":4,"sent_at":"2026-09-26T17:37:14.795920Z","elapsed_ms":2504,"payload":null}
{"kind":"stream.closed","messages":5,"duration_ms":2505}
```

The envelope goes out once, on the first line, and the last line says the stream closed, which
is how a reader tells an ending from a cut connection.

`uv run dg run --local pipelines/echo-stream-read.yaml`:

```text
2026-09-26T19:37:16.323+02:00 [info    ] started                        [run] pipeline=echo-stream-read run_id=01a0deca-ee14-7232-8d87-57ad9a2d6278 local=true scratch=file:///tmp/dirigent-local-339u4p1k/artifacts/runs/01a0deca-ee14-7232-8d87-57ad9a2d6278 root=/tmp/dirigent-local-339u4p1k
2026-09-26T19:37:16.306+02:00 [info    ] queued                         [step read] block=http.request attempt=1
2026-09-26T19:37:16.429+02:00 [info    ] running                        [step read] block=http.request attempt=1
2026-09-26T19:37:17.616+02:00 [info    ] http call                      [log read] method=GET url=http://127.0.0.1:3333/api/v1/playground/stream status=200 bytes=1061 duration_ms=1080
2026-09-26T19:37:17.621+02:00 [info    ] succeeded                      [step read] block=http.request attempt=1 duration_ms=1192
2026-09-26T19:37:17.730+02:00 [info    ] succeeded                      [step lines] block=transform.jq attempt=1 duration_ms=79
2026-09-26T19:37:17.746+02:00 [info    ] finished                       [log lines] duration_ms=66 output_bytes=93
2026-09-26T19:37:18.086+02:00 [info    ] succeeded                      [run] pipeline=echo-stream-read run_id=01a0deca-ee14-7232-8d87-57ad9a2d6278 exit_code=0
steps
┏━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step  ┃ block        ┃ outcome   ┃ after ┃ duration ┃ output                                     ┃
┡━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ read  │ http.request │ succeeded │ -     │ 1.2s     │ status=200  headers={7 keys}  body=<1061   │
│       │              │           │       │          │ chars>  body_bytes=1061  duration_ms=1080  │
│ lines │ transform.jq │ succeeded │ read  │ 0.1s     │ value={3 keys}                             │
└───────┴──────────────┴───────────┴───────┴──────────┴────────────────────────────────────────────┘
```

The step does not see the lines arrive. `http.request` reads the whole body and hands it on, so
`read` waits until the stream has closed and then gets every line at once, as one piece of text
-- `body=<1061 chars>` -- and `lines` splits it back into seven records.

### The same batch, off a real topic

`uv run dg run --local pipelines/echo-stream-topic.yaml --connections connections.yaml`:

```text
2026-09-26T19:37:41.355+02:00 [info    ] started                        [run] pipeline=echo-stream-topic run_id=01a0decb-4fdb-7791-8a91-4a45ebfd16ce local=true scratch=file:///tmp/dirigent-local-v5iomqpo/artifacts/runs/01a0decb-4fdb-7791-8a91-4a45ebfd16ce root=/tmp/dirigent-local-v5iomqpo
2026-09-26T19:37:41.336+02:00 [info    ] queued                         [step publish] block=kafka.produce attempt=1
2026-09-26T19:37:41.479+02:00 [info    ] running                        [step publish] block=kafka.produce attempt=1
2026-09-26T19:37:41.996+02:00 [info    ] produced                       [log publish] topic=readings produced=4 sent_bytes=224
2026-09-26T19:37:42.004+02:00 [info    ] succeeded                      [step publish] block=kafka.produce attempt=1 duration_ms=524
2026-09-26T19:37:42.005+02:00 [info    ] running                        [step wait] block=kafka.consume attempt=1
2026-09-26T19:37:42.233+02:00 [info    ] consumed                       [log wait] topic=readings count=4 group_id=echo-stream
2026-09-26T19:37:42.242+02:00 [info    ] succeeded                      [step wait] block=kafka.consume attempt=1 duration_ms=236
2026-09-26T19:37:42.279+02:00 [info    ] running                        [step summarise] block=transform.jq attempt=1
2026-09-26T19:37:42.345+02:00 [info    ] succeeded                      [step summarise] block=transform.jq attempt=1 duration_ms=66
2026-09-26T19:37:42.358+02:00 [info    ] finished                       [log summarise] duration_ms=45 output_bytes=101
2026-09-26T19:37:42.544+02:00 [info    ] succeeded                      [run] pipeline=echo-stream-topic run_id=01a0decb-4fdb-7791-8a91-4a45ebfd16ce exit_code=0
steps
┏━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step      ┃ block         ┃ outcome   ┃ after   ┃ duration ┃ output                              ┃
┡━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ publish   │ kafka.produce │ succeeded │ -       │ 0.5s     │ produced=4  topic=readings          │
│           │               │           │         │          │ offsets={1 keys}  duration_ms=405   │
│           │               │           │         │          │ sent_bytes=224                      │
│ wait      │ kafka.consume │ succeeded │ publish │ 0.2s     │ messages=[4 items]  count=4         │
│           │               │           │         │          │ cursor={1 keys}                     │
│ summarise │ transform.jq  │ succeeded │ wait    │ 0.1s     │ value={2 keys}                      │
└───────────┴───────────────┴───────────┴─────────┴──────────┴─────────────────────────────────────┘
```

And what `summarise` read, from `uv run dg runs show <run id> --json`:

```json
{"count":4,"stations":["bergen-florida","oslo-blindern","tromso-langnes","trondheim-voll"]}
```

The same program as `echo-stream-wait`'s, over the same shape. `kafka.consume` reads in the
consumer group `echo-stream`, which commits the offsets it read when its poke succeeds, so the
next run reads the four readings its own publish wrote and not the ones before them.

### A batch that keeps arriving

`uv run dg run --local pipelines/echo-stream-source.yaml` runs the pipeline once by hand. No
worker pokes anything in a local run: the run enters with the source's `sample`, a batch
`playground.arrive` arrived with, so its offsets are 0 to 2.

```text
2026-11-01T14:10:46.824+01:00 [info    ] started                        [run] pipeline=echo-stream-source run_id=01a1973b-e29d-73f8-94c5-530ab57e2d41 local=true scratch=file:///tmp/dirigent-local-x5y5hsiq/artifacts/runs/01a1973b-e29d-73f8-94c5-530ab57e2d41 root=/tmp/dirigent-local-x5y5hsiq
2026-11-01T14:10:46.631+01:00 [info    ] queued                         [step arrive] block=sensor attempt=1
2026-11-01T14:10:46.631+01:00 [info    ] running                        [step arrive] block=sensor attempt=1
2026-11-01T14:10:46.631+01:00 [info    ] succeeded                      [step arrive] block=sensor attempt=1 duration_ms=0
2026-11-01T14:10:46.631+01:00 [info    ] queued                         [step work] block=playground.generate attempt=1
2026-11-01T14:10:46.784+01:00 [info    ] received by hand               [log arrive] via=hand bytes=549
2026-11-01T14:10:47.791+01:00 [info    ] running                        [step work] block=playground.generate attempt=1
2026-11-01T14:10:55.542+01:00 [info    ] playground generated           [log work] rows=3 seed=868287513 locale=en_US drift=none
2026-11-01T14:10:55.562+01:00 [info    ] succeeded                      [step work] block=playground.generate attempt=1 duration_ms=7771
2026-11-01T14:10:55.562+01:00 [info    ] queued                         [step summarise] block=transform.jq attempt=1
2026-11-01T14:10:55.626+01:00 [info    ] running                        [step summarise] block=transform.jq attempt=1
2026-11-01T14:10:55.790+01:00 [info    ] finished                       [log summarise] duration_ms=102 output_bytes=70
2026-11-01T14:10:55.782+01:00 [info    ] succeeded                      [step summarise] block=transform.jq attempt=1 duration_ms=156
2026-11-01T14:10:56.240+01:00 [info    ] succeeded                      [run] pipeline=echo-stream-source run_id=01a1973b-e29d-73f8-94c5-530ab57e2d41 exit_code=0
steps
┏━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step      ┃ block               ┃ outcome   ┃ after  ┃ duration ┃ output                         ┃
┡━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ arrive    │ sensor              │ succeeded │ -      │ 0.0s     │ messages=[3 items]  count=3    │
│           │                     │           │        │          │ next_offset=3  pokes=2         │
│           │                     │           │        │          │ waited_ms=5176  seed=7         │
│           │                     │           │        │          │ locale=en_US  fields={2 keys}  │
│           │                     │           │        │          │ drift=none                     │
│ work      │ playground.generate │ succeeded │ arrive │ 7.8s     │ records=[3 items]  rows=3      │
│           │                     │           │        │          │ seed=868287513  locale=en_US   │
│           │                     │           │        │          │ fields={3 keys}  drift=none    │
│           │                     │           │        │          │ delay_ms=7000  attempt=1       │
│           │                     │           │        │          │ fail_until=0                   │
│           │                     │           │        │          │ fail_as=transient              │
│           │                     │           │        │          │ input_rows=3                   │
│ summarise │ transform.jq        │ succeeded │ work   │ 0.2s     │ value={4 keys}                 │
└───────────┴─────────────────────┴───────────┴────────┴──────────┴────────────────────────────────┘
```

On the instance, `uv run dg apply --paused` creates the source paused, and nothing has been
poked yet:

```bash
uv run dg source show echo-stream-source arrive --json | jq -c '.fields | {state, in_flight, max_in_flight, polled_at}'
```

```json
{"state":"paused","in_flight":0,"max_in_flight":2,"polled_at":null}
```

`uv run dg source resume echo-stream-source arrive` sets the worker poking, on no cursor at all:

```text
2026-11-01T14:11:14.577+01:00 [info    ] resumed                        [source.resumed] code=arrive pipeline=echo-stream-source state=starting
```

Thirty seconds later, `uv run dg runs list --pipeline echo-stream-source`:

```text
runs
┏━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┓
┃ run             ┃ pipeline        ┃ status    ┃ triggered by  ┃ started        ┃ finished        ┃
┡━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━┩
│ 01a1973c-b2eb-… │ echo-stream-so… │ running   │ source arrive │ 2026-11-01     │ -               │
│                 │                 │           │               │ 14:11:40       │                 │
│ 01a1973c-9eb9-… │ echo-stream-so… │ succeeded │ source arrive │ 2026-11-01     │ 2026-11-01      │
│                 │                 │           │               │ 14:11:34       │ 14:11:41        │
│ 01a1973c-8824-… │ echo-stream-so… │ succeeded │ source arrive │ 2026-11-01     │ 2026-11-01      │
│                 │                 │           │               │ 14:11:29       │ 14:11:36        │
│ 01a1973c-731b-… │ echo-stream-so… │ succeeded │ source arrive │ 2026-11-01     │ 2026-11-01      │
│                 │                 │           │               │ 14:11:23       │ 14:11:30        │
└─────────────────┴─────────────────┴───────────┴───────────────┴────────────────┴─────────────────┘
```

A new run starts every five or six seconds, each one the moment the source has its batch, and
each run takes seven seconds to work it, so the runs overlap: the run started at 14:11:40 began
before the one from 14:11:34 had finished. A worker pokes the source again the moment a batch
arrives, so the five-second wait is what sets the pace. The run list fills the way a consumed
topic does.

`uv run dg source pause echo-stream-source arrive` stops the poking and keeps where the last
batch ended. The source reads `draining` while its runs still work, then `paused`:

```text
2026-11-01T14:11:59.916+01:00 [info    ] paused                         [source.paused] code=arrive pipeline=echo-stream-source state=draining
```

The runs already working their batch finish it, and nothing starts after the pause.
`uv run dg runs list --pipeline echo-stream-source` a few seconds later:

```text
runs
┏━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┓
┃ run             ┃ pipeline        ┃ status    ┃ triggered by  ┃ started        ┃ finished        ┃
┡━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━┩
│ 01a1973c-f357-… │ echo-stream-so… │ succeeded │ source arrive │ 2026-11-01     │ 2026-11-01      │
│                 │                 │           │               │ 14:11:56       │ 14:12:03        │
│ 01a1973c-de92-… │ echo-stream-so… │ succeeded │ source arrive │ 2026-11-01     │ 2026-11-01      │
│                 │                 │           │               │ 14:11:51       │ 14:11:58        │
│ 01a1973c-c943-… │ echo-stream-so… │ succeeded │ source arrive │ 2026-11-01     │ 2026-11-01      │
│                 │                 │           │               │ 14:11:45       │ 14:11:53        │
│ 01a1973c-b2eb-… │ echo-stream-so… │ succeeded │ source arrive │ 2026-11-01     │ 2026-11-01      │
│                 │                 │           │               │ 14:11:40       │ 14:11:47        │
│ 01a1973c-9eb9-… │ echo-stream-so… │ succeeded │ source arrive │ 2026-11-01     │ 2026-11-01      │
│                 │                 │           │               │ 14:11:34       │ 14:11:41        │
│ 01a1973c-8824-… │ echo-stream-so… │ succeeded │ source arrive │ 2026-11-01     │ 2026-11-01      │
│                 │                 │           │               │ 14:11:29       │ 14:11:36        │
│ 01a1973c-731b-… │ echo-stream-so… │ succeeded │ source arrive │ 2026-11-01     │ 2026-11-01      │
│                 │                 │           │               │ 14:11:23       │ 14:11:30        │
└─────────────────┴─────────────────┴───────────┴───────────────┴────────────────┴─────────────────┘
```

No run waits inside the pipeline, so a pause has nothing to cancel: every run the source started
succeeded. What each run's `summarise` read, oldest run first, from
`uv run dg runs show <run id> --json`:

```json
{"count":3,"first_offset":0,"last_offset":2,"next_offset":3}
{"count":3,"first_offset":3,"last_offset":5,"next_offset":6}
{"count":3,"first_offset":6,"last_offset":8,"next_offset":9}
{"count":3,"first_offset":9,"last_offset":11,"next_offset":12}
{"count":3,"first_offset":12,"last_offset":14,"next_offset":15}
{"count":3,"first_offset":15,"last_offset":17,"next_offset":18}
{"count":3,"first_offset":18,"last_offset":20,"next_offset":21}
```

Each batch starts where the one before it ended. `playground.arrive` says where its batch ended
in `next_offset`, the source stores that as its cursor, and the next wait's first poke starts
from it. The source holds it while it is paused, so a resume reads on rather than starting over:
resumed and paused again a few seconds later, the newest run's batch is

```json
{"count":3,"first_offset":24,"last_offset":26,"next_offset":27}
```

the second batch after 21.

## What this is not

These are batches and polls: a sensor asks on a cadence and a step gets a whole batch, or a
whole body, once it is there. The source makes that continuous -- one run after another, each with
its batch -- but each run still carries a whole batch through the DAG. Nothing here is a stream
flowing through the DAG record by record; that is a separate design round.
