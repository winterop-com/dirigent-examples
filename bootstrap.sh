# Sourced by setup.sh and verify.sh: what both do to put an instance in place for every
# document under pipelines/. Nothing here runs on its own.
#
# The process-side half (the database, the connections, the bucket) reads the database URL
# and DIRIGENT_SECRET_KEY from the environment or .env and needs no server. The server-side
# half (the token, the schemas, the alert rule, the apply) needs DG_URL answering.

S3_IMAGE="${DIRIGENT_S3_IMAGE:-rustfs/rustfs:1.0.0-rc.4}"
S3_ACCESS_KEY=everything-s3-key
S3_SECRET_KEY=everything-s3-secret
S3_BUCKET=echo-s3

SCHEMAS=(
  playground-answer
  read-gate-send-org-units
  metadata-snapshot-org-units
  org-unit-sync-source
  org-unit-sync-import
  org-unit-sync-verdict
  org-units-page
)

free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# Nothing started here may still be listening once its owner is done with it.
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

# A dg dev is stopped by the pid of the `uv run` wrapping it, children first: killing the
# wrapper alone leaves the dg dev under it on the port.
stop_pid() {
  local pid="${1:-}"
  [ -n "$pid" ] || return 0
  pkill -TERM -P "$pid" 2>/dev/null || true
  kill -TERM "$pid" 2>/dev/null || true
  for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || return 0; sleep 0.25; done
  kill -KILL "$pid" 2>/dev/null || true
}

# The S3 server, as container NAME on 127.0.0.1:PORT, left alone when it is already running.
s3_start() {
  local name=$1 port=$2 code
  if ! docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null | grep -q true; then
    docker rm -f "$name" > /dev/null 2>&1 || true
    docker run -d --rm --name "$name" \
      -p "127.0.0.1:$port:9000" \
      -e "RUSTFS_ACCESS_KEY=$S3_ACCESS_KEY" \
      -e "RUSTFS_SECRET_KEY=$S3_SECRET_KEY" \
      "$S3_IMAGE" > /dev/null
  fi
  # An unauthenticated request answers 403, which is a serving endpoint answering.
  for _ in $(seq 1 60); do
    code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/" || true)"
    if [ -n "$code" ] && [ "$code" != "000" ]; then return 0; fi
    sleep 1
  done
  echo "the S3 server on port $port never answered" >&2
  return 1
}

# The database, and every connection the documents name, written straight to it. DG_URL has
# to name the instance first: playground-auth addresses its playground.
seal_connections() {
  local s3_port=$1 code url
  uv run dg db upgrade --json > /dev/null
  for pair in "play https://play.im.dhis2.org/stable-2-43-1 DHIS2 play demo" \
              "source https://play.im.dhis2.org/stable-2-43-1 DHIS2 play demo, the source" \
              "target https://play.im.dhis2.org/stable-2-42-6 DHIS2 play demo, the target"; do
    read -r code url name <<< "$pair"
    uv run dg connection ensure dhis2 "$code" \
      --name "$name" \
      --set "base_url=$url" \
      --set basic_username=admin \
      --set basic_password=district \
      --set timeout=1m \
      --json > /dev/null
  done
  uv run dg connection ensure s3 artifacts \
    --name "Artifact storage" \
    --set "endpoint_url=http://127.0.0.1:$s3_port" \
    --set "bucket=$S3_BUCKET" \
    --set "access_key_id=$S3_ACCESS_KEY" \
    --set "secret_access_key=$S3_SECRET_KEY" \
    --set path_style=true \
    --json > /dev/null
  # The playground's own documented pair, on the instance DG_URL names.
  uv run dg connection ensure http playground-auth \
    --name "The playground's auth route" \
    --set "base_url=$DG_URL/api/v1/playground" \
    --set basic_username=playground \
    --set basic_password=playground \
    --set health_path=/request \
    --json > /dev/null
}

# The bucket echo-s3 writes into. dg storage ensure makes the bucket the artifact root
# addresses, so it is handed a root in that bucket for this one call.
make_bucket() {
  for _ in $(seq 1 30); do
    if DIRIGENT_ARTIFACT_ROOT="s3://$S3_BUCKET/artifacts" uv run dg storage ensure --json > /dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  DIRIGENT_ARTIFACT_ROOT="s3://$S3_BUCKET/artifacts" uv run dg storage ensure --json
}

wait_ready() {
  local url=$1 pid=${2:-}
  for _ in $(seq 1 90); do
    curl -fsS "$url/health/ready" > /dev/null 2>&1 && return 0
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      echo "the instance stopped before it was ready" >&2
      return 1
    fi
    sleep 1
  done
  echo "the instance at $url never answered /health/ready" >&2
  return 1
}

login() {
  uv run dg auth login --username dev --password dirigent-dev --json \
    | jq -r 'select(.kind == "token.issued") | .token'
}

# Every schema under schemas/, replaced when the instance holds a body other than the file's.
ensure_schemas() {
  local schema
  for schema in "${SCHEMAS[@]}"; do
    if ! uv run dg schema show "$schema" --json 2>/dev/null \
         | jq -se --slurpfile want "schemas/$schema.json" \
             'map(select(.kind == "schema")) | last | .fields.body == $want[0]' > /dev/null; then
      uv run dg schema delete "$schema" --json > /dev/null 2>&1 || true
      uv run dg schema create "schemas/$schema.json" --json > /dev/null
    fi
  done
}

# echo-alert's rule, delivering run_failed to a webhook connection pointed at this instance's
# own playground. The rule goes before the connection it names, and is written again after.
ensure_alert() {
  local sink="$DG_URL/api/v1/playground/request"
  if uv run dg alerts rules list --json | jq -e -s 'any(.[]; .fields.code == "echo-failed")' > /dev/null; then
    uv run dg alerts rules delete echo-failed --json > /dev/null
  fi
  uv run dg connection ensure webhook echo-sink \
    --name "The alert sink" \
    --description "The playground's /request, which answers with whatever was POSTed to it." \
    --set "url=$sink" \
    --json > /dev/null
  uv run dg alerts rules create echo-failed \
    --name "Echo failures to the sink" \
    --event run_failed \
    --pipeline echo-alert \
    --connection echo-sink \
    --template '{{ pipeline.code }} run {{ run.status }}' \
    --body 'Run {{ run.id }} of {{ pipeline.code }} (version {{ pipeline.version }}) ended {{ run.status }} in {{ run.duration_ms | duration }}.' \
    --json > /dev/null
}

# Every connection the documents name, asked whether it answers.
check_connections() {
  local code
  for code in play source target artifacts playground-auth; do
    uv run dg connection check "$code" --json \
      | jq -se --arg code "$code" '
          map(select(.kind == "connection.checked")) | last
          | if .healthy then true else error("the \($code) connection is not healthy: \(.detail)") end
        ' > /dev/null
  done
}
