#!/usr/bin/env bash
# Run this example end to end, against the real play demo, and exit non-zero the moment
# anything it claims stops being true.
#
# Every assertion below reads records rather than rendered text: --json asks for the records
# even at a terminal, and a table is only a rendering of one.
#
# The PDF document needs a Docker daemon. Without one it is skipped with a message and the
# rest of this script still has to pass, so the repository verifies on a machine that has no
# Docker at all.
set -euo pipefail

cd "$(dirname "$0")"

PAGE=org-units-to-markdown
PDF=org-units-to-pdf
SCHEMA=org-units-page

# A PDF of one page of a table is tens of kilobytes. Anything under this is not a document.
PDF_FLOOR_BYTES=5000

# Somewhere to keep the streams this script asserts on, removed on the way out.
WORK="$(mktemp -d)"

DEV_PID=""

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
  # Stop the instance this script started, by the pid this script holds. Never by pattern:
  # a pattern matches this shell too. Its wrapper has its children taken first: killing
  # `uv run` alone leaves the dg dev under it on the port.
  if [ -n "$DEV_PID" ] && kill -0 "$DEV_PID" 2>/dev/null; then
    pkill -TERM -P "$DEV_PID" 2>/dev/null || true
    kill -TERM "$DEV_PID" 2>/dev/null || true
    wait "$DEV_PID" 2>/dev/null || true
  fi
  port_clear "${PORT:-}"
  rm -rf "$WORK"
}
trap cleanup EXIT

say() { printf '\n== %s\n' "$1"; }

# The last run record in a stream is how the run settled.
assert_run_succeeded() {
  jq -se --arg what "$2" '
    map(select(.kind == "run")) | last
    | if . == null then error("\($what): the stream carries no run record")
      elif .message == "succeeded" then true
      else error("\($what): the run settled \(.message)") end
  ' "$1" > /dev/null
}

# What the two renderings have to be true of: the title carries the parent's own name, the
# table has one row per unit the gate passed, the HTML really is a table, and each write
# reports the bytes its rendering built at the file name the document named. Both renderings
# are asserted on their own output text: nothing reads a document back.
assert_page() {
  jq -se --arg what "$2" '
    map(select(.kind == "run")) | last | .steps
    | (map(select(.step == "parent")) | last | .output.body.organisationUnits[0].name) as $parent
    | (map(select(.step == "check")) | last | .output.value.organisationUnits) as $gated
    | (map(select(.step == "markdown")) | last | .output) as $md
    | (map(select(.step == "html")) | last | .output) as $html
    | (map(select(.step == "save_markdown")) | last | .output) as $wrote_md
    | (map(select(.step == "save_html")) | last | .output) as $wrote_html
    | ($md.text | split("\n")) as $lines
    # Every data row of the markdown table opens with the id in backticks; the header and the
    # separator do not, so this counts rows and nothing else.
    | ($lines | map(select(startswith("| `"))) | length) as $rows
    | if ($gated | length) < 1 then error("\($what): the gate passed no organisation units")
      elif ($parent | length) < 1 then error("\($what): the parent read answered with no name")
      elif $lines[0] != "# Organisation units under \($parent)" then
        error("\($what): the page opens \($lines[0] | tojson), not with the name the parent step read")
      elif $rows != ($gated | length) then
        error("\($what): the table has \($rows) rows for \($gated | length) gated units")
      elif ($md.content_type != "text/markdown") then error("\($what): the page is \($md.content_type)")
      elif ($html.text | contains("<table") | not) then error("\($what): the HTML carries no <table")
      elif ($html.content_type != "text/html") then error("\($what): the HTML is \($html.content_type)")
      elif $wrote_md.bytes_written != $md.text_bytes then
        error("\($what): \($md.text_bytes) bytes rendered, \($wrote_md.bytes_written) written")
      elif ($wrote_md.uri | endswith("/org-units.md") | not) then
        error("\($what): the markdown landed at \($wrote_md.uri)")
      elif $wrote_html.bytes_written != $html.text_bytes then
        error("\($what): \($html.text_bytes) bytes rendered, \($wrote_html.bytes_written) written")
      elif ($wrote_html.uri | endswith("/org-units.html") | not) then
        error("\($what): the HTML landed at \($wrote_html.uri)")
      else true end
  ' "$1" > /dev/null
}

# The container's own account of what it left behind. docker.run reports a collected output in
# a record of its own, carrying the URI and the bytes, so the PDF is asserted on without
# reading it back.
assert_pdf() {
  jq -se --arg what "$2" --argjson floor "$PDF_FLOOR_BYTES" '
    (map(select(.kind == "log" and .step == "pdf" and .message == "output collected")) | last) as $collected
    | (map(select(.kind == "run")) | last | .steps | map(select(.step == "pdf")) | last | .output) as $ran
    | if $collected == null then error("\($what): the pdf step collected no output")
      elif $ran.exit_code != 0 then error("\($what): pandoc exited \($ran.exit_code): \($ran.stderr)")
      elif ($collected.fields.uri | endswith("/org-units.pdf") | not) then
        error("\($what): the PDF landed at \($collected.fields.uri)")
      elif $collected.fields.bytes_written < $floor then
        error("\($what): the PDF is \($collected.fields.bytes_written) bytes, under the \($floor) byte floor")
      else true end
  ' "$1" > /dev/null
}

# The PDF document is the only thing here that needs a daemon, and a machine without one still
# has to pass the rest.
if command -v docker > /dev/null 2>&1 && docker info > /dev/null 2>&1; then
  HAS_DOCKER=yes
else
  HAS_DOCKER=no
fi

say "the project's own environment"
uv sync --quiet

say "every document, checked offline"
# No argument: the project's own documents, which is everything under pipelines/.
uv run dg validate --json > "$WORK/validate.ndjson"
jq -se '
  map(select(.kind == "validated")) | last
  | if .invalid == 0 then true else error("\(.invalid) document(s) refused") end
' "$WORK/validate.ndjson" > /dev/null

say "the page, run locally against the play demo"
# A local run starts on a throwaway instance holding nothing, so it is handed the connection
# and the schema this document names.
uv run dg run --local "pipelines/$PAGE.yaml" \
  --connections connections.yaml \
  --schema "schemas/$SCHEMA.json" \
  --json > "$WORK/local-page.ndjson"
assert_run_succeeded "$WORK/local-page.ndjson" "the local page run"
assert_page "$WORK/local-page.ndjson" "the local page run"

if [ "$HAS_DOCKER" = yes ]; then
  say "the PDF, run locally"
  # --enable-unsafe is the per-run form of the instance setting: docker.run executes code on
  # the worker, so it runs only where its id was named.
  uv run dg run --local "pipelines/$PDF.yaml" \
    --connections connections.yaml \
    --schema "schemas/$SCHEMA.json" \
    --enable-unsafe docker.run \
    --json > "$WORK/local-pdf.ndjson"
  assert_run_succeeded "$WORK/local-pdf.ndjson" "the local PDF run"
  assert_page "$WORK/local-pdf.ndjson" "the local PDF run"
  assert_pdf "$WORK/local-pdf.ndjson" "the local PDF run"
else
  say "SKIPPED: the PDF, run locally"
  echo "no Docker daemon answered, so $PDF was not run. It is the only document here that"
  echo "needs one: start Docker and run this script again to cover the PDF leg as well."
fi

# The instance seals a connection's secret with this key, so the key has to exist before the
# connection does. It is minted once into .env, which is not in the repository and already
# holds this instance's token, and every command below runs in this directory and reads it
# from there: an instance that changes its key cannot open what it sealed under the old one,
# so the connection this script leaves behind stays readable -- by its next run, and by a
# reader who starts a dg dev of their own on the same state.
if ! grep -q '^DIRIGENT_SECRET_KEY=' .env 2>/dev/null; then
  (umask 077; printf 'DIRIGENT_SECRET_KEY=%s\n' "$(uv run dg secret-key)" >> .env)
fi

PORT="${DG_PORT:-$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')}"
export DG_URL="http://127.0.0.1:$PORT"

say "the instance, on port $PORT"
# .dirigent/state/ is not in the repository, so the first run here starts on nothing: dg dev
# migrates the schema and makes the development admin. Every later run reuses what is there.
# It reads enabled_unsafe_blocks out of dirigent.yaml, which is how docker.run is allowed for
# the server leg below.
uv run dg dev --port "$PORT" > "$WORK/dev.ndjson" 2>&1 &
DEV_PID=$!

for _ in $(seq 1 90); do
  if curl -fsS "$DG_URL/health" > /dev/null 2>&1; then break; fi
  kill -0 "$DEV_PID" 2>/dev/null || { echo "the instance stopped before it was ready:"; cat "$WORK/dev.ndjson"; exit 1; }
  sleep 1
done
curl -fsS "$DG_URL/health" > /dev/null

# dg auth login mints a token and writes it into a record, which is the one place it is
# readable; at a terminal the same command spells the export line out to paste.
DG_TOKEN="$(uv run dg auth login --username dev --password dirigent-dev --json \
  | jq -r 'select(.kind == "token.issued") | .token')"
export DG_TOKEN
[ -n "$DG_TOKEN" ]

say "the shape the instance holds"
# A read writes the row under fields, so the stored body is fields.body. There is no
# `dg schema update`: a schema changes by being deleted and created, so a body that no longer
# matches the file on disk is replaced rather than left as a gate nobody edited.
if ! uv run dg schema show "$SCHEMA" --json 2>/dev/null \
     | jq -se --slurpfile want "schemas/$SCHEMA.json" \
         'map(select(.kind == "schema")) | last | .fields.body == $want[0]' > /dev/null; then
  uv run dg schema delete "$SCHEMA" --json > /dev/null 2>&1 || true
  uv run dg schema create "schemas/$SCHEMA.json" --json > /dev/null
fi

say "the connection to the play demo"
# Written when the instance does not hold it, and left alone when it does: the row is sealed
# with the key in .env, which is the same key on every run, so there is nothing to rewrite and
# the state a reader inherits is the state this script asserted on.
create_play() {
  uv run dg connection create dhis2 play \
    --name "DHIS2 play demo" \
    --set base_url=https://play.im.dhis2.org/stable-2-43-1 \
    --set basic_username=admin \
    --set basic_password=district \
    --json > /dev/null
}

if ! uv run dg connection list --json | jq -e 'select(.fields.code == "play")' > /dev/null; then
  create_play
fi

# A row sealed under a key that is gone cannot be opened by this one, and the check names the
# class in its own record. Nothing recovers that secret, so the connection is written again
# under the key in hand -- which is what a reader does by hand after losing a key.
uv run dg connection check play --json > "$WORK/check.ndjson" || true
if jq -se '
  map(select(.kind == "connection.checked")) | last
  | (.detail // "") | startswith("SecretKeyMismatch")
' "$WORK/check.ndjson" > /dev/null; then
  say "the connection, sealed again under the key in .env"
  uv run dg connection delete play --json > /dev/null
  create_play
  uv run dg connection check play --json > "$WORK/check.ndjson"
fi

jq -se '
  map(select(.kind == "connection.checked")) | last
  | if .healthy then true else error("the play connection is not healthy: \(.detail)") end
' "$WORK/check.ndjson" > /dev/null

say "both documents, applied"
uv run dg apply --json > /dev/null

say "the page, on the instance"
uv run dg run "$PAGE" --watch --json > "$WORK/page.ndjson"
assert_run_succeeded "$WORK/page.ndjson" "the server page run"
assert_page "$WORK/page.ndjson" "the server page run"

if [ "$HAS_DOCKER" = yes ]; then
  say "the PDF, on the instance"
  uv run dg run "$PDF" --watch --json > "$WORK/pdf.ndjson"
  assert_run_succeeded "$WORK/pdf.ndjson" "the server PDF run"
  assert_page "$WORK/pdf.ndjson" "the server PDF run"
  assert_pdf "$WORK/pdf.ndjson" "the server PDF run"
else
  say "SKIPPED: the PDF, on the instance"
  echo "no Docker daemon answered, so $PDF was applied but not run."
fi

if [ "$HAS_DOCKER" = yes ]; then
  say "ok: $PAGE and $PDF rendered the play demo's organisation units as markdown, HTML and PDF"
else
  say "ok: $PAGE rendered the play demo's organisation units as markdown and HTML; $PDF needs Docker and was skipped"
fi
