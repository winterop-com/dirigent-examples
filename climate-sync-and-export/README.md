# climate-sync-and-export

Daily rainfall brought into an open climate service and carried out of it again, in one
document: **an ingestion**, **a sync that brings the dataset forward**, and **an export of it
averaged over each chiefdom of a DHIS2 district**, shaped as the dataValueSet a DHIS2 import
takes and gated on that shape before anything could be sent.

The service is one this project starts on your machine from `ocs/compose.yaml`, under its own
compose project name, `dirigent-example-climate-sync-and-export`, on port 9710, over Bo
district in Sierra Leone. No public climate service is called. The service itself downloads
CHIRPS v3 rainfall from the Climate Hazards Center, and the chiefdoms are read from the public
DHIS2 play demo, so the run needs the network; nothing is written to the demo.

What you learn here:

- that an ingestion, a sync and an openEO batch job are each one step that submits work, hands
  back to the engine and is probed until the service says the work is done, its progress
  (`5 periods pending`, `Wrote 2025-01-01`) streamed into the run;
- that `ingest` and `sync` are two different questions: the first fills a window you name, the
  second asks for everything from the dataset's last day up to a day you name, and the second
  is what a nightly runs;
- that the geometries an aggregation averages over can come from DHIS2 at run time, so the
  values come back already keyed by the org unit uids DHIS2 knows;
- that a named export is the service's own mapping from an aggregate to DHIS2, and that the
  payload it renders can be held to a schema with the dhis2 pack's `dhis2-uid` and
  `dhis2-period` formats before it goes anywhere.

## What you need

- Docker, and 3 GB of disk for the service's image, pulled on the first start. It is built for
  `linux/amd64` only, so an arm64 Mac runs it under emulation. The service is healthy about
  ten seconds after it starts.
- Port 9710 free on 127.0.0.1 (`OCS_PORT` moves it).
- The network: CHIRPS from `data.chc.ucsb.edu`, and the play demo.

The open climate service has no releases, so the image is pinned by digest to the `main` build
this example was run against; `ocs/compose.yaml` names it.

## Run it

```bash
uv sync
docker compose -p dirigent-example-climate-sync-and-export -f ocs/compose.yaml up -d --wait
```

The fast loop, with no dirigent server. A local run starts on a throwaway instance holding
nothing, so it is handed the two connections and the schema the document names:

```bash
uv run dg validate pipelines/climate-sync-and-export.yaml
uv run dg run --local pipelines/climate-sync-and-export.yaml \
  --connections connections.yaml \
  --schema schemas/rainfall-data-value-set.json
```

The service now holds `chirps3_precipitation_daily` from 2025-01-01 to 2025-01-10:

```bash
curl -s http://127.0.0.1:9710/datasets | jq '.items[] | {dataset_id, temporal: .extent.temporal}'
```

Run it again on the same service and the ingestion and the sync find those days already held,
and the export is the same 150 values. `-p end=...` moves the day the sync brings the dataset
forward to, and the window the export covers with it.

Then the instance. A `dhis2` connection carries a password, and a connection secret is sealed
with the instance's own key, so the instance needs a key before it can hold one. Mint it once
into `.env`, which is not in the repository and which every command run in this directory
reads, then start the instance in a second terminal, in this directory:

```bash
grep -q '^DIRIGENT_SECRET_KEY=' .env 2>/dev/null \
  || printf 'DIRIGENT_SECRET_KEY=%s\n' "$(uv run dg secret-key)" >> .env
uv run dg dev
```

On an empty state `dg dev` makes its own admin `admin`, password `admin`. Back in the first
terminal, `uv run dg auth login --username admin --password admin` answers with the
`export DG_TOKEN=` line to paste. Then:

```bash
uv run dg schema create schemas/rainfall-data-value-set.json
uv run dg connection create climate climate-local --name "Local open climate service" \
  --set base_url=http://127.0.0.1:9710 --set timeout=2m
uv run dg connection create dhis2 play --name "DHIS2 play demo" \
  --set base_url=https://play.dhis2.org/2.42 --set follow_redirects_with_auth=true \
  --set basic_username=admin --set basic_password=district
uv run dg apply
uv run dg run climate-sync-and-export --watch
```

When you are done:

```bash
docker compose -p dirigent-example-climate-sync-and-export -f ocs/compose.yaml down -v
```

`./verify.sh` does all of it unattended: the service up on an empty volume, the document run
locally, the service's own word that the dataset now ends on 2025-01-10, then a `dg dev` of its
own on a free port with the schema and both connections, and the same run on the instance
against a service that already holds the days. It asserts on the records -- one value per
chiefdom and day, ten days, every chiefdom present -- and removes the service and its volume
on the way out. It takes a little over a minute.

## What you see

`uv run dg run --local ...`, with a local run's temporary root written as `/tmp/...` and the
`queued` and `running` lines left out:

```text
2026-11-01T13:59:39.360+01:00 [info    ] started                        [run] pipeline=climate-sync-and-export run_id=01a19731-b3c2-77da-b1b3-fc508da7cdaa local=true scratch=file:///tmp/... root=/tmp/...
2026-11-01T13:59:45.559+01:00 [info    ] metadata read                  [log units] resource=organisationUnits rows=15 duration_ms=5637
2026-11-01T13:59:45.906+01:00 [info    ] succeeded                      [step units] block=dhis2.metadata attempt=1 duration_ms=6013
2026-11-01T13:59:46.623+01:00 [info    ] 5 periods pending              [log ingest]
2026-11-01T13:59:46.926+01:00 [info    ] succeeded                      [step shapes] block=transform.jq attempt=1 duration_ms=329
2026-11-01T13:59:48.743+01:00 [info    ] Wrote 2025-01-01               [log ingest]
2026-11-01T13:59:52.845+01:00 [info    ] succeeded                      [step ingest] block=climate.ingest attempt=1 duration_ms=13159
2026-11-01T14:00:06.528+01:00 [info    ] succeeded                      [step sync] block=climate.sync attempt=1 duration_ms=13656
2026-11-01T14:00:07.903+01:00 [info    ] succeeded                      [step aggregate] block=climate.job.run attempt=1 duration_ms=1314
2026-11-01T14:00:08.080+01:00 [info    ] downloaded                     [log export] job=97cbf0b6-a674-425a-871f-904cd14da986 asset=result size_bytes=15973
2026-11-01T14:00:08.394+01:00 [info    ] read                           [log reload] uri=export/attempt-1-result.json bytes_read=15973 content_type=application/json
2026-11-01T14:00:08.528+01:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=36
2026-11-01T14:00:09.452+01:00 [info    ] succeeded                      [run] pipeline=climate-sync-and-export run_id=01a19731-b3c2-77da-b1b3-fc508da7cdaa exit_code=0
```

`units` does not wait for `ingest`: nothing connects them, so the play demo is read while the
service downloads. The sync's own word, in its output's `result`:

```text
"status": "completed",
"message": "Managed dataset was synced by appending missing periods to the committed store."
```

The export, read with `--json | jq`: 150 values, fifteen chiefdoms by ten days, the first of
them Badjia's:

```json
{"dataElement": "RnFaLLdAiLy", "orgUnit": "YuQRtpLP10I", "period": "20250101", "value": "0.008525388572051441"}
{"dataElement": "RnFaLLdAiLy", "orgUnit": "YuQRtpLP10I", "period": "20250102", "value": "0.4100981790822184"}
{"dataElement": "RnFaLLdAiLy", "orgUnit": "YuQRtpLP10I", "period": "20250106", "value": "0"}
```

Millimetres of rain, averaged over the chiefdom, in the dry season. A zero is kept as a zero:
the service omits a missing observation, it never writes one as `0`.

## The document, hop by hop

`pipelines/climate-sync-and-export.yaml` carries these notes as comments at the line each one
is about.

**`ingest`.** `climate.ingest` asks the service to bring `chirps3_precipitation_daily` in over
the instance's extent, from `start` to `ingest_end`, and to publish it. The service answers 202
with the job to follow, and the step probes it every five seconds (`poll: 5s`; the block's own
default is thirty).

**`sync`.** `climate.sync` brings the managed dataset forward from its last day to `end`. Left
without an `end` it fetches up to the newest month CHIRPS has published, which is what a
nightly wants and what an example does not.

**`units` and `shapes`.** `dhis2.metadata` reads the chiefdoms under Bo with `fields=id,name,geometry`,
and `shapes` makes them a FeatureCollection whose feature ids are their uids. The service keys
every aggregated value by that id, so the export names DHIS2 org units without a lookup.

**`aggregate`.** `climate.job.run` runs the service's `aggregate_to_dhis2_json` workflow as an
openEO batch job: the daily rainfall averaged inside each chiefdom, saved through the
`rainfall-daily` export.

**`export`, `reload` and `check`.** `climate.job.result` downloads the job's `result` asset into
the run's storage; `storage.read` reads it back as JSON whatever its size; `validate.schema`
holds it to `schemas/rainfall-data-value-set.json`.

### The service's side

`ocs/climate-service.yaml` is the instance config: the extent, Bo district with a margin, and
the named export. The export is where the mapping to DHIS2 lives -- the dataset, the
aggregation, daily periods, the org unit read from each feature's id, and the data element
every value is for. **That data element, `RnFaLLdAiLy`, names nothing on the play demo**: the
demo has no rainfall data element. Replace it with your own before the payload goes to a DHIS2.

### Where the values would go next

Two ways out, and this example stops before both:

- `dhis2.data_value_set_import` on the `play` connection, the values handed over from `check`,
  imports them through dirigent. Against the demo that would only be refused, for the data
  element above; against your own DHIS2, with its rainfall data element in the export, it is
  one more step with `dry_run: true` first.
- `climate.export` asks the service to deliver the saved job itself, through a DHIS2
  connection the service holds in `dhis2_connections`. That connection authenticates with a
  DHIS2 personal access token only, and minting one on the shared demo is a write this example
  will not make.

## Where to go next

- The pack's own shelves, `uv run dg examples list --local`: `climate-batch-and-export` is the
  `climate.export` delivery, `climate-sync-to-dhis2` the import through dirigent, and
  `climate-to-chap-backtest` the same rainfall handed to Chap.
- [`chap-prediction`](../chap-prediction): what Chap makes of climate and case counts.
- [**The examples**](../README.md): every example in order, and what you need once.
