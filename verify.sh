#!/usr/bin/env bash
# Run this example end to end and assert on the records, never on the rendering: a table is
# what a terminal makes of a record, and this script has no terminal.
#
# Two of the runs below fail on purpose, so their non-zero exit is the expected outcome and what
# is asserted is the error the records carry.
#
# The documents call the playground, which an instance serves under /api/v1/playground, so the
# instance is started first and every run below is pointed at it. A --local run mounts no API of
# its own, which is why even those legs need the instance this script starts.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

uv sync

for document in echo-gate-too-tight.yaml echo-gate-carried.yaml pipelines/echo-gate.yaml; do
  uv run dg validate "$document"
done

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

# The instance: what the documents call, and what holds the shape from step 5 on.
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

# The port is chosen here rather than in the documents, so every run below is handed it.
playground="http://127.0.0.1:$port/api/v1/playground"

# 1. The gate refuses what it was given, because a query argument is text.
if records=$(uv run dg run --local echo-gate-too-tight.yaml --json -p "playground=$playground"); then
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

# 2. The same gate with the line fixed, and its schema still carried in the document. The url the
# gate handed on is the proof that the envelope's own `request` is what reached it.
records=$(uv run dg run --local echo-gate-carried.yaml --json -p "playground=$playground")
printf '%s\n' "$records" | jq -e -s --arg pg "$playground" '
  (map(select(.kind == "run")) | last) as $run
  | $run.message == "succeeded"
    and ($run.steps | all(.status == "succeeded"))
    and ($run.steps
         | map(select(.step == "check"))
         | all(.output.value.url | startswith($pg + "/request")))
' > /dev/null

# 3. Against the instance, as stored documents.
#
# DG_URL beats the local profile, whose url is the default port; without it every command below
# would address an instance this script did not start. The token comes from dg dev's own admin:
# on an empty state that is the fixture dev / dirigent-dev, and dg auth login mints a token from
# it.
export DG_URL="http://127.0.0.1:$port"
token=$(uv run dg auth login --username dev --password dirigent-dev --json \
  | jq -r 'select(.kind == "token.issued") | .token')
export DG_TOKEN="$token"

# 4. A server stores no schema a document carries. Nothing is called, so this needs no parameter.
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
if ! uv run dg schema show playground-answer > /dev/null 2>&1; then
  uv run dg schema create schemas/playground-answer.json
fi

uv run dg apply

records=$(uv run dg run echo-gate --watch --json -p "playground=$playground")
printf '%s\n' "$records" | jq -e -s '
  (map(select(.kind == "run")) | last) as $run
  | $run.message == "succeeded"
    and $run.exit_code == 0
    and ($run.steps | all(.status == "succeeded"))
' > /dev/null

# The gate hands its input on unchanged, which is what makes it a waypoint.
run_id=$(printf '%s\n' "$records" | jq -r -s 'map(select(.kind == "run")) | last | .run_id')
uv run dg runs show "$run_id" --json | jq -e --arg pg "$playground" '
  .fields.attempts[]
  | select(.step_name == "check")
  | .output.value.args.station == "bergen-florida"
    and .output.value.args.reading == "12.4"
    and (.output.value.url | startswith($pg + "/request"))
' > /dev/null

# 6. An empty station is a string the schema will not have, and nothing downstream sees it.
if records=$(uv run dg run echo-gate --watch --json -p "playground=$playground" -p station=); then
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

echo "echo-gate: documents valid, the gate refused twice as written, the carried schema refused at apply, the lifted schema gated a run against the playground"
