#!/usr/bin/env bash
# Run this example end to end and assert on the records, never on the rendering: a table is
# what a terminal makes of a record, and this script has no terminal.
#
# This document fails on purpose -- both its steps fail -- so a non-zero exit is the expected
# outcome, and what is asserted is how many attempts each step was given and under which class.
#
# Every run is made once per echo: the real service the document defaults to, and the stand-in in
# ../local-echo, which the base_url parameter points it at. The stand-in answers /status/<code>
# with that status, so a 404 is classified rejected and a 503 transient against either of them.
# VERIFY_OFFLINE=1 leaves the online leg out, so the whole of this script passes with no network.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

uv sync

uv run dg validate pipelines/echo-retry.yaml

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

# The failures array carries one entry per attempt, with the class the block decided on. Same
# budget, one attempt against three: that is the whole lesson, asserted.
assert_two_classes() {
  jq -e -s '
    (map(select(.kind == "run")) | last) as $run
    | $run.message == "failed"
      and $run.exit_code == 1
      and ([$run.failures[] | select(.step == "refused")]
           | length == 1 and all(.error_class == "rejected"))
      and ([$run.failures[] | select(.step == "unlucky")]
           | length == 3 and all(.error_class == "transient")
           and ([.[].attempt] == [1, 2, 3]))
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

# 1. Without a server.
for base in "${bases[@]}"; do
  base_flags "$base"
  if records=$(uv run dg run --local pipelines/echo-retry.yaml "${flags[@]}"); then
    echo "echo-retry was meant to fail: both of its steps fail by design" >&2
    exit 1
  fi
  printf '%s\n' "$records" | assert_two_classes
  printf '%s\n' "$records" | jq -e -s --arg base "${base:-https://postman-echo.com}" '
    (map(select(.kind == "run")) | last).failures
    | all(.error | startswith("GET " + $base + "/status/"))
  ' > /dev/null
done

# 2. Against an instance this script starts and stops, where every attempt is a row of its own.
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
  if records=$(uv run dg run echo-retry --watch "${flags[@]}"); then
    echo "echo-retry was meant to fail on the instance too" >&2
    exit 1
  fi
  printf '%s\n' "$records" | assert_two_classes

  # An attempt is a row of its own, which is what makes a retry auditable rather than a counter.
  run_id=$(printf '%s\n' "$records" | jq -r -s 'map(select(.kind == "run")) | last | .run_id')
  uv run dg runs show "$run_id" --json | jq -e '
    [.fields.attempts[] | {step: .step_name, attempt: .attempt, class: .error_class}]
    | . == [
        {step: "refused", attempt: 1, class: "rejected"},
        {step: "unlucky", attempt: 1, class: "transient"},
        {step: "unlucky", attempt: 2, class: "transient"},
        {step: "unlucky", attempt: 3, class: "transient"}
      ]
  ' > /dev/null
done

echo "echo-retry: document valid, the refusal took one attempt of three, the outage took all three, against $legs"
