#!/usr/bin/env bash
# Run this example end to end against a real S3 endpoint, and exit non-zero the moment
# anything it claims stops being true.
#
# It starts its own S3 server in a container, creates the bucket, starts its own instance
# with the artifact root pointed into that bucket, runs the document twice -- once with no
# server and once against the instance -- and asserts on the records. Everything it started
# is stopped again on the way out: the instance and the stand-in echo by the pids this
# script holds, the container by the name this script gave it.
#
# Every run is made once per echo: the real service the document defaults to, and the
# stand-in in ../local-echo, which the base_url parameter points the document at.
# VERIFY_OFFLINE=1 leaves the online leg out, so the whole of this script passes with no
# network at all -- the S3 server and the instance were always local.
#
# Needs docker and two images, both of which the compose stack already uses:
#   rustfs/rustfs:1.0.0-rc.4                        the S3 server
#   quay.io/minio/mc:RELEASE.2025-04-16T18-13-26Z   the client that makes the bucket
set -euo pipefail

cd "$(dirname "$0")"

CODE=echo-s3
BUCKET="${S3_BUCKET:-echo-s3}"
STATION=bergen-florida
CONNECTION=artifacts

S3_IMAGE="${DIRIGENT_S3_IMAGE:-rustfs/rustfs:1.0.0-rc.4}"
MC_IMAGE="${DIRIGENT_MC_IMAGE:-quay.io/minio/mc:RELEASE.2025-04-16T18-13-26Z}"

# Thrown away with the container. A real bucket's key belongs in a connection the server
# holds, encrypted under the instance key, and nowhere else.
ACCESS_KEY=echo-s3-key
SECRET_KEY=echo-s3-secret

# Somewhere to keep the streams this script asserts on, removed on the way out.
WORK="$(mktemp -d)"

DEV_PID=""
ECHO_PID=""
S3_NAME=""

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

cleanup() {
  # The instance and the stand-in echo, by the pids this script holds. Never by pattern: a
  # pattern matches the shell running this script too. The instance's wrapper has its
  # children taken first: killing `uv run` alone leaves the dg dev under it on the port.
  if [ -n "$DEV_PID" ] && kill -0 "$DEV_PID" 2>/dev/null; then
    pkill -TERM -P "$DEV_PID" 2>/dev/null || true
    kill -TERM "$DEV_PID" 2>/dev/null || true
    wait "$DEV_PID" 2>/dev/null || true
  fi
  if [ -n "$ECHO_PID" ] && kill -0 "$ECHO_PID" 2>/dev/null; then
    kill -TERM "$ECHO_PID" 2>/dev/null || true
    wait "$ECHO_PID" 2>/dev/null || true
  fi
  port_clear "${PORT:-}"
  port_clear "${ECHO_PORT:-}"
  # The S3 server, by the name this script gave it, whether or not it ever came up.
  if [ -n "$S3_NAME" ]; then
    docker rm -f "$S3_NAME" > /dev/null 2>&1 || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

say() { printf '\n== %s\n' "$1"; }

# mc keeps its alias in its own config, which goes with the container, so every call sets
# the alias and then does its work. --network container: puts mc inside the S3 server's own
# network namespace, so it reaches it at 127.0.0.1:9000 with no host networking, no
# published port and no host.docker.internal -- the same command on Linux and on macOS.
mc() {
  docker run --rm --network "container:$S3_NAME" --entrypoint /bin/sh "$MC_IMAGE" -ec "
    mc --no-color alias set fs http://127.0.0.1:9000 '$ACCESS_KEY' '$SECRET_KEY' > /dev/null
    mc --no-color $*
  "
}

free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# The last run record in a stream is how the run settled.
assert_run_succeeded() {
  jq -se --arg what "$2" '
    map(select(.kind == "run")) | last
    | if . == null then error("\($what): the stream carries no run record")
      elif .message == "succeeded" then true
      else error("\($what): the run settled \(.message)") end
  ' "$1" > /dev/null
}

# What the round trip is for: the object is addressed as s3://, as many bytes come back as
# went out, and what comes back is the answer that was asked for.
assert_round_trip() {
  jq -se --arg what "$2" --arg station "$STATION" '
    map(select(.kind == "run")) | last | .steps
    | (map({key: .step, value: .}) | from_entries) as $step
    | if ($step.save.output.uri | startswith("s3://") | not)
        then error("\($what): the write landed at \($step.save.output.uri), not in a bucket")
      elif $step.back.output.bytes_read != $step.save.output.bytes_written
        then error("\($what): \($step.save.output.bytes_written) bytes written, \($step.back.output.bytes_read) read back")
      elif $step.back.output.value.args.station != $station
        then error("\($what): the answer came back for \($step.back.output.value.args.station)")
      else true end
  ' "$1" > /dev/null
}

say "the project's own environment"
uv sync --quiet

say "every document, checked offline"
uv run dg validate --json > "$WORK/validate.ndjson"
jq -se '
  map(select(.kind == "validated")) | last
  | if .invalid == 0 then true else error("\(.invalid) document(s) refused") end
' "$WORK/validate.ndjson" > /dev/null

# --- the S3 server -------------------------------------------------------------------------
#
# A port of this script's own, and a container named after it, so two verifications never
# collide. --rm is not enough on its own: a container that is still running is still a name
# taken, which is what the trap's docker rm -f is for.
S3_PORT="${S3_PORT:-$(free_port)}"
S3_NAME="echo-s3-$S3_PORT"

say "the S3 server, as $S3_NAME on port $S3_PORT"
docker rm -f "$S3_NAME" > /dev/null 2>&1 || true
docker run -d --rm --name "$S3_NAME" \
  -p "127.0.0.1:$S3_PORT:9000" \
  -e "RUSTFS_ACCESS_KEY=$ACCESS_KEY" \
  -e "RUSTFS_SECRET_KEY=$SECRET_KEY" \
  "$S3_IMAGE" > /dev/null

# An unauthenticated request answers 403 rather than 200, and that is a serving endpoint
# answering, so only the connection is asserted -- curl -f would call 403 a failure. This is
# the compose stack's own healthcheck, in a loop.
serving=false
for _ in $(seq 1 60); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$S3_PORT/" || true)"
  if [ -n "$code" ] && [ "$code" != "000" ]; then serving=true; break; fi
  if ! docker inspect -f '{{.State.Running}}' "$S3_NAME" 2>/dev/null | grep -q true; then
    echo "the S3 server stopped before it was ready" >&2
    exit 1
  fi
  sleep 1
done
[ "$serving" = true ] || { echo "the S3 server on port $S3_PORT never answered" >&2; exit 1; }

say "the bucket"
# A write does not create a bucket, so it has to exist first. --ignore-existing makes this
# the same command on the first run and the tenth; the retry covers the moment between the
# socket opening and the object store being ready to serve.
made=false
for _ in $(seq 1 30); do
  if mc "mb --ignore-existing fs/$BUCKET" > /dev/null 2>&1; then made=true; break; fi
  sleep 1
done
[ "$made" = true ] || { echo "the bucket $BUCKET could not be created:" >&2; mc "mb --ignore-existing fs/$BUCKET"; exit 1; }

# --- the echoes -----------------------------------------------------------------------------
#
# The empty base is the document's own default, which is the real service; the other is the
# stand-in beside this repository, started here on a free port of its own. The document is
# built on base_url, so a leg is a flag rather than an edit.
ECHO_SERVER=../local-echo/echo_server.py
BASES=()
LEGS=
if [ -z "${VERIFY_OFFLINE:-}" ]; then
  BASES+=("")
  LEGS="postman-echo.com"
fi
if [ -f "$ECHO_SERVER" ]; then
  ECHO_PORT=$(free_port)
  say "the stand-in echo, on port $ECHO_PORT"
  python3 "$ECHO_SERVER" --port "$ECHO_PORT" > /dev/null 2>&1 &
  ECHO_PID=$!
  if ! curl -fs --retry 60 --retry-delay 1 --retry-connrefused --retry-all-errors \
       "http://127.0.0.1:$ECHO_PORT/get" > /dev/null; then
    echo "local-echo on port $ECHO_PORT never answered /get" >&2
    exit 1
  fi
  BASES+=("http://127.0.0.1:$ECHO_PORT")
  LEGS="${LEGS:+$LEGS and }local-echo"
fi
if [ "${#BASES[@]}" -eq 0 ]; then
  echo "VERIFY_OFFLINE=1 needs $ECHO_SERVER, and it is not there" >&2
  exit 1
fi

# Seeded with the flags every leg passes, because an empty array is not something every bash
# will expand under set -u.
base_flags() {
  FLAGS=(--json -p "bucket=$BUCKET")
  if [ -n "$1" ]; then
    FLAGS+=(-p "base_url=$1")
  fi
}

# --- without a server --------------------------------------------------------------------
#
# A local run holds its own scratch in a temporary directory whatever DIRIGENT_ARTIFACT_ROOT
# says, so it cannot put the run's artifacts in the bucket. It can still write to an s3://
# URI the document names: the scheme needs a connection, and a local run is handed one the
# same way it is handed any other -- in a connections document, with the environment saying
# which connection serves the scheme.
#
# The committed connections.yaml names port 9000, which is where the README has you start
# the server by hand. This script picked its own port, so it writes that port into a copy.
say "the document, run locally against $S3_NAME, once per echo"
sed "s#http://127.0.0.1:9000#http://127.0.0.1:$S3_PORT#" connections.yaml > "$WORK/connections.yaml"
for base in "${BASES[@]}"; do
  base_flags "$base"
  DIRIGENT_STORAGE_CONNECTIONS="s3=$CONNECTION" \
    uv run dg run --local "pipelines/$CODE.yaml" \
      --connections "$WORK/connections.yaml" \
      "${FLAGS[@]}" > "$WORK/local.ndjson"
  assert_run_succeeded "$WORK/local.ndjson" "the local run against ${base:-postman-echo.com}"
  assert_round_trip "$WORK/local.ndjson" "the local run against ${base:-postman-echo.com}"
  jq -se '
    map(select(.kind == "run")) | last | .steps
    | (map(select(.step == "stash")) | last | .output.uri) as $scratch
    | if ($scratch | startswith("file://")) then true
      else error("a local run held its scratch at \($scratch), which this example says it cannot") end
  ' "$WORK/local.ndjson" > /dev/null
done

# --- the instance ---------------------------------------------------------------------------
#
# The instance seals a connection's secret with this key, so the key has to exist before the
# connection does. It is minted once into .env, which is not in the repository and already
# holds this instance's token, and every command below runs in this directory and reads it
# from there: an instance that changes its key cannot open what it sealed under the old one,
# so the connection this script leaves behind stays readable -- by its next run, and by a
# reader who starts a dg dev of their own on the same state.
if ! grep -q '^DIRIGENT_SECRET_KEY=' .env 2>/dev/null; then
  (umask 077; printf 'DIRIGENT_SECRET_KEY=%s\n' "$(uv run dg secret-key)" >> .env)
fi

PORT="${DG_PORT:-$(free_port)}"
export DG_URL="http://127.0.0.1:$PORT"

say "the instance, on port $PORT, with its artifact root in the bucket"
# These two are what put the run's own scratch in the bucket: one says where artifacts live,
# the other says which connection serves the scheme that address is written in. They belong
# to the instance, not to the document, which is why they are set here and not in the yaml.
DIRIGENT_ARTIFACT_ROOT="s3://$BUCKET/artifacts" \
  DIRIGENT_STORAGE_CONNECTIONS="s3=$CONNECTION" \
  uv run dg dev --port "$PORT" > "$WORK/dev.ndjson" 2>&1 &
DEV_PID=$!

for _ in $(seq 1 90); do
  curl -fsS "$DG_URL/health" > /dev/null 2>&1 && break
  kill -0 "$DEV_PID" 2>/dev/null || { echo "the instance stopped before it was ready:"; cat "$WORK/dev.ndjson"; exit 1; }
  sleep 1
done
curl -fsS "$DG_URL/health" > /dev/null

# dg init minted this instance's first token into .env, where the local profile reads it. A
# fresh clone has neither -- no .env, and no state either -- so the dg dev above just
# migrated an empty database and made the development admin `dev` for it, and a token is one
# login away. dg auth login writes the token into a record, which is the one place it is
# readable.
if [ -z "${DG_TOKEN:-}" ] && [ -f .env ]; then
  DG_TOKEN="$(sed -n 's/^DG_TOKEN=//p' .env | head -1)"
fi
if [ -z "${DG_TOKEN:-}" ]; then
  DG_TOKEN="$(uv run dg auth login --username dev --password dirigent-dev --json \
    | jq -r 'select(.kind == "token.issued") | .token')"
  # Appended, never written over: .env already carries the key this instance seals with.
  [ -n "$DG_TOKEN" ] && (umask 077; printf 'DG_TOKEN=%s\n' "$DG_TOKEN" >> .env)
fi
[ -n "${DG_TOKEN:-}" ] || { echo "no token in .env and none to log in for" >&2; exit 1; }
export DG_TOKEN

say "the connection the s3:// scheme resolves through"
create_artifacts() {
  uv run dg connection create s3 "$CONNECTION" \
    --name "Artifact storage" \
    --set "endpoint_url=http://127.0.0.1:$S3_PORT" \
    --set "bucket=$BUCKET" \
    --set "access_key_id=$ACCESS_KEY" \
    --set "secret_access_key=$SECRET_KEY" \
    --set path_style=true \
    --json > /dev/null
}

# Left alone when the instance already holds it: the row is sealed with the key in .env, which
# is the same key on every run, so the state a reader inherits is the state this script
# asserted on. What does move is the endpoint, because the container above takes a free port
# unless S3_PORT names one, and a row addressing last run's port addresses nothing -- so a row
# naming another endpoint is written again. There is no `dg connection update`: a connection
# changes by being deleted and created.
ENDPOINT="http://127.0.0.1:$S3_PORT"
if ! uv run dg connection show "$CONNECTION" --json 2>/dev/null \
     | jq -se --arg url "$ENDPOINT" '
         map(select(.kind == "connection")) | last | .fields.config.endpoint_url == $url
       ' > /dev/null; then
  uv run dg connection delete "$CONNECTION" --json > /dev/null 2>&1 || true
  create_artifacts
fi

# A row sealed under a key that is gone cannot be opened by this one, and the check names the
# class in its own record. Nothing recovers that secret, so the connection is written again
# under the key in hand -- which is what a reader does by hand after losing a key.
uv run dg connection check "$CONNECTION" --json > "$WORK/check.ndjson" || true
if jq -se '
  map(select(.kind == "connection.checked")) | last
  | (.detail // "") | startswith("SecretKeyMismatch")
' "$WORK/check.ndjson" > /dev/null; then
  say "the connection, sealed again under the key in .env"
  uv run dg connection delete "$CONNECTION" --json > /dev/null
  create_artifacts
  uv run dg connection check "$CONNECTION" --json > "$WORK/check.ndjson"
fi

jq -se '
  map(select(.kind == "connection.checked")) | last
  | if .healthy then true else error("the artifacts connection is not healthy: \(.detail)") end
' "$WORK/check.ndjson" > /dev/null

say "the document, applied"
# Applying an unchanged document again is not a new version, so this passes on every run.
uv run dg apply --json > /dev/null

say "the run, once per echo"
for base in "${BASES[@]}"; do
  base_flags "$base"
  uv run dg run "$CODE" --watch "${FLAGS[@]}" > "$WORK/run.ndjson"
  assert_run_succeeded "$WORK/run.ndjson" "the server run against ${base:-postman-echo.com}"
  assert_round_trip "$WORK/run.ndjson" "the server run against ${base:-postman-echo.com}"

  RUN_ID="$(jq -rs 'map(select(.kind == "run")) | last | .run_id' "$WORK/run.ndjson")"

  # The run's own scratch, which the document addresses without naming a scheme at all. On
  # this instance it is in the bucket, because the artifact root is.
  jq -se --arg run "$RUN_ID" '
    map(select(.kind == "run")) | last | .steps
    | (map(select(.step == "stash")) | last | .output.uri) as $scratch
    | if ($scratch | startswith("s3://") | not)
        then error("the run held its scratch at \($scratch), not in the bucket")
      elif ($scratch | contains("/artifacts/runs/\($run)/") | not)
        then error("the scratch is not under the prefix this run owns: \($scratch)")
      else true end
  ' "$WORK/run.ndjson" > /dev/null

  # The records say where the bytes went; this asks the object store itself, which is the
  # other half of the proof.
  mc "stat fs/$BUCKET/echo/$STATION.json" > /dev/null
  mc "stat fs/$BUCKET/artifacts/runs/$RUN_ID/echo/$STATION.json" > /dev/null
done

say "what the bucket holds"
mc "ls --recursive fs/$BUCKET"

say "ok: $CODE wrote to $BUCKET, read it back, and kept run $RUN_ID's scratch in the same bucket, against $LEGS"
