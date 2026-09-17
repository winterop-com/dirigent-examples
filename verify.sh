#!/usr/bin/env bash
# Run this example end to end and assert on the records, never on the rendering: a table is
# what a terminal makes of a record, and this script has no terminal.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

uv sync

uv run dg validate pipelines/echo-read.yaml

# 1. Without a server at all.
records=$(uv run dg run --local pipelines/echo-read.yaml -p station=oslo-blindern --json)
printf '%s\n' "$records" | jq -e -s '
  (map(select(.kind == "run")) | last) as $run
  | $run.message == "succeeded"
    and $run.exit_code == 0
    and ($run.steps | all(.status == "succeeded"))
' > /dev/null

# 2. Against an instance this script starts and stops.
#
# $DG_PORT, or any port nothing is listening on: several instances share this machine, and two
# of them on one port is two of them failing.
port="${DG_PORT:-$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')}"
devlog=$(mktemp)
uv run dg dev --port "$port" > "$devlog" 2>&1 &
dev_pid=$!
# The instance this script started is stopped by its pid, however this script ends.
trap 'kill "$dev_pid" 2>/dev/null || true; wait "$dev_pid" 2>/dev/null || true' EXIT

# --retry-all-errors covers the moment between the socket opening and the instance answering.
if ! curl -fs --retry 60 --retry-delay 1 --retry-connrefused --retry-all-errors \
     "http://127.0.0.1:$port/health" > /dev/null; then
  echo "the instance on port $port never answered /health" >&2
  exit 1
fi

# DG_URL beats the local profile, whose url is the default port; without it every command below
# would address an instance this script did not start. The token comes from dg dev's own admin:
# on an empty state that is the fixture dev / dirigent-dev, and dg auth login mints a token from
# it, which is the same token dg dev printed at startup.
export DG_URL="http://127.0.0.1:$port"
token=$(uv run dg auth login --username dev --password dirigent-dev --json \
  | jq -r 'select(.kind == "token.issued") | .token')
export DG_TOKEN="$token"

# Applying an unchanged document again is not a new version, so this passes on every run.
uv run dg apply

records=$(uv run dg run echo-read --watch --json)
printf '%s\n' "$records" | jq -e -s '
  (map(select(.kind == "run")) | last) as $run
  | $run.message == "succeeded"
    and $run.exit_code == 0
    and ($run.steps | all(.status == "succeeded"))
' > /dev/null

# The answer itself is in the run rather than on the screen, so read it back out of the run.
run_id=$(printf '%s\n' "$records" | jq -r -s 'map(select(.kind == "run")) | last | .run_id')
uv run dg runs show "$run_id" --json | jq -e '
  .fields.attempts[]
  | select(.step_name == "ask")
  | .output.status == 200
    and .output.body.args.station == "bergen-florida"
    and .output.body.args.reading == "12.4"
' > /dev/null

echo "echo-read: document valid, local run succeeded, instance run succeeded, answer read back"
