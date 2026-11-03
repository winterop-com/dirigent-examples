#!/usr/bin/env bash
# Run this example end to end and assert on what the instance answers, never on a rendering.
#
# The agent here is curl: every call it makes is the JSON-RPC an MCP client sends to the
# instance's /mcp, under the operator token the README mints for it, so no model is needed to
# prove what a model would be allowed to do. The admin's half goes through dg and the API.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

uv sync --quiet

uv run dg validate pipelines/station-report.yaml --json > /dev/null

# Somewhere to keep the answers this script asserts on, removed on the way out.
WORK="$(mktemp -d)"

dev_pid=

# Nothing this script started may still be listening when it returns: a dg dev that outlived
# its wrapper shares .dirigent/state with the next run, claims its steps and fails them.
port_clear() {
  local p="${1:-}" holding
  [ -n "$p" ] || return 0
  for _ in 1 2 3 4 5; do
    holding="$(lsof -nP -iTCP:"$p" -sTCP:LISTEN -t 2>/dev/null || true)"
    [ -n "$holding" ] || return 0
    sleep 0.4
  done
  kill -KILL $holding 2>/dev/null || true
}

# Whatever this script started is stopped by its pid, however this script ends. The
# instance's wrapper has its children taken first: killing `uv run` alone leaves the dg dev
# under it on the port.
cleanup() {
  if [ -n "$dev_pid" ]; then
    pkill -TERM -P "$dev_pid" 2>/dev/null || true
    kill -TERM "$dev_pid" 2>/dev/null || true
    wait "$dev_pid" 2>/dev/null || true
  fi
  port_clear "${port:-}"
  rm -rf "$WORK"
}
trap cleanup EXIT

# Any port nothing is listening on: several instances share this machine, and two of them on one
# port is two of them failing.
free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# A connection's secret is sealed with the instance's own key, so the key exists before the
# admin supplies one. It is minted once into .env, which is not in the repository, and every
# command run in this directory reads it from there.
if ! grep -q '^DIRIGENT_SECRET_KEY=' .env 2>/dev/null; then
  (umask 077; printf 'DIRIGENT_SECRET_KEY=%s\n' "$(uv run dg secret-key)" >> .env)
fi

port="${DG_PORT:-$(free_port)}"
uv run dg dev --port "$port" > "$WORK/dev.ndjson" 2>&1 &
dev_pid=$!

# --retry-all-errors covers the moment between the socket opening and the instance answering.
if ! curl -fs --retry 60 --retry-delay 1 --retry-connrefused --retry-all-errors \
     "http://127.0.0.1:$port/health" > /dev/null; then
  echo "the instance on port $port never answered /health" >&2
  exit 1
fi

# DG_URL beats the local profile, whose url is the default port. The admin's token comes from
# dg dev's own admin, admin / admin on an empty state.
export DG_URL="http://127.0.0.1:$port"
DG_TOKEN=$(uv run dg auth login --username admin --password admin --json \
  | jq -r 'select(.kind == "token.issued") | .token')
export DG_TOKEN
[ -n "$DG_TOKEN" ]

# 1. The admin's half: the pipeline as the file says it, and an operator account for the agent.
#
# Applying the file again stores it as a new version whenever the agent's edit is the current
# one, so every run of this script starts the agent on the same text.
uv run dg apply --json > /dev/null

if ! uv run dg admin user list --json | jq -e 'select(.fields.username == "agent")' > /dev/null; then
  # The agent authenticates with the token below and never with this password.
  uv run dg admin user create agent --role operator --password "agent-$(openssl rand -hex 8)" --json > /dev/null
fi

# The token is answered once, in the record that minted it; it lives in this shell and nowhere
# on disk, as DG_MCP_TOKEN does in the README.
DG_MCP_TOKEN=$(uv run dg admin token create mcp --user agent --json | jq -r 'select(.token).token')
[ -n "$DG_MCP_TOKEN" ]

# What the agent creates below is created on every run, so what an earlier run left is removed
# first. Deleting is an admin's.
for code in team-alerts playground; do
  if uv run dg connection list --json | jq -e --arg c "$code" 'select(.fields.code == $c)' > /dev/null; then
    uv run dg connection delete "$code" --json > /dev/null
  fi
done

# 2. The agent's half, over MCP.
#
# Streamable HTTP: a POST to /mcp carries one JSON-RPC message, and the answer comes back as a
# server-sent event whose data line is the JSON-RPC reply. initialize opens a session, whose id
# arrives in the Mcp-Session-Id header and goes on every later call.
mcp_post() {
  curl -s -D "$WORK/headers" -X POST "$DG_URL/mcp" \
    -H "Authorization: Bearer $DG_MCP_TOKEN" \
    -H 'Accept: application/json, text/event-stream' \
    -H 'Content-Type: application/json' \
    ${mcp_session:+-H "Mcp-Session-Id: $mcp_session"} \
    -d "$1" | sed -n 's/^data: //p'
}

mcp_id=1
mcp_call() {
  mcp_id=$((mcp_id + 1))
  mcp_post "$(jq -nc --arg m "$1" --argjson p "$2" --argjson id "$mcp_id" \
    '{jsonrpc: "2.0", id: $id, method: $m, params: $p}')"
}

# A tool's answer is JSON in its first text content; a refusal sets isError and says why in
# the same place.
mcp_tool() {
  mcp_call tools/call "$(jq -nc --arg n "$1" --argjson a "$2" '{name: $n, arguments: $a}')"
}

mcp_session=
mcp_post '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"agent-over-mcp verify","version":"0"}}}' \
  > "$WORK/initialize.json"
jq -e '.result.serverInfo.name == "dirigent"' "$WORK/initialize.json" > /dev/null
mcp_session=$(tr -d '\r' < "$WORK/headers" | awk -F': ' 'tolower($1) == "mcp-session-id" { print $2 }')
[ -n "$mcp_session" ]
mcp_post '{"jsonrpc":"2.0","method":"notifications/initialized"}' > /dev/null

# An operator is offered what an operator may do: the tools that apply, run and create a
# connection, and none that only an admin may call.
mcp_call tools/list '{}' > "$WORK/tools.json"
jq -e '
  [.result.tools[].name] as $names
  | ($names | index("create_connection")) and ($names | index("edit_pipeline"))
    and ($names | index("list_connection_kinds")) and ($names | index("get_connection_kind"))
    and ($names | index("get_run_report")) and ($names | index("run_pipeline"))
    and ($names | index("check_connection") | not) and ($names | index("create_schema") | not)
    and ($names | index("list_audit") | not)
' "$WORK/tools.json" > /dev/null

mcp_tool whoami '{}' | jq -e '
  .result.content[0].text | fromjson | .username == "agent" and .role == "operator" and .token_name == "mcp"
' > /dev/null

# Before creating anything, the agent reads what each kind takes: its required settings, its
# secret fields, and the forms a credential comes in. A secret field is one it leaves out.
mcp_tool list_connection_kinds '{}' | jq -e '
  .result.content[0].text | fromjson | .items | map({key: .id, value: .}) | from_entries
  | .http.required == ["base_url"] and (.http.secret | index("basic_password"))
    and .slack.secret == ["webhook_url", "bot_token"] and .slack.credential_required == true
' > /dev/null
mcp_tool get_connection_kind '{"kind": "slack"}' | jq -e '
  .result.content[0].text | fromjson
  | (.fields | map({key: .name, value: .}) | from_entries) as $f
  | $f.bot_token.secret == true and $f.bot_token.credential_form == "bot"
    and $f.channel.secret == false and $f.channel.credential_form == "bot"
    and (.credential_forms | map(.code)) == ["webhook", "bot"]
' > /dev/null

# A connection with nothing secret to hold is usable the moment it is created.
mcp_tool create_connection "$(jq -nc --arg u "$DG_URL/api/v1/playground" \
  '{kind: "http", code: "playground", name: "The playground", settings: {base_url: $u}}')" \
  | jq -e '.result.isError == false and (.result.content[0].text | fromjson | .connection.awaiting_secrets == false)' \
  > /dev/null

# A secret handed to the agent is refused by the field's name, and nothing is stored.
mcp_tool create_connection '{"kind": "slack", "code": "team-alerts", "settings": {"channel": "#station-alerts", "bot_token": "xoxb-in-a-transcript"}}' \
  | jq -e '.result.isError == true and (.result.content[0].text | test("server.secrets_need_admin"))' > /dev/null

# A connection that cannot work without its secret is stored awaiting it, and the answer names
# what is missing and the command an admin runs.
mcp_tool create_connection '{"kind": "slack", "code": "team-alerts", "name": "Station alerts", "settings": {"channel": "#station-alerts"}}' \
  > "$WORK/created.json"
jq -e '
  .result.isError == false
  and (.result.content[0].text | fromjson
       | .connection.awaiting_secrets == true
         and (.secrets_to_supply | index("bot_token"))
         and (.supply_with.command | endswith("connection set-secret team-alerts")))
' "$WORK/created.json" > /dev/null

# The edit is matched against the text export_pipeline answers, which is the stored version
# rendered canonically: no comments, keys in their own order. Two replacements: the step calls
# through the connection the agent just made, and the parameter that addressed it goes.
mcp_tool export_pipeline '{"code": "station-report"}' > "$WORK/exported.json"
jq -e '.result.content[0].text | fromjson | .text | contains("url: ${params.playground}/request")' \
  "$WORK/exported.json" > /dev/null

edits=$(jq -nc '{
  code: "station-report",
  edits: [
    {old: "      url: ${params.playground}/request", new: "      connection: playground\n      path: /request"},
    {old: "    playground:\n      type: string\n      description: The playground routes on the instance this calls; `dg dev` serves them here.\n      default: http://127.0.0.1:3333/api/v1/playground\n", new: ""}
  ]
}')

# An edit that does not occur refuses every edit, and nothing is stored.
mcp_tool edit_pipeline '{"code": "station-report", "edits": [{"old": "no such text", "new": "x"}]}' \
  | jq -e '.result.isError == true and (.result.content[0].text | test("does not occur"))' > /dev/null

mcp_tool edit_pipeline "$(jq -c '. + {plan_only: true}' <<< "$edits")" \
  | jq -e '.result.isError == false and (.result.content[0].text | fromjson | .dry_run == true and .plan.action == "update")' \
  > /dev/null

mcp_tool edit_pipeline "$edits" > "$WORK/edited.json"
jq -e '.result.isError == false and (.result.content[0].text | fromjson | .plan.action == "update" and .version > 1)' \
  "$WORK/edited.json" > /dev/null

# The edited pipeline, run by the agent and waited for.
mcp_tool run_pipeline '{"code": "station-report", "params": {"station": "oslo-blindern"}, "wait": true}' \
  > "$WORK/run.json"
jq -e '
  .result.content[0].text | fromjson
  | .status == "succeeded" and .triggered_by_label == "agent (token mcp)"
' "$WORK/run.json" > /dev/null
run_id=$(jq -r '.result.content[0].text | fromjson | .id' "$WORK/run.json")

# The report the run rendered when it settled: its heading is the run's own parameter, and the
# station in it is the one the playground read back through the connection.
mcp_tool get_run_report "$(jq -nc --arg r "$run_id" '{run_id: $r}')" > "$WORK/report.json"
jq -e '
  .result.content[0].text | fromjson
  | .exists == true
    and (.text | startswith("# oslo-blindern"))
    and (.text | contains("**succeeded**"))
    and (.text | contains("read back station\n`oslo-blindern`"))
' "$WORK/report.json" > /dev/null

# 3. The admin completes what the agent began.
#
# The admin reads the same description of the kind the agent read, from dg.
uv run dg connection kinds slack --json | jq -e '
  .kind == "connection_kind" and .fields.id == "slack"
  and ([.fields.fields[] | select(.secret) | .name] == ["webhook_url", "bot_token"])
' > /dev/null

# An operator may not supply a secret, whatever route it takes.
status=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH "$DG_URL/api/v1/connections/team-alerts" \
  -H "Authorization: Bearer $DG_MCP_TOKEN" -H 'Content-Type: application/json' \
  -d '{"config": {"channel": "#station-alerts", "bot_token": "xoxb-not-a-real-token"}}')
[ "$status" = 403 ]

# dg connection set-secret asks at a terminal, without echoing, and refuses where there is none.
uv run dg connection set-secret team-alerts --json < /dev/null > "$WORK/set-secret.ndjson" || true
jq -se 'map(select(.kind == "error")) | last | .code == "cli.cannot_prompt_secret"' \
  "$WORK/set-secret.ndjson" > /dev/null

# So it is given one: a pseudo-terminal that answers the one prompt set-secret puts the way the
# admin would type it. The connection already holds a channel, so set-secret has begun the bot
# form and asks for that form's bot_token alone. The answer waits a moment after the prompt:
# the terminal is switched to not echoing as it is asked, and that switch discards whatever was
# typed ahead of it.
python3 -c '
import os, pty, select, signal, sys, time

answer = sys.argv[1].encode() + b"\n"
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[2], sys.argv[2:])
said, answered = b"", False
while select.select([fd], [], [], 60)[0]:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    said += chunk
    if not answered and said.rstrip().endswith(b"bot_token:"):
        time.sleep(0.5)
        os.write(fd, answer)
        answered = True
else:
    os.kill(pid, signal.SIGKILL)
_, status = os.waitpid(pid, 0)
sys.stdout.write(said.decode(errors="replace"))
sys.exit(os.waitstatus_to_exitcode(status) or (0 if answered else 1))
' "xoxb-not-a-real-token" uv run dg connection set-secret team-alerts > "$WORK/set-secret.txt"

uv run dg connection show team-alerts --json > "$WORK/completed.ndjson"
jq -e '
  .fields.awaiting_secrets == false
    and .fields.config.bot_token == "***"
' "$WORK/completed.ndjson" > /dev/null

echo "agent-over-mcp: an operator over /mcp listed its tools, read the connection kinds, created a connection with its settings alone, edited, ran and read the report of a pipeline; the admin read the kind and completed the connection with dg connection set-secret"
