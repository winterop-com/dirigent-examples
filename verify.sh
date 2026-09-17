#!/usr/bin/env bash
# Run this example end to end and fail if anything about it has moved.
#
# Nothing here needs a server: dg run --local applies and runs the document in a throwaway
# instance in a temporary directory and deletes it on the way out. Run it as often as you
# like; it leaves nothing behind but .venv/.
#
# Every assertion is made once per echo: the real service the document defaults to, and the
# stand-in in ../local-echo, which the base_url parameter points the document at.
# VERIFY_OFFLINE=1 leaves the online leg out, so the whole of this script passes with no
# network at all.
set -euo pipefail

cd "$(dirname "$0")"

uv sync --quiet

uv run dg validate pipelines/echo-transform.yaml

echo_server=../local-echo/echo_server.py
echo_pid=
records=$(mktemp)
delivered=$(mktemp)

# Whatever this script started is stopped by its pid, however this script ends.
cleanup() {
  if [ -n "$echo_pid" ]; then
    kill "$echo_pid" 2>/dev/null || true
    wait "$echo_pid" 2>/dev/null || true
  fi
  rm -f "$records" "$delivered"
}
trap cleanup EXIT

# Any port nothing is listening on: several of these run on one machine, and two of them on
# one port is two of them failing.
free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
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
  # --record appends one JSON object per request, which is how the runs below are held to
  # having reached this echo rather than any other.
  python3 "$echo_server" --port "$echo_port" --record "$delivered" > /dev/null 2>&1 &
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

# Stdout here is a pipe, so dg writes NDJSON whether or not --json is passed; passing it
# says out loud that the assertions below are on records rather than on rendered text. The
# final run record carries every step's output, so one jq program checks the whole chain.
#
# Each verb is held to its own contract: the filter dropped one of four and modified
# nothing, the map returned exactly as many as it was given, the transform turned the list
# into one object, and the send's answer is the echo repeating what it received.
for base in "${bases[@]}"; do
  # Seeded empty, because an empty array is not something every bash expands under set -u.
  flags=(--json)
  if [ -n "$base" ]; then
    flags+=(-p "base_url=$base")
  fi

  uv run dg run --local pipelines/echo-transform.yaml "${flags[@]}" >"$records"

  jq -e -s --arg base "${base:-https://postman-echo.com}" '
    (map(select(.kind == "run" and has("exit_code"))) | last) as $run
    | ($run.steps | map({key: .step, value: .}) | from_entries) as $step
    | $run.message == "succeeded"
      and ($step.active.output.value | length) == 3
      and ($step.active.output.value | map(has("celsius")) | all)
      and ($step.fahrenheit.output.value | length) == ($step.active.output.value | length)
      and $step.summary.output.value.stations == 3
      and $step.summary.output.value.warmest == "bergen-florida"
      and $step.send.output.status == 200
      and $step.send.output.body.json == $step.summary.output.value
      and ($step.send.output.body.url | startswith($base + "/post"))
  ' "$records" >/dev/null
done

# What the local echo was asked, from its own record: the batch on the way in, and the
# summary the three verbs made on the way out.
if [ -s "$delivered" ]; then
  jq -e -s '
    map(select(.method == "POST" and .path == "/post"))
    | (map(select(.json.readings != null)) | length) >= 1
      and (map(select(.json.stations == 3)) | length) >= 1
  ' "$delivered" >/dev/null
fi

echo "echo-transform: succeeded, 4 readings filtered to 3, mapped, reduced, and echoed back, against $legs"
