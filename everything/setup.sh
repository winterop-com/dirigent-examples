#!/usr/bin/env bash
# Take this project from a fresh clone to an instance at http://127.0.0.1:4444 holding every
# pipeline, schema and connection, without asking anything.
#
#   ./setup.sh          the S3 container, the instance, the connections, the schemas, the apply
#   ./setup.sh stop     stop the instance and the S3 container this script started
#
# The instance is the project's own .dirigent/state, so what setup.sh leaves is what a
# `uv run dg dev` in this directory serves. An instance already answering on the port is used
# rather than started, provided it is serving this directory: start `uv run dg dev` in a
# second terminal first to watch its log, and this script fills it.
#
# Needs docker, uv, jq, curl, and the network for the DHIS2 play demos.
set -euo pipefail
trap 'echo "setup.sh: failed at line $LINENO" >&2' ERR

cd "$(dirname "${BASH_SOURCE[0]}")"
here="$(pwd -P)"
# shellcheck source=bootstrap.sh
source ./bootstrap.sh

PORT="${DG_PORT:-4444}"
S3_PORT="${S3_PORT:-9000}"
S3_NAME=everything-s3
SERVICES=everything-services
STATE=.dirigent/state
PIDFILE="$STATE/dev.pid"
LOG="$STATE/dev.log"
export DG_URL="http://127.0.0.1:$PORT"

say() { printf '== %s\n' "$1"; }

if [ "${1:-}" = stop ]; then
  if [ -f "$PIDFILE" ]; then
    stop_pid "$(cat "$PIDFILE")"
    rm -f "$PIDFILE"
    port_clear "$PORT"
    say "stopped the instance on $DG_URL"
  fi
  docker rm -f "$S3_NAME" > /dev/null 2>&1 && say "stopped $S3_NAME"
  services_stop "$SERVICES" && say "stopped $SERVICES"
  exit 0
fi

say "the project's own environment"
uv sync --quiet

# The key every connection's secret is sealed with. Minted once into .env, which is never
# committed, and read from there by every dg command run in this directory.
mkdir -p "$STATE"
if ! grep -q '^DIRIGENT_SECRET_KEY=' .env 2>/dev/null; then
  (umask 077; printf 'DIRIGENT_SECRET_KEY=%s\n' "$(uv run dg secret-key)" >> .env)
fi

say "the S3 server, as $S3_NAME on port $S3_PORT"
s3_start "$S3_NAME" "$S3_PORT"

say "the brokers and the warehouse, as the compose project $SERVICES"
services_start "$SERVICES"

say "the connections, sealed into $STATE"
seal_connections "$S3_PORT"
seal_service_connections

say "the buckets ${BUCKETS[*]}"
make_bucket

# Something on the port is either this directory's own dg dev, which is used, or another
# instance, which is refused: the connections above went into this directory's state.
holder="$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | head -1 || true)"
if [ -n "$holder" ]; then
  cwd="$(lsof -a -p "$holder" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
  if [ "$cwd" != "$here" ]; then
    echo "port $PORT is held by pid $holder, serving ${cwd:-somewhere else}, not $here." >&2
    echo "stop it, or run DG_PORT=<another port> ./setup.sh" >&2
    exit 1
  fi
  say "the instance already running on $DG_URL"
else
  say "the instance, on $DG_URL, logging to $LOG"
  nohup uv run dg dev --port "$PORT" > "$LOG" 2>&1 < /dev/null &
  echo $! > "$PIDFILE"
  disown
fi
wait_ready "$DG_URL"

# A token for the development admin dg dev made on the empty state, kept in .env, where the
# local profile reads it when the shell does not export one.
DG_TOKEN="$(login)"
[ -n "$DG_TOKEN" ] || { echo "dg auth login issued no token" >&2; exit 1; }
export DG_TOKEN
grep -v '^DG_TOKEN=' .env > .env.new || true
(umask 077; printf 'DG_TOKEN=%s\n' "$DG_TOKEN" >> .env.new)
mv .env.new .env

say "every connection, checked"
check_connections

say "the schemas"
ensure_schemas

say "echo-alert's sink, which its document's rule names"
ensure_alert

say "every document under pipelines/, applied"
apply_all "$STATE/seed.ndjson"
jq -r -s '
  (map(select(.kind == "seed.done")) | last) as $done
  | "   \($done.pipelines) applied, \($done.refused) refused; the refusals are in '"$STATE"'/seed.ndjson"
' "$STATE/seed.ndjson"

say "the pipelines on the instance"
uv run dg pipeline list --json | jq -r -s '[.[] | select(.kind == "pipeline") | .fields.code] | sort | join(" ")' \
  | { read -r codes; echo "   $codes"; }

cat <<EOF

Ready: $DG_URL, logged in as admin / admin.
In this directory, dg reads the token from .env; a shell exporting another DG_TOKEN wins, so:

  unset DG_TOKEN DG_URL
  uv run dg run echo-hello --watch

./setup.sh stop stops the instance and the S3 container.
EOF
