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
`https://play.im.dhis2.org/stable-2-43-1`, version **2.43.1**, and the target is
`https://play.im.dhis2.org/stable-2-42-6`, version **2.42.6**, both with the published
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
variable. `pipelines/dhis2-to-other.yaml` and `pipelines/other-to-dhis2.yaml` both take a
`base_url` parameter naming the system on the other side, which defaults to Postman Echo and
points just as happily at the stand-in in `../local-echo`, with no network at all:

```bash
uv run dg run --local pipelines/dhis2-to-other.yaml \
  --connections connections.yaml \
  --schema schemas/org-unit-sync-source.json \
  --schema schemas/org-unit-sync-import.json \
  --schema schemas/org-unit-sync-verdict.json \
  -p base_url=http://127.0.0.1:8080
```

Then the instance. A DHIS2 connection carries a password, and a connection secret is encrypted
at rest with the instance's own key, so mint one and start the instance with it in a second
terminal, in this directory. Keep the key: an instance that changes it cannot read what it
stored under the old one.

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

Back in the first terminal, mint a token for that admin, whose password is `dirigent-dev`. The
command answers with the `export DG_TOKEN=` line to paste into this terminal, and that line is
the one output this page does not print, because it is a credential:

```bash
uv run dg auth login --username dev --password dirigent-dev
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
  --set base_url=https://play.im.dhis2.org/stable-2-43-1 \
  --set basic_username=admin \
  --set basic_password=district
uv run dg connection create dhis2 target \
  --name "DHIS2 play demo, the target" \
  --set base_url=https://play.im.dhis2.org/stable-2-42-6 \
  --set basic_username=admin \
  --set basic_password=district

uv run dg connection check source
uv run dg connection check target
uv run dg apply

uv run dg run dhis2-to-dhis2 --watch
uv run dg run dhis2-to-other --watch
uv run dg run other-to-dhis2 --watch
```

`dg connection create` prompts for every secret field left unset, so each of those two asks
for `api_token`: there is none, so press Enter. `--set api_token=` is not the same thing: an
empty value is still a value, and a `dhis2` connection takes an `api_token` or basic
credentials, not both.

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

`./verify.sh` does all of it unattended -- validate, three local runs against both echoes, the
refusal above, an instance on a free port of its own, the three schemas, both connections, the
apply and the three runs -- and asserts on the records rather than on anything rendered. It
stops the instance it started by pid on the way out. `VERIFY_OFFLINE=1` leaves out the online
echo leg and nothing else: both DHIS2 instances are on the internet and have no stand-in.

## What you see

*Printed as it printed, with this project's directory written as
`/home/you/dhis2-org-unit-sync` and a local run's temporary root as `/tmp`.*

`uv run dg validate`, with no argument, which is the project's own documents:

```text
2026-09-17T16:04:49.046+02:00 [info    ] valid                          [validation] code=dhis2-to-dhis2 document=/home/you/dhis2-org-unit-sync/pipelines/dhis2-to-dhis2.yaml checked="document, offline"
  each step under the last one it waits for
    read  (dhis2.metadata)
      check  (validate.schema)
        shape  (transform.jq)
          send  (http.request)  also after mode
            report  (transform.jq)
              say  (log.write)
                verdict  (validate.schema)
    mode  (value.const)
2026-09-17T16:04:49.050+02:00 [info    ] valid                          [validation] code=dhis2-to-other document=/home/you/dhis2-org-unit-sync/pipelines/dhis2-to-other.yaml checked="document, offline"
  each step under the last one it waits for
    read  (dhis2.metadata)
      check  (validate.schema)
        records  (map.jq)
          batch  (transform.jq)
            send  (http.request)
              say  (log.write)
2026-09-17T16:04:49.051+02:00 [info    ] valid                          [validation] code=other-to-dhis2 document=/home/you/dhis2-org-unit-sync/pipelines/other-to-dhis2.yaml checked="document, offline"
  each step under the last one it waits for
    fixture  (value.const)
      fetch  (http.request)
        shape  (transform.jq)
          check  (validate.schema)
            send  (http.request)  also after mode
              report  (transform.jq)
                say  (log.write)
                  verdict  (validate.schema)
    mode  (value.const)
2026-09-17T16:04:49.052+02:00 [info    ] valid                          [validated] documents=3 invalid=0
```

Nothing has run and nothing has been contacted: those trees are the graphs the documents
already hold, each step under the last one it waits for. `mode` hangs off nothing in two of
them, because a constant waits for no one, and `also after mode` is the second edge `send`
carries.

### The three documents, run locally

`uv run dg run --local pipelines/dhis2-to-dhis2.yaml ...`:

```text
2026-09-17T16:04:50.825+02:00 [info    ] started                        [run] pipeline=dhis2-to-dhis2 run_id=01a0afaf-3705-76a9-8b01-4fd9f1fdd745 local=true scratch=file:///tmp/dirigent-local-82o4dqaj/artifacts/runs/01a0afaf-3705-76a9-8b01-4fd9f1fdd745 root=/tmp/dirigent-local-82o4dqaj
2026-09-17T16:04:50.820+02:00 [info    ] queued                         [step read] block=dhis2.metadata attempt=1
2026-09-17T16:04:50.820+02:00 [info    ] queued                         [step mode] block=value.const attempt=1
2026-09-17T16:04:50.881+02:00 [info    ] succeeded                      [step mode] block=value.const attempt=1 duration_ms=11
2026-09-17T16:04:50.881+02:00 [info    ] running                        [step read] block=dhis2.metadata attempt=1
2026-09-17T16:04:50.885+02:00 [info    ] finished                       [log mode] duration_ms=0 output_bytes=110
2026-09-17T16:04:52.110+02:00 [info    ] metadata read                  [log read] resource=organisationUnits duration_ms=1213
2026-09-17T16:04:52.111+02:00 [info    ] succeeded                      [step read] block=dhis2.metadata attempt=1 duration_ms=1230
2026-09-17T16:04:52.154+02:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=7
2026-09-17T16:04:52.157+02:00 [info    ] finished                       [log check] duration_ms=1 output_bytes=2609
2026-09-17T16:04:52.199+02:00 [info    ] succeeded                      [step shape] block=transform.jq attempt=1 duration_ms=45
2026-09-17T16:04:52.203+02:00 [info    ] finished                       [log shape] duration_ms=31 output_bytes=2219
2026-09-17T16:04:52.502+02:00 [info    ] http call                      [log send] method=POST url=/api/metadata status=200 bytes=346 duration_ms=264
2026-09-17T16:04:52.504+02:00 [info    ] succeeded                      [step send] block=http.request attempt=1 duration_ms=270
2026-09-17T16:04:52.533+02:00 [info    ] succeeded                      [step report] block=transform.jq attempt=1 duration_ms=17
2026-09-17T16:04:52.535+02:00 [info    ] finished                       [log report] duration_ms=9 output_bytes=136
2026-09-17T16:04:52.589+02:00 [info    ] VALIDATE on the target: OK, 0 created, 15 updated, 0 ignored, of 15 units -- no conflicts [log say]
2026-09-17T16:04:52.589+02:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=6
2026-09-17T16:04:52.606+02:00 [info    ] succeeded                      [step verdict] block=validate.schema attempt=1 duration_ms=16
2026-09-17T16:04:52.610+02:00 [info    ] finished                       [log verdict] duration_ms=0 output_bytes=136
2026-09-17T16:04:52.704+02:00 [info    ] succeeded                      [run] pipeline=dhis2-to-dhis2 run_id=01a0afaf-3705-76a9-8b01-4fd9f1fdd745 exit_code=0
steps
┏━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step    ┃ block           ┃ outcome   ┃ after       ┃ duration ┃ output                          ┃
┡━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ mode    │ value.const     │ succeeded │ -           │ 0.0s     │ value={4 keys}                  │
│ read    │ dhis2.metadata  │ succeeded │ -           │ 1.2s     │ body={1 keys}  duration_ms=1213 │
│ check   │ validate.schema │ succeeded │ read        │ 0.0s     │ value={1 keys}                  │
│ shape   │ transform.jq    │ succeeded │ check       │ 0.0s     │ value={1 keys}                  │
│ send    │ http.request    │ succeeded │ shape, mode │ 0.3s     │ status=200  headers={9 keys}    │
│         │                 │           │             │          │ body={4 keys}  body_bytes=346   │
│         │                 │           │             │          │ duration_ms=264                 │
│ report  │ transform.jq    │ succeeded │ send        │ 0.0s     │ value={9 keys}                  │
│ say     │ log.write       │ succeeded │ report      │ 0.0s     │ -                               │
│ verdict │ validate.schema │ succeeded │ say         │ 0.0s     │ value={9 keys}                  │
└─────────┴─────────────────┴───────────┴─────────────┴──────────┴─────────────────────────────────┘
```

Fifteen chiefdoms under Bo, read off 2.43.1 and offered to 2.42.6, which says it would revise
all fifteen and writes nothing. `updated=15` rather than `created=15` is the two demos being
the same database: this is a rehearsal of a sync that has already happened.

`uv run dg run --local pipelines/dhis2-to-other.yaml ...`:

```text
2026-09-17T16:04:55.904+02:00 [info    ] metadata read                  [log read] resource=organisationUnits duration_ms=1148
2026-09-17T16:04:55.906+02:00 [info    ] succeeded                      [step read] block=dhis2.metadata attempt=1 duration_ms=1159
2026-09-17T16:04:55.917+02:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=5
2026-09-17T16:04:55.920+02:00 [info    ] finished                       [log check] duration_ms=1 output_bytes=2609
2026-09-17T16:04:56.007+02:00 [info    ] succeeded                      [step records] block=map.jq attempt=1 duration_ms=38
2026-09-17T16:04:56.010+02:00 [info    ] finished                       [log records] duration_ms=31 output_bytes=1209
2026-09-17T16:04:56.050+02:00 [info    ] succeeded                      [step batch] block=transform.jq attempt=1 duration_ms=9
2026-09-17T16:04:56.052+02:00 [info    ] finished                       [log batch] duration_ms=4 output_bytes=1265
2026-09-17T16:04:56.362+02:00 [info    ] http call                      [log send] method=POST url=https://postman-echo.com/post status=200 bytes=2800 duration_ms=256
2026-09-17T16:04:56.366+02:00 [info    ] succeeded                      [step send] block=http.request attempt=1 duration_ms=265
2026-09-17T16:04:56.397+02:00 [info    ] the register took 15 facilities from dhis2-play-2-43-1, first OU_539 under OU_264 [log say]
2026-09-17T16:04:56.397+02:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=8
2026-09-17T16:04:56.552+02:00 [info    ] succeeded                      [run] pipeline=dhis2-to-other run_id=01a0afaf-4633-7636-9087-4d09ebff9c72 exit_code=0
steps
┏━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step    ┃ block           ┃ outcome   ┃ after   ┃ duration ┃ output                              ┃
┡━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ read    │ dhis2.metadata  │ succeeded │ -       │ 1.2s     │ body={1 keys}  duration_ms=1148     │
│ check   │ validate.schema │ succeeded │ read    │ 0.0s     │ value={1 keys}                      │
│ records │ map.jq          │ succeeded │ check   │ 0.0s     │ value=[15 items]                    │
│ batch   │ transform.jq    │ succeeded │ records │ 0.0s     │ value={3 keys}                      │
│ send    │ http.request    │ succeeded │ batch   │ 0.3s     │ status=200  headers={12 keys}       │
│         │                 │           │         │          │ body={7 keys}  body_bytes=2800      │
│         │                 │           │         │          │ duration_ms=256                     │
│ say     │ log.write       │ succeeded │ send    │ 0.0s     │ -                                   │
└─────────┴─────────────────┴───────────┴─────────┴──────────┴─────────────────────────────────────┘
```

`value=[15 items]` out of `map.jq` and `value={3 keys}` out of `transform.jq` are the two
verbs' contracts on the screen: a map is exactly as long as the list that went in, and a
transform is one program over one whole value.

`uv run dg run --local pipelines/other-to-dhis2.yaml ...`:

```text
2026-09-17T16:04:59.063+02:00 [info    ] http call                      [log fetch] method=POST url=https://postman-echo.com/post status=200 bytes=793 duration_ms=213
2026-09-17T16:04:59.066+02:00 [info    ] succeeded                      [step fetch] block=http.request attempt=1 duration_ms=221
2026-09-17T16:04:59.145+02:00 [info    ] succeeded                      [step shape] block=transform.jq attempt=1 duration_ms=49
2026-09-17T16:04:59.147+02:00 [info    ] finished                       [log shape] duration_ms=40 output_bytes=358
2026-09-17T16:04:59.179+02:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=5
2026-09-17T16:04:59.183+02:00 [info    ] finished                       [log check] duration_ms=0 output_bytes=358
2026-09-17T16:04:59.545+02:00 [info    ] http call                      [log send] method=POST url=/api/metadata status=200 bytes=342 duration_ms=308
2026-09-17T16:04:59.549+02:00 [info    ] succeeded                      [step send] block=http.request attempt=1 duration_ms=317
2026-09-17T16:04:59.608+02:00 [info    ] succeeded                      [step report] block=transform.jq attempt=1 duration_ms=26
2026-09-17T16:04:59.612+02:00 [info    ] finished                       [log report] duration_ms=13 output_bytes=134
2026-09-17T16:04:59.672+02:00 [info    ] VALIDATE on the target by code: OK, 0 created, 3 updated, 0 ignored, of 3 units -- no conflicts [log say]
2026-09-17T16:04:59.672+02:00 [info    ] succeeded                      [step say] block=log.write attempt=1 duration_ms=11
2026-09-17T16:04:59.742+02:00 [info    ] succeeded                      [step verdict] block=validate.schema attempt=1 duration_ms=15
2026-09-17T16:04:59.814+02:00 [info    ] succeeded                      [run] pipeline=other-to-dhis2 run_id=01a0afaf-5610-72ca-8156-53057be8e995 exit_code=0
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
2026-09-17T16:05:12.920+02:00 [info    ] created                        [connection.created] code=source connection_kind=dhis2 name="DHIS2 play demo, the source" config={"base_url":"https://play.im.dhis2.org/stable-2-43-1","api_token":null,"basic_username":"admin","verify_tls":true,"timeout":"30s","basic_password":"***"}
2026-09-17T16:05:14.150+02:00 [info    ] created                        [connection.created] code=target connection_kind=dhis2 name="DHIS2 play demo, the target" config={"base_url":"https://play.im.dhis2.org/stable-2-42-6","api_token":null,"basic_username":"admin","verify_tls":true,"timeout":"30s","basic_password":"***"}
```

The password is already withheld in the record each command answers with, and in every read
after it.

`uv run dg connection check source` and `uv run dg connection check target`:

```text
2026-09-17T16:05:16.323+02:00 [info    ] healthy                        [connection.checked] code=source healthy=true version=2.43.1
2026-09-17T16:05:18.571+02:00 [info    ] healthy                        [connection.checked] code=target healthy=true version=2.42.6
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
2026-09-17T16:05:21.114+02:00 [info    ] started                        [run] pipeline=dhis2-to-dhis2 run_id=01a0afaf-ad56-774a-8e31-142ddc37eede local=false
2026-09-17T16:05:22.297+02:00 [info    ] metadata read                  [log read] resource=organisationUnits duration_ms=687
2026-09-17T16:05:22.302+02:00 [info    ] succeeded                      [step read] block=dhis2.metadata attempt=1 duration_ms=700
2026-09-17T16:05:22.633+02:00 [info    ] succeeded                      [step check] block=validate.schema attempt=1 duration_ms=16
2026-09-17T16:05:23.194+02:00 [info    ] succeeded                      [step shape] block=transform.jq attempt=1 duration_ms=54
2026-09-17T16:05:23.989+02:00 [info    ] http call                      [log send] method=POST url=/api/metadata status=200 bytes=346 duration_ms=311
2026-09-17T16:05:23.991+02:00 [info    ] succeeded                      [step send] block=http.request attempt=1 duration_ms=317
2026-09-17T16:05:24.193+02:00 [info    ] succeeded                      [step report] block=transform.jq attempt=1 duration_ms=10
2026-09-17T16:05:24.699+02:00 [info    ] VALIDATE on the target: OK, 0 created, 15 updated, 0 ignored, of 15 units -- no conflicts [log say]
2026-09-17T16:05:25.207+02:00 [info    ] succeeded                      [step verdict] block=validate.schema attempt=1 duration_ms=5
2026-09-17T16:05:25.247+02:00 [info    ] succeeded                      [run] pipeline=dhis2-to-dhis2 run_id=01a0afaf-ad56-774a-8e31-142ddc37eede pipeline_version=1 triggered_by="dev (token cli-dev)" duration_ms=3618 items_total=0 items_failed=0 exit_code=0 priority=normal
run 01a0afaf-ad56-774a-8e31-142ddc37eede
pipeline      dhis2-to-dhis2 (version 1)
status        succeeded
triggered by  dev (token cli-dev)
duration      3.6s
items         -

steps
┏━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━┓
┃ step    ┃ block           ┃ outcome   ┃ after       ┃ attempts ┃ duration ┃ error ┃
┡━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━┩
│ mode    │ value.const     │ succeeded │ -           │ 1        │ 0.0s     │ -     │
│ read    │ dhis2.metadata  │ succeeded │ -           │ 1        │ 0.7s     │ -     │
│ check   │ validate.schema │ succeeded │ read        │ 1        │ 0.0s     │ -     │
│ shape   │ transform.jq    │ succeeded │ check       │ 1        │ 0.1s     │ -     │
│ send    │ http.request    │ succeeded │ shape, mode │ 1        │ 0.3s     │ -     │
│ report  │ transform.jq    │ succeeded │ send        │ 1        │ 0.0s     │ -     │
│ say     │ log.write       │ succeeded │ report      │ 1        │ 0.0s     │ -     │
│ verdict │ validate.schema │ succeeded │ say         │ 1        │ 0.0s     │ -     │
└─────────┴─────────────────┴───────────┴─────────────┴──────────┴──────────┴───────┘

outputs
┏━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ step    ┃ output                                                                       ┃
┡━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ mode    │ value={4 keys}                                                               │
│ read    │ body={1 keys}  duration_ms=687                                               │
│ check   │ value={1 keys}                                                               │
│ shape   │ value={1 keys}                                                               │
│ send    │ status=200  headers={9 keys}  body={4 keys}  body_bytes=346  duration_ms=311 │
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
2026-09-17T16:05:03.268+02:00 [info    ] http call                      [log send] method=POST url=/api/metadata status=409 bytes=3122 duration_ms=929
2026-09-17T16:05:03.272+02:00 [info    ] succeeded                      [step send] block=http.request attempt=1 duration_ms=938
2026-09-17T16:05:03.320+02:00 [info    ] succeeded                      [step report] block=transform.jq attempt=1 duration_ms=43
2026-09-17T16:05:03.379+02:00 [info    ] VALIDATE on the target by code: ERROR, 0 created, 0 updated, 4 ignored, of 4 units -- Badjia E1523: User `xE7jOejl9FI` is not allowed to move organisation `YuQRtpLP10I` unit to parent `Q8sZZs1982U`; Badjia E5002: Invalid reference [OU_NOT_THERE] (OrganisationUnit) on object Badjia [OU_539] (OrganisationUnit) for association `parent`; Baoma E1523: User `xE7jOejl9FI` is not allowed to move organisation `vWbkYPRmKyS` unit to parent `vIsxd6kHyca`; ... [log say]
2026-09-17T16:05:03.445+02:00 [info    ] failed                         [step verdict] block=validate.schema attempt=1 duration_ms=11
2026-09-17T16:05:03.555+02:00 [error   ] failed                         [run] pipeline=other-to-dhis2 run_id=01a0afaf-61fe-71d7-b197-4069a548dcae exit_code=1

verdict failed  validate.schema, attempt 1, rejected
  at $.conflicts: [{'uid': 'YuQRtpLP10I', 'name': 'Badjia', 'code': 'E1523', 'message': 'User
`xE7jOejl9FI` is not allowed to move organisation `YuQRtpLP10I` unit to parent `Q8sZZs1982U`'},
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

`E1523 ... not allowed to move organisation ... to parent 'Q8sZZs1982U'`, with a uid nobody
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
2026-09-17T16:05:42.245+02:00 [error   ] parameter parent is invalid: 'ImspTQPwCq' is not a 'dhis2-uid' [error] status=422 title="Unprocessable Content" instance=/api/v1/pipelines/dhis2-to-dhis2/$run
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
is corrected in one place. It hands its input on unchanged as `value`, which makes it a
waypoint: every step past it provably received the shape.

```yaml
  check:
    block: validate.schema
    depends_on: [read]
    config:
      input: ${steps.read.output.body}
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
        {organisationUnits: [.organisationUnits[] | {
          id, code, name, shortName, openingDate,
          parent: {id: .parent.id}
        }]}
```

`level` is not a field of a unit, it is a fact about where the unit sits, and the target works
its own out from the parent it is given -- which is why it is not writable on DHIS2's own
`organisationUnit` schema. `path`, `created` and `lastUpdated` are the same kind of thing, and
the projection above never asked for them.

This is also where a version difference between the two instances would be handled, and it is
worth saying plainly that **there was not one to show here**: the `organisationUnit` schema on
2.43.1 and on 2.42.6 publishes the same fifty properties, and a `fields=:owner` bundle read off
2.43.1 imports into 2.42.6 with `status: OK` and nothing ignored. When a version difference does
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

**`params.base_url`** is the receiving system. It defaults to Postman Echo, which answers with
the request it was given -- so the batch comes back and `say` at the bottom reads what *arrived*
rather than what was sent, which is what makes that line a receipt. The stand-in in
`../local-echo` answers the same shapes offline.

**Hop three, `records`.** `map.jq` runs its program once per element and keeps what the program
returns, so the list is exactly as long as the one that went in.

```yaml
  records:
    block: map.jq
    depends_on: [check]
    config:
      input: ${steps.check.output.value.organisationUnits}
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
        {source: "dhis2-play-2-43-1",
         synced: length,
         facilities: .}
```

The count rides with the rows. A sync that ships records without saying how many there should
have been cannot be audited on the far side. What arrives, three of its fifteen rows:

```json
{
  "source": "dhis2-play-2-43-1",
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
another echo. A real receiver gets a connection, like the two DHIS2 instances do.

```yaml
  send:
    block: http.request
    depends_on: [batch]
    config:
      url: ${params.base_url}/post
      method: POST
      body: ${steps.batch.output.value}
```

### `pipelines/other-to-dhis2.yaml`

The direction that goes wrong. Outbound, DHIS2 hands over more than the receiver needs and the
reshape only ever drops fields. Inbound, the register hands over *less* than DHIS2 requires --
no shortName, no uid, a day rather than a timestamp -- and the document is where the difference
is made up, in public.

**Hops one and two, `fixture` and `fetch`.** Three facilities in the other system's own shape,
POSTed to the echo so they come back under `.body.json` the way a real register would answer a
query. That stands in for a `GET` on that system; point `base_url` at the real one and `fetch`
becomes that read.

```yaml
  fixture:
    block: value.const
    config:
      value:
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
      input: ${steps.fetch.output.body.json}
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

This is the last example on the shelf.

- [**The DHIS2 tutorial**](https://winterop-com.github.io/dirigent-dhis2/tutorial/) builds a
  read, a gate and a rehearsed write one section at a time, with the failures shown.
- [**The examples**](../README.md) is the shelf all of these sit on, in the order they build
  on each other.
