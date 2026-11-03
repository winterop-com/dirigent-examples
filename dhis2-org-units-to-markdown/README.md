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
`https://play.dhis2.org/2.42`, the newest 2.42 demo (**2.42.7.1** when this was written) -- the Sierra Leone database,
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
encrypted at rest with the instance's own key, so the instance needs a key before it can hold
one. Mint it once into `.env` -- the gitignored file beside the state that already holds this
instance's token -- and every command run in this directory reads it from there, which is what
keeps this instance on the key it sealed with: one that changes its key cannot open the secrets
it already stored. In a second terminal, in this directory:

```bash
grep -q '^DIRIGENT_SECRET_KEY=' .env 2>/dev/null \
  || printf 'DIRIGENT_SECRET_KEY=%s\n' "$(uv run dg secret-key)" >> .env
DIRIGENT_ENABLED_UNSAFE_BLOCKS='["docker.run"]' uv run dg dev
```

`dg dev` is one process holding the API, the web UI, the scheduler, one worker and a SQLite
file under `.dirigent/state/`. It keeps running; leave it. On an empty state -- which is what a
fresh clone has, because the state directory is not in the repository -- it migrates the schema,
makes its own admin `admin`, mints that admin one token, and prints the `export DG_TOKEN=` line to
paste. The UI is at `http://127.0.0.1:3333`, which is the address the `local` profile in
`.dirigent/profiles.yaml` holds; `dg dev --port` moves the instance and `DG_URL` is how you tell
the CLI where it went.

That instance allows `docker.run`, because the variable on that command names it. It has to be
the process environment, or the file `DIRIGENT_CONFIG_FILE` names: a `dirigent.yaml` or `.env` in
this directory travels with a checkout, so `dg` does not read the allowlist from either. It is the
decision of whoever starts the instance and never the document's: a document that names an unsafe
block still applies cleanly on an instance that refuses to run it, and fails at that step.

Back in the first terminal, mint a token for that admin, whose password is `admin`.
The command answers with the `export DG_TOKEN=` line to paste into this terminal, and that
line is the one output this page does not print, because it is a credential:

```bash
uv run dg auth login --username admin --password admin
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
  --set base_url=https://play.dhis2.org/2.42 \
  --set follow_redirects_with_auth=true \
  --set basic_username=admin \
  --set basic_password=district
uv run dg connection check play
uv run dg apply
uv run dg run org-units-to-markdown --watch
uv run dg run org-units-to-pdf --watch
```

`dg connection create` asks for a credential only when the command gave none. A `dhis2`
connection takes an `api_token` or a `basic_username` and `basic_password`, never both; this
one names the basic pair with `--set`, so it completes without a prompt and leaves `api_token`
unset.

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
still has to pass, so the repository verifies on a machine that has no Docker at all. It keeps
the key on that same `.env` line, and writes the schema and the connection only when the
instance does not already hold them, so its second run inherits the state its first run left.
It stops the instance it started by pid on the way out.

### If the key was lost

A connection is sealed with the key the instance held when it was written, so a state left over
from a key that is gone answers `uv run dg connection check play` with a record whose `detail`
begins `SecretKeyMismatch`. Nothing opens that row again, and the secret it holds is not
recoverable. Nor can it be deleted once a pipeline names it: `dg connection delete` names the
pipeline and refuses. So write it once more, in place, under the key this instance has now.
`dg connection ensure` writes the row straight to this instance's database, reading `.env` for
the key rather than a token, and brings it whole to what the arguments say:

```bash
uv run dg connection ensure dhis2 play \
  --name "DHIS2 play demo" \
  --set base_url=https://play.dhis2.org/2.42 \
  --set follow_redirects_with_auth=true \
  --set basic_username=admin \
  --set basic_password=district
```

`verify.sh` does exactly that when its own check reports that class.

## What you see

*Printed as it printed, with this project's directory written as
`/home/you/dhis2-org-units-to-markdown` and a local run's temporary root as `/tmp`.*

`uv run dg validate`:

```text
2026-11-03T14:36:50.893+01:00 [info    ] valid                          [validation] code=org-units-to-markdown document=/home/you/dhis2-org-units-to-markdown/pipelines/org-units-to-markdown.yaml checked="document and installed blocks"
  each step under the last one it waits for
    parent  (dhis2.metadata)
    read  (dhis2.metadata)
      check  (validate.schema)
        markdown  (report.render)  also after parent
          save_markdown  (storage.write)
        html  (report.render)  also after parent
          save_html  (storage.write)
            say  (log.write)  also after save_markdown
2026-11-03T14:36:50.902+01:00 [info    ] valid                          [validation] code=org-units-to-pdf document=/home/you/dhis2-org-units-to-markdown/pipelines/org-units-to-pdf.yaml checked="document and installed blocks"
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
2026-11-03T14:36:50.903+01:00 [info    ] valid                          [validated] documents=2 invalid=0 skipped=0
```

Nothing has run and nothing has been contacted: each tree is the graph its document already
holds, each step under the last one it waits for. Both trees fork after `check`, because the
two renderings wait on the same gate and on nothing of each other, and `say` is drawn under
one parent with the others named beside it.

`uv run dg run --local pipelines/org-units-to-markdown.yaml ...`:

```text
2026-11-03T14:36:53.660+01:00 [info    ] started                        [run] pipeline=org-units-to-markdown run_id=01a1a1a0-8395-7213-9ae9-42ee2968fd55 local=true scratch=file:///tmp/dirigent-local-f88ul9bj/artifacts/runs/01a1a1a0-8395-7213-9ae9-42ee2968fd55 root=/tmp/dirigent-local-f88ul9bj
2026-11-03T14:36:53.502+01:00 [info    ] queued                         [step parent] block=dhis2.metadata attempt=1
2026-11-03T14:36:53.502+01:00 [info    ] queued                         [step read] block=dhis2.metadata attempt=1
2026-11-03T14:36:53.710+01:00 [info    ] running                        [step parent] block=dhis2.metadata attempt=1
2026-11-03T14:36:53.760+01:00 [info    ] running                        [step read] block=dhis2.metadata attempt=1
2026-11-03T14:36:55.738+01:00 [info    ] metadata read                  [log parent] resource=organisationUnits rows=1 duration_ms=2007
2026-11-03T14:36:55.742+01:00 [info    ] succeeded                      [step parent] block=dhis2.metadata attempt=1 duration_ms=2033
2026-11-03T14:36:55.753+01:00 [info    ] metadata read                  [log read] resource=organisationUnits rows=13 duration_ms=1980
2026-11-03T14:36:55.754+01:00 [info    ] succeeded                      [step read] block=dhis2.metadata attempt=1 duration_ms=1994
2026-11-03T14:36:55.754+01:00 [info    ] queued                         [step check] block=validate.schema attempt=1
2026-11-03T14:36:55.758+01:00 [info    ] running                        [step check] block=validate.schema attempt=1
2026-11-03T14:36:55.771+01:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=13
2026-11-03T14:36:55.771+01:00 [info    ] queued                         [step markdown] block=report.render attempt=1
2026-11-03T14:36:55.771+01:00 [info    ] queued                         [step html] block=report.render attempt=1
2026-11-03T14:36:55.779+01:00 [info    ] finished                       [log check] duration_ms=2 output_bytes=880
2026-11-03T14:36:55.786+01:00 [info    ] running                        [step html] block=report.render attempt=1
2026-11-03T14:36:55.800+01:00 [info    ] rendered                       [log html] content_type=text/html text_bytes=1647
2026-11-03T14:36:55.800+01:00 [info    ] succeeded                      [step html] block=report.render attempt=1 duration_ms=14
2026-11-03T14:36:55.800+01:00 [info    ] queued                         [step save_html] block=storage.write attempt=1
2026-11-03T14:36:55.800+01:00 [info    ] running                        [step markdown] block=report.render attempt=1
2026-11-03T14:36:55.837+01:00 [info    ] rendered                       [log markdown] content_type=text/markdown text_bytes=655
2026-11-03T14:36:55.837+01:00 [info    ] succeeded                      [step markdown] block=report.render attempt=1 duration_ms=37
2026-11-03T14:36:55.837+01:00 [info    ] queued                         [step save_markdown] block=storage.write attempt=1
2026-11-03T14:36:55.837+01:00 [info    ] running                        [step save_html] block=storage.write attempt=1
2026-11-03T14:36:55.869+01:00 [info    ] running                        [step save_markdown] block=storage.write attempt=1
2026-11-03T14:36:55.888+01:00 [info    ] wrote                          [log save_markdown] uri=org-units.md bytes_written=655 content_type=text/markdown
2026-11-03T14:36:55.894+01:00 [info    ] succeeded                      [step save_markdown] block=storage.write attempt=1 duration_ms=25
2026-11-03T14:36:55.910+01:00 [info    ] wrote                          [log save_html] uri=org-units.html bytes_written=1647 content_type=text/html
2026-11-03T14:36:55.929+01:00 [info    ] the page is at file:///tmp/dirigent-local-f88ul9bj/artifacts/runs/01a1a1a0-8395-7213-9ae9-42ee2968fd55/org-units.md (655 bytes) and file:///tmp/dirigent-local-f88ul9bj/artifacts/runs/01a1a1a0-8395-7213-9ae9-42ee2968fd55/org-units.html (1647 bytes) [log say]
2026-11-03T14:36:55.911+01:00 [info    ] succeeded                      [step save_html] block=storage.write attempt=1 duration_ms=74
2026-11-03T14:36:55.911+01:00 [info    ] queued                         [step say] block=log.write attempt=1
2026-11-03T14:36:55.915+01:00 [info    ] running                        [step say] block=log.write attempt=1
2026-11-03T14:36:55.929+01:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=14
2026-11-03T14:36:56.130+01:00 [info    ] succeeded                      [run] pipeline=org-units-to-markdown run_id=01a1a1a0-8395-7213-9ae9-42ee2968fd55 exit_code=0
steps
┏━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━┓
┃ step          ┃ block           ┃ outcome   ┃ after              ┃ duration ┃ output             ┃
┡━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━┩
│ parent        │ dhis2.metadata  │ succeeded │ -                  │ 2.0s     │ rows=[1 items]     │
│               │                 │           │                    │          │ duration_ms=2007   │
│ read          │ dhis2.metadata  │ succeeded │ -                  │ 2.0s     │ rows=[13 items]    │
│               │                 │           │                    │          │ duration_ms=1980   │
│ check         │ validate.schema │ succeeded │ read               │ 0.0s     │ value=[13 items]   │
│ html          │ report.render   │ succeeded │ parent, check      │ 0.0s     │ text=<1647 chars>  │
│               │                 │           │                    │          │ content_type=text… │
│               │                 │           │                    │          │ text_bytes=1647    │
│ markdown      │ report.render   │ succeeded │ parent, check      │ 0.0s     │ text=<655 chars>   │
│               │                 │           │                    │          │ content_type=text… │
│               │                 │           │                    │          │ text_bytes=655     │
│ save_html     │ storage.write   │ succeeded │ html               │ 0.1s     │ uri=org-units.html │
│               │                 │           │                    │          │ bytes_written=1647 │
│               │                 │           │                    │          │ content_type=text… │
│ save_markdown │ storage.write   │ succeeded │ markdown           │ 0.0s     │ uri=org-units.md   │
│               │                 │           │                    │          │ bytes_written=655  │
│               │                 │           │                    │          │ content_type=text… │
│ say           │ log.write       │ succeeded │ save_markdown,     │ 0.0s     │ -                  │
│               │                 │           │ save_html          │          │                    │
└───────────────┴─────────────────┴───────────┴────────────────────┴──────────┴────────────────────┘
```

655 bytes rendered and 655 bytes written, 1647 and 1647: `report.render` says how much text
it built and `storage.write` says how much it put out, and the two agreeing is the whole of
what a write can promise. The two renderings ran in either order, because neither waits on the
other; the log is interleaved for the same reason.

`uv run dg run --local pipelines/org-units-to-pdf.yaml ... --enable-unsafe docker.run`, from
`save_markdown` on:

```text
2026-11-03T14:37:01.137+01:00 [info    ] wrote                          [log save_markdown] uri=org-units.md bytes_written=655 content_type=text/markdown
2026-11-03T14:37:01.138+01:00 [info    ] succeeded                      [step save_markdown] block=storage.write attempt=1 duration_ms=23
2026-11-03T14:37:01.235+01:00 [info    ] running                        [step pdf] block=docker.run attempt=1
2026-11-03T14:37:01.235+01:00 [info    ] waiting                        [step pdf] block=docker.run attempt=1
2026-11-03T14:37:02.517+01:00 [info    ] container started              [log pdf] container_id=20cd6a0c31b8 image=pandoc/typst:3.11-alpine network=none
2026-11-03T14:37:01.235+01:00 [info    ] running                        [step pdf] block=docker.run attempt=1
2026-11-03T14:37:03.576+01:00 [info    ] output collected               [log pdf] name=page uri=org-units.pdf bytes_written=37267
2026-11-03T14:37:03.600+01:00 [info    ] container finished             [log pdf] container_id=20cd6a0c31b8 exit_code=0 stdout_bytes=0 stderr_bytes=0
2026-11-03T14:37:03.610+01:00 [info    ] succeeded                      [step pdf] block=docker.run attempt=1 duration_ms=2375
2026-11-03T14:37:03.621+01:00 [info    ] running                        [step say] block=log.write attempt=1
2026-11-03T14:37:03.636+01:00 [info    ] the page is at file:///tmp/dirigent-local-_fwmirxe/artifacts/runs/01a1a1a0-98cd-712f-8daa-dbfb65a398eb/org-units.md (655 bytes), file:///tmp/dirigent-local-_fwmirxe/artifacts/runs/01a1a1a0-98cd-712f-8daa-dbfb65a398eb/org-units.html (1647 bytes) and file:///tmp/dirigent-local-_fwmirxe/artifacts/runs/01a1a1a0-98cd-712f-8daa-dbfb65a398eb/org-units.pdf [log say]
2026-11-03T14:37:03.636+01:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=14
2026-11-03T14:37:03.726+01:00 [info    ] succeeded                      [run] pipeline=org-units-to-pdf run_id=01a1a1a0-98cd-712f-8daa-dbfb65a398eb exit_code=0
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
2026-11-03T14:37:07.417+01:00 [info    ] created                        [connection.created] code=play connection_kind=dhis2 name="DHIS2 play demo" config={"base_url":"https://play.dhis2.org/2.42","api_token":null,"basic_username":"admin","verify_tls":true,"follow_redirects_with_auth":true,"timeout":"30s","request_deadline":"10m","max_response":"64mb","basic_password":"***"}
```

The password is already withheld in the record the command answers with, and in every read
after it.

`uv run dg connection check play`:

```text
2026-11-03T14:37:10.626+01:00 [info    ] healthy                        [connection.checked] code=play healthy=true version=2.42.7.1
```

One line, four facts: the URL resolves, TLS is as configured, the credential is accepted, and
the instance's version is **2.42.7.1** -- its own word for itself, read from `/api/system/info`
rather than guessed from an `/api/N` path.

`uv run dg apply`:

```text
create org-units-to-markdown  version 1 (/home/you/dhis2-org-units-to-markdown/pipelines/org-units-to-markdown.yaml)
create org-units-to-pdf  version 1 (/home/you/dhis2-org-units-to-markdown/pipelines/org-units-to-pdf.yaml)
```

`uv run dg run org-units-to-markdown --watch`:

```text
2026-11-03T14:37:14.378+01:00 [info    ] started                        [run] pipeline=org-units-to-markdown run_id=01a1a1a0-d482-72a6-9258-c769c047e7a4 local=false
2026-11-03T14:37:14.376+01:00 [info    ] running                        [step parent] block=dhis2.metadata attempt=1
2026-11-03T14:37:14.391+01:00 [info    ] running                        [step read] block=dhis2.metadata attempt=1
2026-11-03T14:37:15.387+01:00 [info    ] metadata read                  [log parent] resource=organisationUnits rows=1 duration_ms=997
2026-11-03T14:37:15.389+01:00 [info    ] succeeded                      [step parent] block=dhis2.metadata attempt=1 duration_ms=1012
2026-11-03T14:37:14.373+01:00 [info    ] queued                         [step check] block=validate.schema attempt=1
2026-11-03T14:37:15.406+01:00 [info    ] metadata read                  [log read] resource=organisationUnits rows=13 duration_ms=1009
2026-11-03T14:37:15.408+01:00 [info    ] succeeded                      [step read] block=dhis2.metadata attempt=1 duration_ms=1016
2026-11-03T14:37:15.411+01:00 [info    ] running                        [step check] block=validate.schema attempt=1
2026-11-03T14:37:14.373+01:00 [info    ] queued                         [step html] block=report.render attempt=1
2026-11-03T14:37:14.373+01:00 [info    ] queued                         [step markdown] block=report.render attempt=1
2026-11-03T14:37:15.422+01:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=11
2026-11-03T14:37:15.447+01:00 [info    ] finished                       [log check] duration_ms=1 output_bytes=880
2026-11-03T14:37:15.449+01:00 [info    ] running                        [step html] block=report.render attempt=1
2026-11-03T14:37:14.373+01:00 [info    ] queued                         [step save_html] block=storage.write attempt=1
2026-11-03T14:37:15.470+01:00 [info    ] rendered                       [log html] content_type=text/html text_bytes=1647
2026-11-03T14:37:15.470+01:00 [info    ] succeeded                      [step html] block=report.render attempt=1 duration_ms=21
2026-11-03T14:37:15.470+01:00 [info    ] running                        [step markdown] block=report.render attempt=1
2026-11-03T14:37:15.493+01:00 [info    ] running                        [step save_html] block=storage.write attempt=1
2026-11-03T14:37:15.517+01:00 [info    ] wrote                          [log save_html] uri=file://./.dirigent/state/artifacts/runs/01a1a1a0-d482-72a6-9258-c769c047e7a4/org-units.html bytes_written=1647 content_type=text/html
2026-11-03T14:37:15.518+01:00 [info    ] succeeded                      [step save_html] block=storage.write attempt=1 duration_ms=25
2026-11-03T14:37:14.373+01:00 [info    ] queued                         [step save_markdown] block=storage.write attempt=1
2026-11-03T14:37:15.493+01:00 [info    ] rendered                       [log markdown] content_type=text/markdown text_bytes=655
2026-11-03T14:37:15.493+01:00 [info    ] succeeded                      [step markdown] block=report.render attempt=1 duration_ms=23
2026-11-03T14:37:15.511+01:00 [info    ] running                        [step save_markdown] block=storage.write attempt=1
2026-11-03T14:37:14.373+01:00 [info    ] queued                         [step say] block=log.write attempt=1
2026-11-03T14:37:15.596+01:00 [info    ] wrote                          [log save_markdown] uri=file://./.dirigent/state/artifacts/runs/01a1a1a0-d482-72a6-9258-c769c047e7a4/org-units.md bytes_written=655 content_type=text/markdown
2026-11-03T14:37:15.596+01:00 [info    ] succeeded                      [step save_markdown] block=storage.write attempt=1 duration_ms=85
2026-11-03T14:37:15.600+01:00 [info    ] running                        [step say] block=log.write attempt=1
2026-11-03T14:37:15.610+01:00 [info    ] the page is at file://./.dirigent/state/artifacts/runs/01a1a1a0-d482-72a6-9258-c769c047e7a4/org-units.md (655 bytes) and file://./.dirigent/state/artifacts/runs/01a1a1a0-d482-72a6-9258-c769c047e7a4/org-units.html (1647 bytes) [log say]
2026-11-03T14:37:15.611+01:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=10
2026-11-03T14:37:15.678+01:00 [info    ] succeeded                      [run] pipeline=org-units-to-markdown run_id=01a1a1a0-d482-72a6-9258-c769c047e7a4 pipeline_version=1 triggered_by="admin (token dev)" duration_ms=1234 items_total=0 items_failed=0 exit_code=0 priority=normal
run 01a1a1a0-d482-72a6-9258-c769c047e7a4
pipeline      org-units-to-markdown (version 1)
status        succeeded
triggered by  admin (token dev)
duration      1.2s
items         -

steps
┏━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━┓
┃ step          ┃ block           ┃ outcome   ┃ after                ┃ attempts ┃ duration ┃ error ┃
┡━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━┩
│ parent        │ dhis2.metadata  │ succeeded │ -                    │ 1        │ 1.0s     │ -     │
│ read          │ dhis2.metadata  │ succeeded │ -                    │ 1        │ 1.0s     │ -     │
│ check         │ validate.schema │ succeeded │ read                 │ 1        │ 0.0s     │ -     │
│ html          │ report.render   │ succeeded │ parent, check        │ 1        │ 0.0s     │ -     │
│ markdown      │ report.render   │ succeeded │ parent, check        │ 1        │ 0.0s     │ -     │
│ save_html     │ storage.write   │ succeeded │ html                 │ 1        │ 0.0s     │ -     │
│ save_markdown │ storage.write   │ succeeded │ markdown             │ 1        │ 0.1s     │ -     │
│ say           │ log.write       │ succeeded │ save_markdown,       │ 1        │ 0.0s     │ -     │
│               │                 │           │ save_html            │          │          │       │
└───────────────┴─────────────────┴───────────┴──────────────────────┴──────────┴──────────┴───────┘

outputs
┏━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step          ┃ output                                                                           ┃
┡━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ parent        │ rows=[1 items]  duration_ms=997                                                  │
│ read          │ rows=[13 items]  duration_ms=1009                                                │
│ check         │ value=[13 items]                                                                 │
│ html          │ text=<1647 chars>  content_type=text/html  text_bytes=1647                       │
│ markdown      │ text=<655 chars>  content_type=text/markdown  text_bytes=655                     │
│ save_html     │ uri=file://./.dirigent/state/artifacts/runs/01a1a1a0-d482-72a6-9258-c769c047e7a… │
│               │ bytes_written=1647  content_type=text/html                                       │
│ save_markdown │ uri=file://./.dirigent/state/artifacts/runs/01a1a1a0-d482-72a6-9258-c769c047e7a… │
│               │ bytes_written=655  content_type=text/markdown                                    │
│ say           │ -                                                                                │
└───────────────┴──────────────────────────────────────────────────────────────────────────────────┘
```

Same document, same eight hops, and the only difference is where the files landed: on the
instance `${run.scratch}` is this run's own directory under the artifact root rather than a
temporary one that is about to be deleted.

`uv run dg run org-units-to-pdf --watch`, the ninth hop and the summary:

```text
run 01a1a1a0-df6a-72a6-8d70-cd3815c0d0ee
pipeline      org-units-to-pdf (version 1)
status        succeeded
triggered by  admin (token dev)
duration      3.7s
items         -

steps
┏━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━┓
┃ step          ┃ block           ┃ outcome   ┃ after                ┃ attempts ┃ duration ┃ error ┃
┡━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━┩
│ parent        │ dhis2.metadata  │ succeeded │ -                    │ 1        │ 0.8s     │ -     │
│ read          │ dhis2.metadata  │ succeeded │ -                    │ 1        │ 0.9s     │ -     │
│ check         │ validate.schema │ succeeded │ read                 │ 1        │ 0.0s     │ -     │
│ html          │ report.render   │ succeeded │ parent, check        │ 1        │ 0.0s     │ -     │
│ markdown      │ report.render   │ succeeded │ parent, check        │ 1        │ 0.0s     │ -     │
│ save_markdown │ storage.write   │ succeeded │ markdown             │ 1        │ 0.0s     │ -     │
│ pdf           │ docker.run      │ succeeded │ save_markdown        │ 1        │ 2.7s     │ -     │
│ save_html     │ storage.write   │ succeeded │ html                 │ 1        │ 0.0s     │ -     │
│ say           │ log.write       │ succeeded │ save_markdown,       │ 1        │ 0.0s     │ -     │
│               │                 │           │ save_html, pdf       │          │          │       │
└───────────────┴─────────────────┴───────────┴──────────────────────┴──────────┴──────────┴───────┘

outputs
┏━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step          ┃ output                                                                           ┃
┡━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ parent        │ rows=[1 items]  duration_ms=835                                                  │
│ read          │ rows=[13 items]  duration_ms=849                                                 │
│ check         │ value=[13 items]                                                                 │
│ html          │ text=<1647 chars>  content_type=text/html  text_bytes=1647                       │
│ markdown      │ text=<655 chars>  content_type=text/markdown  text_bytes=655                     │
│ save_markdown │ uri=file://./.dirigent/state/artifacts/runs/01a1a1a0-df6a-72a6-8d70-cd3815c0d0e… │
│               │ bytes_written=655  content_type=text/markdown                                    │
│ pdf           │ exit_code=0                                                                      │
│               │ stdout_uri=file://./.dirigent/state/artifacts/runs/01a1a1a0-df6a-72a6-8d70-cd38… │
│               │ stderr_uri=file://./.dirigent/state/artifacts/runs/01a1a1a0-df6a-72a6-8d70-cd38… │
│               │ stdout_bytes=0  stderr_bytes=0  stdout_truncated=false  stderr_truncated=false   │
│               │ container_id=<64 chars>  image=pandoc/typst:3.11-alpine  outputs={1 keys}        │
│ save_html     │ uri=file://./.dirigent/state/artifacts/runs/01a1a1a0-df6a-72a6-8d70-cd3815c0d0e… │
│               │ bytes_written=1647  content_type=text/html                                       │
│ say           │ -                                                                                │
└───────────────┴──────────────────────────────────────────────────────────────────────────────────┘
```

The container is 2.7 of the run's 3.7 seconds, and 1.4 of those 2.7 are the daemon starting
it. A PDF is not slow; a container is not free.

The markdown, as `dg runs show` hands it back:

```bash
uv run dg runs show 01a1a1a0-d482-72a6-9258-c769c047e7a4 --json \
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

The same text is the run's report, because the document ends `report: {from: markdown}`, so
`uv run dg runs report <run id> --markdown` prints exactly this page and the run's Report tab
in the UI draws it.

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
  "uri": "file://./.dirigent/state/artifacts/runs/01a1a1a0-d482-72a6-9258-c769c047e7a4/org-units.md",
  "bytes_written": 655,
  "content_type": "text/markdown"
}
```

```json
{
  "page": "file://./.dirigent/state/artifacts/runs/01a1a1a0-df6a-72a6-8d70-cd3815c0d0ee/org-units.pdf"
}
```

`uv run dg run --local pipelines/org-units-to-markdown.yaml ... -p parent=nope`:

```text
2026-11-03T14:34:38.668+01:00 [error   ] parameter parent is invalid: 'nope' is not a 'dhis2-uid' [error] status=3 title=Refused code=cli.guard_refused params={"detail":"parameter parent is invalid: 'nope' is not a 'dhis2-uid'"}
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
      input: ${steps.read.output.rows}
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
        parent: ${steps.parent.output.rows.0.name}
        units: ${steps.check.output.value}
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
        parent: ${steps.parent.output.rows.0.name}
        units: ${steps.check.output.value}
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

And the last line makes the markdown page the run's own report. A run has one report, the
document the Report tab draws and `dg runs report RUN --markdown` prints, and `from:` names the
step whose `text` it is, so the page is rendered once and is both the file and the report. A
`report.render` step that nothing names is only a step's output: `dg validate` warns about one,
and naming `markdown` here is what keeps `html` from being warned about too, because a run with
a report has said where its report is.

```yaml
report:
  from: markdown
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
  "description": "The rows of an organisationUnits read projected to id, code, name and level: one object per row of the page's table, with every identifier held to the pack's own dhis2-uid format and every code, where one is set, to dhis2-code. A code is DHIS2's optional alternate identifier, so a unit without one still makes a row.",
  "type": "array",
  "minItems": 1,
  "items": {
    "type": "object",
    "required": ["id", "name", "level"],
    "properties": {
      "id": { "type": "string", "format": "dhis2-uid" },
      "code": { "type": "string", "format": "dhis2-code" },
      "name": { "type": "string", "minLength": 1 },
      "level": { "type": "integer", "minimum": 1 }
    },
    "additionalProperties": false
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

- [**Docker**](https://winterop-com.github.io/dirigent/docker/) is the family the ninth hop
  belongs to: one container, a whole compose stack, an image built and pushed, and how a
  worker reaches a daemon it is allowed to reach.
- [**The DHIS2 tutorial**](https://winterop-com.github.io/dirigent-dhis2/tutorial/) builds a
  read, a gate and a rehearsed write one section at a time, with the failures shown.
- [**The examples**](../README.md): every example in order, and what you need once.
