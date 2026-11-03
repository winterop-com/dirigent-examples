# echo-report

[`echo-storage`](../echo-storage) declares a `report:` template, and the engine renders it over
the run's own facts when the run settles. This example shows the two things that sit beside
that. The first document hands the job to a step: a `report.render` step writes the page from
the values the steps above it produced, and `report: {from: page}` makes that step's text the
run's report as it stands. The second keeps the template and reads `{{ params.threshold }}`,
so the report says which parameters produced it. On the way, a log line shows how a list, an
object and a boolean read inside a longer `${...}` string: as JSON.

## This one needs no network

Both documents start at `playground.generate` with its `input`, so the readings are the
documents' own data arriving as a step's output. Nothing here reaches a connection, a URL or a
network.

## Run it

The steps run anywhere:

```bash
uv sync
uv run dg validate pipelines/
uv run dg run --local pipelines/echo-report.yaml -p day=2026-01-02
```

The reports are the half that needs an instance: a local run's throwaway instance is deleted
on the way out with the run in it, so there is nothing left to read a report back from. In a
second terminal, in this directory:

```bash
uv run dg dev
```

On an empty state it migrates the schema, makes its own admin `admin` with the password
`admin`, and prints the `export DG_TOKEN=` line to paste. Back in the first terminal, with that
line pasted:

```bash
uv run dg apply
uv run dg run echo-report -p day=2026-01-02 --watch
uv run dg runs report <the run id> --markdown
uv run dg run echo-report-params -p threshold=0 --watch
uv run dg runs report <the run id> --markdown
```

`./verify.sh` does all of that unattended, and also checks what plan says about a `report:`
pointing at the wrong step. It picks a free port of its own, mints its token with
`dg auth login --username admin --password admin`, and stops the instance it started by pid.

## What you see

*Printed as it printed, with this project's directory written as `/home/you/echo-report` and
a local run's temporary root as `/tmp`.*

```bash
uv run dg validate pipelines/echo-report.yaml
```

```text
2026-11-03T14:27:41.633+01:00 [info    ] valid                          [validation] code=echo-report document=pipelines/echo-report.yaml checked="document and installed blocks"
  each step under the last one it waits for
    readings  (playground.generate)
      summary  (transform.jq)
        say  (log.write)
        page  (report.render)
2026-11-03T14:27:41.636+01:00 [info    ] valid                          [validated] documents=1 invalid=0 skipped=0
```

```bash
uv run dg run --local pipelines/echo-report.yaml -p day=2026-01-02
```

```text
2026-11-03T14:27:43.575+01:00 [info    ] started                        [run] pipeline=echo-report run_id=01a1a198-1ed1-754d-be6d-83f251218ef8 local=true scratch=file:///tmp/dirigent-local-35dfjpfk/artifacts/runs/01a1a198-1ed1-754d-be6d-83f251218ef8 root=/tmp/dirigent-local-35dfjpfk
2026-11-03T14:27:43.541+01:00 [info    ] queued                         [step readings] block=playground.generate attempt=1
2026-11-03T14:27:43.616+01:00 [info    ] running                        [step readings] block=playground.generate attempt=1
2026-11-03T14:27:43.643+01:00 [info    ] playground generated           [log readings] rows=4 seed=1263531090 locale=en_US drift=none
2026-11-03T14:27:43.650+01:00 [info    ] succeeded                      [step readings] block=playground.generate attempt=1 duration_ms=35
2026-11-03T14:27:43.650+01:00 [info    ] queued                         [step summary] block=transform.jq attempt=1
2026-11-03T14:27:43.657+01:00 [info    ] running                        [step summary] block=transform.jq attempt=1
2026-11-03T14:27:43.701+01:00 [info    ] succeeded                      [step summary] block=transform.jq attempt=1 duration_ms=44
2026-11-03T14:27:43.701+01:00 [info    ] queued                         [step say] block=log.write attempt=1
2026-11-03T14:27:43.701+01:00 [info    ] queued                         [step page] block=report.render attempt=1
2026-11-03T14:27:43.704+01:00 [info    ] finished                       [log summary] duration_ms=33 output_bytes=200
2026-11-03T14:27:43.758+01:00 [info    ] stations ["bergen-florida","oslo-blindern","tromso-langnes","trondheim-voll"], coldest {"station":"tromso-langnes","celsius":-6.8}, all above freezing: false [log say]
2026-11-03T14:27:43.709+01:00 [info    ] running                        [step page] block=report.render attempt=1
2026-11-03T14:27:43.742+01:00 [info    ] rendered                       [log page] content_type=text/markdown text_bytes=230
2026-11-03T14:27:43.742+01:00 [info    ] succeeded                      [step page] block=report.render attempt=1 duration_ms=32
2026-11-03T14:27:43.742+01:00 [info    ] running                        [step say] block=log.write attempt=1
2026-11-03T14:27:43.758+01:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=17
2026-11-03T14:27:43.889+01:00 [info    ] succeeded                      [run] pipeline=echo-report run_id=01a1a198-1ed1-754d-be6d-83f251218ef8 exit_code=0
steps
┏━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step     ┃ block               ┃ outcome   ┃ after    ┃ duration ┃ output                                  ┃
┡━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ readings │ playground.generate │ succeeded │ -        │ 0.0s     │ records=[4 items]  rows=4               │
│          │                     │           │          │          │ seed=1263531090  locale=en_US           │
│          │                     │           │          │          │ fields={3 keys}  drift=none  delay_ms=0 │
│          │                     │           │          │          │ attempt=1  fail_until=0                 │
│          │                     │           │          │          │ fail_as=transient  input_rows=4         │
│ summary  │ transform.jq        │ succeeded │ readings │ 0.0s     │ value={5 keys}                          │
│ page     │ report.render       │ succeeded │ summary  │ 0.0s     │ text=<230 chars>                        │
│          │                     │           │          │          │ content_type=text/markdown              │
│          │                     │           │          │          │ text_bytes=230                          │
│ say      │ log.write           │ succeeded │ summary  │ 0.0s     │ -                                       │
└──────────┴─────────────────────┴───────────┴──────────┴──────────┴─────────────────────────────────────────┘
```

Read the `say` line. Its message is one string with three `${...}` in it, and each value was
written the way JSON reads it: the list of stations as a JSON array, the coldest reading as a
compact object, and the boolean as `false`. A `${...}` that is the whole of a value hands the
value on as it is; one that is part of a longer string becomes text, and that text is JSON.

The page is the `page` step's `text`, 230 bytes of markdown. On an instance it becomes the
run's report:

```bash
uv run dg apply
```

```text
create echo-report-params  version 1 (/home/you/echo-report/pipelines/echo-report-params.yaml)
create echo-report  version 1 (/home/you/echo-report/pipelines/echo-report.yaml)
```

```bash
uv run dg run echo-report -p day=2026-01-02 --watch
```

```text
2026-11-03T14:27:52.439+01:00 [info    ] started                        [run] pipeline=echo-report run_id=01a1a198-4170-711d-808c-163e2c65312a local=false
...
2026-11-03T14:27:52.628+01:00 [info    ] succeeded                      [run] pipeline=echo-report run_id=01a1a198-4170-711d-808c-163e2c65312a pipeline_version=1 triggered_by="admin (token cli-admin)" duration_ms=127 items_total=0 items_failed=0 exit_code=0 priority=normal
run 01a1a198-4170-711d-808c-163e2c65312a
pipeline      echo-report (version 1)
status        succeeded
triggered by  admin (token cli-admin)
duration      0.1s
items         -

steps
┏━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━┓
┃ step     ┃ block               ┃ outcome   ┃ after    ┃ attempts ┃ duration ┃ error ┃
┡━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━┩
│ readings │ playground.generate │ succeeded │ -        │ 1        │ 0.1s     │ -     │
│ summary  │ transform.jq        │ succeeded │ readings │ 1        │ 0.0s     │ -     │
│ page     │ report.render       │ succeeded │ summary  │ 1        │ 0.0s     │ -     │
│ say      │ log.write           │ succeeded │ summary  │ 1        │ 0.0s     │ -     │
└──────────┴─────────────────────┴───────────┴──────────┴──────────┴──────────┴───────┘
```

Into a pipe `dg runs report --markdown` is one `run.report_document` record carrying the whole
page, so `jq -r .document` is how it comes out as text; at a terminal the command writes the
page as-is.

```bash
uv run dg runs report 01a1a198-4170-711d-808c-163e2c65312a --markdown | jq -r .document
```

```text
# Readings for 2026-01-02

4 stations, mean 2.5 C.
The coldest was tromso-langnes at -6.8 C.
At least one station was below freezing.

| Station |
| --- |
| bergen-florida |
| oslo-blindern |
| tromso-langnes |
| trondheim-voll |
```

That is the step's text, byte for byte. The engine rendered nothing further: `from` takes a
text that is already the page.

The second document keeps a template, and the template reads the run's parameters:

```bash
uv run dg run echo-report-params -p threshold=0 --watch
```

```text
2026-11-03T14:27:58.439+01:00 [info    ] started                        [run] pipeline=echo-report-params run_id=01a1a198-58e1-729d-8a5b-10b3e97ac416 local=false
...
2026-11-03T14:27:58.507+01:00 [info    ] succeeded                      [run] pipeline=echo-report-params run_id=01a1a198-58e1-729d-8a5b-10b3e97ac416 pipeline_version=1 triggered_by="admin (token cli-admin)" duration_ms=28 items_total=0 items_failed=0 exit_code=0 priority=normal
```

```bash
uv run dg runs report 01a1a198-58e1-729d-8a5b-10b3e97ac416 --markdown | jq -r .document
```

```text
# echo-report-params: readings above 0 C

**succeeded**, strict: false.

3 stations: bergen-florida, oslo-blindern, trondheim-voll.

Asked with `{"threshold":0,"strict":false}`.
```

`params` is what the run resolved to, defaults filled in: `strict` was never passed, and the
report still says `false`. `{{ params }}` on its own is the whole mapping as compact JSON, and
a boolean prints as `false`, not Python's `False`.

## What plan says before a run

`from` must name a step whose output carries a `text`. Point it at `summary`, a `transform.jq`
step, and the document is refused at `report.from` before anything runs:

```text
2026-11-03T14:28:09.746+01:00 [error   ] invalid                        [validation] code=echo-report document=wrong-step.yaml
  - report.from: report.from names 'summary', and its block transform.jq hands on no `text` string to be the
run's report
2026-11-03T14:28:09.749+01:00 [error   ] invalid                        [validated] documents=1 invalid=1 skipped=0
```

Drop the `report:` section altogether and the document is still valid, because a page a step
renders is an ordinary output that a later step may send anywhere. Validation warns, though,
and the warning names the line that would make it the run's report:

```bash
uv run dg validate no-report.yaml --json | jq -c 'select(.kind == "validation") | .warnings'
```

```json
[{"code":"document.report_render_unseen","message":"step 'page' renders text with report.render, and with no `report:` it is not the run's report and does not appear in the Report tab; write `report: {from: page}` to make it the run's report","params":{"step":"'page'","bare":"page"},"location":"steps.page"}]
```

## What plan says about a changed report

Once a document is on an instance, `dg apply --dry-run` plans the next version without writing
it, and the plan names every top-level section that changed. Change nothing but the report's
heading in `echo-report-params`, so it says *stations* where it said *readings*, and the plan
is an update that changes no step, no parameter and no trigger -- only the report:

```bash
sed 's/: readings above/: stations above/' pipelines/echo-report-params.yaml > heading.yaml
uv run dg apply heading.yaml --dry-run
```

```text
update echo-report-params  version 2 (/home/you/echo-report/heading.yaml)
  report changed

steps of echo-report-params  each step under the last one it waits for
  readings  (playground.generate)
    over  (transform.jq)
Nothing was written: this was a dry run.
```

The record behind that line is the plan's `diff`, which `dg apply`, the API's plan, MCP's
`plan_document` and the editor all carry:

```bash
uv run dg apply heading.yaml --dry-run --json | jq -c '.fields.plan.diff'
```

```json
{"steps_added":[],"steps_removed":[],"steps_changed":[],"params_changed":false,"triggers_changed":false,"requires_changed":false,"report_changed":true,"settings_changed":false}
```

`report_changed` is the flag a reviewer reads before approving a version whose only change is
what its runs will say about themselves. `requires_changed` does the same for `requires:`, and
`settings_changed` covers the name, description, tags, concurrency, priority and importance.

## The documents, hop by hop

`pipelines/echo-report.yaml`:

**`readings`** is the batch, written into the node's `input`:

```yaml
  readings:
    block: playground.generate
    config:
      input:
        - { station: bergen-florida, celsius: 12.4 }
        - { station: oslo-blindern, celsius: 3.1 }
        - { station: tromso-langnes, celsius: -6.8 }
        - { station: trondheim-voll, celsius: 1.2 }
```

**`summary`** reduces it, and keeps a list, an object and a boolean in its answer on purpose:

```yaml
  summary:
    block: transform.jq
    depends_on: [readings]
    config:
      input: ${steps.readings.output.records}
      program: |
        {rows: length,
         stations: map(.station),
         coldest: (min_by(.celsius) | {station, celsius}),
         mean_celsius: ((map(.celsius) | add) / length * 10 | round / 10),
         all_above_freezing: all(.celsius > 0)}
```

**`say`** puts all three into one string:

```yaml
  say:
    block: log.write
    depends_on: [summary]
    config:
      message: "stations ${steps.summary.output.value.stations}, coldest ${steps.summary.output.value.coldest}, all above freezing: ${steps.summary.output.value.all_above_freezing}"
```

**`page`** renders the markdown. Its template sees `values` and nothing else, so the day and
the summary are handed in by reference under the names the template reads them by. A `${...}`
inside `template` itself is refused, because a value put there would become template source:

```yaml
  page:
    block: report.render
    depends_on: [summary]
    config:
      values:
        day: ${params.day}
        summary: ${steps.summary.output.value}
      template: |
        # Readings for {{ day }}

        {{ summary.rows }} stations, mean {{ summary.mean_celsius }} C.
        The coldest was {{ summary.coldest.station }} at {{ summary.coldest.celsius }} C.
        {% if summary.all_above_freezing %}Every station was above freezing.{% else %}At least one station was below freezing.{% endif %}


        | Station |
        | --- |
        {% for station in summary.stations -%}
        | {{ station }} |
        {% endfor %}
```

The two blank lines after `{% endif %}` are one blank line in the page: a block tag eats the
newline that follows it, and a markdown table needs a blank line above it.

**The report** is the step's text:

```yaml
report:
  from: page
```

`pipelines/echo-report-params.yaml` keeps the template form, and reads `params` and one step:

```yaml
report:
  template: |
    # {{ pipeline.code }}: readings above {{ params.threshold }} C

    **{{ run.status }}**, strict: {{ params.strict }}.

    {% if step.over.output %}
    {{ step.over.output.value | length }} stations: {{ step.over.output.value | join(", ") }}.
    {% endif %}

    Asked with `{{ params }}`.
```

Which to choose: a template sees the run's facts -- its status, its duration, every step's
outcome -- and is rendered even for a run that failed or was cancelled, which is when a report
is worth most. A `report.render` step sees only what it is handed, runs only if the steps
above it succeeded, and its text is an output a later step can write to a file or post to a
webhook in the same run.

## Where to go next

- [`echo-storage`](../echo-storage/README.md) is the template form over a round trip through
  storage, with the `duration`, `bytes` and `iso` filters.
- [**Report documents**](https://winterop-com.github.io/dirigent/reports/) lists every name a
  template may read.
- [**The examples**](../README.md): every example in order, and what you need once.
