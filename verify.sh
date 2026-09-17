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

uv run dg validate pipelines/echo-fanout.yaml

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
  # --record appends one JSON object per request, which is how the run below is held to
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
# says out loud that the assertions below are on records rather than on rendered text.
#
# The run settles completed_with_errors by design and dg exits 0 on that with a warning, so
# the outcome is read off the final run record rather than off the exit status. That record
# carries every step and every item, which is why one jq program can check the whole run.
for base in "${bases[@]}"; do
  # Seeded empty, because an empty array is not something every bash expands under set -u.
  flags=(--json)
  if [ -n "$base" ]; then
    flags+=(-p "base_url=$base")
  fi

  uv run dg run --local pipelines/echo-fanout.yaml "${flags[@]}" >"$records"

  jq -e -s '
    (map(select(.kind == "run" and has("exit_code"))) | last) as $run
    | ($run.steps | map(select(.step == "ask"))) as $items
    | ($run.steps | map(select(.step == "report")) | first) as $report
    | $run.message == "completed_with_errors"
      and ($items | map(select(.status == "succeeded")) | length) == 2
      and ($items | map(select(.status == "failed")) | length) == 1
      and $report.status == "succeeded"
      and $report.output.value.asked == 3
      and $report.output.value.answered == 2
      and $report.output.value.missing == ["oslo-blindern"]
  ' "$records" >/dev/null
done

# What the local echo was asked, from its own record: the two stations that answered and the
# one asked at the endpoint that fails. base_url reached the calls, not only the document.
if [ -s "$delivered" ]; then
  jq -e -s '
    map(select(.method == "GET"))
    | (map(select(.path == "/get" and .args.station != null)) | length) >= 2
      and (map(select(.path == "/status/500")) | length) >= 1
  ' "$delivered" >/dev/null
fi

echo "echo-fanout: completed_with_errors, two stations answered, oslo-blindern missing, against $legs"
