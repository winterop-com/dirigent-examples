# chap-prediction

A Chap forecast end to end, in one document: **a history imported**, **a configured model
backtested and promoted into a prediction setup**, **a forecast run and read back**, and **the
alerts it raises held until a person releases them**. Chap does the modelling; the pipeline is
the order the calls are made in, what each one is handed from the one before it, and the wait
for a reviewer, which holds no worker however long it takes.

Everything runs against a Chap this project starts on your machine from `chap/compose.yaml`,
under its own compose project name, `dirigent-example-chap-prediction`, and on its own port,
8710, so it never meets a Chap you already run. No public Chap is called, and nothing here
needs a token.

What you learn here:

- that every `chap.*` block that starts a Chap job -- an import, a backtest, a forecast --
  submits it, hands the step back to the engine and is probed until the job settles, so a
  six-hour backtest is a row with a due time, not a busy worker;
- that a call a pack has no block for is one `http.request` away, on the same connection the
  pack's blocks use (`promote` and `chap-alert-policy` are that);
- that a jq step can be a gate (`model` fails the run on a model Chap does not have) and a
  shaper (`raise` builds alerts the way Chap spells them);
- that the release gate lives in Chap: a reviewer approves or declines each alert wherever they
  work, and `chap.alerts.reviewed` only reads where they stand.

## What you need

- Docker, and about 15 GB of disk for the two Chap images (`chap-core` 2.4 GB, `chap-worker`
  11.9 GB), pulled on the first start. The images are built for `linux/amd64` only, so an arm64
  Mac runs them under emulation; the stack is up in under a minute on an M-series machine and
  holds about 2 GB of memory while it runs.
- Port 8710 free on 127.0.0.1 (`CHAP_PORT` moves it).

The images are Chap's v2.5.1 release.

## Run it

```bash
uv sync
docker compose -p dirigent-example-chap-prediction -f chap/compose.yaml up -d --wait
```

The policy first. An alert in Chap names a policy and one of its levels, and Chap refuses one
whose level it does not hold. A policy outlives every forecast, so it is a document of its own,
run once per Chap; its output is the id the forecast is handed:

```bash
uv run dg run --local pipelines/chap-alert-policy.yaml --connections connections.yaml
```

Then the forecast. The history is three Laos provinces, 2010 to 2012, with monthly dengue
cases, rainfall, temperature and population -- the rows are chap-core's own
`example_data/laos_subset.csv` -- and it arrives as a parameter file, `-P`, because a history is
what the document runs on, not part of the document:

```bash
uv run dg run --local pipelines/chap-prediction.yaml --connections connections.yaml \
  -P data/laos-dengue.yaml -p alert_policy_id=1
```

The run stops at `review`, `0 of 6 reviewed`, and waits. Approving is a person's decision, made
against Chap. Approve the pending alerts in a second terminal -- a modelling app makes exactly
this call when someone works through the queue:

```bash
curl -s 'http://127.0.0.1:8710/v1/crud/alerts?approved=pending' | jq -c '[.[].id]'
curl -s -X POST 'http://127.0.0.1:8710/v1/crud/alerts/$approve' \
  -H 'content-type: application/json' \
  -d '{"alertIds": [1,2,3,4,5,6], "approved": "approved", "approvedBy": "district-officer"}'
```

Within five seconds `review` succeeds and `release` hands on the six approved alerts. Decline
some instead, `"approved": "declined"`, and they arrive under `held_back`.

On an instance the same documents are applied and run by code. Start one in another terminal,
`uv run dg dev`; on an empty state it makes its own admin `admin`, password `admin`, and
`uv run dg auth login --username admin --password admin` answers with the `export DG_TOKEN=`
line to paste. Then:

```bash
uv run dg connection create chap chap-local --name "Local Chap" --set base_url=http://127.0.0.1:8710
uv run dg connection check chap-local
uv run dg apply
uv run dg run chap-prediction --watch -P data/laos-dengue.yaml -p alert_policy_id=1
```

The `chap` connection carries no secret here, so `dg connection create` asks for nothing. A
Chap that sets `CHAP_API_TOKEN` wants `--set api_token=...`, and every block sends it as
`Authorization: Bearer`.

When you are done:

```bash
docker compose -p dirigent-example-chap-prediction -f chap/compose.yaml down -v
```

`./verify.sh` does all of it unattended: the stack up on fresh volumes, both documents
validated, the policy, the forecast run locally and then on a `dg dev` of its own on a free
port, the reviewer played by the script itself, approving every alert while the run waits, and
the stack removed with its volumes on the way out. It asserts on the records: three locations
imported and none rejected, a stored backtest, eighteen forecast entries, at least one alert,
and every alert released. It takes about a minute and a half once the images are local.

## What you see

`uv run dg run --local pipelines/chap-prediction.yaml ...`, the job-backed steps and the wait:

```text
2026-11-01T13:50:19.358+01:00 [info    ] dataset import submitted       [log dataset] job=cdc1e6cd-0703-430c-b2f3-6a016c543a80
2026-11-01T13:50:20.782+01:00 [info    ] succeeded                      [step dataset] block=chap.dataset.import attempt=1 duration_ms=1763
2026-11-01T13:50:20.978+01:00 [info    ] backtest submitted             [log backtest] job=58e0c3fd-1148-4b4c-b926-af3df46295fb
2026-11-01T13:50:23.903+01:00 [info    ] succeeded                      [step backtest] block=chap.backtest.run attempt=1 duration_ms=3029
2026-11-01T13:50:24.033+01:00 [info    ] http call                      [log promote] method=POST url=/v1/crud/prediction-setups status=200 bytes=8 duration_ms=20
2026-11-01T13:50:24.348+01:00 [info    ] prediction submitted           [log forecast] job=b099eb0a-d054-4595-af2c-4816b777c1d2
2026-11-01T13:50:25.674+01:00 [info    ] succeeded                      [step forecast] block=chap.prediction.run attempt=1 duration_ms=1629
2026-11-01T13:50:26.291+01:00 [info    ] expanded into 1 items from raise [log record] items=1 source=raise
2026-11-01T13:50:26.541+01:00 [info    ] alerts recorded                [log record[0]] count=6
2026-11-01T13:50:26.776+01:00 [info    ] 0 of 6 reviewed                [log review]
2026-11-01T13:50:31.825+01:00 [info    ] succeeded                      [step review] block=chap.alerts.reviewed attempt=1 duration_ms=5181
2026-11-01T13:50:32.506+01:00 [info    ] succeeded                      [run] pipeline=chap-prediction run_id=01a19729-20a5-77aa-b693-64f145324797 exit_code=0
```

The forecast itself is in the run's records. The quantiles, one entry per province, month and
quantile, read with `--json | jq`; the first month:

```text
{"orgUnit":"Bokeo","period":"201301","quantile":0.5,"value":8.0}
{"orgUnit":"Bokeo","period":"201301","quantile":0.9,"value":12.0}
{"orgUnit":"Savannakhet","period":"201301","quantile":0.5,"value":141.0}
{"orgUnit":"Savannakhet","period":"201301","quantile":0.9,"value":156.0}
{"orgUnit":"Vientiane","period":"201301","quantile":0.5,"value":241.5}
{"orgUnit":"Vientiane","period":"201301","quantile":0.9,"value":261.1}
```

Savannakhet and Vientiane reach the threshold of 100 cases in all three forecast months, Bokeo
in none, so `raise` builds six alerts and `record` stores them, all `pending`. The backtest's
`aggregate_metrics` say how far to trust it: `naive_model` repeats the recent past, and its
`mae` of about 145 cases is what that buys on this history. It is the model every Chap
configures and the fastest to train, which is why it is the default; `-p model=...` names any
other that `chap.models.list` returns.

`release`, the step's output:

```json
{
  "released": [
    {"orgUnit": "Savannakhet", "timePeriod": "201301", "level": "action", "approvedBy": "district-officer"},
    {"orgUnit": "Savannakhet", "timePeriod": "201302", "level": "action", "approvedBy": "district-officer"},
    {"orgUnit": "Savannakhet", "timePeriod": "201303", "level": "action", "approvedBy": "district-officer"},
    {"orgUnit": "Vientiane", "timePeriod": "201301", "level": "action", "approvedBy": "district-officer"},
    {"orgUnit": "Vientiane", "timePeriod": "201302", "level": "action", "approvedBy": "district-officer"},
    {"orgUnit": "Vientiane", "timePeriod": "201303", "level": "action", "approvedBy": "district-officer"}
  ],
  "held_back": []
}
```

## The documents, hop by hop

`pipelines/chap-prediction.yaml` carries these notes as comments at the line each one is
about; this is the reading order.

**`models` and `model`.** `chap.models.list` hands on each configured model exactly as Chap
describes it, and `model` is a jq gate over that list: `error(...)` in a jq program fails the
step, so a model Chap does not hold, or has archived, stops the run before anything is written.
It hands on the model's own name, so every later step names the model Chap confirmed.

**`dataset`.** `chap.dataset.import` takes the history as a wide Chap CSV -- `time_period`,
`location`, one column per feature -- and unfolds each cell into one observation. Each
feature's `id` in `org_units` is the `location` its rows name. `on_rejected: fail` sends the
observations as a dry run first, so a location missing from the GeoJSON or a covariate with
gaps fails the step in Chap's own words, and nothing is stored.

**`backtest`.** `chap.backtest.run` trains the model on part of the history and scores it on
the rest. `n_splits: 3` and `n_periods: 3` keep it short; every parameter left out takes the
default Chap saved for the dataset's period type. `poll: 5s` looks at the job every five
seconds rather than the block's thirty.

**`promote`.** A prediction setup is a backtest Chap was told to keep forecasting with: it fixes
the model, the target and the future-weather provider. The pack has no block that creates one,
so `http.request` posts to `/v1/crud/prediction-setups` on the `chap-local` connection, and the
answer's `body.id` is the setup.

**`forecast` and `quantiles`.** `chap.prediction.run` runs the setup on the history and waits for
the forecast job; `chap.prediction.read` reads the stored prediction at the quantiles asked for.

**`raise` and `record`.** `raise` turns every cell whose 0.9 quantile reaches `threshold` into
one alert, and answers with a list of at most one batch, so `record`'s `for_each` is one item
when anything breached and none when nothing did. Over no items `record` is skipped, and the
default `all_success` edge skips everything after it: a forecast that breached nothing has
nothing to review.

**`review` and `release`.** `chap.alerts.reviewed` is a sensor: each poke lists this
prediction's alerts once and succeeds when none is pending. `deadline: 1h` with
`on_timeout: fail` makes an unreviewed forecast a failed run an operator sees; a real review
window is days. `release` is the list a notifier sends from.

`pipelines/chap-alert-policy.yaml` is one `http.request`: the policy, with one level, `action`,
whose channel is the 75th percentile of the same month over the two most recent complete years.
Chap reads that channel when a prediction setup raises alerts itself; an alert recorded by
`chap.alerts.record` only has to name the level.

`connections.yaml` is what a `--local` run is handed, because a local run starts on a throwaway
instance holding nothing. `data/laos-dengue.yaml` is the parameter file: the polygons, cut to a
dozen corners each, and the CSV.

## Where to go next

- The pack's own shelves, `uv run dg examples list --local`, carry the single operations:
  `chap-thresholds` computes the endemic channel, `climate-to-chap-backtest` feeds Chap from the
  open climate service, and `chap-predict-alert-review-notify` messages each district through
  DHIS2 once its alert is approved.
- [`climate-sync-and-export`](../climate-sync-and-export): the open climate service, where the
  rainfall and temperature columns come from in a real deployment.
- [**The examples**](../README.md): every example in order, and what you need once.
