#!/usr/bin/env bash
# Exact-commit acceptance gate: shared by pre-signing and final upload checks.
set -euo pipefail
for attempt in $(seq 1 180); do
  if python3 - <<'PY'
import json
import os
import subprocess
import sys

repo = os.environ["GITHUB_REPOSITORY"]
sha = os.environ["GITHUB_SHA"]

def api(path):
    response = subprocess.run(
        ["gh", "api", path], text=True, capture_output=True, timeout=60
    )
    if response.returncode != 0:
        raise RuntimeError(f"GitHub API {path}: {response.stderr[-400:]}")
    return json.loads(response.stdout)

branch = api(f"repos/{repo}/git/ref/heads/{os.environ['GITHUB_REF_NAME']}")
if branch["object"]["sha"] != sha:
    print("::error::Release branch advanced; refusing to ship stale source.")
    sys.exit(1)

# GitHub may paginate workflow runs when a commit is retried repeatedly.
runs = []
for page in range(1, 6):
    batch = api(f"repos/{repo}/actions/runs?head_sha={sha}&per_page=100&page={page}")["workflow_runs"]
    runs.extend(batch)
    if len(batch) < 100:
        break
else:
    print("::error::More than 500 workflow runs on this commit; refusing incomplete verification.")
    sys.exit(1)
required = [
    "Build ATHLTH",
    "ATHLTH backend regressions",
    "ATHLTH Train and Hybrid Engine XCTest",
    "ATHLTH iPhone Compatibility Smoke Test",
    "ATHLTH iPad Compatibility Smoke Test",
]
selected = {}
pending = False

for name in required:
    matches = [
        run for run in runs
        if run["name"] == name and run["head_sha"] == sha
        and run.get("event") in ("push", "workflow_dispatch")
        and run.get("head_branch") == os.environ["GITHUB_REF_NAME"]
    ]
    if not matches:
        print(f"Waiting for {name}: workflow missing on this commit")
        pending = True
        continue
    # A rerun keeps the same run ID; inspect its current attempt/status.
    run = max(matches, key=lambda item: (item["id"], item.get("run_attempt", 1)))
    selected[name] = run
    if run["status"] != "completed":
        print(f"Waiting for {name}: {run['status']} ({run['id']})")
        pending = True
    elif run["conclusion"] != "success":
        print(f"::error::Release blocked: {name} {run['conclusion']} ({run['id']})")
        sys.exit(1)

if pending:
    sys.exit(2)

# Verify the branch again after waiting for the slowest gate.
# A release must not pass on evidence from an obsolete commit.
branch = api(f"repos/{repo}/git/ref/heads/{os.environ['GITHUB_REF_NAME']}")
if branch["object"]["sha"] != sha:
    print("::error::Release branch advanced during acceptance checks.")
    sys.exit(1)

build_id = selected["Build ATHLTH"]["id"]
jobs = []
for page in range(1, 6):
    batch = api(f"repos/{repo}/actions/runs/{build_id}/jobs?per_page=100&page={page}")["jobs"]
    jobs.extend(batch)
    if len(batch) < 100:
        break
else:
    print("::error::Build job list exceeds verification limit.")
    sys.exit(1)
for name in (["build"] if os.environ["GITHUB_REF_NAME"] in ("release/v2.2.6", "release/v2.2.7", "release/v2.2.8", "release/v2.2.9", "release/v2.3.0", "release/v3.0.0", "release/v3.0.1", "release/v3.0.2") else ["build", "iPad 11-inch smoke", "iPad 13-inch smoke"]):
    matches = [job for job in jobs if job["name"] == name]
    if len(matches) != 1 or matches[0]["conclusion"] != "success":
        print(f"::error::Required iPad/iOS job not verified: {name} in {build_id}")
        sys.exit(1)

artifacts = []
for page in range(1, 6):
    batch = api(f"repos/{repo}/actions/runs/{build_id}/artifacts?per_page=100&page={page}")["artifacts"]
    artifacts.extend(batch)
    if len(batch) < 100:
        break
else:
    print("::error::Build artifact list exceeds verification limit.")
    sys.exit(1)
for size in ((11, 13) if os.environ["GITHUB_REF_NAME"] not in ("release/v2.2.6", "release/v2.2.7", "release/v2.2.8", "release/v2.2.9", "release/v2.3.0", "release/v3.0.0", "release/v3.0.1", "release/v3.0.2") else ()):
    name = f"athlth-ipad-smoke-screenshots-{size}"
    matched = [
        artifact for artifact in artifacts
        if artifact["name"] == name and not artifact["expired"]
        and artifact["size_in_bytes"] >= 10_000
    ]
    if not matched:
        print(f"::error::Missing verified iPad {size}-inch screenshot artifact")
        sys.exit(1)

print(f"All five workflows and branch-specific build jobs verified for {sha}.")
sys.exit(0)
PY
  then
    echo "All release acceptance gates are green."
    exit 0
  else
    status=$?
    if [ "$status" -ne 2 ]; then exit "$status"; fi
  fi
  if [ "$attempt" -eq 180 ]; then
    echo "::error::Timed out awaiting full release verification."
    exit 1
  fi
  sleep 60
done
