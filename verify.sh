#!/usr/bin/env bash
# Run this example end to end and fail if anything about it has moved.
#
# A trigger only exists on an instance, so this one starts its own `dg dev`, applies the
# document, waits for the clock to fire, POSTs the webhook, and stops the instance again.
# .dirigent/state survives between runs by design, so running this twice passes twice.
set -euo pipefail

cd "$(dirname "$0")"

uv sync --quiet

uv run dg validate pipelines/echo-schedule.yaml

# The pipeline itself needs neither trigger, so prove it runs before anything is applied.
uv run dg run --local pipelines/echo-schedule.yaml --json \
  | jq -e -s '(map(select(.kind == "run" and has("exit_code"))) | last).message == "succeeded"' \
    >/dev/null

# --- the instance ----------------------------------------------------------------------
#
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
trap 'kill "$dev" 2>/dev/null || true; wait "$dev" 2>/dev/null || true; rm -f "$log"' EXIT

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

# --- the clock -------------------------------------------------------------------------
#
# Runs come back newest first, so the newest schedule-triggered run is the yardstick: wait
# until it is a different run than the one that was newest before the wait started. A count
# would saturate against the page size once enough verifications have run.
newest_scheduled() {
  uv run dg runs list --pipeline echo-schedule --limit 20 --json \
    | jq -rs '[.[] | select(.fields.triggered_by_kind == "schedule") | .fields.id] | (first // "")'
}

before=$(newest_scheduled)
landed=""
for _ in $(seq 40); do
  landed=$(newest_scheduled)
  [ -n "$landed" ] && [ "$landed" != "$before" ] && break
  sleep 5
done
[ -n "$landed" ] && [ "$landed" != "$before" ] || {
  echo "no scheduled run landed within 200s" >&2
  exit 1
}

# The schedule pins its own parameters over the pipeline's defaults, which is the whole
# reason a second schedule is a schedule rather than a second pipeline.
uv run dg runs show "$landed" --json | jq -e -s '
  .[0].fields.run as $run
  | $run.status == "succeeded"
    and $run.triggered_by_kind == "schedule"
    and $run.params.station == "oslo-blindern"
    and $run.params.reading == "3.1"
' >/dev/null

echo "echo-schedule: the clock fired ${landed}, pinned to oslo-blindern"

# --- the webhook -----------------------------------------------------------------------
#
# An instance holds a hook's token and hands it back exactly once, when it is minted. There
# is no command that reads an existing one, so a script that has to POST rotates it and
# uses what rotation returns -- which also invalidates the token the last verification used.
hook=$(uv run dg webhook rotate-token echo-schedule upstream-reading --json | jq -r '.url')

accepted=$(curl -sf -X POST "$hook" \
  -H 'content-type: application/json' \
  -d '{"station": {"code": "tromso-langnes", "reading": "-6.8"}, "sender": "ignored"}')

echo "$accepted" | jq -e '.outcome == "accepted"' >/dev/null
delivered=$(echo "$accepted" | jq -r '.run_id')

for _ in $(seq 30); do
  status=$(uv run dg runs show "$delivered" --json | jq -rs '.[0].fields.run.status')
  case "$status" in succeeded | failed | completed_with_errors | cancelled) break ;; esac
  sleep 2
done

# The mapping put two payload fields onto two parameters and ignored the third thing the
# POST carried, because nothing in the mapping names it.
uv run dg runs show "$delivered" --json | jq -e -s '
  .[0].fields.run as $run
  | $run.status == "succeeded"
    and $run.triggered_by_kind == "webhook"
    and $run.params.station == "tromso-langnes"
    and $run.params.reading == "-6.8"
    and ($run.params | has("sender") | not)
' >/dev/null

echo "echo-schedule: the webhook started ${delivered}, mapped to tromso-langnes"
