#!/usr/bin/env bash
# Run this example end to end and assert on the records, never on the rendering: a table is
# what a terminal makes of a record, and this script has no terminal.
#
# Every assertion is made once per echo: the real service the document defaults to, and the
# stand-in in ../local-echo, which the base_url parameter points the document at. VERIFY_OFFLINE=1
# leaves the online leg out, so the whole of this script passes with no network at all.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

uv sync

uv run dg validate pipelines/echo-read.yaml

echo_server=../local-echo/echo_server.py
echo_pid=
dev_pid=

# Whatever this script started is stopped by its pid, however this script ends.
cleanup() {
  if [ -n "$dev_pid" ]; then
    kill "$dev_pid" 2>/dev/null || true
    wait "$dev_pid" 2>/dev/null || true
  fi
  if [ -n "$echo_pid" ]; then
    kill "$echo_pid" 2>/dev/null || true
    wait "$echo_pid" 2>/dev/null || true
  fi
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

# The echoes to run against. The empty base is the document's own default, which is the real
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

# 1. Without a server at all.
for base in "${bases[@]}"; do
  base_flags "$base"
  flags+=(-p station=oslo-blindern)
  uv run dg run --local pipelines/echo-read.yaml "${flags[@]}" | assert_succeeded
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

# Applying an unchanged document again is not a new version, so this passes on every run.
uv run dg apply

for base in "${bases[@]}"; do
  base_flags "$base"
  records=$(uv run dg run echo-read --watch "${flags[@]}")
  printf '%s\n' "$records" | assert_succeeded

  # The answer itself is in the run rather than on the screen, so read it back out of the run.
  # The url it carries is the proof that base_url reached the call and not only the document.
  run_id=$(printf '%s\n' "$records" | jq -r -s 'map(select(.kind == "run")) | last | .run_id')
  uv run dg runs show "$run_id" --json | jq -e --arg base "${base:-https://postman-echo.com}" '
    .fields.attempts[]
    | select(.step_name == "ask")
    | .output.status == 200
      and .output.body.args.station == "bergen-florida"
      and .output.body.args.reading == "12.4"
      and (.output.body.url | startswith($base + "/get"))
  ' > /dev/null
done

echo "echo-read: document valid, local run succeeded, instance run succeeded, answer read back, against $legs"
