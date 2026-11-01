# Running the examples with no network

Nearly every example here runs on a train. One thing needs the network and can be carried with
you instead: the Python packages each example installs. This is how you pack it, before you go.

## Before you go, while the network is up

    ./prepare-offline.sh

It syncs every example that has a `pyproject.toml`, so each `.venv` is complete and the uv cache
holds every wheel; it checks that `dg` is on your path (it does not install it -- that was done
when the examples were made, and reinstalling risks moving you off the version they were built
on); and it downloads the two tutorials into `docs/`. It prints what is ready at the end.

Run it again whenever an example gains a dependency.

## On the train

One command, once per shell:

    export UV_OFFLINE=1

`UV_OFFLINE=1` tells uv never to reach for the network: it resolves from the cache
`prepare-offline.sh` filled, and `uv run dg ...` starts as fast as it does at home. Without it,
uv will try to check the index and you will wait for a timeout on every command.

There is nothing else to start. No `echo-*` example calls anything on the internet.

## What the HTTP examples call

`echo-read`, `echo-gate`, `echo-send` and `echo-retry` make real HTTP calls, and what they call
is the **playground**: a request-and-response service every dirigent instance serves itself
under `/api/v1/playground`, unauthenticated. It answers with the request it was given -- the
query arguments, the body, the headers -- and with whatever status it was asked for, so a
document can teach a read, a gate, a send and both classes of failure without a public service
on the other end.

That does mean those four need an instance running, `dg run --local` included: a local run
builds a throwaway database and mounts no API of its own, so it reaches the playground over the
network like anything else does.

    cd echo-read
    uv run dg dev                                       # terminal 2, and leave it running
    uv run dg run --local pipelines/echo-read.yaml      # terminal 1

Each document carries a `playground` parameter defaulting to
`http://127.0.0.1:3333/api/v1/playground`, so an instance on another port is one flag:

    uv run dg run --local pipelines/echo-read.yaml -p playground=http://127.0.0.1:9999/api/v1/playground

The rest -- `echo-hello`, `echo-fanout`, `echo-transform`, `echo-schedule`, `echo-alert`,
`echo-storage`, `echo-s3` -- reach nothing at all. Where they need something to *happen* rather
than something to call, they use `playground.generate`, a block that generates rows, takes a
while, fails on cue or pads its output, and touches no connection, no URL and no network.

`dg dev` itself needs no network -- the instance, its database and its worker are all local.
The one thing it cannot do is read a state an older dirigent wrote: after a version bump,
delete `.dirigent/state/` first, and `verify.sh` rebuilds what the example needs from empty.

## Seeing what a webhook delivered

`echo-alert` posts its notification to the instance's own playground, and the run is over before
you can read the terminal. The instance keeps its own ledger of what it sent, which is where to
look:

    uv run dg alerts queue
    uv run dg alerts queue --json | jq '.fields | {subject, status, attempt, connection}'

## What stays online

The four `dhis2-*` examples talk to the DHIS2 play server at `https://play.im.dhis2.org`, which
has no stand-in: they need the network and will fail without it.
`dhis2-org-units-to-markdown`'s PDF document also needs the `pandoc/typst:3.11-alpine` image,
which `prepare-offline.sh` pulls; its markdown and HTML document needs no container at all.
`echo-s3` needs the `rustfs/rustfs:1.0.0-rc.4` image and `echo-stream` the
`redpandadata/redpanda:v24.2.18` image, which `prepare-offline.sh` pulls too, and the containers
they run are local. Everything else -- the twelve `echo-*` examples, `dg validate`, `dg dev`,
`dg apply`, `dg run`, the reports -- runs offline.

Of the pack examples, `fhir-to-dhis2` reads its form from the play demo and rehearses its import
there, so it stays online with the `dhis2-*` examples. `climate-sync-and-export` starts its own
open climate service, but that service downloads CHIRPS rainfall from `data.chc.ucsb.edu` and
the chiefdoms come from the play demo, so it stays online too. `chap-prediction` runs offline:
its Chap stack is local and its model trains inside it, and `prepare-offline.sh` pulls the four
images it needs -- `chap-core` and `chap-worker` at the digests `chap/compose.yaml` pins,
`valkey/valkey:8` and `postgres:17`, about 15 GB together.

## The tutorials

`prepare-offline.sh` leaves them beside the examples:

- `docs/basics.pdf` -- The basics, the tutorial every echo example follows.
- `docs/dhis2-tutorial.pdf` -- the DHIS2 tutorial, for the two examples that need a server.

## Verifying on the train

Every `echo-*` example's `verify.sh` starts whatever it needs itself -- an instance on a free
port, and for `echo-s3` and `echo-stream` a container -- so one switch is the whole of it:

    export UV_OFFLINE=1        # uv refuses the network instead of hanging on it

With that set, `./verify.sh` in any echo example, or `./verify-all.sh` at the root, passes with
no network at all. The four `dhis2-*` examples fail without the network, because the play demo
has no stand-in.
