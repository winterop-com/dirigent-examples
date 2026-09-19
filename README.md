# dhis2-org-units-to-markdown

A piece of a DHIS2 organisation unit hierarchy, read, gated, and turned into documents
somebody reads: a markdown page, an HTML page, and a PDF. The shape matters because of what
a rendering is in dirigent. `report.render` renders text from a Jinja template over the
values it is handed, and it writes nothing at all -- `storage.write` is the only way a value
leaves a run, so a page is always a render step and a write step. That split is what makes a
second format cost one template and not one pipeline: `markdown` and `html` read the same
two values, `parent` and `units`, and the only thing that differs between them is the
template and where the write points.

The PDF is the same lesson from the other side. Rendering a PDF means a typesetter -- TeX,
or typst, or a browser engine -- tens or hundreds of megabytes of it, with fonts. A block
that shipped one would put it in every worker image, including all the pipelines that never
ask for a PDF. So dirigent does not render PDF: `docker.run` does, and the pipeline names an
image and a version. `pipelines/org-units-to-pdf.yaml` is `pipelines/org-units-to-markdown.yaml`
with one container bolted on the end, and that container is the only reason the second
document needs anything the first one does not.

Two documents, then:

| Document | What it is |
| --- | --- |
| `pipelines/org-units-to-markdown.yaml` | Eight hops: one read for the parent's name, one for its children, a gate, and two renderings with a write each. Needs nothing but a network. |
| `pipelines/org-units-to-pdf.yaml` | The same eight, and a ninth: a pandoc container over the markdown file. Needs a Docker daemon, and `docker.run` allowed. |

Everything below was run against the public DHIS2 demo,
`https://play.im.dhis2.org/stable-2-43-1`, version **2.43.1** -- the Sierra Leone database,
with the published `admin` / `district` credential. Nothing here writes to it.

## Run it

`.dirigent/state/` is not in the repository: it is one instance's own database and its
artifacts, disposable, and a clone makes its own. `.dirigent/profiles.yaml` beside it is
committed, because it is addressing rather than state -- which server, and how to get a token
for it. Everything else here is committed too.

```bash
uv sync
```

The fast loop first, with no server anywhere. `--local` applies and runs the document in a
throwaway instance in a temporary directory and deletes it on the way out, so it is handed
the connection and the schema this document names:

```bash
uv run dg validate
uv run dg run --local pipelines/org-units-to-markdown.yaml \
  --connections connections.yaml \
  --schema schemas/org-units-page.json
```

A local run deletes its artifacts on the way out, so add `--keep` to leave the two pages
behind and be told where they landed.

Then the PDF. `docker.run` runs a container on the worker, and reaching a Docker daemon is
reaching root wherever that daemon runs, so the engine refuses the block unless its id has
been named. `--enable-unsafe` is the per-run form:

```bash
uv run dg run --local pipelines/org-units-to-pdf.yaml \
  --connections connections.yaml \
  --schema schemas/org-units-page.json \
  --enable-unsafe docker.run
```

The image is `pandoc/typst:3.11-alpine`, and the first run pulls it: 86MB, once. It is
pandoc with typst as its PDF engine, which is the smallest of the pandoc images that
produces a PDF out of the box -- `pandoc/latex` is 240MB and `pandoc/extra` 566MB, and of
the three only this one and the `-debian` and `-ubuntu` tags of the other two are published
for arm64 as well as amd64.

Then the instance. A DHIS2 connection carries a password, and a connection secret is
encrypted at rest with the instance's own key, so mint one and start the instance with it in
a second terminal, in this directory. Keep the key: an instance that changes it cannot read
what it stored under the old one.

```bash
export DIRIGENT_SECRET_KEY="$(uv run dg secret-key)"
uv run dg dev
```

`dg dev` is one process holding the API, the web UI, the scheduler, one worker and a SQLite
file under `.dirigent/state/`. It keeps running; leave it. On an empty state -- which is what a
fresh clone has, because the state directory is not in the repository -- it migrates the schema,
makes its own admin `dev`, mints that admin one token, and prints the `export DG_TOKEN=` line to
paste. The UI is at `http://127.0.0.1:3333`, which is the address the `local` profile in
`.dirigent/profiles.yaml` holds; `dg dev --port` moves the instance and `DG_URL` is how you tell
the CLI where it went.

That instance allows `docker.run`, because `dirigent.yaml` in this directory names it:

```yaml
enabled_unsafe_blocks: ["docker.run"]
```

An instance you did not `dg init` yourself is told the same thing with an environment
variable, `DIRIGENT_ENABLED_UNSAFE_BLOCKS='["docker.run"]'`. Either way it is the instance's
decision and never the document's: a document that names an unsafe block still applies
cleanly on an instance that refuses to run it, and fails at that step.

Back in the first terminal, mint a token for that admin, whose password is `dirigent-dev`.
The command answers with the `export DG_TOKEN=` line to paste into this terminal, and that
line is the one output this page does not print, because it is a credential:

```bash
uv run dg auth login --username dev --password dirigent-dev
```

```text
  export DG_TOKEN=<the token>

This is the only time the token is shown.
```

The instance holds the shape and the credential; each document names both by code and carries
neither, which is why they apply unchanged anywhere. Both have to exist before the documents
do, because `dg apply` refuses a document whose `requires` this instance cannot satisfy:

```bash
uv run dg schema create schemas/org-units-page.json
uv run dg connection create dhis2 play \
  --name "DHIS2 play demo" \
  --set base_url=https://play.im.dhis2.org/stable-2-43-1 \
  --set basic_username=admin \
  --set basic_password=district
uv run dg connection check play
uv run dg apply
uv run dg run org-units-to-markdown --watch
uv run dg run org-units-to-pdf --watch
```

`dg connection create` asks only for a secret the kind cannot do without, and only when the
command did not say what it wants. This one carries `--set`, and `api_token` is optional, so it
completes without a prompt and leaves that field unset -- which is what it has to be, because a
`dhis2` connection takes an `api_token` or basic credentials, not both.

The pages themselves are in the run rather than on the screen, and every command writes
records into a pipe, so each of them is one `jq` away:

```bash
uv run dg runs show <run id> --json \
  | jq -r '.fields.attempts[] | select(.step_name == "markdown") | .output.text'
uv run dg runs show <run id> --json \
  | jq '.fields.attempts[] | select(.step_name == "save_markdown") | .output'
uv run dg runs show <run id> --json \
  | jq '.fields.attempts[] | select(.step_name == "pdf") | .output.outputs'
```

The hierarchy is a parameter, so any unit with children is a page:

```bash
uv run dg run org-units-to-markdown --watch -p parent=O6uvpzGd5pu   # the 15 chiefdoms of Bo
uv run dg run org-units-to-markdown --watch -p parent=nope          # refused: not a dhis2-uid
```

`./verify.sh` does all of it unattended -- validate, both local runs, an instance on a free
port of its own, the schema, the connection, the apply, both server runs -- and asserts on
the records rather than on anything rendered. Nothing is read back out of storage: each
assertion is made on what the step that produced it already reported. The page opens with
the name the `parent` step read; the markdown table has exactly one row per unit the gate
passed; the HTML carries a `<table`; each write reports the bytes its rendering built, at the
file name the document named; and the PDF the container collected is above a floor of 5000
bytes. When no Docker daemon answers, the PDF document is skipped with a message and the rest
still has to pass, so the repository verifies on a machine that has no Docker at all. It stops
the instance it started by pid on the way out.

## What you see

*Printed as it printed, with this project's directory written as
`/home/you/dhis2-org-units-to-markdown` and a local run's temporary root as `/tmp`.*

`uv run dg validate`:

```text
2026-09-18T22:13:00.531+02:00 [info    ] valid                          [validation] code=org-units-to-markdown document=/home/you/dhis2-org-units-to-markdown/pipelines/org-units-to-markdown.yaml checked="document, offline"
  each step under the last one it waits for
    parent  (dhis2.metadata)
    read  (dhis2.metadata)
      check  (validate.schema)
        markdown  (report.render)  also after parent
          save_markdown  (storage.write)
        html  (report.render)  also after parent
          save_html  (storage.write)
            say  (log.write)  also after save_markdown
2026-09-18T22:13:00.535+02:00 [info    ] valid                          [validation] code=org-units-to-pdf document=/home/you/dhis2-org-units-to-markdown/pipelines/org-units-to-pdf.yaml checked="document, offline"
  each step under the last one it waits for
    parent  (dhis2.metadata)
    read  (dhis2.metadata)
      check  (validate.schema)
        markdown  (report.render)  also after parent
          save_markdown  (storage.write)
            pdf  (docker.run)
              say  (log.write)  also after save_markdown, save_html
        html  (report.render)  also after parent
          save_html  (storage.write)
2026-09-18T22:13:00.536+02:00 [info    ] valid                          [validated] documents=2 invalid=0
```

Nothing has run and nothing has been contacted: each tree is the graph its document already
holds, each step under the last one it waits for. Both trees fork after `check`, because the
two renderings wait on the same gate and on nothing of each other, and `say` is drawn under
one parent with the others named beside it.

`uv run dg run --local pipelines/org-units-to-markdown.yaml ...`:

```text
2026-09-18T22:11:01.293+02:00 [info    ] started                        [run] pipeline=org-units-to-markdown run_id=01a0b624-d129-7393-8975-7c9bef5108fa local=true scratch=file:///tmp/dirigent-local-dv3ez7r6/artifacts/runs/01a0b624-d129-7393-8975-7c9bef5108fa root=/tmp/dirigent-local-dv3ez7r6
2026-09-18T22:11:01.288+02:00 [info    ] queued                         [step parent] block=dhis2.metadata attempt=1
2026-09-18T22:11:01.288+02:00 [info    ] queued                         [step read] block=dhis2.metadata attempt=1
2026-09-18T22:11:01.325+02:00 [info    ] running                        [step parent] block=dhis2.metadata attempt=1
2026-09-18T22:11:01.361+02:00 [info    ] running                        [step read] block=dhis2.metadata attempt=1
2026-09-18T22:11:02.666+02:00 [info    ] metadata read                  [log parent] resource=organisationUnits duration_ms=1332
2026-09-18T22:11:02.668+02:00 [info    ] succeeded                      [step parent] block=dhis2.metadata attempt=1 duration_ms=1343
2026-09-18T22:11:02.721+02:00 [info    ] metadata read                  [log read] resource=organisationUnits duration_ms=1355
2026-09-18T22:11:02.722+02:00 [info    ] succeeded                      [step read] block=dhis2.metadata attempt=1 duration_ms=1361
2026-09-18T22:11:02.732+02:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=7
2026-09-18T22:11:02.734+02:00 [info    ] finished                       [log check] duration_ms=1 output_bytes=902
2026-09-18T22:11:02.747+02:00 [info    ] rendered                       [log html] content_type=text/html text_bytes=1647
2026-09-18T22:11:02.747+02:00 [info    ] succeeded                      [step html] block=report.render attempt=1 duration_ms=15
2026-09-18T22:11:02.752+02:00 [info    ] rendered                       [log markdown] content_type=text/markdown text_bytes=655
2026-09-18T22:11:02.752+02:00 [info    ] succeeded                      [step markdown] block=report.render attempt=1 duration_ms=5
2026-09-18T22:11:02.762+02:00 [info    ] wrote                          [log save_html] uri=org-units.html bytes_written=1647 content_type=text/html
2026-09-18T22:11:02.767+02:00 [info    ] succeeded                      [step save_html] block=storage.write attempt=1 duration_ms=14
2026-09-18T22:11:02.820+02:00 [info    ] wrote                          [log save_markdown] uri=org-units.md bytes_written=655 content_type=text/markdown
2026-09-18T22:11:02.821+02:00 [info    ] succeeded                      [step save_markdown] block=storage.write attempt=1 duration_ms=8
2026-09-18T22:11:02.876+02:00 [info    ] the page is at file:///tmp/dirigent-local-dv3ez7r6/artifacts/runs/01a0b624-d129-7393-8975-7c9bef5108fa/org-units.md (655 bytes) and file:///tmp/dirigent-local-dv3ez7r6/artifacts/runs/01a0b624-d129-7393-8975-7c9bef5108fa/org-units.html (1647 bytes) [log say]
2026-09-18T22:11:02.876+02:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=5
2026-09-18T22:11:03.161+02:00 [info    ] succeeded                      [run] pipeline=org-units-to-markdown run_id=01a0b624-d129-7393-8975-7c9bef5108fa exit_code=0
steps
┏━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step          ┃ block           ┃ outcome   ┃ after                    ┃ duration ┃ output                             ┃
┡━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ parent        │ dhis2.metadata  │ succeeded │ -                        │ 1.3s     │ body={1 keys}  duration_ms=1332    │
│ read          │ dhis2.metadata  │ succeeded │ -                        │ 1.4s     │ body={1 keys}  duration_ms=1355    │
│ check         │ validate.schema │ succeeded │ read                     │ 0.0s     │ value={1 keys}                     │
│ html          │ report.render   │ succeeded │ parent, check            │ 0.0s     │ text=<1647 chars>                  │
│               │                 │           │                          │          │ content_type=text/html             │
│               │                 │           │                          │          │ text_bytes=1647                    │
│ markdown      │ report.render   │ succeeded │ parent, check            │ 0.0s     │ text=<655 chars>                   │
│               │                 │           │                          │          │ content_type=text/markdown         │
│               │                 │           │                          │          │ text_bytes=655                     │
│ save_html     │ storage.write   │ succeeded │ html                     │ 0.0s     │ uri=org-units.html                 │
│               │                 │           │                          │          │ bytes_written=1647                 │
│               │                 │           │                          │          │ content_type=text/html             │
│ save_markdown │ storage.write   │ succeeded │ markdown                 │ 0.0s     │ uri=org-units.md                   │
│               │                 │           │                          │          │ bytes_written=655                  │
│               │                 │           │                          │          │ content_type=text/markdown         │
│ say           │ log.write       │ succeeded │ save_markdown, save_html │ 0.0s     │ -                                  │
└───────────────┴─────────────────┴───────────┴──────────────────────────┴──────────┴────────────────────────────────────┘
```

655 bytes rendered and 655 bytes written, 1647 and 1647: `report.render` says how much text
it built and `storage.write` says how much it put out, and the two agreeing is the whole of
what a write can promise. The two renderings ran in either order, because neither waits on the
other; the log is interleaved for the same reason.

`uv run dg run --local pipelines/org-units-to-pdf.yaml ... --enable-unsafe docker.run`, from
`save_markdown` on:

```text
2026-09-18T22:11:15.931+02:00 [info    ] wrote                          [log save_markdown] uri=org-units.md bytes_written=655 content_type=text/markdown
2026-09-18T22:11:15.932+02:00 [info    ] succeeded                      [step save_markdown] block=storage.write attempt=1 duration_ms=11
2026-09-18T22:11:15.987+02:00 [info    ] running                        [step pdf] block=docker.run attempt=1
2026-09-18T22:11:15.987+02:00 [info    ] waiting                        [step pdf] block=docker.run attempt=1
2026-09-18T22:11:17.236+02:00 [info    ] container started              [log pdf] container_id=d5c42b973e07 image=pandoc/typst:3.11-alpine network=none
2026-09-18T22:11:18.334+02:00 [info    ] output collected               [log pdf] name=page uri=org-units.pdf bytes_written=37267
2026-09-18T22:11:18.364+02:00 [info    ] container finished             [log pdf] container_id=d5c42b973e07 exit_code=0 stdout_bytes=0 stderr_bytes=0
2026-09-18T22:11:18.366+02:00 [info    ] succeeded                      [step pdf] block=docker.run attempt=1 duration_ms=2379
2026-09-18T22:11:18.382+02:00 [info    ] the page is at file:///tmp/dirigent-local-g_jv4ofa/artifacts/runs/01a0b625-04e3-74cc-95fb-27a00cda5fd0/org-units.md (655 bytes), file:///tmp/dirigent-local-g_jv4ofa/artifacts/runs/01a0b625-04e3-74cc-95fb-27a00cda5fd0/org-units.html (1647 bytes) and file:///tmp/dirigent-local-g_jv4ofa/artifacts/runs/01a0b625-04e3-74cc-95fb-27a00cda5fd0/org-units.pdf [log say]
2026-09-18T22:11:18.382+02:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=15
2026-09-18T22:11:18.500+02:00 [info    ] succeeded                      [run] pipeline=org-units-to-pdf run_id=01a0b625-04e3-74cc-95fb-27a00cda5fd0 exit_code=0
```

`running` then `waiting`: the block creates the container, starts it detached and hands the
run back to the engine, which probes it. A container that ran for an hour would cost one
parked row rather than an hour of a worker. `output collected` is the record that says the
file made it out of the container's mount, with the URI it landed at and its size -- 37267
bytes of PDF from 655 bytes of markdown, which is what a font is.

`uv run dg schema create ...` and `uv run dg connection create ...`:

```text
stored schema org-units-page
```

```text
2026-09-18T22:12:10.022+02:00 [info    ] created                        [connection.created] code=play connection_kind=dhis2 name="DHIS2 play demo" config={"base_url":"https://play.im.dhis2.org/stable-2-43-1","api_token":null,"basic_username":"admin","verify_tls":true,"timeout":"30s","basic_password":"***"}
```

The password is already withheld in the record the command answers with, and in every read
after it.

`uv run dg connection check play`:

```text
2026-09-18T22:12:12.526+02:00 [info    ] healthy                        [connection.checked] code=play healthy=true version=2.43.1
```

One line, four facts: the URL resolves, TLS is as configured, the credential is accepted, and
the instance's version is **2.43.1** -- its own word for itself, read from `/api/system/info`
rather than guessed from an `/api/N` path.

`uv run dg apply`:

```text
create org-units-to-markdown  version 1
(/home/you/dhis2-org-units-to-markdown/pipelines/org-units-to-markdown.yaml)
create org-units-to-pdf  version 1
(/home/you/dhis2-org-units-to-markdown/pipelines/org-units-to-pdf.yaml)
```

`uv run dg run org-units-to-markdown --watch`:

```text
2026-09-18T22:12:14.857+02:00 [info    ] started                        [run] pipeline=org-units-to-markdown run_id=01a0b625-f085-7682-9940-654641423ef5 local=false
2026-09-18T22:12:14.855+02:00 [info    ] queued                         [step parent] block=dhis2.metadata attempt=1
2026-09-18T22:12:14.855+02:00 [info    ] queued                         [step read] block=dhis2.metadata attempt=1
2026-09-18T22:12:15.038+02:00 [info    ] running                        [step parent] block=dhis2.metadata attempt=1
2026-09-18T22:12:15.057+02:00 [info    ] running                        [step read] block=dhis2.metadata attempt=1
2026-09-18T22:12:15.850+02:00 [info    ] metadata read                  [log parent] resource=organisationUnits duration_ms=795
2026-09-18T22:12:15.858+02:00 [info    ] succeeded                      [step parent] block=dhis2.metadata attempt=1 duration_ms=820
2026-09-18T22:12:15.892+02:00 [info    ] metadata read                  [log read] resource=organisationUnits duration_ms=828
2026-09-18T22:12:15.896+02:00 [info    ] succeeded                      [step read] block=dhis2.metadata attempt=1 duration_ms=839
2026-09-18T22:12:16.097+02:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=19
2026-09-18T22:12:16.109+02:00 [info    ] finished                       [log check] duration_ms=2 output_bytes=902
2026-09-18T22:12:16.611+02:00 [info    ] rendered                       [log html] content_type=text/html text_bytes=1647
2026-09-18T22:12:16.611+02:00 [info    ] succeeded                      [step html] block=report.render attempt=1 duration_ms=6
2026-09-18T22:12:16.616+02:00 [info    ] succeeded                      [step markdown] block=report.render attempt=1 duration_ms=5
2026-09-18T22:12:16.626+02:00 [info    ] wrote                          [log save_html] uri=file://./.dirigent/state/artifacts/runs/01a0b625-f085-7682-9940-654641423ef5/org-units.html bytes_written=1647 content_type=text/html
2026-09-18T22:12:16.616+02:00 [info    ] rendered                       [log markdown] content_type=text/markdown text_bytes=655
2026-09-18T22:12:16.627+02:00 [info    ] succeeded                      [step save_html] block=storage.write attempt=1 duration_ms=11
2026-09-18T22:12:17.139+02:00 [info    ] wrote                          [log save_markdown] uri=file://./.dirigent/state/artifacts/runs/01a0b625-f085-7682-9940-654641423ef5/org-units.md bytes_written=655 content_type=text/markdown
2026-09-18T22:12:17.140+02:00 [info    ] succeeded                      [step save_markdown] block=storage.write attempt=1 duration_ms=13
2026-09-18T22:12:17.645+02:00 [info    ] the page is at file://./.dirigent/state/artifacts/runs/01a0b625-f085-7682-9940-654641423ef5/org-units.md (655 bytes) and file://./.dirigent/state/artifacts/runs/01a0b625-f085-7682-9940-654641423ef5/org-units.html (1647 bytes) [log say]
2026-09-18T22:12:17.645+02:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=5
2026-09-18T22:12:19.033+02:00 [info    ] succeeded                      [run] pipeline=org-units-to-markdown run_id=01a0b625-f085-7682-9940-654641423ef5 pipeline_version=1 triggered_by="dev (token cli-dev)" duration_ms=2607 items_total=0 items_failed=0 exit_code=0 priority=normal
run 01a0b625-f085-7682-9940-654641423ef5
pipeline      org-units-to-markdown (version 1)
status        succeeded
triggered by  dev (token cli-dev)
duration      2.6s
items         -

steps
┏━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━┓
┃ step          ┃ block           ┃ outcome   ┃ after                    ┃ attempts ┃ duration ┃ error ┃
┡━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━┩
│ parent        │ dhis2.metadata  │ succeeded │ -                        │ 1        │ 0.8s     │ -     │
│ read          │ dhis2.metadata  │ succeeded │ -                        │ 1        │ 0.8s     │ -     │
│ check         │ validate.schema │ succeeded │ read                     │ 1        │ 0.0s     │ -     │
│ html          │ report.render   │ succeeded │ parent, check            │ 1        │ 0.0s     │ -     │
│ markdown      │ report.render   │ succeeded │ parent, check            │ 1        │ 0.0s     │ -     │
│ save_html     │ storage.write   │ succeeded │ html                     │ 1        │ 0.0s     │ -     │
│ save_markdown │ storage.write   │ succeeded │ markdown                 │ 1        │ 0.0s     │ -     │
│ say           │ log.write       │ succeeded │ save_markdown, save_html │ 1        │ 0.0s     │ -     │
└───────────────┴─────────────────┴───────────┴──────────────────────────┴──────────┴──────────┴───────┘

outputs
┏━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step          ┃ output                                                                                                 ┃
┡━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ parent        │ body={1 keys}  duration_ms=795                                                                         │
│ read          │ body={1 keys}  duration_ms=828                                                                         │
│ check         │ value={1 keys}                                                                                         │
│ html          │ text=<1647 chars>  content_type=text/html  text_bytes=1647                                             │
│ markdown      │ text=<655 chars>  content_type=text/markdown  text_bytes=655                                           │
│ save_html     │ uri=file://./.dirigent/state/artifacts/runs/01a0b625-f085-7682-9940-654641423ef5/org-units.html        │
│               │ bytes_written=1647  content_type=text/html                                                             │
│ save_markdown │ uri=file://./.dirigent/state/artifacts/runs/01a0b625-f085-7682-9940-654641423ef5/org-units.md          │
│               │ bytes_written=655  content_type=text/markdown                                                          │
│ say           │ -                                                                                                      │
└───────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

Same document, same eight hops, and the only difference is where the files landed: on the
instance `${run.scratch}` is this run's own directory under the artifact root rather than a
temporary one that is about to be deleted.

`uv run dg run org-units-to-pdf --watch`, the ninth hop and the summary:

```text
2026-09-18T22:12:25.335+02:00 [info    ] running                        [step pdf] block=docker.run attempt=1
2026-09-18T22:12:25.335+02:00 [info    ] waiting                        [step pdf] block=docker.run attempt=1
2026-09-18T22:12:26.785+02:00 [info    ] container started              [log pdf] container_id=d4091a1299f7 image=pandoc/typst:3.11-alpine network=none
2026-09-18T22:12:27.922+02:00 [info    ] output collected               [log pdf] name=page uri=file://./.dirigent/state/artifacts/runs/01a0b626-127f-76e7-b8f8-be0058dedc46/org-units.pdf bytes_written=37267
2026-09-18T22:12:27.952+02:00 [info    ] container finished             [log pdf] container_id=d4091a1299f7 exit_code=0 stdout_bytes=0 stderr_bytes=0
2026-09-18T22:12:27.954+02:00 [info    ] succeeded                      [step pdf] block=docker.run attempt=1 duration_ms=2619
2026-09-18T22:12:30.255+02:00 [info    ] succeeded                      [run] pipeline=org-units-to-pdf run_id=01a0b626-127f-76e7-b8f8-be0058dedc46 pipeline_version=1 triggered_by="dev (token cli-dev)" duration_ms=4727 items_total=0 items_failed=0 exit_code=0 priority=normal
run 01a0b626-127f-76e7-b8f8-be0058dedc46
pipeline      org-units-to-pdf (version 1)
status        succeeded
triggered by  dev (token cli-dev)
duration      4.7s
items         -

steps
┏━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━┓
┃ step          ┃ block           ┃ outcome   ┃ after                         ┃ attempts ┃ duration ┃ error ┃
┡━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━┩
│ parent        │ dhis2.metadata  │ succeeded │ -                             │ 1        │ 0.9s     │ -     │
│ read          │ dhis2.metadata  │ succeeded │ -                             │ 1        │ 0.9s     │ -     │
│ check         │ validate.schema │ succeeded │ read                          │ 1        │ 0.0s     │ -     │
│ html          │ report.render   │ succeeded │ parent, check                 │ 1        │ 0.0s     │ -     │
│ markdown      │ report.render   │ succeeded │ parent, check                 │ 1        │ 0.0s     │ -     │
│ save_html     │ storage.write   │ succeeded │ html                          │ 1        │ 0.0s     │ -     │
│ save_markdown │ storage.write   │ succeeded │ markdown                      │ 1        │ 0.0s     │ -     │
│ pdf           │ docker.run      │ succeeded │ save_markdown                 │ 1        │ 2.6s     │ -     │
│ say           │ log.write       │ succeeded │ save_markdown, save_html, pdf │ 1        │ 0.0s     │ -     │
└───────────────┴─────────────────┴───────────┴───────────────────────────────┴──────────┴──────────┴───────┘
```

The container is 2.6 of the run's 4.7 seconds, and 1.4 of those 2.6 are the daemon starting
it. A PDF is not slow; a container is not free.

The markdown, as `dg runs show` hands it back:

```bash
uv run dg runs show 01a0b625-f085-7682-9940-654641423ef5 --json \
  | jq -r '.fields.attempts[] | select(.step_name == "markdown") | .output.text'
```

```markdown
# Organisation units under Sierra Leone

| id | code | name |
| --- | --- | --- |
| `O6uvpzGd5pu` | OU_264 | Bo |
| `fdc6uOvgoji` | OU_193190 | Bombali |
| `lc3eMKXaEfw` | OU_197385 | Bonthe |
| `jUb8gELQApl` | OU_204856 | Kailahun |
| `PMa2VCrupOd` | OU_211212 | Kambia |
| `kJq2mPyFEHo` | OU_222616 | Kenema |
| `qhqAxPSTUXp` | OU_226213 | Koinadugu |
| `Vth0fbpFcsO` | OU_233310 | Kono |
| `jmIPBj66vD6` | OU_246990 | Moyamba |
| `TEQlaapDQoK` | OU_254945 | Port Loko |
| `bL4ooGhyHRQ` | OU_260377 | Pujehun |
| `eIQbndfxQMb` | OU_268149 | Tonkolili |
| `at6UHUQatSo` | OU_278310 | Western Area |

13 organisation units, read from the DHIS2 play demo.
```

Thirteen districts, Bo to Western Area, in the order DHIS2 sorted them. The title says
"Sierra Leone" because the `parent` step read the name; the parameter only ever held
`ImspTQPwCqd`.

The HTML is the same values through the other template -- a document that opens from disk,
with its stylesheet inline and nothing to fetch. Two of its thirteen rows:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Organisation units under Sierra Leone</title>
<style>
body { font-family: system-ui, sans-serif; max-width: 48rem; margin: 2rem auto; padding: 0 1rem; }
table { border-collapse: collapse; width: 100%; }
th, td { border-bottom: 1px solid #ccc; padding: 0.4rem 0.6rem; text-align: left; }
code { font-family: ui-monospace, monospace; }
</style>
</head>
<body>
<h1>Organisation units under Sierra Leone</h1>
<table>
<thead><tr><th>id</th><th>code</th><th>name</th></tr></thead>
<tbody>
<tr><td><code>O6uvpzGd5pu</code></td><td>OU_264</td><td>Bo</td></tr>
<tr><td><code>fdc6uOvgoji</code></td><td>OU_193190</td><td>Bombali</td></tr>
</tbody>
</table>
<p>13 organisation units, read from the DHIS2 play demo.</p>
</body>
</html>
```

And the write and the container's output, by name:

```json
{
  "uri": "file://./.dirigent/state/artifacts/runs/01a0b625-f085-7682-9940-654641423ef5/org-units.md",
  "bytes_written": 655,
  "content_type": "text/markdown"
}
```

```json
{
  "page": "file://./.dirigent/state/artifacts/runs/01a0b626-127f-76e7-b8f8-be0058dedc46/org-units.pdf"
}
```

`uv run dg run --local pipelines/org-units-to-markdown.yaml ... -p parent=nope`:

```text
2026-09-18T22:11:31.014+02:00 [error   ] parameter parent is invalid: 'nope' is not a 'dhis2-uid' [error] status=3 title=Refused
```

Nothing ran. `format: dhis2-uid` on the parameter is the pack's own format, and a parameter's
schema is checked with the same checker a gate is, so a uid of the wrong shape is refused
before a single call is made.

## The first document, hop by hop

`pipelines/org-units-to-markdown.yaml`, in full -- the file itself carries these notes as
comments, at the line each one is about.

The header says which document language this is and which sort of document, and then the
quartet every addressable thing carries: `code` is the key this pipeline is addressed by,
`name` a human title with no identity at all, `description` the long form.

```yaml
format: dirigent/v1
kind: pipeline
code: org-units-to-markdown
name: Organisation units, as a page
description: Read the organisation units under one parent, gate them, and render the list as a markdown page and as an HTML page.

tags: [dhis2, metadata, validate, report, storage]
```

`requires` is the document saying what it needs of an instance: every block id, the
connection code, the schema code. An instance missing one of them refuses the document rather
than failing halfway through a run.

```yaml
requires:
  blocks:
    - dhis2.metadata
    - validate.schema
    - report.render
    - storage.write
    - log.write
  connections:
    - play
  schemas:
    - org-units-page
```

`params` is a JSON Schema over the run's parameters, and `format` in it asserts: `dhis2-uid`
is a format the installed pack contributes, so `-p parent=nope` above never reached DHIS2.

```yaml
params:
  type: object
  additionalProperties: false
  properties:
    parent:
      type: string
      format: dhis2-uid
      default: ImspTQPwCqd
      description: The organisation unit whose children the page lists. The default is Sierra Leone, the root of the play demo's hierarchy.
```

**Hop one, `parent`.** One extra round trip, for one string. The parameter holds a uid, and a
page titled `ImspTQPwCqd` is a page nobody reads, so the parent unit is read for its own name
with a projection of two fields. `fields` takes a list since 0.16.4 and sends it comma-joined;
a nested selector such as `parent[id,name]` has to be quoted inside a flow list, because YAML
refuses a bare bracket in a flow item.

```yaml
steps:
  parent:
    block: dhis2.metadata
    retry:
      max_attempts: 3
      backoff: 2s
    config:
      connection: play
      resource: organisationUnits
      fields: [id, name]
      filter: "id:eq:${params.parent}"
```

A reference that is the whole value resolves to the typed value; one inside a larger string
interpolates as text, which is what `filter:` wants. The retry budget is for the failures
worth spending it on: a connection failure on the wire, a 5xx and a 429 are `transient` and
are retried, while any other 4xx and a collection name this version does not publish are
`rejected` and spend no budget at all.

**Hop two, `read`.** The children, and it does not wait for `parent`: neither reads anything
of the other, so the engine runs both at once and the run costs one round trip rather than
two. `order:` sorts in DHIS2, which is why no template here knows how to sort.

```yaml
  read:
    block: dhis2.metadata
    retry:
      max_attempts: 3
      backoff: 2s
    config:
      connection: play
      resource: organisationUnits
      fields: [id, code, name, level]
      filter: "parent.id:eq:${params.parent}"
      order: [name:asc]
```

**Hop three, `check`.** The gate, naming a schema by code -- the one the instance holds, so
two pipelines gating on the same shape gate on the same shape. A mismatch is `rejected`: the
same value against the same schema will never pass, so it is not retried.

```yaml
  check:
    block: validate.schema
    depends_on: [read]
    config:
      input: ${steps.read.output.body}
      schema: org-units-page
```

**Hop four, `markdown`.** `report.render` renders text and hands it on; it opens no file and
reaches nothing. `values` is everything the template may read and the only thing it may read,
and `units` comes out of the gate rather than out of the read, so what the page lists provably
passed the shape. The template is Jinja with `trim_blocks` and `lstrip_blocks` on, which is
why a loop on its own line leaves no blank line between the table's rows.

```yaml
  markdown:
    block: report.render
    depends_on: [parent, check]
    config:
      values:
        parent: ${steps.parent.output.body.organisationUnits.0.name}
        units: ${steps.check.output.value.organisationUnits}
      content_type: text/markdown
      template: |
        # Organisation units under {{ parent }}

        | id | code | name |
        | --- | --- | --- |
        {% for unit in units %}
        | `{{ unit.id }}` | {{ unit.code }} | {{ unit.name }} |
        {% endfor %}

        {{ units | length }} organisation units, read from the DHIS2 play demo.
```

A name the template was not given renders as the empty string rather than failing the step,
so a page missing a fact is still a page. The template is compiled when the document is
applied, so a syntax error is refused at `template` rather than at the first run.

**Hop five, `save_markdown`.** Storage's only door out. `${run.scratch}` is this run's own
directory under the artifact root; a target naming a bucket URI writes there instead and
outlives the run, and nothing above it changes, because the scheme is the only difference.
The content type is said twice on purpose: the render says what the text is and the write
records it, so the object carries its type on a backend that can hold one and is read from
the `.md` extension on one that cannot.

```yaml
  save_markdown:
    block: storage.write
    depends_on: [markdown]
    config:
      target: ${run.scratch}/org-units.md
      text: ${steps.markdown.output.text}
      content_type: ${steps.markdown.output.content_type}
```

**Hops six and seven, `html` and `save_html`.** The same two values, a different template,
its own write. This is the pair that makes the point: a format is a template, and adding a
third is one more render step and one more write, never a change to anything above `markdown`.
The sandbox does not autoescape, so a template writing HTML escapes what it interpolates
itself -- `| e` on every value that reaches the markup.

```yaml
  html:
    block: report.render
    depends_on: [parent, check]
    config:
      values:
        parent: ${steps.parent.output.body.organisationUnits.0.name}
        units: ${steps.check.output.value.organisationUnits}
      content_type: text/html
      template: |
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <title>Organisation units under {{ parent | e }}</title>
        <style>
        body { font-family: system-ui, sans-serif; max-width: 48rem; margin: 2rem auto; padding: 0 1rem; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border-bottom: 1px solid #ccc; padding: 0.4rem 0.6rem; text-align: left; }
        code { font-family: ui-monospace, monospace; }
        </style>
        </head>
        <body>
        <h1>Organisation units under {{ parent | e }}</h1>
        <table>
        <thead><tr><th>id</th><th>code</th><th>name</th></tr></thead>
        <tbody>
        {% for unit in units %}
        <tr><td><code>{{ unit.id | e }}</code></td><td>{{ unit.code | e }}</td><td>{{ unit.name | e }}</td></tr>
        {% endfor %}
        </tbody>
        </table>
        <p>{{ units | length }} organisation units, read from the DHIS2 play demo.</p>
        </body>
        </html>

  save_html:
    block: storage.write
    depends_on: [html]
    config:
      target: ${run.scratch}/org-units.html
      text: ${steps.html.output.text}
      content_type: ${steps.html.output.content_type}
```

**Hop eight, `say`.** Both files on the run's own timeline, named by what the writes returned
rather than by the paths typed a second time. `say` waits for two steps, which is the one
place in this document where the graph is not a tree of single edges.

```yaml
  say:
    block: log.write
    depends_on: [save_markdown, save_html]
    config:
      message: "the page is at ${steps.save_markdown.output.uri} (${steps.save_markdown.output.bytes_written} bytes) and ${steps.save_html.output.uri} (${steps.save_html.output.bytes_written} bytes)"
```

## The PDF, hop by hop

`pipelines/org-units-to-pdf.yaml` is the eight hops above with one more after
`save_markdown`, and a `say` that waits for it too. Its `requires` names `docker.run` and its
`tags` carry `docker`; everything else in the header and the first seven steps is identical.

```yaml
  pdf:
    block: docker.run
    depends_on: [save_markdown]
    deadline: 5m
    config:
      image: pandoc/typst:3.11-alpine
      pull: true
      network: none
      inputs:
        org-units.md: ${steps.save_markdown.output.uri}
      outputs:
        page: ${run.scratch}/org-units.pdf
      argv:
        - /dirigent/inputs/org-units.md
        - --from=markdown
        - --to=pdf
        - --pdf-engine=typst
        - --output=/dirigent/outputs/page
      memory: 512mb
      pids_limit: 128
```

**The two mounts are how a value crosses into a container and back.** `inputs` is always
storage: each key is a file name inside the read-only mount and each value the URI it is read
from, which here is the URI `save_markdown` returned rather than the path typed again.
`outputs` is the way back: a target carrying a URI scheme is copied to storage once the
container exits, and one without a scheme is a path in the run's work directory, which is how
one step hands the next a build context or a compose file.

**The output key carries no dot**, and that is not cosmetic: a reference path splits on dots,
so a key named `org-units.pdf` could never be read back, while `page` reads as
`${steps.pdf.output.outputs.page}`. The extension lives on the target, which is what makes the
stored object `application/pdf` -- and it has to, because `storage.write` takes text or a
value and a PDF is neither. A binary document leaves a run through a container's collected
output or it does not leave at all, which is also why nothing here reads the PDF back: the
size and the URI in `output collected` are the container's own account of what it left behind.

**The container is contained.** `network: none` is the default and is right here: a pandoc
container's input is a file, so it is given no network at all. `memory` and `pids_limit`
bound what a runaway image can take from the worker it landed on, `pull: true` fetches the
image so this runs on a machine that has never rendered a PDF -- the pull is the daemon's,
which `network: none` does not touch -- and `deadline` is the step's, because the container
runs under the engine's deadline and the block never waits on it.

**The image's entrypoint is pandoc itself**, so `argv` is pandoc's argument vector and never
a command of its own. `--to=pdf` says what to build, which is why the output file needs no
extension inside the mount. Three images were tried: `pandoc/typst` (86MB, a PDF in 0.2s),
`pandoc/latex` (240MB, 0.65s), and `pandoc/extra` (566MB, which despite its name carries no
typst, so it renders through LaTeX at the same speed as the smaller image). Only
`pandoc/typst` and the `-debian` and `-ubuntu` tags of the other two are published for arm64.

**A bind mount is resolved on the daemon's filesystem, not the worker's**, so the mounts only
reach the container when the daemon can see the run's work directory. That holds for a daemon
on the same machine and for the `docker:dind` sidecar in dirigent's own compose stack;
[docs/docker.md](https://winterop-com.github.io/dirigent/docker/) has the table of every way
`DOCKER_HOST` is resolved. A deployment where only some workers have a daemon tags them
`docker` and the document declares `requires.workers: [docker]`; this one does not, because
`dg dev` is one worker and it is the one with the daemon.

### The shape, and the credential

`schemas/org-units-page.json` is the contract, applied on its own with `dg schema create`. A
schema reads its identity from its own keywords: `$id` becomes the code it is addressed by,
`title` its name, `description` its body.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "org-units-page",
  "title": "Organisation units, as a page lists them",
  "description": "An organisationUnits read projected to id, code, name and level: one object per row of the page's table, with every identifier held to the pack's own dhis2-uid format and every code to dhis2-code.",
  "type": "object",
  "required": ["organisationUnits"],
  "properties": {
    "organisationUnits": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "required": ["id", "code", "name", "level"],
        "properties": {
          "id": { "type": "string", "format": "dhis2-uid" },
          "code": { "type": "string", "format": "dhis2-code" },
          "name": { "type": "string", "minLength": 1 },
          "level": { "type": "integer", "minimum": 1 }
        },
        "additionalProperties": false
      }
    }
  }
}
```

`required` is about presence, `properties` about shape, and `additionalProperties: false`
closes the door on anything the projection did not ask for -- which is what makes this gate
notice a `fields:` line somebody widened. `dhis2-uid` and `dhis2-code` are this pack's
formats, and they assert because the pack is installed: in JSON Schema a `format` annotates
and nothing more, but dirigent always hands its validator a checker and every installed
pack's formats join it. A uid that is ten characters instead of eleven fails here, in one
line with the path in it -- and a gate is worth more in front of a page than almost anywhere
else, because a page of plausible nonsense is read and believed.

`connections.yaml` is what a `--local` run is handed, because a local run starts on a
throwaway instance holding nothing. The credential in it is the play demo's own, published so
that anyone may try the instance; a real one belongs in a connection the server holds,
encrypted under its key, and never in a file beside the documents. The server refuses a
document that carries a `connections:` section for exactly that reason, which is why this is
a file of its own rather than a section of the pipeline.

## Where to go next

This is the last example on the shelf.

- [**Docker**](https://winterop-com.github.io/dirigent/docker/) is the family the ninth hop
  belongs to: one container, a whole compose stack, an image built and pushed, and how a
  worker reaches a daemon it is allowed to reach.
- [**The DHIS2 tutorial**](https://winterop-com.github.io/dirigent-dhis2/tutorial/) builds a
  read, a gate and a rehearsed write one section at a time, with the failures shown.
- [**The examples**](../README.md): every example in order, and what you need once.
