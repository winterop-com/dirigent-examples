#!/usr/bin/env bash
# Run this example end to end and assert on the records, never on the rendering: a table is
# what a terminal makes of a record, and this script has no terminal.
#
# Two of the runs below fail on purpose, so their non-zero exit is the expected outcome and what
# is asserted is the error the records carry.
#
# Every run is made once per echo: the real service the documents default to, and the stand-in in
# ../local-echo, which the base_url parameter points them at. The gate is the same gate against
# either, because the stand-in answers the shape the real service answers. VERIFY_OFFLINE=1 leaves
# the online leg out, so the whole of this script passes with no network at all.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

uv sync

for document in echo-gate-too-tight.yaml echo-gate-carried.yaml pipelines/echo-gate.yaml; do
  uv run dg validate "$document"
done

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

for base in "${bases[@]}"; do
  base_flags "$base"

  # 1. The gate refuses what it was given, because a query argument is text.
  if records=$(uv run dg run --local echo-gate-too-tight.yaml "${flags[@]}"); then
    echo "echo-gate-too-tight was meant to fail at the gate" >&2
    exit 1
  fi
  printf '%s\n' "$records" | jq -e -s '
    (map(select(.kind == "run")) | last) as $run
    | $run.message == "failed"
      and $run.exit_code == 1
      and ($run.steps | map(select(.step == "ask")) | all(.status == "succeeded"))
      and ($run.steps | map(select(.step == "check")) | all(.status == "failed"))
  ' > /dev/null
  printf '%s\n' "$records" | jq -e -s '
    (map(select(.kind == "run")) | last).failures
    | any(.step == "check"
          and .error_class == "rejected"
          and (.error | test("\\$\\.args\\.reading")))
  ' > /dev/null

  # 2. The same gate with the line fixed, and its schema still carried in the document. The url
  # the gate handed on is the proof that base_url reached the call and not only the document.
  records=$(uv run dg run --local echo-gate-carried.yaml "${flags[@]}")
  printf '%s\n' "$records" | jq -e -s --arg base "${base:-https://postman-echo.com}" '
    (map(select(.kind == "run")) | last) as $run
    | $run.message == "succeeded"
      and ($run.steps | all(.status == "succeeded"))
      and ($run.steps
           | map(select(.step == "check"))
           | all(.output.value.url | startswith($base + "/get")))
  ' > /dev/null
done

# 3. Against an instance this script starts and stops.
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

# 4. A server stores no schema a document carries. Nothing is called, so this is asserted once.
if refusal=$(uv run dg apply echo-gate-carried.yaml --json); then
  echo "a document carrying its own schemas was meant to be refused" >&2
  exit 1
fi
printf '%s\n' "$refusal" | jq -e -s '
  any(.[]; .kind == "error"
      and .status == 422
      and (.message | test("carries its own schemas")))
' > /dev/null

# 5. So the instance holds the shape instead. dg schema create refuses a code the instance
# already has, which is why this asks first.
if ! uv run dg schema show echo-answer > /dev/null 2>&1; then
  uv run dg schema create schemas/echo-answer.json
fi

uv run dg apply

for base in "${bases[@]}"; do
  base_flags "$base"

  records=$(uv run dg run echo-gate --watch "${flags[@]}")
  printf '%s\n' "$records" | jq -e -s '
    (map(select(.kind == "run")) | last) as $run
    | $run.message == "succeeded"
      and $run.exit_code == 0
      and ($run.steps | all(.status == "succeeded"))
  ' > /dev/null

  # The gate hands its input on unchanged, which is what makes it a waypoint.
  run_id=$(printf '%s\n' "$records" | jq -r -s 'map(select(.kind == "run")) | last | .run_id')
  uv run dg runs show "$run_id" --json | jq -e --arg base "${base:-https://postman-echo.com}" '
    .fields.attempts[]
    | select(.step_name == "check")
    | .output.value.args.station == "bergen-florida"
      and .output.value.args.reading == "12.4"
      and (.output.value.url | startswith($base + "/get"))
  ' > /dev/null

  # 6. An empty station is a string the schema will not have, and nothing downstream sees it.
  if records=$(uv run dg run echo-gate --watch -p station= "${flags[@]}"); then
    echo "an empty station was meant to be refused at the gate" >&2
    exit 1
  fi
  printf '%s\n' "$records" | jq -e -s '
    (map(select(.kind == "run")) | last) as $run
    | $run.message == "failed"
      and ($run.steps | map(select(.step == "check")) | all(.status == "failed"))
  ' > /dev/null
  printf '%s\n' "$records" | jq -e -s '
    (map(select(.kind == "run")) | last).failures
    | any(.step == "check"
          and .error_class == "rejected"
          and (.error | test("\\$\\.args\\.station")))
  ' > /dev/null
done

echo "echo-gate: documents valid, the gate refused twice as written, the carried schema refused at apply, the lifted schema gated a run, against $legs"
