# echo-s3

The write-read-back shape of [echo-storage](../echo-storage), with the bytes in a bucket
instead of on a disk. What makes that work is not a block: there is no "upload to S3" step and
no "download from S3" step anywhere in the document. `s3://` is a **registered URI scheme**, so
the ordinary `storage.write` and `storage.read` address an object in a bucket exactly as they
address a file, and what decides where the bytes land is the instance -- one connection holding
the endpoint and the credential, and two settings saying which connection serves the scheme and
where this instance keeps artifacts. The document says `s3://<bucket>/echo/<station>.json` once,
because it has an opinion about that object; it also writes to `${run.scratch}`, which names no
scheme at all and lands in the same bucket here and in a temporary directory under a local run.
That pair is the lesson: the second write is the one that moves from a laptop to a cluster
without being edited, and the first is what you write when the address is the point.

Everything here runs against a local S3 server in a container -- rustfs, the same image the
compose stack ships -- so nothing needs an AWS account and nothing leaves the machine. The
reading it writes is made on this machine too: `playground.generate` takes the station as its
`input`, generates a temperature onto it and hands the record back, so the document reaches
nothing but the bucket.

## Run it

`.dirigent/state/` and `.env` are not in the repository: they are one instance's own database
and its token, and a clone makes its own. Everything else here is committed.

```bash
uv sync
```

`pyproject.toml` pins `dirigent-storage-s3` beside the CLI. That package is what contributes the
`s3://` backend and the `s3` connection kind; the CLI does not carry it, because a scheme is a
package and an instance serves the schemes it has. Without it this document is refused before it
is stored, which is what `requires: {storage: [s3]}` in the document is for:

```text
2026-09-17T15:33:48.531+02:00 [error   ] the document does not validate against the installed catalog:
  requires.connections.0: no connection coded 'artifacts' exists on this instance
  requires.storage.0: no storage backend claims 's3' (file) [error] status=3 title=Refused code=cli.guard_refused params={"detail":"the document does not validate against the installed catalog:\n  requires.connections.0: no connection coded 'artifacts' exists on this instance\n  requires.storage.0: no storage backend claims 's3' (file)"}
```

### The S3 server

One container, and one bucket inside it. The bucket has to exist before anything writes to it:
a write does not create one.

```bash
docker run -d --rm --name dirigent-s3 -p 127.0.0.1:9000:9000 \
  -e RUSTFS_ACCESS_KEY=echo-s3-key \
  -e RUSTFS_SECRET_KEY=echo-s3-secret \
  rustfs/rustfs:1.0.0-rc.4
```

```bash
uv run python - <<'PY'
import boto3
from botocore.config import Config

store = boto3.client(
    "s3",
    endpoint_url="http://127.0.0.1:9000",
    aws_access_key_id="echo-s3-key",
    aws_secret_access_key="echo-s3-secret",
    config=Config(s3={"addressing_style": "path"}),
)
store.create_bucket(Bucket="echo-s3")
PY
```

`boto3` is already here, because `dirigent-storage-s3` brings it: the bucket is made with the
client this project installed rather than with a second image to pull. An instance that already
has its database and its connection makes this bucket with `dg storage ensure` instead, which is
what the compose stack's bootstrap container runs -- but the first write here is the local run
further down, and it has neither. `addressing_style` is the client-side half of the connection's
`path_style=true`.

### Without a server

A local run cannot put **its own scratch** in the bucket: `dg run --local` holds the run in a
throwaway instance in a temporary directory, and that directory is its artifact root whatever
`DIRIGENT_ARTIFACT_ROOT` says. It can still write to an `s3://` URI the document names, because
that only needs the scheme resolved -- a connection handed to the run, and the environment
saying which connection serves `s3`:

```bash
uv run dg validate pipelines/echo-s3.yaml
DIRIGENT_STORAGE_CONNECTIONS=s3=artifacts \
  uv run dg run --local pipelines/echo-s3.yaml --connections connections.yaml
```

### The instance whose artifacts live in the bucket

In a second terminal, in this directory. Three settings are the whole of it: the key the
instance seals connection secrets with, which goes on a line in `.env`, the artifact root, and
which connection serves the scheme that root is written in.

```bash
grep -q '^DIRIGENT_SECRET_KEY=' .env 2>/dev/null \
  || printf 'DIRIGENT_SECRET_KEY=%s\n' "$(uv run dg secret-key)" >> .env
export DIRIGENT_ARTIFACT_ROOT=s3://echo-s3/artifacts
export DIRIGENT_STORAGE_CONNECTIONS=s3=artifacts
uv run dg dev
```

`dg dev` is one process holding the API, the web UI, the scheduler, one worker and a SQLite file
under `.dirigent/state/`. It keeps running; leave it. On an empty state -- which is what a fresh
clone has, because the state directory is not in the repository -- it migrates the schema, makes
its own admin `dev`, mints that admin one token, and prints the `export DG_TOKEN=` line to paste.
The UI is at `http://127.0.0.1:3333`, which is the address the `local` profile in
`.dirigent/profiles.yaml` holds; `dg dev --port` moves the instance and `DG_URL` is how you tell
the CLI where it went.

`.env` is gitignored and already holds this instance's token, so the key goes on a line beside
it, and every command run in this directory reads it from there: an instance that changes its
key cannot open the secrets it already stored. `verify.sh` writes that same line.

Back in the first terminal, with that line pasted:

```bash
uv run dg connection create s3 artifacts \
  --name "Artifact storage" \
  --set endpoint_url=http://127.0.0.1:9000 \
  --set bucket=echo-s3 \
  --set access_key_id=echo-s3-key \
  --set secret_access_key=echo-s3-secret \
  --set path_style=true
uv run dg connection check artifacts
uv run dg apply
uv run dg run echo-s3 --watch
```

An invocation carrying `--set` has said what it wants, so it is asked only for a secret the
kind cannot do without, and `secret_access_key` is not one. Leave every `--set` off instead, and
the command offers each secret field in turn without echoing it, which is what you want for a
credential that is not a throwaway container's. `--set path_style=true` is
not optional against a clone: every S3 implementation but AWS itself addresses a bucket as a
path segment rather than as a subdomain.

Then ask the object store itself what it holds, and stop the server when you are done:

```bash
uv run python - <<'PY'
import boto3
from botocore.config import Config

store = boto3.client(
    "s3",
    endpoint_url="http://127.0.0.1:9000",
    aws_access_key_id="echo-s3-key",
    aws_secret_access_key="echo-s3-secret",
    config=Config(s3={"addressing_style": "path"}),
)
for page in store.get_paginator("list_objects_v2").paginate(Bucket="echo-s3"):
    for obj in page.get("Contents", ()):
        print(f"{obj['Size']:>6}B  {obj['Key']}")
PY
```

```bash
docker rm -f dirigent-s3
```

`./verify.sh` does all of it non-interactively: it starts the server on a free port of its own,
makes the bucket, runs the document locally and then on an instance it starts with the artifact
root pointed into that bucket, asserts on the records, asks the object store to confirm both
objects, and removes the container and the instance it started on the way out. It keeps the key
on that same `.env` line, and leaves the connection alone unless it is addressing another
endpoint -- the container takes a free port unless `S3_PORT` names one -- so its second run
inherits the state its first run left.

### If the key was lost

A connection is sealed with the key the instance held when it was written, so a state left over
from a key that is gone answers `uv run dg connection check artifacts` with a record whose
`detail` begins `SecretKeyMismatch`. Nothing opens that row again -- there is no `dg connection
update`, and the secret it holds is not recoverable -- so delete it and write it once more under
the key this instance has now:

```bash
uv run dg connection delete artifacts
uv run dg connection create s3 artifacts \
  --name "Artifact storage" \
  --set endpoint_url=http://127.0.0.1:9000 \
  --set bucket=echo-s3 \
  --set access_key_id=echo-s3-key \
  --set secret_access_key=echo-s3-secret \
  --set path_style=true
```

`verify.sh` does exactly that when its own check reports that class.

## Offline

Nothing here calls out. The S3 server is a container on this machine, the instance is local, and
the reading is generated by a node rather than fetched. The image is the one thing to carry with
you: pull it once while you still have a network.

```bash
docker pull rustfs/rustfs:1.0.0-rc.4
```

`OFFLINE.md` beside this repository is the rest of the story, including the `UV_OFFLINE=1` that
keeps `uv` off the network too.

## What you see

*Printed as it printed, with this project's directory written as `/home/you/...` and the
temporary directory a local run makes written as `/tmp/...`.*

```bash
uv run dg validate pipelines/echo-s3.yaml
```

```text
2026-09-26T12:56:50.484+02:00 [info    ] valid                          [validation] code=echo-s3 document=pipelines/echo-s3.yaml checked="document, offline"
  each step under the last one it waits for
    ask  (playground.generate)
      save  (storage.write)
        back  (storage.read)
          say  (log.write)  also after stash
      stash  (storage.write)
2026-09-26T12:56:50.489+02:00 [info    ] valid                          [validated] documents=1 invalid=0
```

`save` and `stash` are siblings: both wait on `ask` and neither waits on the other, so the engine
runs them together. Only `back` waits on `save`, because it reads what `save` wrote.

```bash
DIRIGENT_STORAGE_CONNECTIONS=s3=artifacts \
  uv run dg run --local pipelines/echo-s3.yaml --connections connections.yaml
```

```text
2026-09-26T12:56:52.006+02:00 [info    ] started                        [run] pipeline=echo-s3 run_id=01a0dd5c-5922-70a7-b6f4-cdd04d1be52e local=true scratch=file:///tmp/dirigent-local-y2yd_a1b/artifacts/runs/01a0dd5c-5922-70a7-b6f4-cdd04d1be52e root=/tmp/dirigent-local-y2yd_a1b
2026-09-26T12:56:52.001+02:00 [info    ] queued                         [step ask] block=playground.generate attempt=1
2026-09-26T12:56:52.075+02:00 [info    ] playground generated           [log ask] rows=1 seed=4 locale=en_US drift=none
2026-09-26T12:56:52.075+02:00 [info    ] succeeded                      [step ask] block=playground.generate attempt=1 duration_ms=34
2026-09-26T12:56:52.075+02:00 [info    ] queued                         [step save] block=storage.write attempt=1
2026-09-26T12:56:52.075+02:00 [info    ] queued                         [step stash] block=storage.write attempt=1
2026-09-26T12:56:52.319+02:00 [info    ] wrote                          [log stash] uri=echo/bergen-florida.json bytes_written=43 content_type=application/json
2026-09-26T12:56:52.316+02:00 [info    ] wrote                          [log save] uri=s3://echo-s3/echo/bergen-florida.json bytes_written=43 content_type=application/json
2026-09-26T12:56:52.322+02:00 [info    ] succeeded                      [step stash] block=storage.write attempt=1 duration_ms=13
2026-09-26T12:56:52.330+02:00 [info    ] succeeded                      [step save] block=storage.write attempt=1 duration_ms=176
2026-09-26T12:56:52.330+02:00 [info    ] queued                         [step back] block=storage.read attempt=1
2026-09-26T12:56:52.494+02:00 [info    ] read                           [log back] uri=s3://echo-s3/echo/bergen-florida.json bytes_read=43 content_type=application/json
2026-09-26T12:56:52.497+02:00 [info    ] succeeded                      [step back] block=storage.read attempt=1 duration_ms=127
2026-09-26T12:56:52.497+02:00 [info    ] queued                         [step say] block=log.write attempt=1
2026-09-26T12:56:52.549+02:00 [info    ] 43 bytes back from s3://echo-s3/echo/bergen-florida.json for station bergen-florida, with this run's scratch at file:///tmp/dirigent-local-y2yd_a1b/artifacts/runs/01a0dd5c-5922-70a7-b6f4-cdd04d1be52e/echo/bergen-florida.json [log say]
2026-09-26T12:56:52.549+02:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=5
2026-09-26T12:56:52.642+02:00 [info    ] succeeded                      [run] pipeline=echo-s3 run_id=01a0dd5c-5922-70a7-b6f4-cdd04d1be52e exit_code=0
steps
┏━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step  ┃ block               ┃ outcome   ┃ after       ┃ duration ┃ output                        ┃
┡━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask   │ playground.generate │ succeeded │ -           │ 0.0s     │ records=[1 items]  rows=1     │
│       │                     │           │             │          │ seed=4  locale=en_US          │
│       │                     │           │             │          │ fields={1 keys}  drift=none   │
│       │                     │           │             │          │ delay_ms=0  attempt=1         │
│       │                     │           │             │          │ fail_until=0  input_rows=1    │
│ save  │ storage.write       │ succeeded │ ask         │ 0.2s     │ uri=s3://echo-s3/echo/bergen… │
│       │                     │           │             │          │ bytes_written=43              │
│       │                     │           │             │          │ content_type=application/json │
│ stash │ storage.write       │ succeeded │ ask         │ 0.0s     │ uri=echo/bergen-florida.json  │
│       │                     │           │             │          │ bytes_written=43              │
│       │                     │           │             │          │ content_type=application/json │
│ back  │ storage.read        │ succeeded │ save        │ 0.1s     │ content_type=application/json │
│       │                     │           │             │          │ value={2 keys}  bytes_read=43 │
│ say   │ log.write           │ succeeded │ back, stash │ 0.0s     │ -                             │
└───────┴─────────────────────┴───────────┴─────────────┴──────────┴───────────────────────────────┘
```

There is the split. `save` landed at `s3://echo-s3/echo/bergen-florida.json`, in the bucket,
because the document said so; `stash` landed under `/tmp/dirigent-local-y2yd_a1b`, because that
is what `${run.scratch}` means to a local run. Same document, same block, two roots.

```bash
uv run dg connection create s3 artifacts ...
uv run dg connection check artifacts
```

```text
2026-09-26T12:56:57.314+02:00 [info    ] created                        [connection.created] code=artifacts connection_kind=s3 name="Artifact storage" config={"endpoint_url":"http://127.0.0.1:9000","region":"us-east-1","access_key_id":"echo-s3-key","path_style":true,"verify_tls":true,"bucket":"echo-s3","secret_access_key":"***"}
2026-09-26T12:56:58.606+02:00 [info    ] healthy                        [connection.checked] code=artifacts healthy=true detail="bucket 'echo-s3' reachable"
```

The record carries the config back with the secret half as `***`: a connection's secret goes in
and is never readable again, only usable. `dg connection check` is the `s3` kind probing its own
endpoint -- a `head_bucket` when the connection names a bucket, which is why the detail says
which bucket answered.

```bash
uv run dg apply
uv run dg run echo-s3 --watch
```

```text
create echo-s3  version 1 (/home/you/echo-s3/pipelines/echo-s3.yaml)
```

```text
2026-09-26T12:57:01.049+02:00 [info    ] started                        [run] pipeline=echo-s3 run_id=01a0dd5c-7c74-7168-bf05-63356749480c local=false
2026-09-26T12:57:01.047+02:00 [info    ] queued                         [step ask] block=playground.generate attempt=1
2026-09-26T12:57:01.047+02:00 [info    ] queued                         [step save] block=storage.write attempt=1
2026-09-26T12:57:01.047+02:00 [info    ] queued                         [step stash] block=storage.write attempt=1
2026-09-26T12:57:01.151+02:00 [info    ] playground generated           [log ask] rows=1 seed=4 locale=en_US drift=none
2026-09-26T12:57:01.151+02:00 [info    ] succeeded                      [step ask] block=playground.generate attempt=1 duration_ms=34
2026-09-26T12:57:01.047+02:00 [info    ] queued                         [step say] block=log.write attempt=1
2026-09-26T12:57:01.719+02:00 [info    ] wrote                          [log save] uri=s3://echo-s3/echo/bergen-florida.json bytes_written=43 content_type=application/json
2026-09-26T12:57:01.774+02:00 [info    ] succeeded                      [step save] block=storage.write attempt=1 duration_ms=119
2026-09-26T12:57:01.777+02:00 [info    ] wrote                          [log stash] uri=s3://echo-s3/artifacts/runs/01a0dd5c-7c74-7168-bf05-63356749480c/echo/bergen-florida.json bytes_written=43 content_type=application/json
2026-09-26T12:57:01.780+02:00 [info    ] succeeded                      [step stash] block=storage.write attempt=1 duration_ms=66
2026-09-26T12:57:02.424+02:00 [info    ] read                           [log back] uri=s3://echo-s3/echo/bergen-florida.json bytes_read=43 content_type=application/json
2026-09-26T12:57:02.425+02:00 [info    ] succeeded                      [step back] block=storage.read attempt=1 duration_ms=141
2026-09-26T12:57:02.929+02:00 [info    ] 43 bytes back from s3://echo-s3/echo/bergen-florida.json for station bergen-florida, with this run's scratch at s3://echo-s3/artifacts/runs/01a0dd5c-7c74-7168-bf05-63356749480c/echo/bergen-florida.json [log say]
2026-09-26T12:57:02.929+02:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=5
2026-09-26T12:57:03.614+02:00 [info    ] succeeded                      [run] pipeline=echo-s3 run_id=01a0dd5c-7c74-7168-bf05-63356749480c pipeline_version=1 triggered_by="dev (token cli-dev)" duration_ms=1813 items_total=0 items_failed=0 exit_code=0 priority=normal
run 01a0dd5c-7c74-7168-bf05-63356749480c
pipeline      echo-s3 (version 1)
status        succeeded
triggered by  dev (token cli-dev)
duration      1.8s
items         -

steps
┏━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━┓
┃ step  ┃ block               ┃ outcome   ┃ after       ┃ attempts ┃ duration ┃ error ┃
┡━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━┩
│ ask   │ playground.generate │ succeeded │ -           │ 1        │ 0.0s     │ -     │
│ save  │ storage.write       │ succeeded │ ask         │ 1        │ 0.1s     │ -     │
│ stash │ storage.write       │ succeeded │ ask         │ 1        │ 0.1s     │ -     │
│ back  │ storage.read        │ succeeded │ save        │ 1        │ 0.1s     │ -     │
│ say   │ log.write           │ succeeded │ back, stash │ 1        │ 0.0s     │ -     │
└───────┴─────────────────────┴───────────┴─────────────┴──────────┴──────────┴───────┘

outputs
┏━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step  ┃ output                                                                                   ┃
┡━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask   │ records=[1 items]  rows=1  seed=4  locale=en_US  fields={1 keys}  drift=none  delay_ms=0 │
│       │ attempt=1  fail_until=0  input_rows=1                                                    │
│ save  │ uri=s3://echo-s3/echo/bergen-florida.json  bytes_written=43                              │
│       │ content_type=application/json                                                            │
│ stash │ uri=s3://echo-s3/artifacts/runs/01a0dd5c-7c74-7168-bf05-63356749480c/echo/bergen-florid… │
│       │ bytes_written=43  content_type=application/json                                          │
│ back  │ content_type=application/json  value={2 keys}  bytes_read=43                             │
│ say   │ -                                                                                        │
└───────┴──────────────────────────────────────────────────────────────────────────────────────────┘
```

`stash` now says `s3://echo-s3/artifacts/runs/<run id>/echo/bergen-florida.json`. Nothing in the
document changed between the two runs -- the instance's artifact root did, and `${run.scratch}`
followed it. That is what `DIRIGENT_ARTIFACT_ROOT=s3://echo-s3/artifacts` bought: every worker on
the instance now reads and writes one address, which is what lets there be more than one of them.

And the listing from the last block of "Run it":

```text
    43B  artifacts/runs/01a0dd5c-7c74-7168-bf05-63356749480c/echo/bergen-florida.json
    43B  echo/bergen-florida.json
```

The two objects, in the one bucket, the run's own prefix beside the object the document named.
The records already said this; asking the object store is the other half of the proof, and it is
what `verify.sh` does after every run.

```bash
uv run dg runs show 01a0dd5c-7c74-7168-bf05-63356749480c --json \
  | jq '.fields.attempts[] | select(.step_name == "back") | .output.value'
```

```json
{
  "celsius": -4.4,
  "station": "bergen-florida"
}
```

That value never touched the worker's disk. It was made in a step, went into a bucket, came back
out of it, and is in the run because `storage.read` put it there. `-4.4` is what seed 4 makes of
that provider, which is why it is the same on your machine.


## The document, hop by hop

`pipelines/echo-s3.yaml`:

```yaml
requires:
  blocks:
    - playground.generate
    - storage.write
    - storage.read
    - log.write
  connections:
    - artifacts
  storage:
    - s3
```

`storage: [s3]` is the line worth reading twice. It is not "this pipeline uses S3"; it is "this
instance must serve the `s3` scheme", and an instance that does not refuses the document at apply
with the list above rather than failing a run halfway through. `connections: [artifacts]` is the
same preflight for the credential.

```yaml
params:
  type: object
  properties:
    station:
      type: string
      default: bergen-florida
    bucket:
      type: string
      default: echo-s3
```

The bucket is a parameter because the bucket is part of the address, not part of the credential.
A connection's own `bucket` field is only what `dg connection check` probes; every `s3://` URI a
step writes carries its own.

```yaml
steps:
  ask:
    block: playground.generate
    config:
      rows: 1
      seed: 4
      input:
        station: ${params.station}
      fields:
        celsius:
          provider: pyfloat
          args:
            min_value: -20
            max_value: 30
            right_digits: 1
```

The reading. The station is the node's `input` and travels through untouched; `celsius` is
generated onto it, because `fields:` names it. The seed is what makes the object deterministic:
the same station writes the same bytes on every run, which is why `verify.sh` can compare what
was written with what came back.

```yaml
  save:
    block: storage.write
    depends_on: [ask]
    config:
      target: s3://${params.bucket}/echo/${params.station}.json
      value: ${steps.ask.output.records.0}
      content_type: application/json
```

An address the document has an opinion about: a named bucket, a named key, an object somebody
else will come and fetch. The node's records are a list and this object is one reading, so the
reference indexes into it -- an array index is a dot like any other. `value:` is written as
canonical JSON -- sorted keys, no spaces -- so the same reading writes the same bytes every run,
and `content_type` is stored **on the object**, so whoever fetches it out of the bucket is told
what it is.

```yaml
  stash:
    block: storage.write
    depends_on: [ask]
    config:
      target: ${run.scratch}/echo/${params.station}.json
      value: ${steps.ask.output.records.0}
      content_type: application/json
```

The same write with no scheme, no bucket and no host in it. `${run.scratch}` is this run's own
prefix under whatever the instance's artifact root is, and it is the form to reach for whenever
the next step is the only reader: it costs nothing to run on a laptop and nothing to move to a
cluster.

```yaml
  back:
    block: storage.read
    depends_on: [save]
    config:
      source: ${steps.save.output.uri}
```

The other door. It names `${steps.save.output.uri}` rather than typing the path a second time, so
one line decides where the object is and everything downstream follows it. `storage.read` holds
at most 1mb unless `max_size` says otherwise, and refuses an object above the cap rather than
truncating it: half a document is not a smaller one, it is a wrong one.

```yaml
  say:
    block: log.write
    depends_on: [back, stash]
    config:
      message: >-
        ${steps.back.output.bytes_read} bytes back from ${steps.save.output.uri}
        for station ${steps.back.output.value.station}, with this run's scratch
        at ${steps.stash.output.uri}
```

One line in the run's log with both URIs in it, which is what makes the difference between the
local run and the instance run visible without reading the run back.

## Where to go next

- [`dhis2-read-gate-send`](../dhis2-read-gate-send/README.md) is what comes next: the same three
  moves against the DHIS2 play demo, with a pack's blocks, a connection and a rehearsed import.
- [**The basics**](https://winterop-com.github.io/dirigent/basics/) is the tutorial these
  examples are cut from.
- [**The examples**](../README.md): every example in order, and what you need once.
- [**Artifacts in object storage**](https://winterop-com.github.io/dirigent/operations/#artifacts-in-object-storage)
  is why a second worker makes a bucket mandatory, and what the compose stack does about it.
