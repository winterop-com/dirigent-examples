# Sourced by setup.sh and verify.sh: what both do to put an instance in place for every
# document under pipelines/. Nothing here runs on its own.
#
# The process-side half (the database, the connections, the bucket) reads the database URL
# and DIRIGENT_SECRET_KEY from the environment or .env and needs no server. The server-side
# half (the token, the schemas, the alert rule, the apply) needs DG_URL answering.

# The unsafe blocks the documents use: shell.run for the execute shelf, and the docker family
# for org-units-to-pdf and the docker and git shelves. The s3:// scheme echo-s3 writes to is
# served by the `artifacts` connection. Both are in the environment because dg does not read
# them from a dirigent.yaml or .env in the working directory.
export DIRIGENT_ENABLED_UNSAFE_BLOCKS='["shell.run","docker.run","docker.build","docker.compose.up","docker.compose.down"]'
export DIRIGENT_STORAGE_CONNECTIONS='s3=artifacts'

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
  ou-record
  playground-reading
  station-reading
)

# The buckets the documents write into: echo-s3's, and the corpus's s3 shelf's.
BUCKETS=(echo-s3 dirigent-archive)

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
  for pair in "play https://play.dhis2.org/2.42 DHIS2 play demo" \
              "source https://play.im.dhis2.org/dev DHIS2 play demo, the source" \
              "target https://play.dhis2.org/2.42 DHIS2 play demo, the target"; do
    read -r code url name <<< "$pair"
    uv run dg connection ensure dhis2 "$code" \
      --name "$name" \
      --set "base_url=$url" \
      --set follow_redirects_with_auth=true \
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
  # The corpus's playground connection, on the instance DG_URL names.
  uv run dg connection ensure http playground \
    --name "The playground" \
    --set "base_url=$DG_URL/api/v1/playground" \
    --set basic_username=playground \
    --set basic_password=playground \
    --set "hmac_secret=a shared secret between two dirigent instances" \
    --set timeout=30s \
    --set health_path=/request \
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

# The buckets the documents write into. dg storage ensure makes the bucket the artifact root
# addresses, so it is handed a root in each bucket for one call.
make_bucket() {
  local bucket made
  for bucket in "${BUCKETS[@]}"; do
    made=false
    for _ in $(seq 1 30); do
      if DIRIGENT_ARTIFACT_ROOT="s3://$bucket/artifacts" uv run dg storage ensure --json > /dev/null 2>&1; then
        made=true
        break
      fi
      sleep 1
    done
    [ "$made" = true ] || DIRIGENT_ARTIFACT_ROOT="s3://$bucket/artifacts" uv run dg storage ensure --json
  done
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
  uv run dg auth login --username admin --password admin --json \
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

# echo-alert's sink: a webhook connection pointed at this instance's own playground. The
# document's echo-failed rule names it, and plan refuses a rule naming a connection the
# instance does not hold, so it is written before the apply.
ensure_alert() {
  local sink="$DG_URL/api/v1/playground/request"
  uv run dg connection ensure webhook echo-sink \
    --name "The alert sink" \
    --description "The playground's /request, which answers with whatever was POSTed to it." \
    --set "url=$sink" \
    --json > /dev/null
}

# Every connection the documents name, asked whether it answers.
check_connections() {
  local code
  for code in play source target artifacts playground playground-auth; do
    uv run dg connection check "$code" --json \
      | jq -se --arg code "$code" '
          map(select(.kind == "connection.checked")) | last
          | if .healthy then true else error("the \($code) connection is not healthy: \(.detail)") end
        ' > /dev/null
  done
}

# Every document under pipelines/, however deep, checked offline, eight at a time. `dg validate`
# with no argument reads the top level of pipelines/ alone.
validate_all() {
  local out=$1
  find pipelines -name '*.yaml' | sort \
    | xargs -P 8 -I{} sh -c 'uv run dg validate "$1" --json | jq -c --arg path "$1" "select(.kind == \"validated\") | . + {path: \$path}"' _ {} \
    > "$out"
}

# Every document under pipelines/ onto the instance, through seed.py, and echo-schedule's clock
# resumed: a schedule the walk creates is created paused.
apply_all() {
  local out=$1
  uv run python seed.py pipelines > "$out"
  uv run dg schedule resume echo-schedule every-minute --json > /dev/null
}

# The brokers and the warehouse the queues and sql shelves reach, as compose project NAME with
# the host ports KAFKA_PORT, RABBITMQ_PORT, RABBITMQ_UI_PORT and WAREHOUSE_PORT, and the
# topic and queue those documents expect: neither block declares one.
services_start() {
  local name=$1
  if ! docker compose -f services/compose.yaml -p "$name" up -d --wait > /dev/null 2>&1; then
    docker compose -f services/compose.yaml -p "$name" ps >&2
    return 1
  fi
  local answer made=false
  for _ in $(seq 1 30); do
    answer="$(KAFKA_BOOTSTRAP="127.0.0.1:${KAFKA_PORT:-9092}" uv run python - 2>&1 <<'PY' || true
import asyncio
import os

from aiokafka.admin import AIOKafkaAdminClient, NewTopic
from aiokafka.errors import TopicAlreadyExistsError


async def main() -> None:
    admin = AIOKafkaAdminClient(bootstrap_servers=os.environ["KAFKA_BOOTSTRAP"])
    await admin.start()
    try:
        await admin.create_topics([NewTopic("orders", num_partitions=1, replication_factor=1)])
    except TopicAlreadyExistsError:
        pass
    finally:
        await admin.close()
    print("OK")


asyncio.run(main())
PY
)"
    if printf '%s' "$answer" | grep -q '^OK$'; then made=true; break; fi
    sleep 1
  done
  [ "$made" = true ] || { echo "redpanda never created the topic orders: $answer" >&2; return 1; }
  local queue declared
  for queue in shop-orders shop-reports; do
    declared=false
    for _ in $(seq 1 30); do
      if curl -fsS -u dirigent:dirigent -X PUT -H 'content-type: application/json' -d '{"durable": true}' \
           "http://127.0.0.1:${RABBITMQ_UI_PORT:-15672}/api/queues/%2F/$queue" > /dev/null 2>&1; then
        declared=true
        break
      fi
      sleep 1
    done
    [ "$declared" = true ] || { echo "the rabbitmq management API never declared $queue" >&2; return 1; }
  done
}

# One order on shop-orders, for rabbitmq-consume-ack-on-success to take.
publish_order() {
  curl -fsS -u dirigent:dirigent -X POST -H 'content-type: application/json' \
    -d '{"properties": {"content_type": "application/json"}, "routing_key": "shop-orders", "payload": "{\"order\": 1042, \"sku\": \"valve\", \"quantity\": 3}", "payload_encoding": "string"}' \
    "http://127.0.0.1:${RABBITMQ_UI_PORT:-15672}/api/exchanges/%2F/amq.default/publish" > /dev/null
}

services_stop() {
  docker compose -f services/compose.yaml -p "$1" down -v > /dev/null 2>&1 || true
}

# The connections to those services.
seal_service_connections() {
  uv run dg connection ensure kafka orders-topic \
    --name "Orders topic" \
    --set "bootstrap_servers=[\"127.0.0.1:${KAFKA_PORT:-9092}\"]" \
    --json > /dev/null
  uv run dg connection ensure rabbitmq shop-queue \
    --name "Shop queue" \
    --set "url=amqp://dirigent@127.0.0.1:${RABBITMQ_PORT:-5672}/" \
    --set password=dirigent \
    --json > /dev/null
  uv run dg connection ensure sql warehouse-read \
    --name "The warehouse, read-only" \
    --set "url=postgresql+asyncpg://reader@127.0.0.1:${WAREHOUSE_PORT:-5433}/warehouse" \
    --set password=reader-password \
    --set read_only=true \
    --json > /dev/null
}
