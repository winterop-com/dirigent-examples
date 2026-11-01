#!/usr/bin/env bash
# Run every example's own verify.sh in turn and summarise, failing if any failed.
# Each example is verified from its own folder in a subshell, so one cannot affect the next.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
passed=()
failed=()
for repo in "$here"/*/; do
  name="$(basename "$repo")"
  [ -x "$repo/verify.sh" ] || continue
  echo "=== $name"
  if (cd "$repo" && ./verify.sh); then
    passed+=("$name")
  else
    failed+=("$name")
  fi
done
echo
echo "passed: ${#passed[@]}  ${passed[*]:-}"
echo "failed: ${#failed[@]}  ${failed[*]:-}"
[ "${#failed[@]}" -eq 0 ]
