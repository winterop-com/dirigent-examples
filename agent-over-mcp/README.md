# agent-over-mcp

A coding agent working on a running instance, the way a person would hand one the job: through
the instance's own MCP server at `/mcp`, under a token of its own, with a role that decides what
it may touch. Every dirigent server answers MCP there, so nothing is installed beside the agent.
The agent here reads and changes a pipeline, runs it and reads the report it rendered, and sets
up the connections it wants -- but never holds a secret. It creates a connection with its
settings alone, and a person who is an admin supplies the secret afterwards with
`dg connection set-secret`. What the agent did is attributed to it on the instance, run by run.

The project is one pipeline, `station-report`, which asks the playground for a station's
reading and writes the run's own report of it, and a `.mcp.json` that points an agent at the
instance. `verify.sh` plays the agent with `curl`, so the whole of it is checked with no model
in the loop.

## What it calls

The **playground**, the request-and-response service every dirigent instance serves itself
under `/api/v1/playground`: it answers with the request it was given. Nothing here leaves the
machine. The Slack connection the agent creates is never used to send anything; it is there
because a Slack connection cannot work without its token, which is what makes it wait for one.

## Run it

`verify.sh` does everything below non-interactively, on a free port of its own, and stops the
instance it started:

```bash
uv sync
./verify.sh
```

```text
agent-over-mcp: an operator over /mcp listed its tools, created a connection with its settings alone, edited, ran and read the report of a pipeline; the admin completed the connection
```

The rest of this page is the same thing done by hand, with a real agent.

## 1. The instance, and the pipeline

A connection secret is sealed with the instance's own key, so the instance needs one before the
admin supplies a secret at the end. Mint it once into `.env`, which is not in the repository,
and start the instance in a second terminal, in this directory:

```bash
grep -q '^DIRIGENT_SECRET_KEY=' .env 2>/dev/null \
  || printf 'DIRIGENT_SECRET_KEY=%s\n' "$(uv run dg secret-key)" >> .env
uv run dg dev
```

On an empty state `dg dev` makes its own admin, `admin` / `admin`, and the UI is at
http://127.0.0.1:3333. Back in the first terminal, log in as that admin and paste the
`export DG_TOKEN=` line it answers with, then apply the pipeline:

```bash
uv run dg auth login --username admin --password admin
uv run dg apply
```

```text
create station-report  version 1 (/home/you/agent-over-mcp/pipelines/station-report.yaml)
```

*Printed as it printed, with this project's directory written as `/home/you/...`. Where an
instance's address appears below it is written as `127.0.0.1:3333`, the port `dg dev` uses.*

## 2. An account for the agent, and its token

Give the agent an account of its own rather than yours, so everything it does says it was the
agent, and an `operator` rather than an `admin`: an operator applies, edits and runs pipelines
and creates connections, and is refused a secret, a schema, an account, a connection check and
the audit trail. `dg admin user create` writes the account straight to this instance's
database, so it needs no token; it asks for a password the agent never uses.

```bash
uv run dg admin user create agent --role operator
```

```text
password (at least 8 characters):
2026-11-03T14:32:33.419+01:00 [info    ] created                        [user.created] username=agent role=operator database=sqlite+aiosqlite:///./.dirigent/state/dirigent.db hint="log in with dg auth login, or mint a token with dg admin token create"
```

Then mint it a token into this shell only. The admin token in `DG_TOKEN` is what mints it, and
the token is answered once, so it goes straight into a variable and never into a file:

```bash
export DG_MCP_TOKEN=$(uv run dg admin token create mcp --user agent --json | jq -r 'select(.token).token')
echo ${#DG_MCP_TOKEN}     # 43; 0 means the create failed: run it without | jq to see why
```

## 3. The agent's connection to the instance

`.mcp.json` beside `pyproject.toml` is what Claude Code reads from a project:

```json
{
  "mcpServers": {
    "dirigent": {
      "type": "http",
      "url": "http://127.0.0.1:3333/mcp",
      "headers": { "Authorization": "Bearer ${DG_MCP_TOKEN}" }
    }
  }
}
```

It holds no secret: Claude Code expands `${DG_MCP_TOKEN}` from the environment it is started
with, which is why the file is committed. Start it from this directory, in the shell that holds
the token:

```bash
claude
```

Approve the `dirigent` server once when asked, and `/mcp` lists it as connected. Every request
acts as the token it carries, so the agent is offered the tools an operator may call and no
others: 52 of them, without `check_connection`, `create_schema`, `update_schema`,
`delete_schema` or `list_audit`. Ask it who it is, and `whoami` answers:

```json
{
  "user_id": "01a1a19c-8b08-737d-9655-cf3b54f47aeb",
  "username": "agent",
  "role": "operator",
  "via": "api",
  "token_name": "mcp"
}
```

Any MCP client that sends a header on an HTTP server connects the same way; `.mcp.json` is
Claude Code's form of it.

## 4. The agent sets up its connections

Ask the agent to call the playground through a connection rather than a URL, and to set up a
Slack connection for the station alerts in `#station-alerts`. It calls `create_connection` for
each. The playground needs no secret, so that one is complete the moment it is stored:

```json
{
  "kind": "http",
  "code": "playground",
  "name": "The playground",
  "settings": { "base_url": "http://127.0.0.1:3333/api/v1/playground" }
}
```

A Slack connection cannot post without a webhook or a bot token. Had the agent been handed the
token and put it in the call, the instance would refuse the field by its name, never echoing
the value, and store nothing:

```text
Error executing tool create_connection: bot_token is secret, and only an admin sets a connection's secrets: leave it out, and the connection is created awaiting it [server.secrets_need_admin]
```

With the channel alone, it is stored awaiting its secret, and the answer says what is missing
and who supplies it:

```json
{
  "connection": {
    "code": "team-alerts",
    "name": "Station alerts",
    "kind": "slack",
    "config": {
      "webhook_url": null,
      "bot_token": null,
      "channel": "#station-alerts",
      "verify_tls": true,
      "timeout": "15s"
    },
    "secret_fields": ["webhook_url", "bot_token"],
    "awaiting_secrets": true
  },
  "secrets_to_supply": ["webhook_url", "bot_token"],
  "optional_secrets": [],
  "supply_with": {
    "by": "an admin of this instance",
    "command": "dg --url http://127.0.0.1:3333 connection set-secret team-alerts",
    "screen": "http://127.0.0.1:3333/connections/team-alerts"
  }
}
```

`secrets_to_supply` names both because either form will do: a webhook, or a bot token with the
channel already given. Until one is set, every step, alert and check that names `team-alerts`
is refused with `secret.connection_awaiting_secrets`. The Connections screen draws it as
*awaiting secrets*, and so does the listing:

```bash
uv run dg connection list
```

```text
connections
┏━━━━━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━━━━┓
┃ code        ┃ name         ┃ kind  ┃ last check ┃ healthy      ┃ description ┃
┡━━━━━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━━━━┩
│ playground  │ The          │ http  │ -          │ never        │ -           │
│             │ playground   │       │            │ checked      │             │
│ team-alerts │ Station      │ slack │ -          │ awaiting     │ -           │
│             │ alerts       │       │            │ secrets      │             │
└─────────────┴──────────────┴───────┴────────────┴──────────────┴─────────────┘
```

## 5. The agent edits the pipeline in place

To move the step onto the connection, the agent does not send the document again. It reads the
stored version with `export_pipeline` and hands `edit_pipeline` exact replacements in that text.
The text is the stored version rendered canonically, not the file in `pipelines/`: no comments,
and the keys in their own order. So the edits below match the export, and would not match the
file:

```json
{
  "code": "station-report",
  "edits": [
    {
      "old": "      url: ${params.playground}/request",
      "new": "      connection: playground\n      path: /request"
    },
    {
      "old": "    playground:\n      type: string\n      description: The playground routes on the instance this calls; `dg dev` serves them here.\n      default: http://127.0.0.1:3333/api/v1/playground\n",
      "new": ""
    }
  ]
}
```

The first moves the call onto the connection, the second drops the parameter that addressed the
playground, now that the connection does. Each `old` must occur exactly once; one that misses,
or matches twice, refuses every edit and stores nothing. With `plan_only: true` the same call
answers the plan alone:

```json
{
  "dry_run": true,
  "version": null,
  "plan": {
    "code": "station-report",
    "action": "update",
    "current_version": 1,
    "next_version": 2,
    "issues": [],
    "warnings": [],
    "diff": {
      "steps_added": [],
      "steps_removed": [],
      "steps_changed": ["ask"],
      "params_changed": true,
      "triggers_changed": false,
      "settings_changed": false
    }
  }
}
```

and without it the edit is applied as version 2. The step in the stored version now reads:

```yaml
steps:
  ask:
    block: http.request
    config:
      connection: playground
      method: GET
      path: /request
      query:
        reading: '12.4'
        station: ${params.station}
```

`pipelines/station-report.yaml` is unchanged: the instance is where definitions live, and
`uv run dg export station-report` writes the edited version out as canonical YAML, which is how
it would come back into the project.

## 6. The agent runs it and reads the report

`run_pipeline` with `wait: true` answers once the run has settled:

```json
{
  "id": "01a1a19d-0980-72e4-87da-8c7e5939b13f",
  "pipeline": "station-report",
  "pipeline_version": 2,
  "status": "succeeded",
  "params": { "station": "oslo-blindern" },
  "triggered_by_label": "agent (token mcp)",
  "started_at": "2026-11-03T13:33:05.796296Z",
  "finished_at": "2026-11-03T13:33:05.917532Z"
}
```

`triggered_by_label` is the account and the token, which is what every screen and every
`dg runs` listing names the run by. The pipeline declares a `report:`, so the run rendered one
when it settled, and `get_run_report` reads it back:

```json
{
  "run_id": "01a1a19d-0980-72e4-87da-8c7e5939b13f",
  "exists": true,
  "text": "# oslo-blindern\n\n**succeeded** in 121ms, started by agent (token mcp).\n\nThe playground answered 200 and read back station\n`oslo-blindern`, reading `12.4`.\n",
  "offset": 0,
  "total_chars": 155
}
```

The heading is `{{ params.station }}`: a report template reads the run's resolved parameters
as `params`. A long report comes back a stretch at a time, with `next_offset` while more
remains, so an agent never reads more than it can hold. The same document is what
`uv run dg runs report <run id> --markdown` prints and what the run's Report tab draws.

## 7. The admin supplies the secret

The connection the agent began is finished by a person. In the first terminal, as the admin:

```bash
uv run dg connection set-secret team-alerts
```

The connection already holds a `channel`, so it has begun the bot form, and `set-secret` asks
only for that form's `bot_token`, without echoing it, then sends it with the settings already
stored so the kind's model judges the whole config. The completed connection is used by
anything that names it from then on, and its row no longer says *awaiting secrets*:

```text
connections
┏━━━━━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━━━━━┓
┃ code        ┃ name         ┃ kind  ┃ last check ┃ healthy      ┃ description ┃
┡━━━━━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━━━━━┩
│ playground  │ The          │ http  │ -          │ never        │ -           │
│             │ playground   │       │            │ checked      │             │
│ team-alerts │ Station      │ slack │ -          │ never        │ -           │
│             │ alerts       │       │            │ checked      │             │
└─────────────┴──────────────┴───────┴────────────┴──────────────┴─────────────┘
```

`set-secret` prompts, so it refuses where nobody is at a terminal
(`cli.cannot_prompt_secret`). `verify.sh` therefore sends the same update through the API as
the admin, `PATCH /api/v1/connections/team-alerts` with the whole config, and first proves that
the agent's own token is refused the same request with a 403: supplying a secret is an admin's,
whichever way it is asked. Editing the connection on the Connections screen is the third way.

## What verify.sh asserts

- `/mcp` opens a session under the operator token, and `tools/list` offers `create_connection`,
  `edit_pipeline`, `run_pipeline` and `get_run_report` and none of the admin's tools;
  `whoami` is `agent`, `operator`, token `mcp`.
- `create_connection` stores the playground complete, refuses a `bot_token` as
  `server.secrets_need_admin`, and stores `team-alerts` awaiting `bot_token` with the
  `set-secret` command in its answer.
- `edit_pipeline` refuses an edit that does not occur, plans the real edits as an update with
  `plan_only`, then applies them as a new version.
- The run the agent starts succeeds, is triggered by `agent (token mcp)`, and its report starts
  `# oslo-blindern` and names the station the playground read back through the connection.
- `dg connection set-secret` refuses without a terminal, the operator's PATCH is a 403, the
  admin's completes the connection, and `dg connection show` reads `awaiting_secrets: false`
  with the token redacted.

Each run starts the agent from the same place: the file is applied again, the account is kept,
a new token is minted, and the two connections an earlier run left are deleted first.

## Where next

- [echo-read](../echo-read) is the same playground call written by a person, one step at a time.
- [Agents](https://winterop-com.github.io/dirigent/agents/) lists every MCP tool, what each role
  is offered, and how to run the MCP server as a process of its own.
