# dhis2-org-unit-sync

An organisation-unit sync, in all three directions it is ever asked for: **DHIS2 to DHIS2**,
**DHIS2 to a system that is not DHIS2**, and **that system back into DHIS2**. The hierarchy is
the spine every other DHIS2 payload hangs off -- a data value names an `orgUnit`, an enrollment
names an `orgUnit` -- so keeping two systems agreeing about it is the first integration anybody
builds and the one that keeps breaking. The shape matters because of what a sync actually is: a
read you do not control, a shape you decide, and a write to somewhere that can refuse you. Each
of the three documents here is those three moves, and the interesting part is always the same
one -- the reshape in the middle, where one system's vocabulary is turned into another's in
public, where a reviewer can read it.

The two `dhis2` connections are the other half. A sync names two instances by code and never a
URL, which is what lets the same document rehearse against a demo today and move production
metadata tomorrow with nothing edited but a connection row.

Everything below was run against two public DHIS2 demos: the source is
`https://play.im.dhis2.org/dev`, version **2.44** (a development build), and the target is
`https://play.dhis2.org/2.42`, the newest 2.42 demo (**2.42.7.1** when this was written), both with the published
`admin` / `district` credential.

**Both of them are the Sierra Leone demo database.** That makes this sync a rehearsal by
construction: every unit the source hands over already exists on the target, so the import
report says *updated* and never *created*, and the interesting failure -- a unit arriving
before its parent -- has to be asked for on purpose. It also means nothing here may ever be
committed. `importMode=VALIDATE` is a parameter with a default, the default is `VALIDATE`, and
a real sync is the one that sets `COMMIT` against an instance it owns. Never against these.

## Run it

`.dirigent/state/` and `.env` are not in the repository: one is this instance's own database
and its artifacts, disposable, the other its token, and a clone makes its own of each.
`.dirigent/profiles.yaml` beside them is committed, because it is addressing rather than
state -- which server, and how to get a token for it -- and so is the `.dirigent/.gitignore`
that keeps the state directory out. Everything else here is committed too.

```bash
uv sync
```

The fast loop first, with no server anywhere. `--local` applies and runs a document in a
throwaway instance in a temporary directory and deletes it on the way out, so it is handed the
connections and the schemas the document names:

```bash
uv run dg validate

uv run dg run --local pipelines/dhis2-to-dhis2.yaml \
  --connections connections.yaml \
  --schema schemas/org-unit-sync-source.json \
  --schema schemas/org-unit-sync-import.json \
  --schema schemas/org-unit-sync-verdict.json
```

The same three `--schema` flags run the other two documents, so they are worth a shell
variable. `pipelines/other-to-dhis2.yaml` needs nothing further: the register it reads is a
`playground.generate` node carrying this document's own rows, so it reaches only the target
demo. `pipelines/dhis2-to-other.yaml` posts to a system that is not DHIS2, and the stand-in
for that system is the **playground** an instance serves itself under `/api/v1/playground` --
so `dg dev` has to be running before it, even for a local run, because a local run mounts no
API of its own:

```bash
uv run dg run --local pipelines/dhis2-to-other.yaml \
  --connections connections.yaml \
  --schema schemas/org-unit-sync-source.json \
  --schema schemas/org-unit-sync-import.json \
  --schema schemas/org-unit-sync-verdict.json \
  -p playground=http://127.0.0.1:3333/api/v1/playground
```

Then the instance. A DHIS2 connection carries a password, and a connection secret is encrypted
at rest with the instance's own key, so the instance needs a key before it can hold one. Mint it
once into `.env` -- the gitignored file beside the state that already holds this instance's
token -- and every command run in this directory reads it from there, which is what keeps this
instance on the key it sealed with: one that changes its key cannot open the secrets it already
stored. In a second terminal, in this directory:

```bash
grep -q '^DIRIGENT_SECRET_KEY=' .env 2>/dev/null \
  || printf 'DIRIGENT_SECRET_KEY=%s\n' "$(uv run dg secret-key)" >> .env
uv run dg dev
```

`dg dev` is one process holding the API, the web UI, the scheduler, one worker and a SQLite
file under `.dirigent/state/`. It keeps running; leave it. On an empty state -- which is what a
fresh clone has, because the state directory is not in the repository -- it migrates the schema,
makes its own admin `admin`, mints that admin one token, and prints the `export DG_TOKEN=` line to
paste. The UI is at `http://127.0.0.1:3333`, which is the address the `local` profile in
`.dirigent/profiles.yaml` holds; `dg dev --port` moves the instance and `DG_URL` is how you tell
the CLI where it went.

Back in the first terminal, mint a token for that admin, whose password is `admin`. The
command answers with the `export DG_TOKEN=` line to paste into this terminal, and that line is
the one output this page does not print, because it is a credential:

```bash
uv run dg auth login --username admin --password admin
```

```text
  export DG_TOKEN=<the token>

This is the only time the token is shown.
```

The instance holds the shapes and the credentials; the documents name both by code and carry
neither, which is why they apply unchanged anywhere. All five have to exist before the
documents do, because `dg apply` refuses a document whose `requires` this instance cannot
satisfy:

```bash
uv run dg schema create schemas/org-unit-sync-source.json
uv run dg schema create schemas/org-unit-sync-import.json
uv run dg schema create schemas/org-unit-sync-verdict.json

uv run dg connection create dhis2 source \
  --name "DHIS2 play demo, the source" \
  --set base_url=https://play.im.dhis2.org/dev \
  --set basic_username=admin \
  --set basic_password=district
uv run dg connection create dhis2 target \
  --name "DHIS2 play demo, the target" \
  --set base_url=https://play.dhis2.org/2.42 \
  --set follow_redirects_with_auth=true \
  --set basic_username=admin \
  --set basic_password=district

uv run dg connection check source
uv run dg connection check target
uv run dg apply

uv run dg run dhis2-to-dhis2 --watch
uv run dg run dhis2-to-other --watch
uv run dg run other-to-dhis2 --watch
```

`dg connection create` asks for a credential only when the command gave none. A `dhis2`
connection takes an `api_token` or a `basic_username` and `basic_password`, never both; each of
those two names the basic pair with `--set`, so both complete without a prompt and leave
`api_token` unset.

The import report is in the run rather than on the screen, and every command writes records
into a pipe, so the whole of it is one `jq` away:

```bash
uv run dg runs show <run id> --json \
  | jq '.fields.attempts[] | select(.step_name == "report") | .output.value'
uv run dg runs show <run id> --json \
  | jq '.fields.attempts[] | select(.step_name == "mode") | .output.value'
```

A parameter is a JSON Schema too, and `format: dhis2-uid` is this pack's, so a run submitted
with something that is not a DHIS2 uid is refused before a single call is made:

```bash
uv run dg run dhis2-to-dhis2 --watch -p parent=ImspTQPwCq
```

And the failure worth seeing on purpose, which is safe because it is a rehearsal:

```bash
uv run dg run other-to-dhis2 --watch -p parent_code=OU_NOT_THERE
```

`./verify.sh` does all of it unattended -- validate, an instance on a free port of its own,
three local runs, the refusal above, the three schemas, both connections, the apply and the
three runs -- and asserts on the records rather than on anything rendered. It starts the
instance before the local runs, because that instance is what `dhis2-to-other` posts to. It
keeps the key on that same `.env` line, and writes the schemas and the connections only when
the instance does not already hold them, so its second run inherits the state its first run
left. It stops the instance it started by pid on the way out. Both DHIS2 demos are on the
internet and have no stand-in, so this needs the network either way.

### If the key was lost

A connection is sealed with the key the instance held when it was written, so a state left over
from a key that is gone answers `uv run dg connection check source` with a record whose `detail`
begins `SecretKeyMismatch`. Nothing opens that row again, and the secret it holds is not
recoverable. Nor can it be deleted once a pipeline names it: `dg connection delete` names the
pipeline and refuses. So write each one that answers that way once more, in place, under the
key this instance has now. `dg connection ensure` writes the row straight to this instance's
database, reading `.env` for the key rather than a token, and brings it whole to what the
arguments say:

```bash
uv run dg connection ensure dhis2 source \
  --name "DHIS2 play demo, the source" \
  --set base_url=https://play.im.dhis2.org/dev \
  --set basic_username=admin \
  --set basic_password=district
```

`verify.sh` does exactly that, for each connection whose check reports that class.

## What you see

*Printed as it printed, with this project's directory written as
`/home/you/dhis2-org-unit-sync` and a local run's temporary root as `/tmp`.*

`uv run dg validate`, with no argument, which is the project's own documents:

```text
2026-11-03T14:30:47.267+01:00 [info    ] valid                          [validation] code=dhis2-to-dhis2 document=/home/you/dhis2-org-unit-sync/pipelines/dhis2-to-dhis2.yaml checked="document and installed blocks"
  each step under the last one it waits for
    read  (dhis2.metadata)
      check  (validate.schema)
        shape  (transform.jq)
          send  (http.request)  also after mode
            report  (transform.jq)
              say  (log.write)
                verdict  (validate.schema)
    mode  (value.const)
2026-11-03T14:30:47.304+01:00 [info    ] valid                          [validation] code=dhis2-to-other document=/home/you/dhis2-org-unit-sync/pipelines/dhis2-to-other.yaml checked="document and installed blocks"
  each step under the last one it waits for
    read  (dhis2.metadata)
      check  (validate.schema)
        records  (map.jq)
          batch  (transform.jq)
            send  (http.request)
              say  (log.write)
2026-11-03T14:30:47.316+01:00 [info    ] valid                          [validation] code=other-to-dhis2 document=/home/you/dhis2-org-unit-sync/pipelines/other-to-dhis2.yaml checked="document and installed blocks"
  each step under the last one it waits for
    fetch  (playground.generate)
      shape  (transform.jq)
        check  (validate.schema)
          send  (http.request)  also after mode
            report  (transform.jq)
              say  (log.write)
                verdict  (validate.schema)
    mode  (value.const)
2026-11-03T14:30:47.317+01:00 [info    ] valid                          [validated] documents=3 invalid=0 skipped=0
```

Nothing has run and nothing has been contacted: those trees are the graphs the documents
already hold, each step under the last one it waits for. `mode` hangs off nothing in two of
them, because a constant waits for no one, and `also after mode` is the second edge `send`
carries.

### The three documents, run locally

`uv run dg run --local pipelines/dhis2-to-dhis2.yaml ...`:

```text
2026-11-03T14:30:52.238+01:00 [info    ] started                        [run] pipeline=dhis2-to-dhis2 run_id=01a1a19a-ffc1-73d6-86a0-304b651980a6 local=true scratch=file:///tmp/dirigent-local-tm9hj0jr/artifacts/runs/01a1a19a-ffc1-73d6-86a0-304b651980a6 root=/tmp/dirigent-local-tm9hj0jr
2026-11-03T14:30:51.902+01:00 [info    ] queued                         [step read] block=dhis2.metadata attempt=1
2026-11-03T14:30:51.902+01:00 [info    ] queued                         [step mode] block=value.const attempt=1
2026-11-03T14:30:52.443+01:00 [info    ] running                        [step mode] block=value.const attempt=1
2026-11-03T14:30:52.570+01:00 [info    ] succeeded                      [step mode] block=value.const attempt=1 duration_ms=127
2026-11-03T14:30:52.571+01:00 [info    ] running                        [step read] block=dhis2.metadata attempt=1
2026-11-03T14:30:52.584+01:00 [info    ] finished                       [log mode] duration_ms=2 output_bytes=110
2026-11-03T14:30:56.136+01:00 [info    ] metadata read                  [log read] resource=organisationUnits rows=15 duration_ms=3468
2026-11-03T14:30:56.140+01:00 [info    ] succeeded                      [step read] block=dhis2.metadata attempt=1 duration_ms=3569
2026-11-03T14:30:56.140+01:00 [info    ] queued                         [step check] block=validate.schema attempt=1
2026-11-03T14:30:56.146+01:00 [info    ] running                        [step check] block=validate.schema attempt=1
2026-11-03T14:30:56.178+01:00 [info    ] finished                       [log check] duration_ms=2 output_bytes=2587
2026-11-03T14:30:56.166+01:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=19
2026-11-03T14:30:56.166+01:00 [info    ] queued                         [step shape] block=transform.jq attempt=1
2026-11-03T14:30:56.212+01:00 [info    ] running                        [step shape] block=transform.jq attempt=1
2026-11-03T14:30:56.320+01:00 [info    ] succeeded                      [step shape] block=transform.jq attempt=1 duration_ms=108
2026-11-03T14:30:56.320+01:00 [info    ] queued                         [step send] block=http.request attempt=1
2026-11-03T14:30:56.325+01:00 [info    ] finished                       [log shape] duration_ms=70 output_bytes=2219
2026-11-03T14:30:56.331+01:00 [info    ] running                        [step send] block=http.request attempt=1
2026-11-03T14:30:56.981+01:00 [info    ] http call                      [log send] method=POST url=/api/metadata status=200 bytes=346 duration_ms=616
2026-11-03T14:30:56.983+01:00 [info    ] succeeded                      [step send] block=http.request attempt=1 duration_ms=651
2026-11-03T14:30:56.983+01:00 [info    ] queued                         [step report] block=transform.jq attempt=1
2026-11-03T14:30:56.987+01:00 [info    ] running                        [step report] block=transform.jq attempt=1
2026-11-03T14:30:57.007+01:00 [info    ] succeeded                      [step report] block=transform.jq attempt=1 duration_ms=20
2026-11-03T14:30:57.007+01:00 [info    ] queued                         [step say] block=log.write attempt=1
2026-11-03T14:30:57.011+01:00 [info    ] finished                       [log report] duration_ms=5 output_bytes=136
2026-11-03T14:30:57.050+01:00 [info    ] running                        [step say] block=log.write attempt=1
2026-11-03T14:30:57.089+01:00 [info    ] VALIDATE on the target: OK, 0 created, 15 updated, 0 ignored, of 15 units -- no conflicts [log say]
2026-11-03T14:30:57.165+01:00 [info    ] finished                       [log verdict] duration_ms=2 output_bytes=136
2026-11-03T14:30:57.089+01:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=39
2026-11-03T14:30:57.089+01:00 [info    ] queued                         [step verdict] block=validate.schema attempt=1
2026-11-03T14:30:57.089+01:00 [info    ] running                        [step verdict] block=validate.schema attempt=1
2026-11-03T14:30:57.159+01:00 [info    ] succeeded                      [step verdict] block=validate.schema attempt=1 duration_ms=70
2026-11-03T14:30:57.434+01:00 [info    ] succeeded                      [run] pipeline=dhis2-to-dhis2 run_id=01a1a19a-ffc1-73d6-86a0-304b651980a6 exit_code=0
steps
┏━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step    ┃ block           ┃ outcome   ┃ after       ┃ duration ┃ output                          ┃
┡━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ mode    │ value.const     │ succeeded │ -           │ 0.1s     │ value={4 keys}                  │
│ read    │ dhis2.metadata  │ succeeded │ -           │ 3.6s     │ rows=[15 items]                 │
│         │                 │           │             │          │ duration_ms=3468                │
│ check   │ validate.schema │ succeeded │ read        │ 0.0s     │ value=[15 items]                │
│ shape   │ transform.jq    │ succeeded │ check       │ 0.1s     │ value={1 keys}                  │
│ send    │ http.request    │ succeeded │ shape, mode │ 0.7s     │ status=200  headers={9 keys}    │
│         │                 │           │             │          │ body={4 keys}  body_bytes=346   │
│         │                 │           │             │          │ duration_ms=616                 │
│ report  │ transform.jq    │ succeeded │ send        │ 0.0s     │ value={9 keys}                  │
│ say     │ log.write       │ succeeded │ report      │ 0.0s     │ -                               │
│ verdict │ validate.schema │ succeeded │ say         │ 0.1s     │ value={9 keys}                  │
└─────────┴─────────────────┴───────────┴─────────────┴──────────┴─────────────────────────────────┘
```

Fifteen chiefdoms under Bo, read off 2.44 and offered to 2.42.7.1, which says it would revise
all fifteen and writes nothing. `updated=15` rather than `created=15` is the two demos being
the same database: this is a rehearsal of a sync that has already happened.

`uv run dg run --local pipelines/dhis2-to-other.yaml ...`:

```text
2026-11-03T14:31:01.212+01:00 [info    ] started                        [run] pipeline=dhis2-to-other run_id=01a1a19b-22d4-7324-9753-25e0bde8043c local=true scratch=file:///tmp/dirigent-local-97xqllsb/artifacts/runs/01a1a19b-22d4-7324-9753-25e0bde8043c root=/tmp/dirigent-local-97xqllsb
2026-11-03T14:31:00.936+01:00 [info    ] queued                         [step read] block=dhis2.metadata attempt=1
2026-11-03T14:31:01.294+01:00 [info    ] running                        [step read] block=dhis2.metadata attempt=1
2026-11-03T14:31:03.958+01:00 [info    ] metadata read                  [log read] resource=organisationUnits rows=15 duration_ms=2639
2026-11-03T14:31:04.086+01:00 [info    ] finished                       [log check] duration_ms=7 output_bytes=2587
2026-11-03T14:31:04.252+01:00 [info    ] finished                       [log records] duration_ms=102 output_bytes=1209
2026-11-03T14:31:04.329+01:00 [info    ] finished                       [log batch] duration_ms=8 output_bytes=1262
2026-11-03T14:31:04.392+01:00 [info    ] http call                      [log send] method=POST url=http://127.0.0.1:3333/api/v1/playground/request status=200 bytes=1722 duration_ms=21
2026-11-03T14:31:04.423+01:00 [info    ] the register took 15 facilities from dhis2-play-dev, first OU_539 under OU_264 [log say]
2026-11-03T14:31:03.970+01:00 [info    ] succeeded                      [step read] block=dhis2.metadata attempt=1 duration_ms=2676
2026-11-03T14:31:03.970+01:00 [info    ] queued                         [step check] block=validate.schema attempt=1
2026-11-03T14:31:03.985+01:00 [info    ] running                        [step check] block=validate.schema attempt=1
2026-11-03T14:31:04.064+01:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=79
2026-11-03T14:31:04.064+01:00 [info    ] queued                         [step records] block=map.jq attempt=1
2026-11-03T14:31:04.093+01:00 [info    ] running                        [step records] block=map.jq attempt=1
2026-11-03T14:31:04.236+01:00 [info    ] succeeded                      [step records] block=map.jq attempt=1 duration_ms=143
2026-11-03T14:31:04.236+01:00 [info    ] queued                         [step batch] block=transform.jq attempt=1
2026-11-03T14:31:04.256+01:00 [info    ] running                        [step batch] block=transform.jq attempt=1
2026-11-03T14:31:04.310+01:00 [info    ] succeeded                      [step batch] block=transform.jq attempt=1 duration_ms=54
2026-11-03T14:31:04.310+01:00 [info    ] queued                         [step send] block=http.request attempt=1
2026-11-03T14:31:04.339+01:00 [info    ] running                        [step send] block=http.request attempt=1
2026-11-03T14:31:04.395+01:00 [info    ] succeeded                      [step send] block=http.request attempt=1 duration_ms=56
2026-11-03T14:31:04.395+01:00 [info    ] queued                         [step say] block=log.write attempt=1
2026-11-03T14:31:04.404+01:00 [info    ] running                        [step say] block=log.write attempt=1
2026-11-03T14:31:04.423+01:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=19
2026-11-03T14:31:04.922+01:00 [info    ] succeeded                      [run] pipeline=dhis2-to-other run_id=01a1a19b-22d4-7324-9753-25e0bde8043c exit_code=0
steps
┏━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step    ┃ block           ┃ outcome   ┃ after   ┃ duration ┃ output                              ┃
┡━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ read    │ dhis2.metadata  │ succeeded │ -       │ 2.7s     │ rows=[15 items]  duration_ms=2639   │
│ check   │ validate.schema │ succeeded │ read    │ 0.1s     │ value=[15 items]                    │
│ records │ map.jq          │ succeeded │ check   │ 0.1s     │ value=[15 items]                    │
│ batch   │ transform.jq    │ succeeded │ records │ 0.1s     │ value={3 keys}                      │
│ send    │ http.request    │ succeeded │ batch   │ 0.1s     │ status=200  headers={11 keys}       │
│         │                 │           │         │          │ body={3 keys}  body_bytes=1722      │
│         │                 │           │         │          │ duration_ms=21                      │
│ say     │ log.write       │ succeeded │ send    │ 0.0s     │ -                                   │
└─────────┴─────────────────┴───────────┴─────────┴──────────┴─────────────────────────────────────┘
```

`value=[15 items]` out of `map.jq` and `value={3 keys}` out of `transform.jq` are the two
verbs' contracts on the screen: a map is exactly as long as the list that went in, and a
transform is one program over one whole value.

`uv run dg run --local pipelines/other-to-dhis2.yaml ...`:

```text
2026-11-03T14:31:09.905+01:00 [info    ] started                        [run] pipeline=other-to-dhis2 run_id=01a1a19b-44c4-73e8-b07f-afe4688be8d7 local=true scratch=file:///tmp/dirigent-local-88gwf874/artifacts/runs/01a1a19b-44c4-73e8-b07f-afe4688be8d7 root=/tmp/dirigent-local-88gwf874
2026-11-03T14:31:09.604+01:00 [info    ] queued                         [step fetch] block=playground.generate attempt=1
2026-11-03T14:31:09.604+01:00 [info    ] queued                         [step mode] block=value.const attempt=1
2026-11-03T14:31:10.045+01:00 [info    ] running                        [step fetch] block=playground.generate attempt=1
2026-11-03T14:31:10.087+01:00 [info    ] running                        [step mode] block=value.const attempt=1
2026-11-03T14:31:10.141+01:00 [info    ] finished                       [log mode] duration_ms=0 output_bytes=111
2026-11-03T14:31:10.128+01:00 [info    ] succeeded                      [step mode] block=value.const attempt=1 duration_ms=41
2026-11-03T14:31:10.185+01:00 [info    ] playground generated           [log fetch] rows=1 seed=1447398121 locale=en_US drift=none
2026-11-03T14:31:10.188+01:00 [info    ] succeeded                      [step fetch] block=playground.generate attempt=1 duration_ms=142
2026-11-03T14:31:10.188+01:00 [info    ] queued                         [step shape] block=transform.jq attempt=1
2026-11-03T14:31:10.193+01:00 [info    ] running                        [step shape] block=transform.jq attempt=1
2026-11-03T14:31:10.241+01:00 [info    ] succeeded                      [step shape] block=transform.jq attempt=1 duration_ms=47
2026-11-03T14:31:10.241+01:00 [info    ] queued                         [step check] block=validate.schema attempt=1
2026-11-03T14:31:10.244+01:00 [info    ] finished                       [log shape] duration_ms=35 output_bytes=358
2026-11-03T14:31:10.246+01:00 [info    ] running                        [step check] block=validate.schema attempt=1
2026-11-03T14:31:10.266+01:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=20
2026-11-03T14:31:10.266+01:00 [info    ] queued                         [step send] block=http.request attempt=1
2026-11-03T14:31:10.273+01:00 [info    ] finished                       [log check] duration_ms=2 output_bytes=358
2026-11-03T14:31:10.297+01:00 [info    ] running                        [step send] block=http.request attempt=1
2026-11-03T14:31:10.994+01:00 [info    ] http call                      [log send] method=POST url=/api/metadata status=200 bytes=342 duration_ms=684
2026-11-03T14:31:10.997+01:00 [info    ] succeeded                      [step send] block=http.request attempt=1 duration_ms=700
2026-11-03T14:31:10.997+01:00 [info    ] queued                         [step report] block=transform.jq attempt=1
2026-11-03T14:31:11.006+01:00 [info    ] running                        [step report] block=transform.jq attempt=1
2026-11-03T14:31:11.033+01:00 [info    ] succeeded                      [step report] block=transform.jq attempt=1 duration_ms=28
2026-11-03T14:31:11.033+01:00 [info    ] queued                         [step say] block=log.write attempt=1
2026-11-03T14:31:11.053+01:00 [info    ] finished                       [log report] duration_ms=5 output_bytes=134
2026-11-03T14:31:11.076+01:00 [info    ] VALIDATE on the target by code: OK, 0 created, 3 updated, 0 ignored, of 3 units -- no conflicts [log say]
2026-11-03T14:31:11.111+01:00 [info    ] finished                       [log verdict] duration_ms=1 output_bytes=134
2026-11-03T14:31:11.057+01:00 [info    ] running                        [step say] block=log.write attempt=1
2026-11-03T14:31:11.076+01:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=19
2026-11-03T14:31:11.076+01:00 [info    ] queued                         [step verdict] block=validate.schema attempt=1
2026-11-03T14:31:11.087+01:00 [info    ] running                        [step verdict] block=validate.schema attempt=1
2026-11-03T14:31:11.101+01:00 [info    ] succeeded                      [step verdict] block=validate.schema attempt=1 duration_ms=13
2026-11-03T14:31:11.264+01:00 [info    ] succeeded                      [run] pipeline=other-to-dhis2 run_id=01a1a19b-44c4-73e8-b07f-afe4688be8d7 exit_code=0
steps
┏━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step    ┃ block               ┃ outcome   ┃ after       ┃ duration ┃ output                      ┃
┡━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ fetch   │ playground.generate │ succeeded │ -           │ 0.1s     │ records=[1 items]  rows=1   │
│         │                     │           │             │          │ seed=1447398121             │
│         │                     │           │             │          │ locale=en_US  fields={3     │
│         │                     │           │             │          │ keys}  drift=none           │
│         │                     │           │             │          │ delay_ms=0  attempt=1       │
│         │                     │           │             │          │ fail_until=0                │
│         │                     │           │             │          │ fail_as=transient           │
│         │                     │           │             │          │ input_rows=1                │
│ mode    │ value.const         │ succeeded │ -           │ 0.0s     │ value={4 keys}              │
│ shape   │ transform.jq        │ succeeded │ fetch       │ 0.0s     │ value={1 keys}              │
│ check   │ validate.schema     │ succeeded │ shape       │ 0.0s     │ value={1 keys}              │
│ send    │ http.request        │ succeeded │ check, mode │ 0.7s     │ status=200  headers={9      │
│         │                     │           │             │          │ keys}  body={4 keys}        │
│         │                     │           │             │          │ body_bytes=342              │
│         │                     │           │             │          │ duration_ms=684             │
│ report  │ transform.jq        │ succeeded │ send        │ 0.0s     │ value={9 keys}              │
│ say     │ log.write           │ succeeded │ report      │ 0.0s     │ -                           │
│ verdict │ validate.schema     │ succeeded │ say         │ 0.0s     │ value={9 keys}              │
└─────────┴─────────────────────┴───────────┴─────────────┴──────────┴─────────────────────────────┘
```

Three facilities, matched on their codes rather than their uids, and the target says it would
revise all three.

### The instance

`uv run dg schema create ...`, three times:

```text
stored schema org-unit-sync-source
stored schema org-unit-sync-import
stored schema org-unit-sync-verdict
```

`uv run dg connection create dhis2 ...`, twice:

```text
2026-11-03T14:31:24.506+01:00 [info    ] created                        [connection.created] code=source connection_kind=dhis2 name="DHIS2 play demo, the source" config={"base_url":"https://play.im.dhis2.org/dev","api_token":null,"basic_username":"admin","verify_tls":true,"follow_redirects_with_auth":false,"timeout":"30s","request_deadline":"10m","max_response":"64mb","basic_password":"***"}
2026-11-03T14:31:29.230+01:00 [info    ] created                        [connection.created] code=target connection_kind=dhis2 name="DHIS2 play demo, the target" config={"base_url":"https://play.dhis2.org/2.42","api_token":null,"basic_username":"admin","verify_tls":true,"follow_redirects_with_auth":true,"timeout":"30s","request_deadline":"10m","max_response":"64mb","basic_password":"***"}
```

The password is already withheld in the record each command answers with, and in every read
after it.

`uv run dg connection check source` and `uv run dg connection check target`:

```text
2026-11-03T14:31:34.822+01:00 [info    ] healthy                        [connection.checked] code=source healthy=true version=2.44-SNAPSHOT
2026-11-03T14:31:39.959+01:00 [info    ] healthy                        [connection.checked] code=target healthy=true version=2.42.7.1
```

Two lines, and the two versions are the point of them. A check builds the client from the
stored config and reads `/api/system/info` with the credential attached, so a healthy verdict
means the URL resolves, TLS is as configured, the credential is accepted, and the version is
the instance's own word for itself rather than something inferred from an `/api/N` path. Two
different answers here is also how this repository knows its two connections are two
instances -- `verify.sh` fails if they ever report the same version, because a sync that reads
and writes one instance is not a sync.

`uv run dg apply`:

```text
create dhis2-to-dhis2  version 1 (/home/you/dhis2-org-unit-sync/pipelines/dhis2-to-dhis2.yaml)
create dhis2-to-other  version 1 (/home/you/dhis2-org-unit-sync/pipelines/dhis2-to-other.yaml)
create other-to-dhis2  version 1 (/home/you/dhis2-org-unit-sync/pipelines/other-to-dhis2.yaml)
```

`uv run dg run dhis2-to-dhis2 --watch`:

```text
2026-11-03T14:31:45.829+01:00 [info    ] started                        [run] pipeline=dhis2-to-dhis2 run_id=01a1a19b-d10d-7080-bf64-506aac9d6a10 local=false
2026-11-03T14:31:45.811+01:00 [info    ] queued                         [step mode] block=value.const attempt=1
2026-11-03T14:31:45.811+01:00 [info    ] queued                         [step read] block=dhis2.metadata attempt=1
2026-11-03T14:31:45.959+01:00 [info    ] running                        [step mode] block=value.const attempt=1
2026-11-03T14:31:45.991+01:00 [info    ] running                        [step read] block=dhis2.metadata attempt=1
2026-11-03T14:31:45.991+01:00 [info    ] succeeded                      [step mode] block=value.const attempt=1 duration_ms=33
2026-11-03T14:31:46.063+01:00 [info    ] finished                       [log mode] duration_ms=0 output_bytes=110
2026-11-03T14:31:45.811+01:00 [info    ] queued                         [step check] block=validate.schema attempt=1
2026-11-03T14:31:46.706+01:00 [info    ] metadata read                  [log read] resource=organisationUnits rows=15 duration_ms=679
2026-11-03T14:31:46.710+01:00 [info    ] succeeded                      [step read] block=dhis2.metadata attempt=1 duration_ms=718
2026-11-03T14:31:46.728+01:00 [info    ] running                        [step check] block=validate.schema attempt=1
2026-11-03T14:31:45.811+01:00 [info    ] queued                         [step shape] block=transform.jq attempt=1
2026-11-03T14:31:46.775+01:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=47
2026-11-03T14:31:46.790+01:00 [info    ] finished                       [log check] duration_ms=6 output_bytes=2587
2026-11-03T14:31:46.858+01:00 [info    ] running                        [step shape] block=transform.jq attempt=1
2026-11-03T14:31:45.811+01:00 [info    ] queued                         [step send] block=http.request attempt=1
2026-11-03T14:31:46.969+01:00 [info    ] succeeded                      [step shape] block=transform.jq attempt=1 duration_ms=111
2026-11-03T14:31:46.978+01:00 [info    ] finished                       [log shape] duration_ms=83 output_bytes=2219
2026-11-03T14:31:46.992+01:00 [info    ] running                        [step send] block=http.request attempt=1
2026-11-03T14:31:45.811+01:00 [info    ] queued                         [step report] block=transform.jq attempt=1
2026-11-03T14:31:47.755+01:00 [info    ] http call                      [log send] method=POST url=/api/metadata status=200 bytes=346 duration_ms=686
2026-11-03T14:31:47.759+01:00 [info    ] succeeded                      [step send] block=http.request attempt=1 duration_ms=767
2026-11-03T14:31:47.771+01:00 [info    ] running                        [step report] block=transform.jq attempt=1
2026-11-03T14:31:45.811+01:00 [info    ] queued                         [step say] block=log.write attempt=1
2026-11-03T14:31:47.811+01:00 [info    ] succeeded                      [step report] block=transform.jq attempt=1 duration_ms=40
2026-11-03T14:31:47.835+01:00 [info    ] finished                       [log report] duration_ms=8 output_bytes=136
2026-11-03T14:31:47.891+01:00 [info    ] running                        [step say] block=log.write attempt=1
2026-11-03T14:31:45.811+01:00 [info    ] queued                         [step verdict] block=validate.schema attempt=1
2026-11-03T14:31:47.910+01:00 [info    ] VALIDATE on the target: OK, 0 created, 15 updated, 0 ignored, of 15 units -- no conflicts [log say]
2026-11-03T14:31:47.911+01:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=20
2026-11-03T14:31:47.958+01:00 [info    ] running                        [step verdict] block=validate.schema attempt=1
2026-11-03T14:31:47.981+01:00 [info    ] succeeded                      [step verdict] block=validate.schema attempt=1 duration_ms=23
2026-11-03T14:31:47.990+01:00 [info    ] finished                       [log verdict] duration_ms=3 output_bytes=136
2026-11-03T14:31:48.055+01:00 [info    ] succeeded                      [run] pipeline=dhis2-to-dhis2 run_id=01a1a19b-d10d-7080-bf64-506aac9d6a10 pipeline_version=1 triggered_by="admin (token dev)" duration_ms=2022 items_total=0 items_failed=0 exit_code=0 priority=normal
run 01a1a19b-d10d-7080-bf64-506aac9d6a10
pipeline      dhis2-to-dhis2 (version 1)
status        succeeded
triggered by  admin (token dev)
duration      2.0s
items         -

steps
┏━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━┓
┃ step    ┃ block           ┃ outcome   ┃ after       ┃ attempts ┃ duration ┃ error ┃
┡━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━┩
│ mode    │ value.const     │ succeeded │ -           │ 1        │ 0.0s     │ -     │
│ read    │ dhis2.metadata  │ succeeded │ -           │ 1        │ 0.7s     │ -     │
│ check   │ validate.schema │ succeeded │ read        │ 1        │ 0.0s     │ -     │
│ shape   │ transform.jq    │ succeeded │ check       │ 1        │ 0.1s     │ -     │
│ send    │ http.request    │ succeeded │ shape, mode │ 1        │ 0.8s     │ -     │
│ report  │ transform.jq    │ succeeded │ send        │ 1        │ 0.0s     │ -     │
│ say     │ log.write       │ succeeded │ report      │ 1        │ 0.0s     │ -     │
│ verdict │ validate.schema │ succeeded │ say         │ 1        │ 0.0s     │ -     │
└─────────┴─────────────────┴───────────┴─────────────┴──────────┴──────────┴───────┘

outputs
┏━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step    ┃ output                                                                       ┃
┡━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ mode    │ value={4 keys}                                                               │
│ read    │ rows=[15 items]  duration_ms=679                                             │
│ check   │ value=[15 items]                                                             │
│ shape   │ value={1 keys}                                                               │
│ send    │ status=200  headers={9 keys}  body={4 keys}  body_bytes=346  duration_ms=686 │
│ report  │ value={9 keys}                                                               │
│ say     │ -                                                                            │
│ verdict │ value={9 keys}                                                               │
└─────────┴──────────────────────────────────────────────────────────────────────────────┘
```

Same document, same eight hops, and the only difference from the local run is where it ran.

### The import report, and the request that earned it

`uv run dg runs show ... | jq '... select(.step_name == "report") ...'`:

```json
{
  "status": "OK",
  "created": 0,
  "updated": 15,
  "deleted": 0,
  "ignored": 0,
  "total": 15,
  "refused": 0,
  "conflicts": [],
  "detail": "no conflicts"
}
```

That is the `report` step's own reading of DHIS2's answer. The answer itself is under `send`,
and it is worth seeing whole once, because it is the shape a `/api/metadata` import always
comes back in:

```json
{
  "httpStatus": "OK",
  "httpStatusCode": 200,
  "status": "OK",
  "response": {
    "status": "OK",
    "stats": { "created": 0, "updated": 15, "deleted": 0, "ignored": 0, "total": 15 },
    "typeReports": [
      {
        "klass": "org.hisp.dhis.organisationunit.OrganisationUnit",
        "stats": { "created": 0, "updated": 15, "deleted": 0, "ignored": 0, "total": 15 },
        "objectReports": []
      }
    ],
    "responseType": "ImportReport"
  }
}
```

Two statuses, one the envelope's and one the report's, and the report's is the verdict. `stats`
is the summary, `typeReports` the same counts per resource type, and `objectReports` -- empty
here -- is where a refusal names the object that caused it. `/api/dataValueSets` answers with a
flat `conflicts[]` list instead, so a pipeline that reads one shape reads nothing from the
other.

`uv run dg runs show ... | jq '... select(.step_name == "mode") ...'` is the other half of the
proof, and the reason `mode` is a step rather than four lines typed into the request:

```json
{
  "atomicMode": "ALL",
  "identifier": "UID",
  "importMode": "VALIDATE",
  "importStrategy": "CREATE_AND_UPDATE"
}
```

`importMode: VALIDATE` is in the run, permanently, as the value the request's query was built
from. A report saying `updated: 15` says the same thing whether the import was rehearsed or
performed; this is what says which it was. `verify.sh` asserts on exactly this record, which is
how it can claim the demos were not written to. They were not: the target's `Badjia` still
carries `lastUpdated: 2015-03-27`.

### What a refusal looks like

The interesting failure is a unit arriving before the parent it names. On two copies of the
same database it has to be asked for, and a rehearsal is a safe place to ask:

`uv run dg run --local pipelines/other-to-dhis2.yaml ... -p parent_code=OU_NOT_THERE`:

```text
2026-11-03T14:31:15.577+01:00 [info    ] http call                      [log send] method=POST url=/api/metadata status=409 bytes=3122 duration_ms=652
2026-11-03T14:31:15.579+01:00 [info    ] succeeded                      [step send] block=http.request attempt=1 duration_ms=665
2026-11-03T14:31:15.600+01:00 [info    ] succeeded                      [step report] block=transform.jq attempt=1 duration_ms=15
2026-11-03T14:31:15.627+01:00 [info    ] VALIDATE on the target by code: ERROR, 0 created, 0 updated, 4 ignored, of 4 units -- Badjia E1523: User `xE7jOejl9FI` is not allowed to move organisation `YuQRtpLP10I` unit to parent `vEylsCVoeSm`; Badjia E5002: Invalid reference [OU_NOT_THERE] (OrganisationUnit) on object Badjia [OU_539] (OrganisationUnit) for association `parent`; Baoma E1523: User `xE7jOejl9FI` is not allowed to move organisation `vWbkYPRmKyS` unit to parent `jIwliNaZMCL`; ... [log say]
2026-11-03T14:31:15.627+01:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=9
2026-11-03T14:31:15.661+01:00 [info    ] failed                         [step verdict] block=validate.schema attempt=1 duration_ms=20
2026-11-03T14:31:15.792+01:00 [error   ] failed                         [run] pipeline=other-to-dhis2 run_id=01a1a19b-577a-7207-8611-42e27e63baa3 exit_code=1

verdict failed  validate.schema, attempt 1, rejected
  at $.conflicts: [{'uid': 'YuQRtpLP10I', 'name': 'Badjia', 'code': 'E1523', 'message': 'User
`xE7jOejl9FI` is not allowed to move organisation `YuQRtpLP10I` unit to parent `vEylsCVoeSm`'},
{'uid': 'YuQRtpLP10I', 'name': 'Badjia', 'code': 'E5002', 'message': 'Invalid reference
[OU_NOT_THERE] (OrganisationUnit) on object Badjia [OU_539] (OrganisationUnit) for association
`parent`'}, ...] is expected to be empty
```

*(the `say` line and the failure each carry all six errors; both are cut here at the second.)*

Four things in that, in the order they matter.

`status=409`. A DHIS2 metadata import answers a refusal with a 409 whose body is the report.
The step still succeeded, because `success_status: [200, 409]` says a 409 is an answer here and
not a transport failure -- the same judgement the pack's own `dhis2.data_value_set_import` block
makes. Without that line the step would have failed with nothing to show for it but the number.

`E5002 Invalid reference [OU_NOT_THERE] ... for association 'parent'`. The target's own words
for the only thing that is actually wrong.

`E1523 ... not allowed to move organisation ... to parent 'vEylsCVoeSm'`, with a uid nobody
sent. DHIS2 mints a placeholder for an unresolved reference and then complains about the
placeholder, so one mistake arrives as two errors and the counts say `4 ignored, of 4` for
three units. A pipeline that repeats DHIS2's numbers rather than counting its own has to be
ready for that.

`verdict failed ... rejected`. The gate is the thing that ends the run, and it runs *after*
`say`, which is why the target's words are in the run's log before the run is failed on them.
`rejected` and not `transient`: the same payload against the same instance will be refused
again in two hours, so no retry budget is spent on it.

And the parameter refused before anything is contacted:

```text
2026-11-03T14:31:58.644+01:00 [error   ] parameter parent is invalid: 'ImspTQPwCq' is not a 'dhis2-uid' [error] status=422 title="Unprocessable Content" code=parameter.invalid params={"location":"parent","detail":"'ImspTQPwCq' is not a 'dhis2-uid'"} instance=/api/v1/pipelines/dhis2-to-dhis2/$run
```

Ten characters instead of eleven. Nothing ran.

## The documents, hop by hop

Each file carries these notes as comments, at the line each one is about.

### `pipelines/dhis2-to-dhis2.yaml`

The header says which document language this is and which sort of document, and then the
quartet every addressable thing carries: `code` is the key this pipeline is addressed by,
`name` a human title with no identity at all, `description` the long form.

```yaml
format: dirigent/v1
kind: pipeline
code: dhis2-to-dhis2
name: Organisation units, source to target
```

`requires` is the document saying what it needs of an instance: every block id, both connection
codes, both schema codes. An instance missing one of them refuses the document rather than
failing halfway through a run, which is why the schemas and the connections are created before
the apply above and not after it.

```yaml
requires:
  blocks:
    - dhis2.metadata
    - validate.schema
    - transform.jq
    - value.const
    - http.request
    - log.write
  connections:
    - source
    - target
  schemas:
    - org-unit-sync-source
    - org-unit-sync-verdict
```

**`params.parent`** is the subtree. It is a uid rather than a level or a name because a uid is
the one thing about a DHIS2 hierarchy that does not change underneath you, and `format:
dhis2-uid` is a format this pack contributes, so it asserts rather than annotates: a run
submitted with ten characters is refused at submission. The default is Bo district, which has
fifteen chiefdoms under it; `-p parent=at6UHUQatSo` is Western Area instead.

**`params.import_mode`** is the parameter to be suspicious of, and the reason it is a parameter
at all is that it should be visible in the run rather than buried in a document nobody
re-reads.

```yaml
params:
  type: object
  properties:
    parent:
      type: string
      format: dhis2-uid
      default: O6uvpzGd5pu
      description: The uid of the parent whose children are synchronised. Bo district by default, which has fifteen chiefdoms under it.
    import_mode:
      type: string
      enum: [VALIDATE, COMMIT]
      default: VALIDATE
      description: VALIDATE rehearses the import and writes nothing. COMMIT performs it, and belongs against your own instance and never against a shared demo.
```

**Hop one, `read`.** `dhis2.metadata` reads one collection through the accessor the instance's
own version publishes, so `resource` is the collection name exactly as it appears in the API
path. `fields` is the DHIS2 projection and it is the import's shopping list: DHIS2 requires
`name`, `shortName`, `openingDate` and a `parent` of every unit below the root, and `id` and
`code` are the two ways a unit can be matched on the far side. `parent[id,code]` is DHIS2's
nested selector -- the brackets pick fields of the related object rather than fetching all of
it. The step names the connection by code and carries no credential at all.

```yaml
steps:
  read:
    block: dhis2.metadata
    retry:
      max_attempts: 3
      backoff: 2s
    config:
      connection: source
      resource: organisationUnits
      fields: "id,code,name,shortName,openingDate,level,parent[id,code]"
      filter: "parent.id:eq:${params.parent}"
      order: [name:asc]
```

The retry budget is for the failures worth spending it on. A connection failure on the wire, a
5xx and a 429 are `transient` and are retried; any other 4xx, a credential the instance refused,
and a collection name this version does not publish are `rejected` and spend no budget at all.

**Hop two, `check`.** The gate. It names the schema by code, and the code resolves to the one
the instance holds -- so two pipelines gating on the same shape gate on the same shape, and it
is corrected in one place. A read answers the rows it found under `rows`, a list, whichever
collection it read, and the gate holds that list. It hands its input on unchanged as `value`,
which makes it a waypoint: every step past it provably received the shape.

```yaml
  check:
    block: validate.schema
    depends_on: [read]
    config:
      input: ${steps.read.output.rows}
      schema: org-unit-sync-source
```

**Hop three, `shape`.** The reshape every cross-instance move needs, and it is smaller than it
looks: `level` is dropped, and `parent` is narrowed to its uid.

```yaml
  shape:
    block: transform.jq
    depends_on: [check]
    config:
      input: ${steps.check.output.value}
      program: |
        {organisationUnits: [.[] | {
          id, code, name, shortName, openingDate,
          parent: {id: .parent.id}
        }]}
```

`level` is not a field of a unit, it is a fact about where the unit sits, and the target works
its own out from the parent it is given -- which is why it is not writable on DHIS2's own
`organisationUnit` schema. `path`, `created` and `lastUpdated` are the same kind of thing, and
the projection above never asked for them.

This is also where a version difference between the two instances would be handled, and here
there is one that does not bite: the `organisationUnit` schema on 2.44 publishes forty-eight
properties to 2.42.6's fifty, the two it no longer has being `favorite` and `favorites`, which
are not owner properties, so a `fields=:owner` bundle read off 2.44 imports into 2.42.6 with
`status: OK` and nothing ignored. When a version difference does
bite -- a field the newer instance emits and the older one has never heard of -- it arrives as
an `errorReport` in the `objectReports` tree naming that property, and this step is where it is
dropped or rewritten. Ask the two instances before believing a bundle is portable:

```bash
curl -s -u admin:district "$SOURCE/api/schemas/organisationUnit?fields=properties[fieldName]"
curl -s -u admin:district "$TARGET/api/schemas/organisationUnit?fields=properties[fieldName]"
```

**Hop four, `mode`.** The four parameters that decide what the request below means, as a value
rather than as four lines typed into it.

```yaml
  mode:
    block: value.const
    config:
      value:
        importStrategy: CREATE_AND_UPDATE
        atomicMode: ALL
        identifier: UID
        importMode: ${params.import_mode}
```

| Parameter | What it decides |
| --- | --- |
| `importStrategy=CREATE_AND_UPDATE` | create what is missing, revise what is there |
| `atomicMode=ALL` | the whole payload lands, or none of it does |
| `identifier=UID` | match each unit by its uid |
| `importMode=VALIDATE` | **a dry run**: resolve, check, report, write nothing |

A step's output is in the run for as long as the run is kept, so writing them here rather than
inline is what lets a person, and `verify.sh`, answer "was that import real?" months later.
DHIS2 spells a rehearsal differently per endpoint, too: `importMode=VALIDATE` on `/api/metadata`
but `dryRun=true` on `/api/dataValueSets`. Reaching for the wrong spelling does not fail -- it
imports.

**Hop five, `send`.** The write, rehearsed. The pack has no metadata-import block and does not
need one: `http.request` naming a `dhis2` connection gets that connection's base URL,
credential, TLS setting and timeout, exactly as a `dhis2.*` block does, and the step still
carries no credential.

```yaml
  send:
    block: http.request
    depends_on: [shape, mode]
    config:
      connection: target
      path: /api/metadata
      method: POST
      query: ${steps.mode.output.value}
      body: ${steps.shape.output.value}
      success_status: [200, 409]
      max_response: 16mb
```

A reference that is the whole value resolves to the typed value, so `query:` is handed the
four-key map `mode` produced and `body:` the payload `shape` produced. `success_status: [200,
409]` is the line that keeps a refusal readable.

**Hops six and seven, `report` and `say`.** The three-level tree flattened to a verdict, a set
of counts and a list of refusals, and then one line of it in the run's log.

```yaml
  report:
    block: transform.jq
    depends_on: [send]
    config:
      input: ${steps.send.output.body}
      program: |
        [ .response.typeReports[]?.objectReports[]?
          | .uid as $uid
          | .displayName as $name
          | .errorReports[]?
          | {uid: $uid, name: $name, code: .errorCode, message: .message}
        ] as $conflicts
        | { status: .response.status, ... }
```

The `?` after each iteration is jq's "if it is there": a clean import has no `objectReports` at
all, and a program that insisted on them would fail on success.

**Hop eight, `verdict`.** The same verb as the gate at the top, pointed at the answer instead of
at the read. An import the target refused fails the run here.

```yaml
  verdict:
    block: validate.schema
    depends_on: [say]
    config:
      input: ${steps.report.output.value}
      schema: org-unit-sync-verdict
```

`depends_on: [say]` rather than `[report]` is the whole of the ordering lesson: the log line is
written before the gate is allowed to end the run, so the target's own words survive the
failure.

### `pipelines/dhis2-to-other.yaml`

The same read and the same gate, and then a translation instead of an import.

**`params.playground`** is the receiving system. It defaults to the playground an instance
serves under `/api/v1/playground`, which answers with the request it was given -- so the batch
comes back under `.body.request.body` and `say` at the bottom reads what *arrived* rather than
what was sent, which is what makes that line a receipt. Nothing on the public internet takes
the batch, and pointing this at the real receiver is one flag.

**Hop three, `records`.** `map.jq` runs its program once per element and keeps what the program
returns, so the list is exactly as long as the one that went in.

```yaml
  records:
    block: map.jq
    depends_on: [check]
    config:
      input: ${steps.check.output.value}
      program: |
        {code: .code,
         name: .name,
         parent_code: .parent.code,
         opened: (.openingDate | split("T")[0])}
```

Three decisions in four lines. **The code travels and the uid stays home**: a uid is DHIS2's own
key and means nothing in a system that was never given one, while a code is what both systems
were configured with. **The parent is named by code** for the same reason, which is what makes
a flat register rebuildable into a tree on the far side. And **the date is a day**: DHIS2 writes
an opening date as a timestamp because that is how it stores it, and a facility register wants
the day it opened.

**Hop four, `batch`.** One program over the whole list -- the verb for a change of shape rather
than an element-wise edit -- adding the envelope the receiver is handed.

```yaml
  batch:
    block: transform.jq
    depends_on: [records]
    config:
      input: ${steps.records.output.value}
      program: |
        {source: "dhis2-play-dev",
         synced: length,
         facilities: .}
```

The count rides with the rows. A sync that ships records without saying how many there should
have been cannot be audited on the far side. What arrives, three of its fifteen rows:

```json
{
  "source": "dhis2-play-dev",
  "synced": 15,
  "facilities": [
    { "code": "OU_539", "name": "Badjia", "parent_code": "OU_264", "opened": "1970-01-01" },
    { "code": "OU_540", "name": "Baoma", "parent_code": "OU_264", "opened": "1970-01-01" },
    { "code": "OU_543", "name": "Bumpe Ngao", "parent_code": "OU_264", "opened": "2011-05-01" }
  ]
}
```

**Hop five, `send`.** An absolute `url:` built from the parameter rather than a connection,
because this receiver needs no credential and because one flag then moves the whole document to
the real system. A real receiver gets a connection, like the two DHIS2 instances do.

```yaml
  send:
    block: http.request
    depends_on: [batch]
    config:
      url: ${params.playground}/request
      method: POST
      body: ${steps.batch.output.value}
```

### `pipelines/other-to-dhis2.yaml`

The direction that goes wrong. Outbound, DHIS2 hands over more than the receiver needs and the
reshape only ever drops fields. Inbound, the register hands over *less* than DHIS2 requires --
no shortName, no uid, a day rather than a timestamp -- and the document is where the difference
is made up, in public.

**Hop one, `fetch`.** Three facilities in the other system's own shape. The read is a node,
not a call: `playground.generate` takes an `input` and hands it back as its one record, so
nothing pretends to fetch what this document already carries and the step stands exactly where
a `GET` on that system would. Replace it with an `http.request` against the real register and
nothing under it moves.

```yaml
  fetch:
    block: playground.generate
    config:
      input:
        facilities:
          - code: OU_539
            name: Badjia
            parent_code: ${params.parent_code}
            opened: "1970-01-01"
```

**`params.parent_code`** is the district every facility in the register sits under, and it is a
parameter so that the failure above can be asked for: `-p parent_code=OU_NOT_THERE` is a code
the target does not hold, which is what a real inbound sync hits when the hierarchy above it
has not been synced yet.

**Hop three, `shape`.** The register's record turned into DHIS2 metadata, and each of the three
made-up values is a choice a reviewer should be able to argue with.

```yaml
  shape:
    block: transform.jq
    depends_on: [fetch]
    config:
      input: ${steps.fetch.output.records.0}
      program: |
        {organisationUnits: [.facilities[] | {
          code: .code,
          name: .name,
          shortName: (.name[0:50]),
          openingDate: .opened,
          parent: {code: .parent_code}
        }]}
```

`shortName` is required by DHIS2 and absent from the register, so the name is used, cut to the
fifty characters DHIS2 allows. `openingDate` takes the day as it stands, because a day is a
valid DHIS2 date and the timestamp is the instance's own rendering of it. And `parent` is named
by `code`, with no uid anywhere in the payload, which is what the next hop's `identifier=CODE`
resolves. What comes out, one of its three rows:

```json
{
  "organisationUnits": [
    {
      "code": "OU_539",
      "name": "Badjia",
      "shortName": "Badjia",
      "openingDate": "1970-01-01",
      "parent": { "code": "OU_264" }
    }
  ]
}
```

**Hop four, `check`.** The gate, on the payload rather than on the read. This is the end where
the shape is not under your control and the next hop writes, so this is where the gate belongs:
each document gates what it does not control, which in the other two is the DHIS2 read and
here is the register.

**Hop five, `mode`.** The same four parameters, with one changed:

| Parameter | What it decides |
| --- | --- |
| `importStrategy=CREATE_AND_UPDATE` | create what is missing, revise what is there |
| `atomicMode=ALL` | the whole payload lands, or none of it does |
| `identifier=CODE` | match each unit, **and each parent**, by its code rather than its uid |
| `importMode=VALIDATE` | **a dry run**: resolve, check, report, write nothing |

`identifier=CODE` is the parameter this document turns on. The register has no idea what a DHIS2
uid is, so every unit and every parent is named by its code and the import is told to match on
codes. Get this wrong and DHIS2 reads `code` as a field to write rather than as a key to match,
and creates a second copy of every unit.

The rest -- `send`, `report`, `say`, `verdict` -- is the first document's ending, against the
same target, with the same rule about what may be committed.

## The shapes, and the credentials

Three schemas, applied on their own with `dg schema create`. A schema reads its identity from
its own keywords: `$id` becomes the code it is addressed by, `title` its name, `description` its
body.

`schemas/org-unit-sync-source.json` is what a read off the source has to look like before
anything downstream believes it: every `id` held to `dhis2-uid`, every `code` to `dhis2-code`,
and `parent` required, because a root has nowhere to go on the far side. `additionalProperties:
false` is deliberate -- the projection asked for seven fields, so an eighth arriving means the
read changed.

`schemas/org-unit-sync-import.json` is what may be posted to `/api/metadata`: `name`,
`shortName`, `openingDate` and `parent` required because DHIS2 requires them, and an identifier
required through `anyOf` because a unit has to be findable, while which of `id` and `code` it is
stays the request's business rather than the shape's.

`schemas/org-unit-sync-verdict.json` is the one that is not about DHIS2's data at all but about
its answer: `status` must be `OK`, `ignored` and `refused` must be zero, and `conflicts` must be
empty. A metadata import answers a refusal with a 200 or a 409 and a report either way, so the
status code is not the verdict -- this shape is.

`dhis2-uid` and `dhis2-code` assert because the pack is installed: in JSON Schema a `format`
annotates and nothing more, but dirigent always hands its validator a checker and every
installed pack's formats join it.

`connections.yaml` is what a `--local` run is handed, because a local run starts on a throwaway
instance holding nothing. The credentials in it are the play demos' own, published so that
anyone may try the instances; a real one belongs in a connection the server holds, encrypted
under its key, and never in a file beside the documents. The server refuses a document that
carries a `connections:` section for exactly that reason, which is why this is a file of its own
rather than a section of a pipeline.

## Where to go next

- [`dhis2-org-units-to-markdown`](../dhis2-org-units-to-markdown/README.md) renders the units
  this example reads as a markdown page, an HTML page and a PDF, the last one from a pandoc
  container.
- [**The DHIS2 tutorial**](https://winterop-com.github.io/dirigent-dhis2/tutorial/) builds a
  read, a gate and a rehearsed write one section at a time, with the failures shown.
- [**The examples**](../README.md): every example in order, and what you need once.
