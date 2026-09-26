# everything

Every pipeline from every example beside this one, and the whole
[dirigent examples corpus](https://github.com/winterop-com/dirigent/tree/main/examples), in one
project: one instance, one apply, and every pipeline, schema and connection in the same UI.
The documents are copied as they are, comments included; each one's README or shelf is where it
is explained.

`pipelines/` holds the 21 pipelines beside the shelves at its top level and the corpus under
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
on http://127.0.0.1:4444 in the background; logs in as `dev` / `dirigent-dev` and keeps the
token in `.env`; creates the ten schemas; applies everything under `pipelines/` through
`seed.py`, which creates what a document carries and applies it without; and writes
echo-alert's rule `echo-failed` with its sink `echo-sink`, the instance's own playground.
Running it again changes nothing that is already right.

A schedule the walk creates is created paused, as `dg dev --seed` does, except echo-schedule's
`every-minute`, which is resumed.

The instance is on 4444 rather than dg's default 3333: `port: 4444` in `dirigent.yaml`, the
local profile, and every playground address in the documents say so. The other examples beside
this one use 3333, so both can run at once.

To watch the instance's log, start it first in a second terminal and `setup.sh` fills it
instead of starting its own:

```bash
uv run dg dev                             # terminal 2
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
| `echo-schedule` | [echo-schedule](../echo-schedule) | A one-minute schedule and an inbound webhook, firing on their own. | `uv run dg run echo-schedule --watch` |
| `echo-alert` | [echo-alert](../echo-alert) | A failure, and the `run_failed` alert it raises. Fails by design. | `uv run dg run echo-alert --watch` |
| `playground-unreliable` | this project | The playground's `/unreliable`: two 503s and a 200, kept as rows by `success_status`. | `uv run dg run playground-unreliable --watch` |
| `playground-response-headers` | this project | The playground's `/response-headers`: a content-type and a header chosen, read back. | `uv run dg run playground-response-headers --watch` |
| `playground-auth` | this project | The playground's `/auth`: a 401 bare, a 200 through the `playground-auth` connection. | `uv run dg run playground-auth --watch` |
| `echo-storage` | [echo-storage](../echo-storage) | A round trip through storage, and a run report. | `uv run dg run echo-storage --watch` |
| `echo-s3` | [echo-s3](../echo-s3) | The same through `s3://`, into the rustfs bucket. | `uv run dg run echo-s3 --watch` |
| `dhis2-read-gate-send` | [dhis2-read-gate-send](../dhis2-read-gate-send) | Read, gate and a dry-run import on the play demo. | `uv run dg run dhis2-read-gate-send --watch` |
| `dhis2-metadata-to-storage` | [dhis2-metadata-to-storage](../dhis2-metadata-to-storage) | Organisation units gated, snapshotted and read back. | `uv run dg run dhis2-metadata-to-storage --watch` |
| `dhis2-to-dhis2` | [dhis2-org-unit-sync](../dhis2-org-unit-sync) | Organisation units from 2.43 to 2.42, rehearsed. | `uv run dg run dhis2-to-dhis2 --watch` |
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

190 documents across 20 shelves and `hello-world`, from dirigent's `examples/` at f6a69199.
A document with a required parameter or a `${run.window}` reference says so in its command.
Three changes from the corpus: every `127.0.0.1:3333` is `127.0.0.1:4444`;
`a-stream-to-read` takes `playground` rather than `instance`; and
`connections-referenced-vs-carried` builds its absolute URL from a `playground` parameter
rather than spelling out the port, so a run on another instance is a flag. `a-stream-to-read`
needs the dirigent after 0.19: on 0.19 its route answers 404.

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`hello-world`](https://github.com/winterop-com/dirigent/tree/main/examples/hello-world.yaml) | Emit a greeting, and nothing else. | `uv run dg run hello-world --watch` |

### composition

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`chained-instances`](https://github.com/winterop-com/dirigent/tree/main/examples/composition/chained-instances.yaml) | Produce a result, then hand it to another dirigent instance as a signed webhook. | `uv run dg run chained-instances --watch -p day=2026-01-01` |
| [`composition-child`](https://github.com/winterop-com/dirigent/tree/main/examples/composition/composition-child.yaml) | Load one region's data for one day; callable on its own or by a parent pipeline. | `uv run dg run composition-child --watch -p region=east -p day=2026-01-01` |
| [`composition-parent`](https://github.com/winterop-com/dirigent/tree/main/examples/composition/composition-parent.yaml) | Run the child pipeline for two regions, waiting for one and not for the other. | `uv run dg run composition-parent --watch -p day=2026-01-01` |

### demo

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`markdown-showcase`](https://github.com/winterop-com/dirigent/tree/main/examples/demo/markdown-showcase.yaml) | A pipeline whose **description** is the point. | `uv run dg run markdown-showcase --watch` |
| [`params-showcase`](https://github.com/winterop-com/dirigent/tree/main/examples/demo/params-showcase.yaml) | Everything a run form is built from, in one parameter schema. | `uv run dg run params-showcase --watch -p day=2026-01-01 -p dataset=climate` |
| [`requires`](https://github.com/winterop-com/dirigent/tree/main/examples/demo/requires.yaml) | Declare the blocks and connections this document cannot run without. | `uv run dg run requires --watch` |
| [`weekly-import-malawi`](https://github.com/winterop-com/dirigent/tree/main/examples/demo/weekly-import-malawi.yaml) | The Malawi half of a deliberately ambiguous pair. | `uv run dg run weekly-import-malawi --watch` |
| [`weekly-import-nepal`](https://github.com/winterop-com/dirigent/tree/main/examples/demo/weekly-import-nepal.yaml) | The Nepal half of a deliberately ambiguous pair. | `uv run dg run weekly-import-nepal --watch` |

### docker

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`docker-build-push`](https://github.com/winterop-com/dirigent/tree/main/examples/docker/docker-build-push.yaml) | Build an image from a context in the work directory and push every tag to the registry a docker connection names. | not applied: needs ghcr, a registry connection with a push credential |
| [`docker-build-run`](https://github.com/winterop-com/dirigent/tree/main/examples/docker/docker-build-run.yaml) | Write a Dockerfile into the run's work directory, build it with buildx, and run the tag. | `uv run dg run docker-build-run --watch` |
| [`docker-compose-database`](https://github.com/winterop-com/dirigent/tree/main/examples/docker/docker-compose-database.yaml) | Bring PostgreSQL up behind its healthcheck, run SQL against it, and remove it with its volumes. | `uv run dg run docker-compose-database --watch` |
| [`docker-compose-failing-up`](https://github.com/winterop-com/dirigent/tree/main/examples/docker/docker-compose-failing-up.yaml) | A service whose healthcheck never passes, so the bring-up fails and cleans up after itself. | `uv run dg run docker-compose-failing-up --watch` |
| [`docker-compose-file`](https://github.com/winterop-com/dirigent/tree/main/examples/docker/docker-compose-file.yaml) | Write a compose file into the run's work directory, bring the stack up from that path, and tear it down. | `uv run dg run docker-compose-file --watch` |
| [`docker-compose-profiles-env`](https://github.com/winterop-com/dirigent/tree/main/examples/docker/docker-compose-profiles-env.yaml) | A compose stack whose greeting comes from a parameter and whose optional service comes from a profile. | `uv run dg run docker-compose-profiles-env --watch` |
| [`docker-compose-stack`](https://github.com/winterop-com/dirigent/tree/main/examples/docker/docker-compose-stack.yaml) | Bring a two-service stack up, reach it from a container, and tear it down on any outcome. | `uv run dg run docker-compose-stack --watch` |
| [`docker-hello`](https://github.com/winterop-com/dirigent/tree/main/examples/docker/docker-hello.yaml) | Run a command in a container, with no network and the image pulled first. | `uv run dg run docker-hello --watch` |
| [`docker-remote-daemon`](https://github.com/winterop-com/dirigent/tree/main/examples/docker/docker-remote-daemon.yaml) | Bring a stack up, drive it and tear it down on the daemon a docker connection names. | not applied: needs build-daemon, a remote Docker daemon over TCP and TLS |
| [`docker-run-failing-teardown`](https://github.com/winterop-com/dirigent/tree/main/examples/docker/docker-run-failing-teardown.yaml) | A container that reaches the stack and then exits 1, with the teardown running on any outcome. | `uv run dg run docker-run-failing-teardown --watch` |
| [`docker-ticker`](https://github.com/winterop-com/dirigent/tree/main/examples/docker/docker-ticker.yaml) | A container printing a line every two seconds, streamed into the run as it goes. | `uv run dg run docker-ticker --watch` |

### execute

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`long-log`](https://github.com/winterop-com/dirigent/tree/main/examples/execute/long-log.yaml) | A step that prints a few hundred lines, so a log viewer has something to do. | `uv run dg run long-log --watch` |

### failure

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`error-handler`](https://github.com/winterop-com/dirigent/tree/main/examples/failure/error-handler.yaml) | Load a batch, alert on failure, and always release the lock afterwards. | `uv run dg run error-handler --watch` |
| [`optional-step`](https://github.com/winterop-com/dirigent/tree/main/examples/failure/optional-step.yaml) | Import a batch, push metrics on a best-effort basis, and publish either way. | `uv run dg run optional-step --watch` |
| [`retries`](https://github.com/winterop-com/dirigent/tree/main/examples/failure/retries.yaml) | Publish through a step that refuses, then warm an optional cache that is slow. | `uv run dg run retries --watch` |
| [`retry-budget`](https://github.com/winterop-com/dirigent/tree/main/examples/failure/retry-budget.yaml) | A local command that always exits 1, given three attempts to prove it. | `uv run dg run retry-budget --watch` |
| [`step-timeout`](https://github.com/winterop-com/dirigent/tree/main/examples/failure/step-timeout.yaml) | A sleep that is asked to take thirty seconds, given two. | `uv run dg run step-timeout --watch` |

### git

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`git-checkout-build`](https://github.com/winterop-com/dirigent/tree/main/examples/git/git-checkout-build.yaml) | Check a public repository out, build the Dockerfile it ships, and run the image once. | `uv run dg run git-checkout-build --watch` |
| [`git-checkout-compose`](https://github.com/winterop-com/dirigent/tree/main/examples/git/git-checkout-compose.yaml) | Check a repository out, bring up the compose file it ships, probe it, and tear it down. | `uv run dg run git-checkout-compose --watch` |
| [`git-checkout-public`](https://github.com/winterop-com/dirigent/tree/main/examples/git/git-checkout-public.yaml) | Clone a public repository at its default branch into the run's work directory and report the commit. | `uv run dg run git-checkout-public --watch` |

### graph

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`deep-chain`](https://github.com/winterop-com/dirigent/tree/main/examples/graph/deep-chain.yaml) | Ten steps in one line, each reading the one above it. | `uv run dg run deep-chain --watch` |
| [`fan-in`](https://github.com/winterop-com/dirigent/tree/main/examples/graph/fan-in.yaml) | Read several datasets in parallel, then hand the whole batch on in one step. | `uv run dg run fan-in --watch` |
| [`fan-out`](https://github.com/winterop-com/dirigent/tree/main/examples/graph/fan-out.yaml) | Push one payload per region, tolerating a region that refuses it. | `uv run dg run fan-out --watch -p day=2026-01-01` |
| [`linear`](https://github.com/winterop-com/dirigent/tree/main/examples/graph/linear.yaml) | Generate a payload, store it, archive the object, then report what was archived. | `uv run dg run linear --watch -p day=2026-01-01` |
| [`parallel-branches`](https://github.com/winterop-com/dirigent/tree/main/examples/graph/parallel-branches.yaml) | Run two branches in parallel and summarise both results. | `uv run dg run parallel-branches --watch` |
| [`parallel-sleep`](https://github.com/winterop-com/dirigent/tree/main/examples/graph/parallel-sleep.yaml) | Three independent waits that run at once, and one step that waits for all of them. | `uv run dg run parallel-sleep --watch` |
| [`skip-diamond`](https://github.com/winterop-com/dirigent/tree/main/examples/graph/skip-diamond.yaml) | A load that works, an alarm that is therefore skipped, and a close-out that runs either way. | `uv run dg run skip-diamond --watch` |
| [`wide-fan`](https://github.com/winterop-com/dirigent/tree/main/examples/graph/wide-fan.yaml) | One step splits, eight run at once, one joins them back. | `uv run dg run wide-fan --watch` |

### open-data

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`feeds-composition`](https://github.com/winterop-com/dirigent/tree/main/examples/open-data/feeds-composition.yaml) | One document that runs two others: the **Wikidata** country reference and the **WHO GHO** indicator extract, then reports how each child ended. | `uv run dg run feeds-composition --watch` |
| [`gdacs-disaster-updates`](https://github.com/winterop-com/dirigent/tree/main/examples/open-data/gdacs-disaster-updates.yaml) | Disaster events active inside the run's window, read from the **GDACS** event list, deduplicated against the previous day's list and posted onward. | `uv run dg run gdacs-disaster-updates --watch --window START..END` |
| [`github-releases-relay`](https://github.com/winterop-com/dirigent/tree/main/examples/open-data/github-releases-relay.yaml) | Releases of a public repository published since a floor, read from **GitHub's REST API** without a token, and relayed onward -- only when there are any. | `uv run dg run github-releases-relay --watch` |
| [`hdx-dataset-watch`](https://github.com/winterop-com/dirigent/tree/main/examples/open-data/hdx-dataset-watch.yaml) | Poll one **HDX** (CKAN) dataset for a new `metadata_modified`, comparing against a marker object in storage, and publish the resource url list when it moves. | `uv run dg run hdx-dataset-watch --watch` |
| [`kobo-submissions-to-csv`](https://github.com/winterop-com/dirigent/tree/main/examples/open-data/kobo-submissions-to-csv.yaml) | Submissions for one **KoboToolbox** form, flattened to named columns and written as csv. | `uv run dg run kobo-submissions-to-csv --watch -p asset_uid=... -p token=...` |
| [`nominatim-geocode-facilities`](https://github.com/winterop-com/dirigent/tree/main/examples/open-data/nominatim-geocode-facilities.yaml) | A handful of facility names geocoded through **Nominatim**, one request per second, joined into one table of coordinates. | `uv run dg run nominatim-geocode-facilities --watch` |
| [`odk-central-submissions`](https://github.com/winterop-com/dirigent/tree/main/examples/open-data/odk-central-submissions.yaml) | Submissions for one **ODK Central** form, read from its OData feed through a connection that holds the credential, flattened to named columns and written as csv. | not applied: needs odk-central, an ODK Central server and an account on it |
| [`open-meteo-weekly-report`](https://github.com/winterop-com/dirigent/tree/main/examples/open-data/open-meteo-weekly-report.yaml) | A week of daily temperature and precipitation for one coordinate, read from the **Open-Meteo archive API**, transposed from columns to rows and written as csv. | `uv run dg run open-meteo-weekly-report --watch --window START..END` |
| [`overpass-health-facilities`](https://github.com/winterop-com/dirigent/tree/main/examples/open-data/overpass-health-facilities.yaml) | Hospitals and clinics inside a bounding box, read from the **Overpass API**, flattened into rows and written twice: csv for a person and parquet for the next pipeline. | `uv run dg run overpass-health-facilities --watch` |
| [`usgs-earthquakes-alert`](https://github.com/winterop-com/dirigent/tree/main/examples/open-data/usgs-earthquakes-alert.yaml) | The **USGS** past-day earthquake feed, filtered by magnitude and great-circle distance from a point, posted onward as a digest -- and posted only when something matched. | `uv run dg run usgs-earthquakes-alert --watch` |
| [`who-gho-indicators-to-parquet`](https://github.com/winterop-com/dirigent/tree/main/examples/open-data/who-gho-indicators-to-parquet.yaml) | One **GHO** indicator fetched once per country, flattened out of the OData envelopes into one table and written as parquet, with a manifest counting what came back. | `uv run dg run who-gho-indicators-to-parquet --watch` |
| [`wikidata-country-reference`](https://github.com/winterop-com/dirigent/tree/main/examples/open-data/wikidata-country-reference.yaml) | ISO 3166-1 alpha-2, alpha-3 and numeric codes for every sovereign state, read from **Wikidata** over SPARQL and saved as a json reference table other pipelines read. | `uv run dg run wikidata-country-reference --watch` |
| [`world-bank-population-trend`](https://github.com/winterop-com/dirigent/tree/main/examples/open-data/world-bank-population-trend.yaml) | One country's population series from the **World Bank indicator API**, with year-on-year growth computed in jq, checked against a carried schema and written as csv. | `uv run dg run world-bank-population-trend --watch` |

### patterns

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`concurrency-queue`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/concurrency-queue.yaml) | `concurrency: queue` creates the second run and holds it: no step advances until the slot is free, and then the oldest held run is released. | `uv run dg run concurrency-queue --watch` |
| [`concurrency-replace`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/concurrency-replace.yaml) | `concurrency: replace` cancels every run in flight, telling any remote about the attempts that had one, and starts the new run. | `uv run dg run concurrency-replace --watch` |
| [`concurrency-skip`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/concurrency-skip.yaml) | `concurrency: skip` creates no run at all when one is already in flight: not queued, not deferred, nothing. | `uv run dg run concurrency-skip --watch` |
| [`connections-referenced-vs-carried`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/connections-referenced-vs-carried.yaml) | A step names a connection by code and the instance holds the credential, encrypted at rest and redacted in every response. | `uv run dg run connections-referenced-vs-carried --watch` |
| [`deadline-on-a-sensor`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/deadline-on-a-sensor.yaml) | `poll`, `deadline` and `on_timeout` are step-level engine semantics, uniform across every sensor and never buried in a block's config. | `uv run dg run deadline-on-a-sensor --watch` |
| [`fan-out-continue`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/fan-out-continue.yaml) | `items: continue` lets the surviving elements finish. | `uv run dg run fan-out-continue --watch` |
| [`fan-out-fail-fast`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/fan-out-fail-fast.yaml) | `items: fail_fast` is the default: one failed element fails the whole fan-out step, and nothing downstream reads a partial batch. | `uv run dg run fan-out-fail-fast --watch` |
| [`fan-out-from-params`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/fan-out-from-params.yaml) | `for_each: "${params.regions}"` lets the caller decide how wide the run is, while the parameter schema keeps that from meaning anything at all. | `uv run dg run fan-out-from-params --watch` |
| [`fan-out-item-wise`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/fan-out-item-wise.yaml) | `for_each: ${steps.<name>.items}` maps a step over another fan-out's grid, so the two are paired by item position and `${steps.<name>.item.output}` is the matching item's output. | `uv run dg run fan-out-item-wise --watch` |
| [`fan-out-literal-list`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/fan-out-literal-list.yaml) | `for_each` written as a list in the document: one step definition, one run item per element, all claimable at once. | `uv run dg run fan-out-literal-list --watch` |
| [`fan-out-nested-objects`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/fan-out-nested-objects.yaml) | A `for_each` element is any JSON value. | `uv run dg run fan-out-nested-objects --watch` |
| [`fan-out-then-join`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/fan-out-then-join.yaml) | A step joins a fan-out by depending on it and having no `for_each` of its own: one attempt, and the batch arrives as a JSON array of the items' outputs. | `uv run dg run fan-out-then-join --watch` |
| [`importance-critical`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/importance-critical.yaml) | `importance` is one word -- `routine`, `normal` or `critical` -- and it says how much this pipeline matters, not when its work is claimed. | `uv run dg run importance-critical --watch` |
| [`log-levels`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/log-levels.yaml) | `--log-level` is a **run** setting, not a document one: `debug` for everything, or `PATTERN=LEVEL` for one block family, repeatable. | `uv run dg run log-levels --watch` |
| [`outputs-inline-vs-storage`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/outputs-inline-vs-storage.yaml) | A value travels in a step's output. | `uv run dg run outputs-inline-vs-storage --watch` |
| [`params-every-type`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/params-every-type.yaml) | The six JSON Schema types and the keywords that constrain each of them, with every parameter carrying a default so the document runs bare. | `uv run dg run params-every-type --watch` |
| [`params-validation-refuses`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/params-validation-refuses.yaml) | Parameters are validated when the run is **created**, so a bad request produces no run at all: nothing to find in `dg runs list`, and no side effect anywhere. | `uv run dg run params-validation-refuses --watch` |
| [`pipeline-run-child`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/pipeline-run-child.yaml) | An ordinary pipeline that four composition examples call. | `uv run dg run pipeline-run-child --watch -p region=east` |
| [`pipeline-run-fire-and-forget`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/pipeline-run-fire-and-forget.yaml) | `wait: false` finishes the step as soon as the child run exists, reporting `started` and the child's run id. | `uv run dg run pipeline-run-fire-and-forget --watch` |
| [`pipeline-run-strict`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/pipeline-run-strict.yaml) | `completed_with_errors` is a third status, and whether it is acceptable is the caller's judgement: `strict: false` (the default) passes it, `strict: true` fails the step on it. | `uv run dg run pipeline-run-strict --watch` |
| [`pipeline-run-wait`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/pipeline-run-wait.yaml) | `pipeline.run` with the default `wait: true` finishes when the child finishes, and the child's status becomes the step's outcome. | `uv run dg run pipeline-run-wait --watch` |
| [`pipeline-run-with-params`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/pipeline-run-with-params.yaml) | A parent writes its child's parameters out explicitly; they are validated against the **child's** schema when the step executes, not when the parent is applied. | `uv run dg run pipeline-run-with-params --watch` |
| [`poll-cadence`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/poll-cadence.yaml) | The same wait polled every second and every four seconds, with the difference in `waited_ms` reported. | `uv run dg run poll-cadence --watch` |
| [`priority-layered`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/priority-layered.yaml) | `priority` is one word -- `low`, `normal` or `high` -- and it layers: the document declares the default, a schedule or webhook overrides it for what it triggers, and `dg run --priority` overrides it once more. | `uv run dg run priority-layered --watch` |
| [`references-cheat-sheet`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/references-cheat-sheet.yaml) | Five namespaces -- `params`, `steps`, `item`, `run`, `artifacts` -- and no expressions, conditionals or functions anywhere. | `uv run dg run references-cheat-sheet --watch --window START..END` |
| [`retry-budget-exhausted`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/retry-budget-exhausted.yaml) | Three attempts against a step that fails every time, then a failed step. | `uv run dg run retry-budget-exhausted --watch` |
| [`retry-exponential-backoff`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/retry-exponential-backoff.yaml) | The five retry fields and the delays they compute: `backoff`, `multiplier`, `max_backoff`, `jitter`, and the `max_attempts` that counts the first try. | `uv run dg run retry-exponential-backoff --watch` |
| [`retry-only-transient`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/retry-only-transient.yaml) | The same three-attempt budget on two steps: a transient failure spends all three, a rejected one spends one. | `uv run dg run retry-only-transient --watch` |
| [`retry-with-jitter`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/retry-with-jitter.yaml) | `jitter` spreads each computed backoff randomly, so four items that failed together do not retry together and rebuild the herd that took the dependency down. | `uv run dg run retry-with-jitter --watch` |
| [`rule-all-done`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/rule-all-done.yaml) | `rule: all_done` runs a step once every prerequisite has **settled**, whatever it settled as. | `uv run dg run rule-all-done --watch` |
| [`rule-all-success`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/rule-all-success.yaml) | The default trigger rule: a step runs once every prerequisite **succeeded**. | `uv run dg run rule-all-success --watch` |
| [`rule-always`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/rule-always.yaml) | `rule: always` runs a step once every prerequisite has settled, whatever they settled as and however many of them were skipped. | `uv run dg run rule-always --watch` |
| [`rule-one-failed`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/rule-one-failed.yaml) | `rule: one_failed` runs a step only when a prerequisite **failed**, and skips it when none did. | `uv run dg run rule-one-failed --watch` |
| [`schedule-at-once`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/schedule-at-once.yaml) | `at:` fires once, at a single instant, and then pauses itself so its parameters and firing history stay readable. | `uv run dg run schedule-at-once --watch` |
| [`schedule-cron-timezone`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/schedule-cron-timezone.yaml) | Five columns and the zone that decides what they mean. | `uv run dg run schedule-cron-timezone --watch` |
| [`schedule-interval`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/schedule-interval.yaml) | An interval is a cadence rather than a calendar moment: a duration is the same length in every zone, so nothing here consults a clock face. | `uv run dg run schedule-interval --watch` |
| [`schedule-window-half-open`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/schedule-window-half-open.yaml) | `${run.window.start}` and `${run.window.end}` are the interval a run covers: half-open, so consecutive firings tile the timeline without overlapping or leaving a gap. | `uv run dg run schedule-window-half-open --watch --window START..END` |
| [`sensor-http-ready`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/sensor-http-ready.yaml) | `http.ready` pokes an endpoint until it answers ready. | `uv run dg run sensor-http-ready --watch` |
| [`sensor-storage-exists`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/sensor-storage-exists.yaml) | `storage.exists` waits for an object at a URI, which may end in a **glob**, and ignores it until it is at least `min_size` -- the guard against opening a file a producer is still uploading. | `uv run dg run sensor-storage-exists --watch` |
| [`step-names-and-keys`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/step-names-and-keys.yaml) | A step's map **key** is its code: the only thing anything references, and what `${steps.<key>.output...}` names. | `uv run dg run step-names-and-keys --watch` |
| [`timeout-fails-the-step`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/timeout-fails-the-step.yaml) | `timeout` bounds one block call. | `uv run dg run timeout-fails-the-step --watch` |
| [`timeout-skips-the-step`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/timeout-skips-the-step.yaml) | `on_timeout: skip` turns an expired **deadline** into a skipped step rather than a failed one, and the skip carries down the branch through the default `all_success` edges. | `uv run dg run timeout-skips-the-step --watch` |
| [`webhook-mapping-nested-payload`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/webhook-mapping-nested-payload.yaml) | `params_from_payload` maps JSONPaths in the delivered body onto parameters, and that mapping is the whole interface: unmapped fields are ignored, unmapped parameters are unreachable, and what is mapped is validated like any other run's parameters. | `uv run dg run webhook-mapping-nested-payload --watch` |
| [`webhook-signed`](https://github.com/winterop-com/dirigent/tree/main/examples/patterns/webhook-signed.yaml) | `webhook.post` with `sign_with` presents `X-Dirigent-Signature` over the exact bytes it sends, computed the way dirigent's own inbound `/hooks/{token}` verifies one. | `uv run dg run webhook-signed --watch` |

### playground

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`a-gate-catching-drift`](https://github.com/winterop-com/dirigent/tree/main/examples/playground/a-gate-catching-drift.yaml) | Generated records against a carried JSON Schema, with a knob that makes the shape wrong. | `uv run dg run a-gate-catching-drift --watch` |
| [`a-page-at-a-time`](https://github.com/winterop-com/dirigent/tree/main/examples/playground/a-page-at-a-time.yaml) | One page of a generated hundred, walked element by element, with filler that pushes the step's output past the inline limit and out to storage. | `uv run dg run a-page-at-a-time --watch` |
| [`a-stream-to-read`](https://github.com/winterop-com/dirigent/tree/main/examples/playground/a-stream-to-read.yaml) | The playground's streaming route, read by a step and split back into its lines. | `uv run dg run a-stream-to-read --watch` |
| [`generated-rows`](https://github.com/winterop-com/dirigent/tree/main/examples/playground/generated-rows.yaml) | A first step that needs no input: a field map of Faker providers, a row count and a seed. | `uv run dg run generated-rows --watch` |
| [`in-the-middle-of-a-flow`](https://github.com/winterop-com/dirigent/tree/main/examples/playground/in-the-middle-of-a-flow.yaml) | A list from upstream, enriched with generated columns, then handed to the node again as the document's last step. | `uv run dg run in-the-middle-of-a-flow --watch` |
| [`retry-that-really-retries`](https://github.com/winterop-com/dirigent/tree/main/examples/playground/retry-that-really-retries.yaml) | A step that fails its first two attempts and succeeds on the third, on purpose. | `uv run dg run retry-that-really-retries --watch` |
| [`waiting-for-a-batch`](https://github.com/winterop-com/dirigent/tree/main/examples/playground/waiting-for-a-batch.yaml) | A sensor that answers "not yet" for a few pokes and then hands over a generated batch. | not applied: its block playground.arrive is not in dirigent 0.19 |

### preview

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`s3-parquet-to-ingestion`](https://github.com/winterop-com/dirigent/tree/main/examples/preview/s3-parquet-to-ingestion.yaml) | Wait for the daily parquet drop, hand each region its address, alert on failure. | not applied: a preview: needs an adapter pack's modelling-api and ops-webhook |

### queues

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`kafka-consume-then-transform`](https://github.com/winterop-com/dirigent/tree/main/examples/queues/kafka-consume-then-transform.yaml) | Wait for messages on a Kafka topic and reshape the batch the sensor handed on. | `uv run dg run kafka-consume-then-transform --watch` |
| [`kafka-produce-then-consume`](https://github.com/winterop-com/dirigent/tree/main/examples/queues/kafka-produce-then-consume.yaml) | Publish records to a Kafka topic and read the same batch back off it. | `uv run dg run kafka-produce-then-consume --watch` |
| [`rabbitmq-consume-ack-on-success`](https://github.com/winterop-com/dirigent/tree/main/examples/queues/rabbitmq-consume-ack-on-success.yaml) | Wait for messages on a RabbitMQ queue and reshape the batch, handing a short batch back to the queue. | `uv run dg run rabbitmq-consume-ack-on-success --watch` |
| [`report-to-kafka`](https://github.com/winterop-com/dirigent/tree/main/examples/queues/report-to-kafka.yaml) | Render a markdown page from a Jinja template and publish it as one record on a Kafka topic. | `uv run dg run report-to-kafka --watch` |
| [`report-to-rabbitmq`](https://github.com/winterop-com/dirigent/tree/main/examples/queues/report-to-rabbitmq.yaml) | Render a markdown page from a Jinja template and publish it as one message on a RabbitMQ queue. | `uv run dg run report-to-rabbitmq --watch` |

### recipes

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`csv-header-rules`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/csv-header-rules.yaml) | How the csv codec reads a ragged file and writes a union header, and the two headers it refuses to read at all. | `uv run dg run csv-header-rules --watch` |
| [`csv-to-ndjson`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/csv-to-ndjson.yaml) | Re-spell a csv as one JSON object per line, then give the string cells the types the columns actually have. | `uv run dg run csv-to-ndjson --watch` |
| [`etl-csv-clean-validate-parquet`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/etl-csv-clean-validate-parquet.yaml) | Parse a messy csv, clean and type it, sort out the unloadable rows, hold the rest to a schema, and write parquet. | `uv run dg run etl-csv-clean-validate-parquet --watch` |
| [`filter-by-predicate`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/filter-by-predicate.yaml) | Keep the elements a true-or-false program accepts, unmodified and in order, and report how many were dropped. | `uv run dg run filter-by-predicate --watch` |
| [`filter-then-map-then-reduce`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/filter-then-map-then-reduce.yaml) | Keep the usable readings, convert each one, and fold the result into a summary with reduce. | `uv run dg run filter-then-map-then-reduce --watch` |
| [`http-fetch-validate-post`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/http-fetch-validate-post.yaml) | The full shape: a GET from an endpoint, a schema gate on what came back, a jq reshaping, a second gate on what was made, and a POST of the result. | `uv run dg run http-fetch-validate-post --watch` |
| [`http-follow-redirects`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/http-follow-redirects.yaml) | Make the same redirecting call twice, with and without follow_redirects, and compare the status and the Location header. | `uv run dg run http-follow-redirects --watch` |
| [`http-get-with-query`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/http-get-with-query.yaml) | Build a GET whose query is a map rather than a hand-written string, and reshape the JSON body it answers with. | `uv run dg run http-get-with-query --watch` |
| [`http-headers-and-auth-connection`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/http-headers-and-auth-connection.yaml) | Call a basic-auth endpoint through a connection that holds the credentials, with the step contributing only non-secret headers. | `uv run dg run http-headers-and-auth-connection --watch` |
| [`http-post-file-from-storage`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/http-post-file-from-storage.yaml) | Write a file into the run's scratch space, read it back with storage.read, and POST what the read brought back. | `uv run dg run http-post-file-from-storage --watch` |
| [`http-post-json-body`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/http-post-json-body.yaml) | Build a payload upstream, POST it as structure rather than as text, and read the receipt the endpoint answers with. | `uv run dg run http-post-json-body --watch` |
| [`http-post-report`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/http-post-report.yaml) | POST a generated batch to the playground, summarise the receipt, and render the run's own markdown report from the run's facts and its steps' outputs. | `uv run dg run http-post-report --watch` |
| [`http-save-body-to-storage`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/http-save-body-to-storage.yaml) | Call an endpoint, write the body it answered with to a storage URI, and read the file back for a summary. | `uv run dg run http-save-body-to-storage --watch` |
| [`http-success-status-list`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/http-success-status-list.yaml) | Accept a specific non-2xx as success for one call with success_status, and branch on what the status actually meant. | `uv run dg run http-success-status-list --watch` |
| [`http-timeout-override`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/http-timeout-override.yaml) | Override a connection's timeout for one slow call, under an engine step deadline that covers the whole attempt. | `uv run dg run http-timeout-override --watch` |
| [`jq-dedupe-by-key`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/jq-dedupe-by-key.yaml) | Collapse repeated rows to one per key by first seen, last seen, and newest timestamp, and list the keys that repeated. | `uv run dg run jq-dedupe-by-key --watch` |
| [`jq-defaults-and-nulls`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/jq-defaults-and-nulls.yaml) | Distinguish absent, null, false, and empty when defaulting fields, and show what the alternative operator gets wrong. | `uv run dg run jq-defaults-and-nulls --watch` |
| [`jq-group-by-and-sum`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/jq-group-by-and-sum.yaml) | Bucket flat rows by one column, total two numeric columns per bucket, and keep a grand total beside them. | `uv run dg run jq-group-by-and-sum --watch` |
| [`jq-join-two-lists`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/jq-join-two-lists.yaml) | Join readings to their station dimension with INDEX, keeping the unmatched rows in a list of their own. | `uv run dg run jq-join-two-lists --watch` |
| [`jq-long-to-wide`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/jq-long-to-wide.yaml) | Widen one-record-per-measurement rows into one row per subject, with an explicit fill in every unreported cell. | `uv run dg run jq-long-to-wide --watch` |
| [`jq-nested-to-flat`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/jq-nested-to-flat.yaml) | Flatten nested records into joined-path keys, with list fields collapsed into one cell rather than indexed columns. | `uv run dg run jq-nested-to-flat --watch` |
| [`jq-pivot-wide-to-long`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/jq-pivot-wide-to-long.yaml) | Melt a column-per-measure table into one record per measurement, dropping the cells that were never measured. | `uv run dg run jq-pivot-wide-to-long --watch` |
| [`jq-running-totals`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/jq-running-totals.yaml) | Sort a daily series, then add cumulative sums, day-on-day deltas, and a moving average over a configurable window. | `uv run dg run jq-running-totals --watch` |
| [`jq-string-cleaning`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/jq-string-cleaning.yaml) | Trim, collapse, case-fold and extract the strings a spreadsheet export brings in, and report which fields changed. | `uv run dg run jq-string-cleaning --watch` |
| [`jq-top-n`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/jq-top-n.yaml) | Rank rows by a measure and keep the leaders, the rows tied with the last of them, and a summary of everything below. | `uv run dg run jq-top-n --watch` |
| [`jq-validate-in-jq-vs-schema`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/jq-validate-in-jq-vs-schema.yaml) | Sort a batch into accepted and rejected rows with jq, then hold the accepted ones to a carried schema at a gate. | `uv run dg run jq-validate-in-jq-vs-schema --watch` |
| [`jq-window-dates`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/jq-window-dates.yaml) | Build a window of days from a start date, bucket it into ISO weeks, and show why strptime alone is not a date. | `uv run dg run jq-window-dates --watch` |
| [`json-to-csv-flattening`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/json-to-csv-flattening.yaml) | Reach into an envelope, flatten the nested fields into named columns, join the list cells, and convert the written rows into a csv artifact. | `uv run dg run json-to-csv-flattening --watch` |
| [`large-output-to-storage`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/large-output-to-storage.yaml) | Generate a payload far past the inline artifact threshold, write it to storage under a name of its own, and keep only a bounded summary in a step output. | `uv run dg run large-output-to-storage --watch` |
| [`map-enrich-with-lookup`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/map-enrich-with-lookup.yaml) | Merge a dimension table into every row with a whole-value step, then compute the per-row columns with map.jq. | `uv run dg run map-enrich-with-lookup --watch` |
| [`ndjson-to-parquet`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/ndjson-to-parquet.yaml) | Write typed records into the run's scratch space, convert them through ndjson into parquet, and read the file back to see what landed. | `uv run dg run ndjson-to-parquet --watch` |
| [`pagination-by-fan-out`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/pagination-by-fan-out.yaml) | Fetch a literal list of pages concurrently with for_each, each item its own attempt, then stitch the pages into one list. | `uv run dg run pagination-by-fan-out --watch` |
| [`parquet-round-trip-types`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/parquet-round-trip-types.yaml) | Write one record of every JSON scalar, convert it out to parquet and back, and compare it against the same record round-tripped through csv. | `uv run dg run parquet-round-trip-types --watch` |
| [`reconcile-two-sources`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/reconcile-two-sources.yaml) | Compare two systems' totals by key with a tolerance, report the four buckets, and fail when too many rows disagree. | `uv run dg run reconcile-two-sources --watch` |
| [`report-built-in`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/report-built-in.yaml) | The smallest pipeline that renders a report document, with an empty report section and no template of its own. | `uv run dg run report-built-in --watch` |
| [`report-daily-digest`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/report-daily-digest.yaml) | Compute a day's numbers once, write them to storage and convert them into a csv artifact, derive a digest line, and post the summary to a receiver. | `uv run dg run report-daily-digest --watch` |
| [`report-to-file`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/report-to-file.yaml) | Render a markdown page from a Jinja template, write it to the run's scratch space, and read it back. | `uv run dg run report-to-file --watch` |
| [`report-to-webhook`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/report-to-webhook.yaml) | Render a markdown page from a Jinja template and deliver it to a receiver as one field of a webhook body. | `uv run dg run report-to-webhook --watch` |
| [`schema-carried`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/schema-carried.yaml) | Validate a payload against a shape the document carries, and read the gate's output downstream as proof of the check. | `uv run dg run schema-carried --watch` |
| [`schema-formats`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/schema-formats.yaml) | Hold a record of strings to date, date-time, email, uri, uuid4 and digest formats, and show what a pack-contributed format does. | `uv run dg run schema-formats --watch` |
| [`schema-referenced`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/schema-referenced.yaml) | Validate a record against ou-record, a schema applied to the instance on its own, and declare the dependency in requires. | `uv run dg run schema-referenced --watch` |
| [`schema-refuses-then-rule`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/schema-refuses-then-rule.yaml) | A validation that fails on purpose, an error branch on rule one_failed, a load that is skipped, and a cleanup on all_done. | `uv run dg run schema-refuses-then-rule --watch` |
| [`storage-copy-dated-archive`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/storage-copy-dated-archive.yaml) | Write a file, copy it to a date-partitioned archive key, and record both URIs and the bytes copied in a manifest. | `uv run dg run storage-copy-dated-archive --watch` |
| [`storage-exists-gate`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/storage-exists-gate.yaml) | Park on a storage.exists sensor with a size floor and a deadline, then read whatever file the sensor reports it found. | `uv run dg run storage-exists-gate --watch` |
| [`storage-keep-past-the-run`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/storage-keep-past-the-run.yaml) | Fetch a body, write a working copy to the run's scratch and a kept copy under the artifact root, and read the kept one back. | `uv run dg run storage-keep-past-the-run --watch` |
| [`storage-manifest-of-a-fan-out`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/storage-manifest-of-a-fan-out.yaml) | Write one file per item with for_each, then read the fan's outputs back as one list and record every file in a manifest. | `uv run dg run storage-manifest-of-a-fan-out --watch` |
| [`storage-write-then-read`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/storage-write-then-read.yaml) | Put a transform's result in the run's scratch space with storage.write, read it into the next step with storage.read, and do it again with what that step produced. | `uv run dg run storage-write-then-read --watch` |
| [`webhook-post-hmac`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/webhook-post-hmac.yaml) | POST an event with an HMAC-SHA256 signature over the exact bytes sent, using a secret that lives on a connection. | `uv run dg run webhook-post-hmac --watch` |
| [`webhook-post-summary`](https://github.com/winterop-com/dirigent/tree/main/examples/recipes/webhook-post-summary.yaml) | Build a notification body of counts and identifiers, derive its human line from those counts, and deliver it on all_done. | `uv run dg run webhook-post-summary --watch` |

### s3

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`report-to-s3`](https://github.com/winterop-com/dirigent/tree/main/examples/s3/report-to-s3.yaml) | Render a markdown page from a Jinja template and write it to an object in S3. | `uv run dg run report-to-s3 --watch -p day=2026-01-01` |
| [`s3-copy-and-verify`](https://github.com/winterop-com/dirigent/tree/main/examples/s3/s3-copy-and-verify.yaml) | Promote an object to a published prefix, and prove it landed before reading it. | `uv run dg run s3-copy-and-verify --watch -p day=2026-01-01` |
| [`s3-csv-report`](https://github.com/winterop-com/dirigent/tree/main/examples/s3/s3-csv-report.yaml) | Shape records into flat rows and write them as a csv object in S3. | `uv run dg run s3-csv-report --watch -p day=2026-01-01` |
| [`s3-parquet-report`](https://github.com/winterop-com/dirigent/tree/main/examples/s3/s3-parquet-report.yaml) | Write typed records as a parquet object in S3, where an analysis can read them. | `uv run dg run s3-parquet-report --watch -p day=2026-01-01` |
| [`s3-round-trip`](https://github.com/winterop-com/dirigent/tree/main/examples/s3/s3-round-trip.yaml) | Move an artifact from local storage out to S3 and back, then confirm it landed. | `uv run dg run s3-round-trip --watch -p day=2026-01-01` |

### sensors

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`sensor-gate`](https://github.com/winterop-com/dirigent/tree/main/examples/sensors/sensor-gate.yaml) | Wait for today's drop to land, then load it; skip the day if it never does. | `uv run dg run sensor-gate --watch -p day=2026-01-01` |
| [`time-window`](https://github.com/winterop-com/dirigent/tree/main/examples/sensors/time-window.yaml) | Wait until the local clock is inside a window, then do the work it guards. | `uv run dg run time-window --watch` |

### showcase

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`morning-briefing`](https://github.com/winterop-com/dirigent/tree/main/examples/showcase/morning-briefing.yaml) | Four feeds, each filtered to what clears a threshold, each reading banded, each summarised, and the four summaries joined into one gated briefing that is rendered, saved and read back. | `uv run dg run morning-briefing --watch` |
| [`nightly-regional-load`](https://github.com/winterop-com/dirigent/tree/main/examples/showcase/nightly-regional-load.yaml) | A night's load over eight regions: a maintenance window, a catalogue read gated on its shape, one export submitted, deposited and waited on per region, a per-region gate and write, the joins over them, and a page saved beside the data. | `uv run dg run nightly-regional-load --watch` |
| [`one-region-refuses`](https://github.com/winterop-com/dirigent/tree/main/examples/showcase/one-region-refuses.yaml) | Eight regional exports where one fails every attempt and is given up on: the item is recorded against itself, the other seven finish, and the run ends `completed_with_errors`. | `uv run dg run one-region-refuses --watch` |

### sql

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`duckdb-parquet-to-report`](https://github.com/winterop-com/dirigent/tree/main/examples/sql/duckdb-parquet-to-report.yaml) | Write a parquet artifact, group it with DuckDB over the file itself, and copy the answer out as csv. | `uv run dg run duckdb-parquet-to-report --watch` |
| [`sql-postgres-readonly`](https://github.com/winterop-com/dirigent/tree/main/examples/sql/sql-postgres-readonly.yaml) | Query a PostgreSQL warehouse over a connection that refuses writes, with both values bound as parameters. | `uv run dg run sql-postgres-readonly --watch --window START..END` |
| [`sql-query-to-storage`](https://github.com/winterop-com/dirigent/tree/main/examples/sql/sql-query-to-storage.yaml) | Read a table with sql.query and hand its rows to storage.write, which is how a result becomes a file. | `uv run dg run sql-query-to-storage --watch` |
| [`sql-sqlite-roundtrip`](https://github.com/winterop-com/dirigent/tree/main/examples/sql/sql-sqlite-roundtrip.yaml) | Create a SQLite database in the run's work directory, insert rows with bound parameters, and read them back. | `uv run dg run sql-sqlite-roundtrip --watch` |

### transform

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`csv-report`](https://github.com/winterop-com/dirigent/tree/main/examples/transform/csv-report.yaml) | Shape records into flat rows, store them as json, and re-encode that as a csv artifact. | `uv run dg run csv-report --watch` |
| [`jq-filter-and-map`](https://github.com/winterop-com/dirigent/tree/main/examples/transform/jq-filter-and-map.yaml) | Keep the active readings with filter.jq, convert each with map.jq, and summarise them. | `uv run dg run jq-filter-and-map --watch` |
| [`jq-group-and-aggregate`](https://github.com/winterop-com/dirigent/tree/main/examples/transform/jq-group-and-aggregate.yaml) | Group a flat list of readings by region, aggregate each group, and total them. | `uv run dg run jq-group-and-aggregate --watch` |
| [`jq-join-two-sources`](https://github.com/winterop-com/dirigent/tree/main/examples/transform/jq-join-two-sources.yaml) | Enrich a list of readings with the station records they refer to, keeping unmatched rows. | `uv run dg run jq-join-two-sources --watch` |
| [`jq-reshape`](https://github.com/winterop-com/dirigent/tree/main/examples/transform/jq-reshape.yaml) | Reshape a reading payload with jq, then map the result over one region each. | `uv run dg run jq-reshape --watch` |
| [`jq-stream-through-storage`](https://github.com/winterop-com/dirigent/tree/main/examples/transform/jq-stream-through-storage.yaml) | Write a generated list to storage, read it back as a value, and write the smaller result out the same way. | `uv run dg run jq-stream-through-storage --watch` |
| [`ndjson-round-trip`](https://github.com/winterop-com/dirigent/tree/main/examples/transform/ndjson-round-trip.yaml) | Re-spell a stored JSON array as ndjson, convert it back, and read the result in as a value. | `uv run dg run ndjson-round-trip --watch` |
| [`parquet-round-trip`](https://github.com/winterop-com/dirigent/tree/main/examples/transform/parquet-round-trip.yaml) | Write records to a parquet file, then read them back with their types intact. | `uv run dg run parquet-round-trip --watch` |
| [`std-convert-fan-out`](https://github.com/winterop-com/dirigent/tree/main/examples/transform/std-convert-fan-out.yaml) | Store an inline csv, re-encode it as json, reshape it with jq, and fan out over the regions. | `uv run dg run std-convert-fan-out --watch` |
| [`xml-feed-to-ndjson`](https://github.com/winterop-com/dirigent/tree/main/examples/transform/xml-feed-to-ndjson.yaml) | Store an XML feed, convert it to one record per line, aggregate the records with jq, and convert the same object to one whole value to show the mapping that round-trips. | `uv run dg run xml-feed-to-ndjson --watch` |
| [`yaml-config-to-json`](https://github.com/winterop-com/dirigent/tree/main/examples/transform/yaml-config-to-json.yaml) | Read a stored YAML config as the JSON object it describes, take what a run needs out of it, and write the answer back out as YAML. | `uv run dg run yaml-config-to-json --watch` |

### triggers

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`at-one-time`](https://github.com/winterop-com/dirigent/tree/main/examples/triggers/at-one-time.yaml) | A one-time schedule firing a bounded backfill at a single agreed instant. | `uv run dg run at-one-time --watch` |
| [`cron-nightly`](https://github.com/winterop-com/dirigent/tree/main/examples/triggers/cron-nightly.yaml) | One pipeline on a nightly cron schedule, in its own timezone, with pinned parameters. | `uv run dg run cron-nightly --watch` |
| [`cron-windowed`](https://github.com/winterop-com/dirigent/tree/main/examples/triggers/cron-windowed.yaml) | A nightly schedule whose runs read the **interval that just closed** rather than the instant they started at. | `uv run dg run cron-windowed --watch --window START..END` |
| [`document-nightly`](https://github.com/winterop-com/dirigent/tree/main/examples/triggers/document-nightly.yaml) | Schedules and a webhook for a pipeline another document defines. | a triggers document for `managed-and-manual` |
| [`interval-rolling`](https://github.com/winterop-com/dirigent/tree/main/examples/triggers/interval-rolling.yaml) | A pipeline on a rolling hourly interval, refreshing a window rather than hitting a calendar moment. | `uv run dg run interval-rolling --watch` |
| [`managed-and-manual`](https://github.com/winterop-com/dirigent/tree/main/examples/triggers/managed-and-manual.yaml) | Two document-managed schedules and a webhook, and what an apply leaves untouched. | `uv run dg run managed-and-manual --watch` |
| [`webhook-trigger`](https://github.com/winterop-com/dirigent/tree/main/examples/triggers/webhook-trigger.yaml) | One pipeline started by an inbound webhook that maps a payload onto its parameters. | `uv run dg run webhook-trigger --watch` |

### validate

| Pipeline | What it shows | Run it |
| --- | --- | --- |
| [`expects-a-shape`](https://github.com/winterop-com/dirigent/tree/main/examples/validate/expects-a-shape.yaml) | Validate a payload against a schema the document carries, then read the value the gate passed through. | `uv run dg run expects-a-shape --watch` |
| [`the-shape-is-wrong`](https://github.com/winterop-com/dirigent/tree/main/examples/validate/the-shape-is-wrong.yaml) | A payload missing a required field, refused at the gate with the path that is wrong. | `uv run dg run the-shape-is-wrong --watch` |

### What is not applied

| Document | Why |
| --- | --- |
| `docker/docker-build-push` | Needs `ghcr`, a registry connection with a push credential. |
| `docker/docker-remote-daemon` | Needs `build-daemon`, a remote Docker daemon over TCP and TLS. |
| `open-data/odk-central-submissions` | Needs `odk-central`, an ODK Central server and an account on it. |
| `playground/waiting-for-a-batch` | Its block `playground.arrive` arrives in the dirigent after 0.19. |
| `preview/s3-parquet-to-ingestion` | A preview: it needs an adapter pack's `modelling-api` and `ops-webhook`. |

`triggers/document-nightly` is applied as what it is, a triggers document for
`managed-and-manual`, and is not a pipeline of its own.

## Verify it

```bash
./verify.sh
```

starts its own rustfs, brokers, warehouse and instance on free ports and a throwaway state, so
it leaves the demo instance on 4444 alone; validates all 211 documents; applies them; runs the 21
pipelines beside the shelves and the two playground routes on the shelves with their own assertions and the three tutorial documents locally;
runs every corpus pipeline through `corpus.py`, six at a time, each judged on its last run
record against the outcome it is meant to end with; waits for echo-schedule's webhook and its
clock; and stops what it started. Expect about ten minutes. It does not run:

| Pipeline | Why |
| --- | --- |
| `kobo-submissions-to-csv` | Needs a KoboToolbox account: an `asset_uid` and a token. |
| the five above | They are not applied. |
