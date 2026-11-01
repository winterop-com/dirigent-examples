#!/usr/bin/env bash
# Run this while you still have a network. It fills every example's .venv and the uv cache,
# and fetches the two tutorials, so the examples run afterwards with UV_OFFLINE=1.
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$PWD"

BASICS_PDF_URL="https://winterop-com.github.io/dirigent/basics.pdf"
DHIS2_PDF_URL="https://winterop-com.github.io/dirigent-dhis2/tutorial.pdf"

synced=()
skipped=()
failed=()

echo "Preparing $ROOT for offline use"
echo

echo "== Syncing every example =="
for project in */; do
  name="${project%/}"
  # docs/ is this script's own download folder, not an example.
  if [ "$name" = "docs" ]; then
    continue
  fi
  if [ ! -f "${name}/pyproject.toml" ]; then
    skipped+=("$name")
    continue
  fi
  printf '%-28s ' "$name"
  # env -u VIRTUAL_ENV: an activated venv elsewhere makes uv sync the wrong environment.
  if (cd "$name" && env -u VIRTUAL_ENV uv sync --quiet) 2>"${TMPDIR:-/tmp}/prepare-offline.err"; then
    echo "synced"
    synced+=("$name")
  else
    echo "FAILED"
    sed 's/^/    /' "${TMPDIR:-/tmp}/prepare-offline.err" >&2
    failed+=("$name")
  fi
done
rm -f "${TMPDIR:-/tmp}/prepare-offline.err"
echo

echo "== The dg command line =="
# The examples installed dirigent-cli as a uv tool already; reinstalling it here would only
# risk moving them off the version they were built on.
if dg_version="$(dg --version 2>/dev/null)"; then
  echo "$dg_version"
else
  dg_version=""
  echo "dg is not on PATH. The examples all run through 'uv run dg', so this is not fatal;"
  echo "if you want the bare command too, run this now, while the network is up:"
  echo '    uv tool install "dirigent-cli>=0.29,<0.30"'
fi
echo

echo "== The images the examples run =="
# echo-s3 runs an S3 server as a container, echo-stream a Kafka broker, and the PDF document
# runs pandoc; every image must be local before the network goes, or its verify.sh cannot start
# them.
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  # chap-prediction's Chap stack is the four after HAPI, pinned as chap/compose.yaml pins them;
  # HAPI is fhir-to-fhir's, pinned as hapi/compose.yaml pins it.
  for image in rustfs/rustfs:1.0.0-rc.4 redpandadata/redpanda:v24.2.18 pandoc/typst:3.11-alpine \
    hapiproject/hapi:v8.12.0-2@sha256:0ff86aac4c7bd13a1ee226444a70263bb46ed1c28ef543c30a44f865b80ca04e \
    ghcr.io/dhis2-chap/chap-core@sha256:ccbfaada86a0af66daa21847662ce06dabd9b84ee7aba54051414fae285e7d7f \
    ghcr.io/dhis2-chap/chap-worker@sha256:59212c42d7167cebe74ba9e467e81c56d6ae8cb531a74ca34cdc46622aa877df \
    valkey/valkey:8 postgres:17; do
    if docker image inspect "$image" >/dev/null 2>&1; then
      echo "already local: $image"
    else
      echo "pulling $image"
      docker pull -q "$image"
    fi
  done
else
  echo "docker is not running, so the images were not pulled; start Docker and run this again"
fi
echo

echo "== The tutorials =="
mkdir -p docs
fetch_pdf() {
  local url="$1" target="$2"
  printf '%-28s ' "$(basename "$target")"
  if ! curl -fsSL "$url" -o "$target"; then
    echo "FAILED"
    echo "could not download ${url}" >&2
    return 1
  fi
  # GitHub Pages answers 200 with an HTML page for some wrong paths, so check the magic bytes.
  if [ "$(head -c 4 "$target")" != "%PDF" ]; then
    echo "FAILED"
    echo "${url} did not answer with a PDF" >&2
    rm -f "$target"
    return 1
  fi
  echo "$(wc -c < "$target" | tr -d ' ') bytes"
}
fetch_pdf "$BASICS_PDF_URL" "docs/basics.pdf"
fetch_pdf "$DHIS2_PDF_URL" "docs/dhis2-tutorial.pdf"
echo

echo "== Ready for the train =="
echo "${#synced[@]} example(s) synced: ${synced[*]:-}"
if [ "${#skipped[@]}" -gt 0 ]; then
  echo "${#skipped[@]} directory(ies) with no pyproject.toml, nothing to sync: ${skipped[*]:-}"
fi
if [ -n "$dg_version" ]; then
  echo "dg on PATH: ${dg_version}"
fi
echo "tutorials in ${ROOT}/docs: basics.pdf, dhis2-tutorial.pdf"
echo "the four dhis2-* examples and fhir-to-dhis2 need the DHIS2 play server and stay online"
echo "climate-sync-and-export needs the network for CHIRPS and the play server, and stays online"
if [ "${#failed[@]}" -gt 0 ]; then
  echo
  echo "${#failed[@]} example(s) did NOT sync and will not run offline: ${failed[*]:-}" >&2
  exit 1
fi
echo
echo "Offline, one command per shell:"
echo "    export UV_OFFLINE=1"
echo
echo "Nothing else has to be started: the examples that call anything call the playground their"
echo "own instance serves, and the rest reach nothing at all. For instance:"
echo "    cd ${ROOT}/echo-fanout && uv run dg run --local pipelines/echo-fanout.yaml"
echo "    cd ${ROOT}/echo-read && uv run dg dev    # then, in another shell, dg run --local"
