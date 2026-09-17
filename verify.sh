#!/usr/bin/env bash
# Run this example end to end and fail if anything about it has moved.
#
# An alert rule is a record the instance holds, so this one starts its own `dg dev`, mints
# the connection and the rule if they are not there yet, fails a run on purpose, waits for
# the notification to be delivered to Postman Echo, and stops the instance again.
# .dirigent/state survives between runs by design, so running this twice passes twice.
set -euo pipefail

cd "$(dirname "$0")"

uv sync --quiet

uv run dg validate pipelines/echo-alert.yaml

records=$(mktemp)

# The pipeline fails by design, so dg exits non-zero and the run record is what is read.
uv run dg run --local pipelines/echo-alert.yaml --json >"$records" || true
jq -e -s '
  (map(select(.kind == "run" and has("exit_code"))) | last) as $run
  | ($run.steps | map({key: .step, value: .}) | from_entries) as $step
  | $run.message == "failed"
    and $step.ask.status == "succeeded"
    and $step.publish.status == "failed"
    and $step.note.status == "skipped"
    and ($run.failures | map(.error_class)) == ["rejected"]
' "$records" >/dev/null

# --- the instance ----------------------------------------------------------------------
#
# A connection carries a credential, so the instance will not store one until it has a key
# to seal it with. The key is minted once and kept, because an instance that changes its
# key cannot read what it stored under the old one -- and this script has to read, on its
# second run, the connection its first run stored.
if [ ! -f .secret-key ]; then
  (umask 077; uv run dg secret-key >.secret-key)
fi
export DIRIGENT_SECRET_KEY="$(cat .secret-key)"

# A port of this script's own, so two verifications never collide and neither takes 3333
# from a dg dev somebody is watching. DG_URL has to name the same port: --port moves the
# server, and the `local` profile dg init wrote still says 3333.
port="${DG_PORT:-$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')}"
export DG_URL="http://127.0.0.1:${port}"

log=$(mktemp)
uv run dg dev --port "$port" >"$log" 2>&1 &
dev=$!
# Stop what this script started, by pid, on whatever it exits on -- never by name: a
# pattern matching `dg dev` matches the shell running this script too.
trap 'kill "$dev" 2>/dev/null || true; wait "$dev" 2>/dev/null || true; rm -f "$log" "$records"' EXIT

for _ in $(seq 60); do
  curl -sf "$DG_URL/health/ready" >/dev/null 2>&1 && break
  sleep 1
done
curl -sf "$DG_URL/health/ready" >/dev/null

# dg init minted this instance's first token and wrote it into .env, where the `local`
# profile reads it. A clone has neither -- no .env, and no instance either -- so dg dev made
# one just now and minted a token into its starting record, once. Whichever it is, it is
# exported here: the CLI reads --url/--token first, then DG_URL/DG_TOKEN, then a profile.
if [ -z "${DG_TOKEN:-}" ] && [ -f .env ]; then
  DG_TOKEN=$(sed -n 's/^DG_TOKEN=//p' .env | head -1)
fi
if [ -z "${DG_TOKEN:-}" ]; then
  DG_TOKEN=$(jq -r 'select(.kind == "process") | .token // empty' "$log" | head -1)
  if [ -n "$DG_TOKEN" ]; then (umask 077; printf 'DG_TOKEN=%s\n' "$DG_TOKEN" >.env); fi
fi
[ -n "${DG_TOKEN:-}" ] || { echo "no token in .env and none minted at startup" >&2; exit 1; }
export DG_TOKEN

uv run dg apply

# --- the channel, and the rule that uses it ----------------------------------------------
#
# Both are made once and kept, so each is created only where it is missing: creating one
# that exists is refused, which is the right answer for a command a person types and the
# wrong one for a script run twice.
if ! uv run dg connection list --json | jq -e -s 'any(.[]; .fields.code == "echo-sink")' >/dev/null; then
  uv run dg connection create webhook echo-sink \
    --name "The alert sink" \
    --description "Postman Echo's /post, which answers with whatever was POSTed to it." \
    --set url=https://postman-echo.com/post
fi

# No --throttle, which means no throttle: every failed run of echo-alert raises its own
# notification. A rule with one would suppress the second verification's alert.
if ! uv run dg alerts rules list --json | jq -e -s 'any(.[]; .fields.code == "echo-failed")' >/dev/null; then
  uv run dg alerts rules create echo-failed \
    --name "Echo failures to the sink" \
    --event run_failed \
    --pipeline echo-alert \
    --notifier webhook \
    --connection echo-sink \
    --template '{{ pipeline.code }} run {{ run.status }}' \
    --body 'Run {{ run.id }} of {{ pipeline.code }} (version {{ pipeline.version }}) ended {{ run.status }} in {{ run.duration_ms | duration }}.'
fi

# --- the failure, and what it raises -----------------------------------------------------
uv run dg run echo-alert --watch --json >"$records" || true
run=$(jq -rs '[.[] | select(.kind == "run") | .run_id] | first' "$records")
jq -e -s '(map(select(.kind == "run")) | last).message == "failed"' "$records" >/dev/null

# The notification goes on a queue, is leased by a worker, and is POSTed from there -- so
# it is delivered a moment after the run settles rather than in the same breath.
sent=""
for _ in $(seq 30); do
  sent=$(uv run dg alerts queue --json \
    | jq -rs --arg run "$run" '[.[] | select(.fields.run_id == $run and .fields.status == "sent") | .fields.id] | (first // "")')
  [ -n "$sent" ] && break
  sleep 2
done
[ -n "$sent" ] || { echo "no notification was delivered for run ${run}" >&2; exit 1; }

# Delivered where: the rule named a channel, the channel named a connection, and that
# connection's url is the sink. `dg alerts queue` says sent once the POST answered 2xx.
uv run dg alerts queue --json | jq -e -s --arg run "$run" '
  ([.[] | select(.fields.run_id == $run)] | first).fields as $n
  | $n.status == "sent"
    and $n.event == "run_failed"
    and $n.rule == "echo-failed"
    and $n.notifier == "webhook"
    and $n.connection == "echo-sink"
    and $n.attempt == 1
' >/dev/null

uv run dg connection show echo-sink --json | jq -e -s '
  .[0].fields.config.url == "https://postman-echo.com/post"
' >/dev/null

echo "echo-alert: run ${run} failed, and its alert reached https://postman-echo.com/post"
