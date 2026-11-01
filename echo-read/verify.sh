#!/usr/bin/env bash
# Run this example end to end and assert on the records, never on the rendering: a table is
# what a terminal makes of a record, and this script has no terminal.
#
# The document calls the playground, which an instance serves under /api/v1/playground, so the
# instance is started first and both runs below are pointed at it. A --local run mounts no API
# of its own, which is why even that leg needs the instance this script starts.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

uv sync

uv run dg validate pipelines/echo-read.yaml

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
}
trap cleanup EXIT

# Any port nothing is listening on: several instances share this machine, and two of them on one
# port is two of them failing.
free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

assert_succeeded() {
  jq -e -s '
    (map(select(.kind == "run")) | last) as $run
    | $run.message == "succeeded"
      and $run.exit_code == 0
      and ($run.steps | all(.status == "succeeded"))
  ' > /dev/null
}

# The instance, which is both what the runs are stored on and what answers them.
port="${DG_PORT:-$(free_port)}"
devlog=$(mktemp)
uv run dg dev --port "$port" > "$devlog" 2>&1 &
dev_pid=$!

# --retry-all-errors covers the moment between the socket opening and the instance answering.
if ! curl -fs --retry 60 --retry-delay 1 --retry-connrefused --retry-all-errors \
     "http://127.0.0.1:$port/health" > /dev/null; then
  echo "the instance on port $port never answered /health" >&2
  exit 1
fi

# The port is chosen here rather than in the document, so every run below is handed it.
playground="http://127.0.0.1:$port/api/v1/playground"

# 1. Without a server of its own. The playground it calls is still the instance above.
uv run dg run --local pipelines/echo-read.yaml --json \
  -p "playground=$playground" -p station=oslo-blindern | assert_succeeded

# 2. Against the instance, as a stored pipeline.
#
# DG_URL beats the local profile, whose url is the default port; without it every command below
# would address an instance this script did not start. The token comes from dg dev's own admin:
# on an empty state that is the fixture admin / admin, and dg auth login mints a token from
# it.
export DG_URL="http://127.0.0.1:$port"
token=$(uv run dg auth login --username admin --password admin --json \
  | jq -r 'select(.kind == "token.issued") | .token')
export DG_TOKEN="$token"

# Applying an unchanged document again is not a new version, so this passes on every run.
uv run dg apply

records=$(uv run dg run echo-read --watch --json -p "playground=$playground")
printf '%s\n' "$records" | assert_succeeded

# The answer itself is in the run rather than on the screen, so read it back out of the run.
# Every playground answer carries what arrived under `request`, so the arguments there are the
# proof of what was asked and the url is the proof that the parameter reached the call.
run_id=$(printf '%s\n' "$records" | jq -r -s 'map(select(.kind == "run")) | last | .run_id')
uv run dg runs show "$run_id" --json | jq -e --arg pg "$playground" '
  .fields.attempts[]
  | select(.step_name == "ask")
  | .output.status == 200
    and .output.body.kind == "request"
    and .output.body.request.args.station == "bergen-florida"
    and .output.body.request.args.reading == "12.4"
    and (.output.body.request.url | startswith($pg + "/request"))
' > /dev/null

echo "echo-read: document valid, local run succeeded, instance run succeeded, answer read back from the playground"
