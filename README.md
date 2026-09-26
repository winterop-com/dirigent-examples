# everything

Every pipeline from every example beside this one, in one project: one instance, one
`dg apply`, and every pipeline, schema and connection in the same UI. The documents are the
siblings' own, copied as they are, comments included; each one's README is where it is
explained.

## Set it up

```bash
./setup.sh
```

On a fresh clone that makes `.env` with the instance key, starts rustfs as `everything-s3` on
port 9000, writes the connections `play`, `source`, `target` and `artifacts` into
`.dirigent/state`, creates the bucket `echo-s3`, starts `dg dev` on http://127.0.0.1:3333 in the
background, logs in as `dev` / `dirigent-dev` and keeps the token in `.env`, creates the seven
schemas, applies `pipelines/`, and writes echo-alert's rule `echo-failed` with its sink
`echo-sink`, the instance's own playground. Running it again changes nothing that is already
right.

To watch the instance's log, start it first in a second terminal and `setup.sh` fills it
instead of starting its own:

```bash
uv run dg dev                             # terminal 2
./setup.sh                                # terminal 1
```

`./setup.sh stop` stops what it started. `DG_PORT` and `S3_PORT` move the two ports. It needs
Docker, and the network for the DHIS2 play demos.

In this directory `dg` reads the token from `.env`, so a shell still exporting another example's
`DG_TOKEN` or `DG_URL` wants `unset DG_TOKEN DG_URL` first.

## The pipelines

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
answering the playground on 3333:

```bash
uv run dg run --local tutorial/echo-gate-too-tight.yaml    # fails at the gate, by design
uv run dg run --local tutorial/echo-gate-carried.yaml
uv run dg run --local tutorial/echo-send-before.yaml --schema schemas/playground-answer.json
```

## Verify it

```bash
./verify.sh
```

starts its own rustfs and its own instance on free ports and a throwaway state, so it leaves
the demo instance alone; applies everything, runs every pipeline on the instance and the three
tutorial documents locally, waits for echo-schedule's webhook and its clock, asserts on the
records, and stops what it started. Expect about three minutes.
