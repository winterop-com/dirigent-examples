#!/usr/bin/env bash
# Run this example end to end and assert on the records, never on the rendering: a table is
# what a terminal makes of a record, and this script has no terminal.
#
# One of the runs below fails on purpose, so its non-zero exit is the expected outcome and what is
# asserted is which step failed and which step never ran at all.
#
# Every run is made once per echo: the real service the documents default to, and the stand-in in
# ../local-echo, which the base_url parameter points them at. The stand-in answers a POST with the
# body it was given, as the real service does, so the same assertions hold against either.
# VERIFY_OFFLINE=1 leaves the online leg out, so the whole of this script passes with no network.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

uv sync

for document in echo-send-before.yaml pipelines/echo-send.yaml; do
  uv run dg validate "$document"
done

echo_server=../local-echo/echo_server.py
echo_pid=
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
  if [ -n "$echo_pid" ]; then
    kill -TERM "$echo_pid" 2>/dev/null || true
    wait "$echo_pid" 2>/dev/null || true
  fi
  port_clear "${port:-}"
  port_clear "${echo_port:-}"
}
trap cleanup EXIT

# Any port nothing is listening on: several instances share this machine, and two of them on one
# port is two of them failing.
free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# The echoes to run against. The empty base is the documents' own default, which is the real
# service; the other is the stand-in, started here when it is beside this repository.
bases=()
legs=
if [ -z "${VERIFY_OFFLINE:-}" ]; then
  bases+=("")
  legs="postman-echo.com"
fi
if [ -f "$echo_server" ]; then
  echo_port=$(free_port)
  python3 "$echo_server" --port "$echo_port" > /dev/null 2>&1 &
  echo_pid=$!
  if ! curl -fs --retry 60 --retry-delay 1 --retry-connrefused --retry-all-errors \
       "http://127.0.0.1:$echo_port/get" > /dev/null; then
    echo "local-echo on port $echo_port never answered /get" >&2
    exit 1
  fi
  bases+=("http://127.0.0.1:$echo_port")
  legs="${legs:+$legs and }local-echo"
fi
if [ "${#bases[@]}" -eq 0 ]; then
  echo "VERIFY_OFFLINE=1 needs $echo_server, and it is not there" >&2
  exit 1
fi

# Seeded with the flag every leg passes, because an empty array is not something every bash will
# expand under set -u.
base_flags() {
  flags=(--json)
  if [ -n "$1" ]; then
    flags+=(-p "base_url=$1")
  fi
}

# 1. Without a server. A local run starts on an empty throwaway instance, so the schema the
# document requires is handed over rather than looked up.
for base in "${bases[@]}"; do
  base_flags "$base"
  records=$(uv run dg run --local pipelines/echo-send.yaml --schema schemas/echo-answer.json "${flags[@]}")
  printf '%s\n' "$records" | jq -e -s '
    (map(select(.kind == "run")) | last) as $run
    | $run.message == "succeeded"
      and ($run.steps | length) == 3
      and ($run.steps | all(.status == "succeeded"))
  ' > /dev/null

  # An echo answers a POST with the body it was given, so its answer is the proof of what the
  # send carried out of the gate. The url it answers with is the proof of where it was sent.
  printf '%s\n' "$records" | jq -e -s --arg base "${base:-https://postman-echo.com}" '
    (map(select(.kind == "run")) | last).steps
    | map(select(.step == "send"))
    | all(.output.body.json.station == "bergen-florida"
          and .output.body.json.reading == "12.4"
          and (.output.body.url | startswith($base + "/post")))
  ' > /dev/null
done

# 2. Against an instance this script starts and stops.
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

# DG_URL beats the local profile, whose url is the default port; without it every command below
# would address an instance this script did not start. The token comes from dg dev's own admin:
# on an empty state that is the fixture dev / dirigent-dev, and dg auth login mints a token from
# it.
export DG_URL="http://127.0.0.1:$port"
token=$(uv run dg auth login --username dev --password dirigent-dev --json \
  | jq -r 'select(.kind == "token.issued") | .token')
export DG_TOKEN="$token"

# dg schema create refuses a code the instance already holds, so create it only the first time.
if ! uv run dg schema show echo-answer > /dev/null 2>&1; then
  uv run dg schema create schemas/echo-answer.json
fi

# The two-step form first, so that applying the real document is a version with a step in it.
uv run dg apply echo-send-before.yaml > /dev/null

uv run dg apply --json | jq -e -s '
  map(select(.kind == "apply")) | last | .fields.plan
  | .code == "echo-send"
    and .action == "update"
    and (.diff.steps_added | index("send") != null)
' > /dev/null

for base in "${bases[@]}"; do
  base_flags "$base"

  records=$(uv run dg run echo-send --watch "${flags[@]}")
  printf '%s\n' "$records" | jq -e -s '
    (map(select(.kind == "run")) | last) as $run
    | $run.message == "succeeded"
      and $run.exit_code == 0
      and ($run.steps | all(.status == "succeeded"))
  ' > /dev/null

  run_id=$(printf '%s\n' "$records" | jq -r -s 'map(select(.kind == "run")) | last | .run_id')
  uv run dg runs show "$run_id" --json | jq -e --arg base "${base:-https://postman-echo.com}" '
    .fields.attempts[]
    | select(.step_name == "send")
    | .output.status == 200
      and .output.body.json.station == "bergen-florida"
      and .output.body.json.reading == "12.4"
      and (.output.body.url | startswith($base + "/post"))
  ' > /dev/null

  # 3. A refused gate skips what waits on it: send never ran, so it is skipped rather than failed.
  if records=$(uv run dg run echo-send --watch -p station= "${flags[@]}"); then
    echo "an empty station was meant to be refused at the gate" >&2
    exit 1
  fi
  printf '%s\n' "$records" | jq -e -s '
    (map(select(.kind == "run")) | last) as $run
    | $run.message == "failed"
      and ($run.steps | map(select(.step == "check")) | all(.status == "failed"))
      and ($run.steps | map(select(.step == "send")) | all(.status == "skipped"))
  ' > /dev/null
done

echo "echo-send: documents valid, the send carried the gate's values through, a refused gate skipped the send, against $legs"
