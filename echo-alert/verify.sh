#!/usr/bin/env bash
# Run this example end to end and fail if anything about it has moved.
#
# An alert rule is a record the instance holds, so this one starts its own `dg dev`, writes
# the connection and two rules, fails a run on purpose, waits for both notifications to be
# delivered, reads the log rule's line out of dg dev's own log file, reads the runs summary and
# the audit trail, and stops the instance again. .dirigent/state survives between runs by design,
# so running this twice passes twice.
#
# The document reaches nothing, and the sink the notification is POSTed to is the instance's
# own playground, so the whole of this script passes with no network at all.
set -euo pipefail

cd "$(dirname "$0")"

uv sync --quiet

uv run dg validate pipelines/echo-alert.yaml

dev_pid=
records=$(mktemp)
log=$(mktemp)

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

# Whatever this script started is stopped by its pid, however this script ends -- never by
# name: a pattern matching `dg dev` matches the shell running this script too. The
# instance's wrapper has its children taken first: killing `uv run` alone leaves the dg dev
# under it on the port.
cleanup() {
  if [ -n "$dev_pid" ]; then
    pkill -TERM -P "$dev_pid" 2>/dev/null || true
    kill -TERM "$dev_pid" 2>/dev/null || true
    wait "$dev_pid" 2>/dev/null || true
  fi
  port_clear "${port:-}"
  rm -f "$records" "$log"
}
trap cleanup EXIT

# Any port nothing is listening on, so two verifications never collide and neither takes
# 3333 from a dg dev somebody is watching.
free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# --- the failure, without a server at all -------------------------------------------------
#
# The pipeline fails by design, so dg exits non-zero and the run record is what is read.
uv run dg run --local pipelines/echo-alert.yaml --json >"$records" || true
jq -e -s '
  (map(select(.kind == "run" and has("exit_code"))) | last) as $run
  | ($run.steps | map({key: .step, value: .}) | from_entries) as $step
  | $run.message == "failed"
    and $step.ask.status == "succeeded"
    and $step.publish.status == "failed"
    and $step.note.status == "skipped"
    and ($run.failures | map(.error_class)) == ["transient", "transient"]
    and ($run.failures | map(.attempt)) == [1, 2]
' "$records" >/dev/null

# --- the instance ----------------------------------------------------------------------
#
# A connection carries a credential, so the instance will not store one until it has a key
# to seal it with. The key is minted once into .env, which is not in the repository and
# already holds this instance's token, and every command below runs in this directory and
# reads it from there: an instance that changes its key cannot read what it stored under the
# old one, and this script has to read, on its second run, the connection its first run
# stored.
if ! grep -q '^DIRIGENT_SECRET_KEY=' .env 2>/dev/null; then
  (umask 077; printf 'DIRIGENT_SECRET_KEY=%s\n' "$(uv run dg secret-key)" >> .env)
fi

port="${DG_PORT:-$(free_port)}"
export DG_URL="http://127.0.0.1:${port}"

uv run dg dev --port "$port" >"$log" 2>&1 &
dev_pid=$!

for _ in $(seq 60); do
  curl -sf "$DG_URL/health/ready" >/dev/null 2>&1 && break
  sleep 1
done
curl -sf "$DG_URL/health/ready" >/dev/null

# DG_URL beats the local profile, whose url is the default port; without it every command
# below would address an instance this script did not start. The token comes from dg dev's
# own admin: on an empty state that is the fixture admin / admin, and dg auth login
# mints a token of its own from it.
DG_TOKEN=$(uv run dg auth login --username admin --password admin --json \
  | jq -r 'select(.kind == "token.issued") | .token')
export DG_TOKEN
[ -n "$DG_TOKEN" ]

uv run dg apply

# --- the notifier, and the rule that uses it ----------------------------------------------
#
# The sink is an instance record, so pointing this example at another echo is a command
# rather than a flag. An instance refuses to delete a connection something still points at,
# which is why the rule goes first and is written again after: one leg, one sink.
#
# The rule carries no --throttle, which means no throttle: every failed run of echo-alert
# raises its own notification.
point_sink_at() {
  if uv run dg alerts rules list --json | jq -e -s 'any(.[]; .fields.code == "echo-failed")' >/dev/null; then
    uv run dg alerts rules delete echo-failed --json >/dev/null
  fi
  if uv run dg connection list --json | jq -e -s 'any(.[]; .fields.code == "echo-sink")' >/dev/null; then
    uv run dg connection delete echo-sink --json >/dev/null
  fi
  uv run dg connection create webhook echo-sink \
    --name "The alert sink" \
    --description "The instance's own playground, which answers 200 to whatever is POSTed." \
    --set url="$1" \
    --json >/dev/null
  uv run dg alerts rules create echo-failed \
    --name "Echo failures to the sink" \
    --event run_failed \
    --pipeline echo-alert \
    --connection echo-sink \
    --template '{{ pipeline.code }} run {{ run.status }}' \
    --body 'Run {{ run.id }} of {{ pipeline.code }} (version {{ pipeline.version }}) ended {{ run.status }} in {{ run.duration_ms | duration }}.' \
    --json >/dev/null
}

# The second rule names no connection, so it delivers to the process log: nothing to point
# anywhere, so it is written once and left alone on a second run.
if ! uv run dg alerts rules list --json | jq -e -s 'any(.[]; .fields.code == "echo-failed-log")' >/dev/null; then
  uv run dg alerts rules create echo-failed-log \
    --name "Echo failures to the log" \
    --event run_failed \
    --pipeline echo-alert \
    --json >/dev/null
fi

# --- the failure on the instance, and what it raises --------------------------------------
#
# The sink is this instance's own playground: unauthenticated, answers 200 to a POST, and
# reachable without anything on the public internet being involved.
sink="$DG_URL/api/v1/playground/request"
point_sink_at "$sink"

uv run dg run echo-alert --watch --json >"$records" || true
run=$(jq -rs '[.[] | select(.kind == "run") | .run_id] | first' "$records")
jq -e -s '(map(select(.kind == "run")) | last).message == "failed"' "$records" >/dev/null

# Each notification goes on a queue, is leased by a worker, and is delivered from there -- so
# it is sent a moment after the run settles rather than in the same breath. One per rule.
sent=0
for _ in $(seq 30); do
  sent=$(uv run dg alerts queue --json \
    | jq -rs --arg run "$run" '[.[] | select(.fields.run_id == $run and .fields.status == "sent")] | length')
  [ "$sent" -ge 2 ] && break
  sleep 2
done
[ "$sent" -ge 2 ] || { echo "both notifications were not delivered for run ${run}" >&2; exit 1; }

# Delivered where, and carrying what: the rule named a notifier, the notifier named a
# connection, and that connection's url is the sink. `dg alerts queue` says sent once the
# POST answered 2xx, and the subject is the rule's own template rendered against the run.
uv run dg alerts queue --json | jq -e -s --arg run "$run" '
  ([.[] | select(.fields.run_id == $run and .fields.rule == "echo-failed")] | first).fields as $n
  | $n.status == "sent"
    and $n.event == "run_failed"
    and $n.rule == "echo-failed"
    and $n.notifier == "webhook"
    and $n.connection == "echo-sink"
    and $n.attempt == 1
    and $n.subject == "echo-alert run failed"
' >/dev/null

uv run dg connection show echo-sink --json | jq -e -s --arg sink "$sink" '
  .[0].fields.config.url == $sink
' >/dev/null

# The log rule went through the log notifier, with no connection.
uv run dg alerts queue --json | jq -e -s --arg run "$run" '
  ([.[] | select(.fields.run_id == $run and .fields.rule == "echo-failed-log")] | first).fields as $n
  | $n.status == "sent" and $n.notifier == "log" and $n.connection == null
' >/dev/null

# --- the log notifier's line ----------------------------------------------------------------
#
# dg dev writes its own log as NDJSON to .dirigent/state/dev.log whatever its stdout is. The
# log notifier's line is one record under the dirigent.alert logger, and its facts are fields:
# the step that failed, the error and its code, and who started the run.
jq -e -s --arg run "$run" '
  [.[] | select(.logger == "dirigent.alert" and .run_id == $run)] | first as $line
  | $line.level == "warning"
    and $line.event_kind == "run_failed"
    and $line.pipeline == "echo-alert"
    and $line.failing_step == "publish"
    and $line.error_code == "playground.failed_on_purpose"
    and ($line.error | startswith("the playground failed attempt 1 on purpose"))
' .dirigent/state/dev.log >/dev/null

# --- the runs summary -------------------------------------------------------------------------
#
# The same document green once, so the pipeline's row counts more than one state and its
# newest run is the green one.
uv run dg run echo-alert -p fail_until=0 --watch --json >"$records"
jq -e -s '(map(select(.kind == "run")) | last).message == "succeeded"' "$records" >/dev/null

uv run dg runs summary --since 1h --pipeline echo-alert --json | jq -e -s '
  (map(select(.kind == "runs.summary")) | first) as $summary
  | ($summary.pipelines | map(select(.pipeline == "echo-alert")) | first) as $row
  | $row.latest.status == "succeeded"
    and $row.counts.failed >= 1
    and $row.counts.succeeded >= 1
    and ($row.recent | last).status == "succeeded"
    and ($row.median_duration_ms | type) == "number"
' >/dev/null

# --- the audit trail --------------------------------------------------------------------------
#
# Every change above is a row, newest first, naming the account that made it and never a value.
# This run wrote the connection and the webhook rule again; the log rule may be from an earlier
# run, so it is asked for by its code alone.
uv run dg audit --since 1h --json | jq -e -s '
  [.[] | select(.kind == "audit") | .fields] as $rows
  | ($rows | any(.action == "created" and .subject_kind == "connection" and .subject_code == "echo-sink" and .actor_username == "admin"))
    and ($rows | any(.action == "created" and .subject_kind == "alert_rule" and .subject_code == "echo-failed" and .actor_username == "admin"))
' >/dev/null
uv run dg audit --kind alert_rule --subject echo-failed-log --action created --json | jq -e -s '
  any(.[]; .kind == "audit" and .fields.subject_code == "echo-failed-log" and .fields.actor_username == "admin")
' >/dev/null

echo "echo-alert: run ${run} failed, its alerts reached ${sink} and the log, and the summary and audit trail say so"
