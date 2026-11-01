# everything

Every pipeline from the tutorial examples beside this one except `echo-stream`, and the whole
[dirigent examples corpus](https://github.com/winterop-com/dirigent/tree/main/packages/dirigent-examples/src/dirigent_examples/shelves), in one
project: one instance, one apply, and every pipeline, schema and connection in the same UI.
The documents are copied as they are, comments included; each one's README or shelf is where it
is explained.

`pipelines/` holds the 22 pipelines beside the shelves at its top level and the corpus under
`pipelines/<shelf>/`. `dg validate` and `dg apply` with no argument read the top level alone,
so `setup.sh` and `verify.sh` walk the whole tree: `seed.py` applies it the way
`dg dev --seed pipelines` does.

## Set it up

```bash
./setup.sh
```

On a fresh clone that makes `.env` with the instance key; starts rustfs as `everything-s3` on
port 9000, and Redpanda, RabbitMQ and a PostgreSQL warehouse as the compose project
`everything-services` from `services/compose.yaml` (dirigent's own `infra/compose.queues.yaml`
and the warehouse of `infra/compose.sql.yaml`), with the topic `orders` and the queues
`shop-orders` and `shop-reports`; writes the connections `play`, `source`, `target`,
`artifacts`, `playground`, `playground-auth`, `orders-topic`, `shop-queue` and `warehouse-read`
into `.dirigent/state`; creates the buckets `echo-s3` and `dirigent-archive`; starts `dg dev`
on http://127.0.0.1:4444 in the background; logs in as `admin` / `admin` and keeps the
token in `.env`; creates the ten schemas; applies everything under `pipelines/` through
`seed.py`, which creates what a document carries and applies it without; and writes
echo-alert's rule `echo-failed` with its sink `echo-sink`, the instance's own playground.
Running it again changes nothing that is already right.

A schedule the walk creates is created paused, as `dg dev --seed` does, except echo-schedule's
`every-minute`, which is resumed. So is a source a worker polls or holds, and the corpus's four
stay paused, so the demo does not keep starting runs on its own:
`uv run dg source resume sensor-arrivals arrive` sets one going and
`uv run dg source pause sensor-arrivals arrive` stops it again. An endpoint source stays
listening, because it only acts when it is called.

The instance is on 4444 rather than dg's default 3333: `port: 4444` in `dirigent.yaml`, the
local profile, and every playground address in the documents say so. The other examples beside
this one use 3333, so both can run at once.

To watch the instance's log, start it first in a second terminal and `setup.sh` fills it
instead of starting its own:

```bash
# terminal 2: what bootstrap.sh exports for setup.sh, because dg does not read either from a
# dirigent.yaml or .env in this directory
export DIRIGENT_ENABLED_UNSAFE_BLOCKS='["shell.run","docker.run","docker.build","docker.compose.up","docker.compose.down"]'
export DIRIGENT_STORAGE_CONNECTIONS='s3=artifacts'
uv run dg dev

./setup.sh                                # terminal 1
```

`./setup.sh stop` stops what it started. `DG_PORT` and `S3_PORT` move the two ports. It needs
Docker, and the network for the DHIS2 play demos and the open-data APIs.

In this directory `dg` reads the token from `.env`, so a shell still exporting another example's
`DG_TOKEN` or `DG_URL` wants `unset DG_TOKEN DG_URL` first.

## The pipelines beside the shelves

| Pipeline | From | What it shows | Run it |
| --- | --- | --- | --- |
| `echo-hello` | [echo-hello](../echo-hello) | One step reading the step before it. | `uv run dg run echo-hello --watch` |
| `echo-read` | [echo-read](../echo-read) | One HTTP request to the playground, the answer read back. | `uv run dg run echo-read --watch` |
| `echo-gate` | [echo-gate](../echo-gate) | A JSON Schema gate on the answer, against `playground-answer`. | `uv run dg run echo-gate --watch` |
| `echo-send` | [echo-send](../echo-send) | A send built from the gate's output; skipped behind a refused gate. | `uv run dg run echo-send --watch` |
| `echo-retry` | [echo-retry](../echo-retry) | A refusal beside an outage under one retry budget. Fails by design. | `uv run dg run echo-retry --watch` |
| `echo-fanout` | [echo-fanout](../echo-fanout) | One item per station, one bad item tolerated, a join. | `uv run dg run echo-fanout --watch` |
| `echo-transform` | [echo-transform](../echo-transform) | The three jq verbs between a source and a sink. | `uv run dg run echo-transform --watch` |
| `echo-schedule` | [echo-schedule](../echo-schedule) | A one-minute schedule, firing on its own. | `uv run dg run echo-schedule --watch` |
| `echo-endpoint` | [echo-schedule](../echo-schedule) | An endpoint source, started by a POST to `/endpoints/readings`. | `uv run dg run echo-endpoint --watch` |
| `echo-alert` | [echo-alert](../echo-alert) | A failure, and the `run_failed` alert it raises. Fails by design. | `uv run dg run echo-alert --watch` |
| `playground-unreliable` | this project | The playground's `/unreliable`: two 503s and a 200, kept as rows by `success_status`. | `uv run dg run playground-unreliable --watch` |
| `playground-response-headers` | this project | The playground's `/response-headers`: a content-type and a header chosen, read back. | `uv run dg run playground-response-headers --watch` |
| `playground-auth` | this project | The playground's `/auth`: a 401 bare, a 200 through the `playground-auth` connection. | `uv run dg run playground-auth --watch` |
| `echo-storage` | [echo-storage](../echo-storage) | A round trip through storage, and a run report. | `uv run dg run echo-storage --watch` |
| `echo-s3` | [echo-s3](../echo-s3) | The same through `s3://`, into the rustfs bucket. | `uv run dg run echo-s3 --watch` |
| `dhis2-read-gate-send` | [dhis2-read-gate-send](../dhis2-read-gate-send) | Read, gate and a dry-run import on the play demo. | `uv run dg run dhis2-read-gate-send --watch` |
| `dhis2-metadata-to-storage` | [dhis2-metadata-to-storage](../dhis2-metadata-to-storage) | Organisation units gated, snapshotted and read back. | `uv run dg run dhis2-metadata-to-storage --watch` |
| `dhis2-to-dhis2` | [dhis2-org-unit-sync](../dhis2-org-unit-sync) | Organisation units from 2.44 to 2.42, rehearsed. | `uv run dg run dhis2-to-dhis2 --watch` |
| `dhis2-to-other` | [dhis2-org-unit-sync](../dhis2-org-unit-sync) | Organisation units to another system through jq. | `uv run dg run dhis2-to-other --watch` |
| `other-to-dhis2` | [dhis2-org-unit-sync](../dhis2-org-unit-sync) | Another system's register into DHIS2 through jq, rehearsed. | `uv run dg run other-to-dhis2 --watch` |
| `org-units-to-markdown` | [dhis2-org-units-to-markdown](../dhis2-org-units-to-markdown) | Organisation units as a markdown and an HTML page. | `uv run dg run org-units-to-markdown --watch` |
| `org-units-to-pdf` | [dhis2-org-units-to-markdown](../dhis2-org-units-to-markdown) | The same page as a PDF, from a pandoc container. | `uv run dg run org-units-to-pdf --watch` |

`tutorial/` holds the three documents the echo tutorials step through on the way to theirs,
which an instance does not take: `echo-gate-too-tight` and `echo-gate-carried` carry their own
schemas, and `echo-send-before` is an earlier `echo-send`. They run locally, with an instance
answering the playground on 4444:

```bash
uv run dg run --local tutorial/echo-gate-too-tight.yaml    # fails at the gate, by design
uv run dg run --local tutorial/echo-gate-carried.yaml
uv run dg run --local tutorial/echo-send-before.yaml --schema schemas/playground-answer.json
```

## The corpus

202 documents across 21 shelves and `hello-world`, from dirigent's `examples/` at v0.30.0.
A document with a required parameter or a `${run.window}` reference says so in its command, and
one that starts at a source a worker polls or holds says how to resume that source.
Two changes from the corpus: every `127.0.0.1:3333` is `127.0.0.1:4444`; and
`connections-referenced-vs-carried` builds its absolute URL from a `playground` parameter
rather than spelling out the port, so a run on another instance is a flag.

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`hello-world`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/hello-world.yaml) | Emit a greeting, and nothing else. | `uv run dg run hello-world --watch` |

### composition

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`chained-instances`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/composition/chained-instances.yaml) | Produce a result, then hand it to another dirigent instance's signed endpoint. | `uv run dg run chained-instances --watch -p day=2026-01-01` |
| [`composition-child`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/composition/composition-child.yaml) | Load one region's data for one day. | `uv run dg run composition-child --watch -p region=east -p day=2026-01-01` |
| [`composition-parent`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/composition/composition-parent.yaml) | Run the child pipeline for two regions, waiting for one and not for the other. | `uv run dg run composition-parent --watch -p day=2026-01-01` |

### demo

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`markdown-showcase`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/demo/markdown-showcase.yaml) | Count a list of markdown elements, under a description that uses all of them. | `uv run dg run markdown-showcase --watch` |
| [`params-showcase`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/demo/params-showcase.yaml) | Run once per region, echoing every kind of parameter a run form can ask for. | `uv run dg run params-showcase --watch -p day=2026-01-01 -p dataset=climate` |
| [`requires`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/demo/requires.yaml) | Log in to the playground, post a result, and archive the receipt. | `uv run dg run requires --watch` |
| [`weekly-import-malawi`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/demo/weekly-import-malawi.yaml) | Summarise one week's district import for Malawi. | `uv run dg run weekly-import-malawi --watch` |
| [`weekly-import-nepal`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/demo/weekly-import-nepal.yaml) | Summarise one week's district import for Nepal. | `uv run dg run weekly-import-nepal --watch` |

### docker

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`docker-build-push`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/docker/docker-build-push.yaml) | Build a Docker image and push it to a registry. | not applied: needs ghcr, a registry connection with a push credential |
| [`docker-build-run`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/docker/docker-build-run.yaml) | Write a Dockerfile, build the image, and run it. | `uv run dg run docker-build-run --watch` |
| [`docker-compose-database`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/docker/docker-compose-database.yaml) | Start a PostgreSQL database, run SQL against it, and remove it. | `uv run dg run docker-compose-database --watch` |
| [`docker-compose-failing-up`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/docker/docker-compose-failing-up.yaml) | Start a Docker stack that fails on purpose, and clean up what it left behind. | `uv run dg run docker-compose-failing-up --watch` |
| [`docker-compose-file`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/docker/docker-compose-file.yaml) | Write a compose file, start the stack from it, and tear it down. | `uv run dg run docker-compose-file --watch` |
| [`docker-compose-profiles-env`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/docker/docker-compose-profiles-env.yaml) | Start a Docker stack whose greeting and optional service come from parameters. | `uv run dg run docker-compose-profiles-env --watch` |
| [`docker-compose-stack`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/docker/docker-compose-stack.yaml) | Start a Docker stack, reach it from a container, and tear it down. | `uv run dg run docker-compose-stack --watch` |
| [`docker-hello`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/docker/docker-hello.yaml) | Run a command in a container, with no network and the image pulled first. | `uv run dg run docker-hello --watch` |
| [`docker-remote-daemon`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/docker/docker-remote-daemon.yaml) | Start a Docker stack on a remote daemon, use it, and tear it down. | not applied: needs build-daemon, a remote Docker daemon over TCP and TLS |
| [`docker-run-failing-teardown`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/docker/docker-run-failing-teardown.yaml) | Fail a step on purpose against a Docker stack, and tear the stack down anyway. | `uv run dg run docker-run-failing-teardown --watch` |
| [`docker-ticker`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/docker/docker-ticker.yaml) | Run a container that prints a line every two seconds, streamed to the run log. | `uv run dg run docker-ticker --watch` |

### execute

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`long-log`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/execute/long-log.yaml) | A step that prints a few hundred lines, so a log viewer has something to do. | `uv run dg run long-log --watch` |

### failure

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`error-handler`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/failure/error-handler.yaml) | Load a batch, alert on failure, and always release the lock afterwards. | `uv run dg run error-handler --watch` |
| [`fan-out-too-wide`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/failure/fan-out-too-wide.yaml) | Fail on purpose on a list too long to process, before any item runs. | `uv run dg run fan-out-too-wide --watch` |
| [`optional-step`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/failure/optional-step.yaml) | Import a batch, push metrics on a best-effort basis, and publish either way. | `uv run dg run optional-step --watch` |
| [`retries`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/failure/retries.yaml) | Retry a publish that refuses, then warm an optional cache that is slow. | `uv run dg run retries --watch` |
| [`retry-budget`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/failure/retry-budget.yaml) | Fail on purpose after three attempts at a command that always exits 1. | `uv run dg run retry-budget --watch` |
| [`step-timeout`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/failure/step-timeout.yaml) | Fail on purpose by giving a thirty-second sleep only two seconds to finish. | `uv run dg run step-timeout --watch` |

### git

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`git-checkout-build`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/git/git-checkout-build.yaml) | Check out a public repository, build its Dockerfile, and run the image once. | `uv run dg run git-checkout-build --watch` |
| [`git-checkout-compose`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/git/git-checkout-compose.yaml) | Check out a repository, start the compose file it ships, and tear it down. | `uv run dg run git-checkout-compose --watch` |
| [`git-checkout-public`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/git/git-checkout-public.yaml) | Clone a public repository and report the commit it landed on. | `uv run dg run git-checkout-public --watch` |

### graph

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`deep-chain`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/graph/deep-chain.yaml) | Run ten steps in one line, each reading the one above it. | `uv run dg run deep-chain --watch` |
| [`fan-in`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/graph/fan-in.yaml) | Read several datasets in parallel, then hand the whole batch on in one step. | `uv run dg run fan-in --watch` |
| [`fan-out`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/graph/fan-out.yaml) | Push one payload per region, tolerating a region that refuses it. | `uv run dg run fan-out --watch -p day=2026-01-01` |
| [`linear`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/graph/linear.yaml) | Generate a payload, store it, archive it, then report what was archived. | `uv run dg run linear --watch -p day=2026-01-01` |
| [`parallel-branches`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/graph/parallel-branches.yaml) | Run two branches in parallel and summarise both results. | `uv run dg run parallel-branches --watch` |
| [`parallel-sleep`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/graph/parallel-sleep.yaml) | Run three independent waits at once, and one step that waits for all of them. | `uv run dg run parallel-sleep --watch` |
| [`skip-diamond`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/graph/skip-diamond.yaml) | Verify a load, skip the alarm when it passes, and close out either way. | `uv run dg run skip-diamond --watch` |
| [`wide-fan`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/graph/wide-fan.yaml) | One step splits, eight run at once, one joins them back. | `uv run dg run wide-fan --watch` |

### open-data

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`feeds-composition`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/open-data/feeds-composition.yaml) | Run the Wikidata country table and a WHO extract, then report how each ended. | `uv run dg run feeds-composition --watch` |
| [`gdacs-disaster-updates`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/open-data/gdacs-disaster-updates.yaml) | Fetch GDACS disaster alerts and post the ones the previous day did not have. | `uv run dg run gdacs-disaster-updates --watch --window START..END` |
| [`github-releases-relay`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/open-data/github-releases-relay.yaml) | Pass on new releases of a public GitHub repository, when there are any. | `uv run dg run github-releases-relay --watch` |
| [`hdx-dataset-watch`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/open-data/hdx-dataset-watch.yaml) | Watch an HDX dataset and publish its file links when the dataset changes. | `uv run dg run hdx-dataset-watch --watch` |
| [`kobo-submissions-to-csv`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/open-data/kobo-submissions-to-csv.yaml) | Fetch the submissions for a KoboToolbox form and save them as a csv file. | `uv run dg run kobo-submissions-to-csv --watch -p asset_uid=... -p token=...` |
| [`nominatim-geocode-facilities`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/open-data/nominatim-geocode-facilities.yaml) | Look up the coordinates of a few facility names, one request per second. | `uv run dg run nominatim-geocode-facilities --watch` |
| [`odk-central-submissions`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/open-data/odk-central-submissions.yaml) | Fetch the submissions for an ODK Central form and save them as a csv file. | not applied: needs odk-central, an ODK Central server and an account on it |
| [`open-meteo-weekly-report`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/open-data/open-meteo-weekly-report.yaml) | Fetch a week of daily weather for one place and save it as a csv file. | `uv run dg run open-meteo-weekly-report --watch --window START..END` |
| [`overpass-health-facilities`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/open-data/overpass-health-facilities.yaml) | List hospitals and clinics in an area from OpenStreetMap, as csv and parquet. | `uv run dg run overpass-health-facilities --watch` |
| [`usgs-earthquakes-alert`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/open-data/usgs-earthquakes-alert.yaml) | Post a digest of nearby earthquakes from the past day, only when there are any. | `uv run dg run usgs-earthquakes-alert --watch` |
| [`who-gho-indicators-to-parquet`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/open-data/who-gho-indicators-to-parquet.yaml) | Fetch a WHO health indicator for several countries and save it as parquet. | `uv run dg run who-gho-indicators-to-parquet --watch` |
| [`wikidata-country-reference`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/open-data/wikidata-country-reference.yaml) | Build a table of ISO country codes from Wikidata for other pipelines to read. | `uv run dg run wikidata-country-reference --watch` |
| [`world-bank-population-trend`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/open-data/world-bank-population-trend.yaml) | Work out a country's yearly population growth and save it as a csv file. | `uv run dg run world-bank-population-trend --watch` |

### patterns

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`concurrency-queue`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/concurrency-queue.yaml) | Process a batch, and hold any new run until the current one finishes. | `uv run dg run concurrency-queue --watch` |
| [`concurrency-replace`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/concurrency-replace.yaml) | Render and publish a revision, cancelling any render already in progress. | `uv run dg run concurrency-replace --watch` |
| [`concurrency-skip`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/concurrency-skip.yaml) | Refresh a view, and do nothing if a refresh is already running. | `uv run dg run concurrency-skip --watch` |
| [`connections-referenced-vs-carried`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/connections-referenced-vs-carried.yaml) | Call the same service three ways, and compare the answers. | `uv run dg run connections-referenced-vs-carried --watch` |
| [`deadline-on-a-sensor`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/deadline-on-a-sensor.yaml) | Wait for a file that never arrives, then give up and alert someone. | `uv run dg run deadline-on-a-sensor --watch` |
| [`fan-out-continue`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/fan-out-continue.yaml) | Process a list of items, and let the rest finish when one fails. | `uv run dg run fan-out-continue --watch` |
| [`fan-out-fail-fast`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/fan-out-fail-fast.yaml) | Process a list of items, and fail the whole batch when one fails. | `uv run dg run fan-out-fail-fast --watch` |
| [`fan-out-from-params`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/fan-out-from-params.yaml) | Process each region the caller names when starting the run. | `uv run dg run fan-out-from-params --watch` |
| [`fan-out-item-wise`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/fan-out-item-wise.yaml) | Shape each region's data, write one file per region, and list the files. | `uv run dg run fan-out-item-wise --watch` |
| [`fan-out-late-after-continue`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/fan-out-late-after-continue.yaml) | Check three stations, and publish only the ones that succeeded. | `uv run dg run fan-out-late-after-continue --watch` |
| [`fan-out-late-item-wise`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/fan-out-late-item-wise.yaml) | List stations, take a reading for each, then label each one. | `uv run dg run fan-out-late-item-wise --watch` |
| [`fan-out-literal-list`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/fan-out-literal-list.yaml) | Greet three cities at once from a list written in the document. | `uv run dg run fan-out-literal-list --watch` |
| [`fan-out-nested-objects`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/fan-out-nested-objects.yaml) | Check three feeds, each with its own time limit, and report which were slow. | `uv run dg run fan-out-nested-objects --watch` |
| [`fan-out-over-a-nested-path`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/fan-out-over-a-nested-path.yaml) | Take a list from deep inside a larger answer, and process each item. | `uv run dg run fan-out-over-a-nested-path --watch` |
| [`fan-out-over-an-empty-listing`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/fan-out-over-an-empty-listing.yaml) | List stations, find none, skip the work, and still succeed. | `uv run dg run fan-out-over-an-empty-listing --watch` |
| [`fan-out-over-an-output`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/fan-out-over-an-output.yaml) | List some stations, then take a reading for each one found. | `uv run dg run fan-out-over-an-output --watch` |
| [`fan-out-then-join`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/fan-out-then-join.yaml) | Scale four station readings side by side, then summarise them in one step. | `uv run dg run fan-out-then-join --watch` |
| [`importance-critical`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/importance-critical.yaml) | Reconcile the day's balances at low priority, and treat a failure as critical. | `uv run dg run importance-critical --watch` |
| [`log-levels`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/log-levels.yaml) | Run steps of three kinds, so the logs of one kind can be turned up. | `uv run dg run log-levels --watch` |
| [`outputs-inline-vs-storage`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/outputs-inline-vs-storage.yaml) | Build a large list, save it to storage, and read it back. | `uv run dg run outputs-inline-vs-storage --watch` |
| [`params-every-type`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/params-every-type.yaml) | Try every kind of run parameter, with a default for each so it runs as is. | `uv run dg run params-every-type --watch` |
| [`params-validation-refuses`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/params-validation-refuses.yaml) | Plan a load, and refuse a bad request before any run exists. | `uv run dg run params-validation-refuses --watch` |
| [`pipeline-run-child`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/pipeline-run-child.yaml) | Load one region's data, on its own or when another pipeline calls it. | `uv run dg run pipeline-run-child --watch -p region=east` |
| [`pipeline-run-fire-and-forget`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/pipeline-run-fire-and-forget.yaml) | Run another pipeline twice, waiting for one call and not for the other. | `uv run dg run pipeline-run-fire-and-forget --watch` |
| [`pipeline-run-strict`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/pipeline-run-strict.yaml) | Run another pipeline twice, accepting its errors in only one of the calls. | `uv run dg run pipeline-run-strict --watch` |
| [`pipeline-run-wait`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/pipeline-run-wait.yaml) | Run another pipeline, wait for it to finish, and record how it ended. | `uv run dg run pipeline-run-wait --watch` |
| [`pipeline-run-with-params`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/pipeline-run-with-params.yaml) | Run another pipeline once per region, each with its own parameters. | `uv run dg run pipeline-run-with-params --watch` |
| [`poll-cadence`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/poll-cadence.yaml) | Time the same wait checked every second and every four seconds. | `uv run dg run poll-cadence --watch` |
| [`priority-layered`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/priority-layered.yaml) | Reload four regions at low priority by default, and higher when asked. | `uv run dg run priority-layered --watch` |
| [`references-cheat-sheet`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/references-cheat-sheet.yaml) | Use every way a step can refer to a value, once each. | `uv run dg run references-cheat-sheet --watch --window START..END` |
| [`retry-budget-exhausted`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/retry-budget-exhausted.yaml) | Three attempts against a step that fails every time, then a failed step. | `uv run dg run retry-budget-exhausted --watch` |
| [`retry-exponential-backoff`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/retry-exponential-backoff.yaml) | Retry a failing step with a longer wait each time, until it gives up. | `uv run dg run retry-exponential-backoff --watch` |
| [`retry-only-transient`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/retry-only-transient.yaml) | Fail three steps in three different ways, and see which ones get retried. | `uv run dg run retry-only-transient --watch` |
| [`retry-with-jitter`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/retry-with-jitter.yaml) | Retry four failing jobs at random intervals, so they do not retry at once. | `uv run dg run retry-with-jitter --watch` |
| [`rule-all-done`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/rule-all-done.yaml) | Release a lock even when the load fails, as it does here on purpose. | `uv run dg run rule-all-done --watch` |
| [`rule-all-success`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/rule-all-success.yaml) | Skip the remaining steps when a load fails, as it does here on purpose. | `uv run dg run rule-all-success --watch` |
| [`rule-always`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/rule-always.yaml) | Always deliver a summary, even when a load fails, as it does here. | `uv run dg run rule-always --watch` |
| [`rule-one-failed`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/rule-one-failed.yaml) | Raise an alert when a load fails, as it does here on purpose. | `uv run dg run rule-one-failed --watch` |
| [`schedule-at-once`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/schedule-at-once.yaml) | Run a migration once, at a single moment agreed in advance. | `uv run dg run schedule-at-once --watch` |
| [`schedule-cron-timezone`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/schedule-cron-timezone.yaml) | Load a region's data on three schedules, each in its own time zone. | `uv run dg run schedule-cron-timezone --watch --window START..END` |
| [`schedule-interval`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/schedule-interval.yaml) | Refresh a rolling window of data every hour, and a wider one every six. | `uv run dg run schedule-interval --watch` |
| [`schedule-window-half-open`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/schedule-window-half-open.yaml) | Read the time window a scheduled run covers, with no gaps or overlaps. | `uv run dg run schedule-window-half-open --watch --window START..END` |
| [`sensor-http-ready`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/sensor-http-ready.yaml) | Wait for a service to be ready, then send it a test request. | `uv run dg run sensor-http-ready --watch` |
| [`sensor-storage-exists`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/sensor-storage-exists.yaml) | Wait for a file to land and reach a minimum size, then archive it. | `uv run dg run sensor-storage-exists --watch` |
| [`step-names-and-keys`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/step-names-and-keys.yaml) | Load, check and publish a batch, with two steps sharing one title. | `uv run dg run step-names-and-keys --watch` |
| [`timeout-fails-the-step`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/timeout-fails-the-step.yaml) | Stop a slow step after two seconds and fail the run, on purpose. | `uv run dg run timeout-fails-the-step --watch` |
| [`timeout-skips-the-step`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/timeout-skips-the-step.yaml) | Wait for a file, and skip the work without failing if it never arrives. | `uv run dg run timeout-skips-the-step --watch` |
| [`webhook-signed`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/patterns/webhook-signed.yaml) | Send a webhook signed with a shared secret, and one unsigned to compare. | `uv run dg run webhook-signed --watch` |

### playground

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`a-gate-catching-drift`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/playground/a-gate-catching-drift.yaml) | Check generated records against a schema, with a switch that makes them wrong. | `uv run dg run a-gate-catching-drift --watch` |
| [`a-page-at-a-time`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/playground/a-page-at-a-time.yaml) | Walk one page of generated records, and spill a large result out to storage. | `uv run dg run a-page-at-a-time --watch` |
| [`a-stream-to-read`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/playground/a-stream-to-read.yaml) | Read a streaming response to its end and split it back into lines. | `uv run dg run a-stream-to-read --watch` |
| [`generated-rows`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/playground/generated-rows.yaml) | Generate rows of fake data with no input, and summarise them. | `uv run dg run generated-rows --watch` |
| [`in-the-middle-of-a-flow`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/playground/in-the-middle-of-a-flow.yaml) | Add generated columns to a list from an earlier step, then pass the rows on. | `uv run dg run in-the-middle-of-a-flow --watch` |
| [`retry-that-really-retries`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/playground/retry-that-really-retries.yaml) | A step that fails its first two attempts and succeeds on the third, on purpose. | `uv run dg run retry-that-really-retries --watch` |
| [`waiting-for-a-batch`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/playground/waiting-for-a-batch.yaml) | Wait through a few checks for a generated batch to arrive, then read it. | `uv run dg run waiting-for-a-batch --watch` |

### preview

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`s3-parquet-to-ingestion`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/preview/s3-parquet-to-ingestion.yaml) | Wait for the daily parquet drop, hand each region its address, alert on failure. | not applied: a preview: needs an adapter pack's modelling-api and ops-webhook |

### queues

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`kafka-consume-then-transform`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/queues/kafka-consume-then-transform.yaml) | Wait for messages on a Kafka topic, then reshape the batch. | `uv run dg run kafka-consume-then-transform --watch` |
| [`kafka-produce-then-consume`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/queues/kafka-produce-then-consume.yaml) | Publish records to a Kafka topic and read the same batch back off it. | `uv run dg run kafka-produce-then-consume --watch` |
| [`kafka-source-then-transform`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/queues/kafka-source-then-transform.yaml) | Start one run for each message on a Kafka topic, and reshape its order. | `uv run dg source resume kafka-source-then-transform order`, or once: `uv run dg run kafka-source-then-transform --watch` |
| [`rabbitmq-consume-ack-on-success`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/queues/rabbitmq-consume-ack-on-success.yaml) | Wait for messages on a RabbitMQ queue, then reshape the batch. | `uv run dg run rabbitmq-consume-ack-on-success --watch` |
| [`report-to-kafka`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/queues/report-to-kafka.yaml) | Render a report page and publish it as one record on a Kafka topic. | `uv run dg run report-to-kafka --watch` |
| [`report-to-rabbitmq`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/queues/report-to-rabbitmq.yaml) | Render a report page and publish it as one message on a RabbitMQ queue. | `uv run dg run report-to-rabbitmq --watch` |

### recipes

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`csv-header-rules`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/csv-header-rules.yaml) | Read a csv with uneven rows, and write uneven records out to a csv. | `uv run dg run csv-header-rules --watch` |
| [`csv-to-ndjson`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/csv-to-ndjson.yaml) | Turn a csv into one JSON object per line, then give the cells their real types. | `uv run dg run csv-to-ndjson --watch` |
| [`etl-csv-clean-validate-parquet`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/etl-csv-clean-validate-parquet.yaml) | Clean a messy csv, check it against a schema, and write it to parquet. | `uv run dg run etl-csv-clean-validate-parquet --watch` |
| [`filter-by-predicate`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/filter-by-predicate.yaml) | Keep the rows that pass a yes-or-no check, and report which were dropped. | `uv run dg run filter-by-predicate --watch` |
| [`filter-then-map-then-reduce`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/filter-then-map-then-reduce.yaml) | Keep the usable readings, convert each one, and add them up in a summary. | `uv run dg run filter-then-map-then-reduce --watch` |
| [`http-fetch-validate-post`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/http-fetch-validate-post.yaml) | Fetch data, check it, reshape it, check the result, and post it on. | `uv run dg run http-fetch-validate-post --watch` |
| [`http-follow-redirects`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/http-follow-redirects.yaml) | Call a redirecting URL twice, followed and not, and compare the answers. | `uv run dg run http-follow-redirects --watch` |
| [`http-get-with-query`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/http-get-with-query.yaml) | Send a GET request with query parameters and reshape the JSON answer. | `uv run dg run http-get-with-query --watch` |
| [`http-headers-and-auth-connection`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/http-headers-and-auth-connection.yaml) | Call a password-protected endpoint using credentials held on a connection. | `uv run dg run http-headers-and-auth-connection --watch` |
| [`http-post-file-from-storage`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/http-post-file-from-storage.yaml) | Save a file, read it back, and upload its contents to an endpoint. | `uv run dg run http-post-file-from-storage --watch` |
| [`http-post-json-body`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/http-post-json-body.yaml) | Build a payload, post it as JSON, and read the receipt that comes back. | `uv run dg run http-post-json-body --watch` |
| [`http-post-report`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/http-post-report.yaml) | Post a generated batch, summarise the reply, and write a page about the run. | `uv run dg run http-post-report --watch` |
| [`http-save-body-to-storage`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/http-save-body-to-storage.yaml) | Call an endpoint, save the answer to a file, and read it back for a summary. | `uv run dg run http-save-body-to-storage --watch` |
| [`http-success-status-list`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/http-success-status-list.yaml) | Accept a chosen HTTP error status as success, and report what it meant. | `uv run dg run http-success-status-list --watch` |
| [`http-timeout-override`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/http-timeout-override.yaml) | Give one slow call a longer timeout than its connection allows. | `uv run dg run http-timeout-override --watch` |
| [`jq-dedupe-by-key`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/jq-dedupe-by-key.yaml) | Reduce repeated rows to one per key, and list the keys that repeated. | `uv run dg run jq-dedupe-by-key --watch` |
| [`jq-defaults-and-nulls`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/jq-defaults-and-nulls.yaml) | Fill in missing fields without overwriting false, and see the mistake to avoid. | `uv run dg run jq-defaults-and-nulls --watch` |
| [`jq-group-by-and-sum`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/jq-group-by-and-sum.yaml) | Total two columns for each group of rows, with a grand total alongside. | `uv run dg run jq-group-by-and-sum --watch` |
| [`jq-join-two-lists`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/jq-join-two-lists.yaml) | Join readings to their stations, keeping the ones that match nothing. | `uv run dg run jq-join-two-lists --watch` |
| [`jq-long-to-wide`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/jq-long-to-wide.yaml) | Turn rows with one measurement each into one row per subject. | `uv run dg run jq-long-to-wide --watch` |
| [`jq-nested-to-flat`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/jq-nested-to-flat.yaml) | Flatten nested records into rows that a csv or parquet file can hold. | `uv run dg run jq-nested-to-flat --watch` |
| [`jq-pivot-wide-to-long`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/jq-pivot-wide-to-long.yaml) | Turn a table with one column per measure into one row per measurement. | `uv run dg run jq-pivot-wide-to-long --watch` |
| [`jq-running-totals`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/jq-running-totals.yaml) | Add running totals, daily changes and a moving average to a daily series. | `uv run dg run jq-running-totals --watch` |
| [`jq-string-cleaning`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/jq-string-cleaning.yaml) | Clean up messy text from a spreadsheet, and report which fields changed. | `uv run dg run jq-string-cleaning --watch` |
| [`jq-top-n`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/jq-top-n.yaml) | Keep the top rows by a measure, with ties and the rest summarised. | `uv run dg run jq-top-n --watch` |
| [`jq-validate-in-jq-vs-schema`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/jq-validate-in-jq-vs-schema.yaml) | Sort rows into good and bad, then check the good ones against a schema. | `uv run dg run jq-validate-in-jq-vs-schema --watch` |
| [`jq-window-dates`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/jq-window-dates.yaml) | List the days from a start date and group them into ISO weeks. | `uv run dg run jq-window-dates --watch` |
| [`json-to-csv-flattening`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/json-to-csv-flattening.yaml) | Turn nested JSON into a flat csv with named columns. | `uv run dg run json-to-csv-flattening --watch` |
| [`large-output-to-storage`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/large-output-to-storage.yaml) | Write a large generated result to a named file, and report a small summary. | `uv run dg run large-output-to-storage --watch` |
| [`map-enrich-with-lookup`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/map-enrich-with-lookup.yaml) | Add columns to every row from a lookup table, then compute more per row. | `uv run dg run map-enrich-with-lookup --watch` |
| [`ndjson-to-parquet`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/ndjson-to-parquet.yaml) | Write records to a parquet file and read them back to see what landed. | `uv run dg run ndjson-to-parquet --watch` |
| [`pagination-by-fan-out`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/pagination-by-fan-out.yaml) | Fetch several pages at once, then stitch them into one list. | `uv run dg run pagination-by-fan-out --watch` |
| [`parquet-round-trip-types`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/parquet-round-trip-types.yaml) | Compare what a round trip through parquet and through csv does to each type. | `uv run dg run parquet-round-trip-types --watch` |
| [`reconcile-two-sources`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/reconcile-two-sources.yaml) | Compare two systems' totals, and fail when too many rows disagree. | `uv run dg run reconcile-two-sources --watch` |
| [`report-built-in`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/report-built-in.yaml) | Total sales by region and add the standard run report. | `uv run dg run report-built-in --watch` |
| [`report-daily-digest`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/report-daily-digest.yaml) | Summarise a day's readings, save a csv, and post the digest to a receiver. | `uv run dg run report-daily-digest --watch` |
| [`report-to-file`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/report-to-file.yaml) | Render a report page from a template, save it to a file, and read it back. | `uv run dg run report-to-file --watch` |
| [`report-to-webhook`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/report-to-webhook.yaml) | Render a report page and send it to a receiver as a webhook. | `uv run dg run report-to-webhook --watch` |
| [`schema-carried`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/schema-carried.yaml) | Check a payload against a schema included in the same file. | `uv run dg run schema-carried --watch` |
| [`schema-formats`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/schema-formats.yaml) | Check that a record's strings are real dates, emails, URLs, IDs and digests. | `uv run dg run schema-formats --watch` |
| [`schema-referenced`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/schema-referenced.yaml) | Check a record against a schema stored on the instance. | `uv run dg run schema-referenced --watch` |
| [`schema-refuses-then-rule`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/schema-refuses-then-rule.yaml) | Fail a check on purpose, raise an alert, skip the load, and clean up. | `uv run dg run schema-refuses-then-rule --watch` |
| [`storage-copy-dated-archive`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/storage-copy-dated-archive.yaml) | Save a file, copy it to a dated archive folder, and record what was copied. | `uv run dg run storage-copy-dated-archive --watch` |
| [`storage-exists-gate`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/storage-exists-gate.yaml) | Wait for a file to arrive, then read whichever one turned up. | `uv run dg run storage-exists-gate --watch` |
| [`storage-keep-past-the-run`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/storage-keep-past-the-run.yaml) | Fetch something and save a copy that outlasts the run. | `uv run dg run storage-keep-past-the-run --watch` |
| [`storage-manifest-of-a-fan-out`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/storage-manifest-of-a-fan-out.yaml) | Write one file per region, then list them all in a manifest. | `uv run dg run storage-manifest-of-a-fan-out --watch` |
| [`storage-write-then-read`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/storage-write-then-read.yaml) | Pass work from one step to the next through storage, twice over. | `uv run dg run storage-write-then-read --watch` |
| [`webhook-post-hmac`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/webhook-post-hmac.yaml) | Post an event with a signature the receiver can check, and once without. | `uv run dg run webhook-post-hmac --watch` |
| [`webhook-post-summary`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/recipes/webhook-post-summary.yaml) | Send a receiver a summary of a batch load, with counts and a one-line message. | `uv run dg run webhook-post-summary --watch` |

### s3

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`report-to-s3`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/s3/report-to-s3.yaml) | Render a markdown page from a Jinja template and write it to an object in S3. | `uv run dg run report-to-s3 --watch -p day=2026-01-01` |
| [`s3-copy-and-verify`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/s3/s3-copy-and-verify.yaml) | Copy a file to a published folder in S3, and check it landed before reading it. | `uv run dg run s3-copy-and-verify --watch -p day=2026-01-01` |
| [`s3-csv-report`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/s3/s3-csv-report.yaml) | Shape records into flat rows and write them as a csv object in S3. | `uv run dg run s3-csv-report --watch -p day=2026-01-01` |
| [`s3-parquet-report`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/s3/s3-parquet-report.yaml) | Write typed records as a parquet object in S3, where an analysis can read them. | `uv run dg run s3-parquet-report --watch -p day=2026-01-01` |
| [`s3-round-trip`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/s3/s3-round-trip.yaml) | Copy a local file up to S3, wait until it is there, and copy it back. | `uv run dg run s3-round-trip --watch -p day=2026-01-01` |

### sensors

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`sensor-gate`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/sensors/sensor-gate.yaml) | Wait for a day's file to arrive, then load it; skip the day if it never does. | `uv run dg run sensor-gate --watch -p day=2026-01-01` |
| [`time-window`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/sensors/time-window.yaml) | Wait until the clock is inside a set time window, then do the work it guards. | `uv run dg run time-window --watch` |

### showcase

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`morning-briefing`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/showcase/morning-briefing.yaml) | Filter four feeds, summarise each, and join them into one morning briefing. | `uv run dg run morning-briefing --watch` |
| [`nightly-regional-load`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/showcase/nightly-regional-load.yaml) | Load eight regions overnight, check each one, and write a page about the night. | `uv run dg run nightly-regional-load --watch` |
| [`one-region-refuses`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/showcase/one-region-refuses.yaml) | Load eight regions where one always fails, and report the one that is missing. | `uv run dg run one-region-refuses --watch` |

### sources

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`echo-by-hand`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/sources/echo-by-hand.yaml) | Answer a request by sending its body straight back. | `uv run dg run echo-by-hand --watch` |
| [`greet-by-hand`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/sources/greet-by-hand.yaml) | Answer a request with a greeting for the name in its path. | `uv run dg run greet-by-hand --watch` |
| [`landing-files`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/sources/landing-files.yaml) | Start one run for each CSV that lands in a folder, and say what arrived. | `uv run dg source resume landing-files arrived`, or once: `uv run dg run landing-files --watch` |
| [`sensor-arrivals`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/sources/sensor-arrivals.yaml) | Start one run for each batch of generated messages, and summarise the batch. | `uv run dg source resume sensor-arrivals arrive`, or once: `uv run dg run sensor-arrivals --watch` |
| [`sensor-fan-out-per-message`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/sources/sensor-fan-out-per-message.yaml) | Handle a batch of messages one at a time, so a bad message fails alone. | `uv run dg source resume sensor-fan-out-per-message arrive`, or once: `uv run dg run sensor-fan-out-per-message --watch` |
| [`signed-nested-payload`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/sources/signed-nested-payload.yaml) | Accept a signed request, and keep only the named fields from its nested body. | `uv run dg run signed-nested-payload --watch` |
| [`signup-form`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/sources/signup-form.yaml) | Start a run from a submitted web form, and tidy the fields it carried. | `uv run dg run signup-form --watch` |

### sql

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`duckdb-parquet-to-report`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/sql/duckdb-parquet-to-report.yaml) | Summarise a parquet file with DuckDB, and save the answer as csv. | `uv run dg run duckdb-parquet-to-report --watch` |
| [`sql-postgres-readonly`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/sql/sql-postgres-readonly.yaml) | Query a PostgreSQL warehouse through a connection that cannot write. | `uv run dg run sql-postgres-readonly --watch --window START..END` |
| [`sql-query-to-storage`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/sql/sql-query-to-storage.yaml) | Read a SQLite table and save its rows to a file. | `uv run dg run sql-query-to-storage --watch` |
| [`sql-sqlite-roundtrip`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/sql/sql-sqlite-roundtrip.yaml) | Create a SQLite database, insert rows, and read them back. | `uv run dg run sql-sqlite-roundtrip --watch` |

### transform

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`csv-report`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/transform/csv-report.yaml) | Turn records into flat rows, and save them as a csv file. | `uv run dg run csv-report --watch` |
| [`jq-filter-and-map`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/transform/jq-filter-and-map.yaml) | Keep the active readings, convert each to fahrenheit, and summarise them. | `uv run dg run jq-filter-and-map --watch` |
| [`jq-group-and-aggregate`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/transform/jq-group-and-aggregate.yaml) | Group a flat list of readings by region, aggregate each group, and total them. | `uv run dg run jq-group-and-aggregate --watch` |
| [`jq-join-two-sources`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/transform/jq-join-two-sources.yaml) | Add station details to a list of readings, keeping rows with no match. | `uv run dg run jq-join-two-sources --watch` |
| [`jq-reshape`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/transform/jq-reshape.yaml) | Reshape a payload of readings, then summarise it once for each region. | `uv run dg run jq-reshape --watch` |
| [`jq-stream-through-storage`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/transform/jq-stream-through-storage.yaml) | Save a generated list to a file, read it back, and save the cold readings. | `uv run dg run jq-stream-through-storage --watch` |
| [`ndjson-round-trip`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/transform/ndjson-round-trip.yaml) | Convert a JSON list to one record per line, and back again. | `uv run dg run ndjson-round-trip --watch` |
| [`parquet-round-trip`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/transform/parquet-round-trip.yaml) | Write records to a parquet file, then read them back with their types intact. | `uv run dg run parquet-round-trip --watch` |
| [`std-convert-fan-out`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/transform/std-convert-fan-out.yaml) | Read a csv, average its active readings by region, and write a new csv. | `uv run dg run std-convert-fan-out --watch` |
| [`xml-feed-to-ndjson`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/transform/xml-feed-to-ndjson.yaml) | Read an XML feed as records, average them by region, and convert it to JSON. | `uv run dg run xml-feed-to-ndjson --watch` |
| [`yaml-config-to-json`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/transform/yaml-config-to-json.yaml) | Read a YAML config, pick out what a run needs, and write that back as YAML. | `uv run dg run yaml-config-to-json --watch` |

### triggers

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`at-one-time`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/triggers/at-one-time.yaml) | Run a backfill once, at one agreed moment. | `uv run dg run at-one-time --watch` |
| [`cron-nightly`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/triggers/cron-nightly.yaml) | Run a small load every night at five, Oslo time. | `uv run dg run cron-nightly --watch` |
| [`cron-windowed`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/triggers/cron-windowed.yaml) | Read the day that just closed, every night at five, Oslo time. | `uv run dg run cron-windowed --watch --window START..END` |
| [`document-nightly`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/triggers/document-nightly.yaml) | Set three schedules on a pipeline that another document defines. | a triggers document for `managed-and-manual` |
| [`interval-rolling`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/triggers/interval-rolling.yaml) | Refresh a rolling window every hour, rather than at a set time of day. | `uv run dg run interval-rolling --watch` |
| [`managed-and-manual`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/triggers/managed-and-manual.yaml) | Run a load on two schedules the document manages, beside any made by hand. | `uv run dg run managed-and-manual --watch` |

### validate

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`expects-a-shape`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/validate/expects-a-shape.yaml) | Check a payload against a schema, then read the value that passed. | `uv run dg run expects-a-shape --watch` |
| [`the-shape-is-wrong`](https://github.com/winterop-com/dirigent/blob/main/packages/dirigent-examples/src/dirigent_examples/shelves/validate/the-shape-is-wrong.yaml) | Check a payload that is missing a required field, which fails on purpose. | `uv run dg run the-shape-is-wrong --watch` |

### What is not applied

| Document | Why |
| --- | --- |
| `docker/docker-build-push` | Needs `ghcr`, a registry connection with a push credential. |
| `docker/docker-remote-daemon` | Needs `build-daemon`, a remote Docker daemon over TCP and TLS. |
| `open-data/odk-central-submissions` | Needs `odk-central`, an ODK Central server and an account on it. |
| `preview/s3-parquet-to-ingestion` | A preview: it needs an adapter pack's `modelling-api` and `ops-webhook`. |

`triggers/document-nightly` is applied as what it is, a triggers document for
`managed-and-manual`, and is not a pipeline of its own.

## Verify it

```bash
./verify.sh
```

starts its own rustfs, brokers, warehouse and instance on free ports and a throwaway state, so
it leaves the demo instance on 4444 alone; validates all 224 documents; applies them, and checks
the corpus's polled and held sources landed paused and its endpoints listening; runs the
22 pipelines beside the shelves and the two playground routes on the shelves with their own
assertions, and the three tutorial documents locally;
runs every corpus pipeline through `corpus.py`, six at a time and the docker and git shelves
one at a time after them, each judged on its last run
record against the outcome it is meant to end with; POSTs echo-endpoint's endpoint and waits for
echo-schedule's clock; and stops what it started. Expect about ten minutes. It does not run:

| Pipeline | Why |
| --- | --- |
| `kobo-submissions-to-csv` | Needs a KoboToolbox account: an `asset_uid` and a token. |
| the four above | They are not applied. |
