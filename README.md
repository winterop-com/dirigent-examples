# echo-s3

The read-write-read-back shape of [echo-storage](../echo-storage), with the bytes in a bucket
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
compose stack ships -- so nothing needs an AWS account and nothing leaves the machine.

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
  requires.storage.0: no storage backend claims 's3' (file) [error] status=3 title=Refused
```

### The S3 server

One container, and one bucket inside it. The bucket has to exist before anything writes to it:
a write does not create one.

```bash
docker run -d --rm --name dirigent-s3 -p 127.0.0.1:9000:9000 \
  -e RUSTFS_ACCESS_KEY=echo-s3-key \
  -e RUSTFS_SECRET_KEY=echo-s3-secret \
  rustfs/rustfs:1.0.0-rc.4

docker run --rm --network container:dirigent-s3 --entrypoint /bin/sh \
  quay.io/minio/mc:RELEASE.2025-04-16T18-13-26Z -ec '
    mc alias set fs http://127.0.0.1:9000 echo-s3-key echo-s3-secret
    mc mb --ignore-existing fs/echo-s3'
```

`--network container:dirigent-s3` puts the client inside the server's own network namespace, so
it reaches it at `127.0.0.1:9000` with no published port to find and nothing host-specific about
the command. The published port on the line above is for `dg` on the host, which is outside that
namespace.

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

In a second terminal, in this directory. The three environment settings are the whole of it: the
key the instance seals connection secrets with, the artifact root, and which connection serves
the scheme that root is written in.

```bash
export DIRIGENT_SECRET_KEY="$(uv run dg secret-key)"
export DIRIGENT_ARTIFACT_ROOT=s3://echo-s3/artifacts
export DIRIGENT_STORAGE_CONNECTIONS=s3=artifacts
uv run dg dev
```

Keep the key. An instance that changes it cannot open what it sealed under the old one, which is
why `verify.sh` mints one per run and writes the connection fresh every time.

Back in the first terminal, with the `export DG_TOKEN=` line `dg dev` printed:

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

Leave `--set secret_access_key=` off and the command asks for it without echoing it, which is
what you want for a credential that is not a throwaway container's. `--set path_style=true` is
not optional against a clone: every S3 implementation but AWS itself addresses a bucket as a
path segment rather than as a subdomain.

Then ask the object store itself what it holds, and stop the server when you are done:

```bash
docker run --rm --network container:dirigent-s3 --entrypoint /bin/sh \
  quay.io/minio/mc:RELEASE.2025-04-16T18-13-26Z -ec '
    mc alias set fs http://127.0.0.1:9000 echo-s3-key echo-s3-secret
    mc ls --recursive fs/echo-s3'

docker rm -f dirigent-s3
```

`./verify.sh` does all of it non-interactively: it starts the server on a free port of its own,
makes the bucket, runs the document locally and then on an instance it starts with the artifact
root pointed into that bucket, asserts on the records, asks the object store to confirm both
objects, and removes the container and the instance it started on the way out.

## What you see

```bash
uv run dg validate pipelines/echo-s3.yaml
```

```text
2026-09-17T15:31:42.032+02:00 [info    ] valid                          [validation] code=echo-s3 document=pipelines/echo-s3.yaml checked="document, offline"
  each step under the last one it waits for
    ask  (http.request)
      save  (storage.write)
        back  (storage.read)
          say  (log.write)  also after stash
      stash  (storage.write)
2026-09-17T15:31:42.035+02:00 [info    ] valid                          [validated] documents=1 invalid=0
```

`save` and `stash` are siblings: both wait on `ask` and neither waits on the other, so the engine
runs them together. Only `back` waits on `save`, because it reads what `save` wrote.

```bash
DIRIGENT_STORAGE_CONNECTIONS=s3=artifacts \
  uv run dg run --local pipelines/echo-s3.yaml --connections connections.yaml
```

```text
2026-09-17T15:31:43.412+02:00 [info    ] started                        [run] pipeline=echo-s3 run_id=01a0af90-e3b0-759c-847e-cb752b3184de local=true scratch=file:///tmp/dirigent-local-yvoc9ffj/artifacts/runs/01a0af90-e3b0-759c-847e-cb752b3184de root=/tmp/dirigent-local-yvoc9ffj
2026-09-17T15:31:43.763+02:00 [info    ] http call                      [log ask] method=GET url=https://postman-echo.com/get status=200 bytes=243 duration_ms=310
2026-09-17T15:31:43.876+02:00 [info    ] wrote                          [log stash] uri=echo/bergen-florida.json bytes_written=243 content_type=application/json
2026-09-17T15:31:43.878+02:00 [info    ] wrote                          [log save] uri=s3://echo-s3/echo/bergen-florida.json bytes_written=243 content_type=application/json
2026-09-17T15:31:44.032+02:00 [info    ] read                           [log back] uri=s3://echo-s3/echo/bergen-florida.json bytes_read=243 content_type=application/json
2026-09-17T15:31:44.087+02:00 [info    ] 243 bytes back from s3://echo-s3/echo/bergen-florida.json for station bergen-florida, with this run's scratch at file:///tmp/dirigent-local-yvoc9ffj/artifacts/runs/01a0af90-e3b0-759c-847e-cb752b3184de/echo/bergen-florida.json [log say]
2026-09-17T15:31:44.174+02:00 [info    ] succeeded                      [run] pipeline=echo-s3 run_id=01a0af90-e3b0-759c-847e-cb752b3184de exit_code=0
steps
┏━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step  ┃ block         ┃ outcome   ┃ after       ┃ duration ┃ output                              ┃
┡━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ask   │ http.request  │ succeeded │ -           │ 0.3s     │ status=200  headers={12 keys}       │
│       │               │           │             │          │ body={3 keys}  body_bytes=243       │
│       │               │           │             │          │ duration_ms=310                     │
│ save  │ storage.write │ succeeded │ ask         │ 0.1s     │ uri=s3://echo-s3/echo/bergen-flori… │
│       │               │           │             │          │ bytes_written=243                   │
│       │               │           │             │          │ content_type=application/json       │
│ stash │ storage.write │ succeeded │ ask         │ 0.0s     │ uri=echo/bergen-florida.json        │
│       │               │           │             │          │ bytes_written=243                   │
│       │               │           │             │          │ content_type=application/json       │
│ back  │ storage.read  │ succeeded │ save        │ 0.1s     │ content_type=application/json       │
│       │               │           │             │          │ value={3 keys}  bytes_read=243      │
│ say   │ log.write     │ succeeded │ back, stash │ 0.0s     │ -                                   │
└───────┴───────────────┴───────────┴─────────────┴──────────┴─────────────────────────────────────┘
```

There is the split. `save` landed at `s3://echo-s3/echo/bergen-florida.json`, in the bucket,
because the document said so; `stash` landed under `/tmp/dirigent-local-yvoc9ffj`, because that
is what `${run.scratch}` means to a local run. Same document, same block, two roots.

```bash
uv run dg connection create s3 artifacts ...
uv run dg connection check artifacts
```

```text
2026-09-17T15:31:49.827+02:00 [info    ] created                        [connection.created] code=artifacts connection_kind=s3 name="Artifact storage" config={"endpoint_url":"http://127.0.0.1:9000","region":"us-east-1","access_key_id":"echo-s3-key","path_style":true,"verify_tls":true,"bucket":"echo-s3","secret_access_key":"***"}
2026-09-17T15:31:51.048+02:00 [info    ] healthy                        [connection.checked] code=artifacts healthy=true detail="bucket 'echo-s3' reachable"
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
create echo-s3  version 1
(/home/you/echo-s3/pipelines/echo-s3.yaml)
```

```text
2026-09-17T15:31:53.461+02:00 [info    ] started                        [run] pipeline=echo-s3 run_id=01a0af91-0af0-75f0-922e-a118cca37b4b local=false
2026-09-17T15:31:53.771+02:00 [info    ] http call                      [log ask] method=GET url=https://postman-echo.com/get status=200 bytes=243 duration_ms=207
2026-09-17T15:31:54.231+02:00 [info    ] wrote                          [log save] uri=s3://echo-s3/echo/bergen-florida.json bytes_written=243 content_type=application/json
2026-09-17T15:31:54.236+02:00 [info    ] wrote                          [log stash] uri=s3://echo-s3/artifacts/runs/01a0af91-0af0-75f0-922e-a118cca37b4b/echo/bergen-florida.json bytes_written=243 content_type=application/json
2026-09-17T15:31:54.856+02:00 [info    ] read                           [log back] uri=s3://echo-s3/echo/bergen-florida.json bytes_read=243 content_type=application/json
2026-09-17T15:31:55.360+02:00 [info    ] 243 bytes back from s3://echo-s3/echo/bergen-florida.json for station bergen-florida, with this run's scratch at s3://echo-s3/artifacts/runs/01a0af91-0af0-75f0-922e-a118cca37b4b/echo/bergen-florida.json [log say]
2026-09-17T15:31:56.008+02:00 [info    ] succeeded                      [run] pipeline=echo-s3 run_id=01a0af91-0af0-75f0-922e-a118cca37b4b pipeline_version=1 triggered_by="dev (token cli-dev)" duration_ms=1804 items_total=0 items_failed=0 exit_code=0 priority=normal
run
01a0af91-0af0-75f0-922e-a118cca37b4
b
pipeline      echo-s3 (version 1)
status        succeeded
triggered by  dev (token cli-dev)
duration      1.8s
items         -

steps
┏━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━┓
┃ step  ┃ block         ┃ outcome   ┃ after       ┃ attempts ┃ duration ┃ error ┃
┡━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━┩
│ ask   │ http.request  │ succeeded │ -           │ 1        │ 0.2s     │ -     │
│ save  │ storage.write │ succeeded │ ask         │ 1        │ 0.2s     │ -     │
│ stash │ storage.write │ succeeded │ ask         │ 1        │ 0.1s     │ -     │
│ back  │ storage.read  │ succeeded │ save        │ 1        │ 0.1s     │ -     │
│ say   │ log.write     │ succeeded │ back, stash │ 1        │ 0.0s     │ -     │
└───────┴───────────────┴───────────┴─────────────┴──────────┴──────────┴───────┘
```

`stash` now says `s3://echo-s3/artifacts/runs/<run id>/echo/bergen-florida.json`. Nothing in the
document changed between the two runs -- the instance's artifact root did, and `${run.scratch}`
followed it. That is what `DIRIGENT_ARTIFACT_ROOT=s3://echo-s3/artifacts` bought: every worker on
the instance now reads and writes one address, which is what lets there be more than one of them.

And the `mc ls --recursive fs/echo-s3` from the last block of "Run it":

```text
[2026-09-17 13:31:54 UTC]   243B STANDARD artifacts/runs/01a0af91-0af0-75f0-922e-a118cca37b4b/echo/bergen-florida.json
[2026-09-17 13:31:54 UTC]   243B STANDARD echo/bergen-florida.json
```

The two objects, in the one bucket, the run's own prefix beside the object the document named.
The records already said this; asking the object store is the other half of the proof, and it is
what `verify.sh` does after every run.

```bash
uv run dg runs show 01a0af91-0af0-75f0-922e-a118cca37b4b --json \
  | jq '.fields.attempts[] | select(.step_name == "back") | .output.value'
```

```json
{
  "args": {
    "station": "bergen-florida"
  },
  "headers": {
    "accept": "*/*",
    "accept-encoding": "gzip, br",
    "host": "postman-echo.com",
    "user-agent": "python-httpx2/2.13.0",
    "x-forwarded-proto": "https"
  },
  "url": "https://postman-echo.com/get?station=bergen-florida"
}
```

That value never touched the worker's disk. It came off the wire, went into a bucket, came back
out of it, and is in the run because `storage.read` put it there.

## Offline

Nothing here needs a network once the two images are pulled. `base_url` is a parameter for
exactly that: [../local-echo](../local-echo) is the same echo service in one file of Python, with
the same answer shapes, and pointing the run at it is one flag.

```bash
python3 ../local-echo/echo_server.py &
uv run dg run echo-s3 -p base_url=http://127.0.0.1:8080 --watch
```

The S3 server is already local, the instance is already local, and the read is the only thing
that was ever leaving the machine. Pull the images once while you still have a network:

```bash
docker pull rustfs/rustfs:1.0.0-rc.4
docker pull quay.io/minio/mc:RELEASE.2025-04-16T18-13-26Z
```

## The document, hop by hop

`pipelines/echo-s3.yaml`:

```yaml
requires:
  blocks:
    - http.request
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
    base_url:
      type: string
      default: https://postman-echo.com
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
    block: http.request
    config:
      url: ${params.base_url}/get
      method: GET
      query:
        station: ${params.station}
```

The read. Postman Echo answers a GET with the arguments it was given, so the answer is the proof
of what was asked -- and `base_url` as a parameter is what lets the local echo stand in for it.

```yaml
  save:
    block: storage.write
    depends_on: [ask]
    config:
      target: s3://${params.bucket}/echo/${params.station}.json
      value: ${steps.ask.output.body}
      content_type: application/json
```

An address the document has an opinion about: a named bucket, a named key, an object somebody
else will come and fetch. `value:` is written as canonical JSON -- sorted keys, no spaces -- so
the same answer writes the same bytes every run, and `content_type` is stored **on the object**,
so whoever fetches it out of the bucket is told what it is.

```yaml
  stash:
    block: storage.write
    depends_on: [ask]
    config:
      target: ${run.scratch}/echo/${params.station}.json
      value: ${steps.ask.output.body}
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
        for station ${steps.back.output.value.args.station}, with this run's scratch
        at ${steps.stash.output.uri}
```

One line in the run's log with both URIs in it, which is what makes the difference between the
local run and the instance run visible without reading the run back.

## Where to go next

- [**The basics**](https://winterop-com.github.io/dirigent/basics/) is the tutorial these
  examples are cut from.
- [**echo-storage**](../echo-storage) is this shape on a filesystem, with a `report:` section:
  the same two doors, one scheme down.
- [**Artifacts in object storage**](https://winterop-com.github.io/dirigent/operations/#artifacts-in-object-storage)
  is why a second worker makes a bucket mandatory, and what the compose stack does about it.
