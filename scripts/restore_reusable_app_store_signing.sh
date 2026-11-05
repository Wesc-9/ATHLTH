#!/usr/bin/env bash
# Find the most recent encrypted Apple Distribution identity produced by ATHLTH
# TestFlight CI. This is ciphertext only; GH_TOKEN must have actions:read.
set -euo pipefail
: "${GH_TOKEN:?GitHub Actions token required to restore signing identity}"
: "${GITHUB_REPOSITORY:?GitHub repository is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"

restore_dir="$RUNNER_TEMP/athlth-reusable-signing"
mkdir -p "$restore_dir"
artifact_list="$RUNNER_TEMP/athlth-signing-artifacts.json"

gh api "repos/$GITHUB_REPOSITORY/actions/artifacts?name=athlth-ci-signing-v1&per_page=100" > "$artifact_list"

source_run="$(python3 - "$artifact_list" "${GITHUB_RUN_ID:-}" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as file:
    items = json.load(file).get("artifacts", [])
current = sys.argv[2]
matches = [
    item for item in items
    if item.get("name") == "athlth-ci-signing-v1"
    and not item.get("expired", False)
    and str((item.get("workflow_run") or {}).get("id", "")) != current
    and (item.get("workflow_run") or {}).get("id")
]
matches.sort(key=lambda item: item.get("created_at", ""), reverse=True)
print((matches[0].get("workflow_run") or {}).get("id", "") if matches else "")
PY
)"

if [ -z "$source_run" ]; then
  echo "::notice::No reusable signing identity was found. A first-time bootstrap is required."
  exit 0
fi

echo "::notice::Restoring encrypted ATHLTH signing identity from prior CI run $source_run."
gh run download "$source_run" \
  --repo "$GITHUB_REPOSITORY" \
  --name "athlth-ci-signing-v1" \
  --dir "$restore_dir"

if [ ! -s "$restore_dir/signing-envelope.json" ]; then
  echo "::error::The signing artifact was present but its encrypted envelope is missing."
  exit 1
fi
echo "::notice::Encrypted identity downloaded; its private key is only decrypted on the signing runner."
