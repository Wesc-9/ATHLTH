"""Locate an optional exact-commit simulator artifact without masking real smoke failures."""
import json
import os
import subprocess
import time


def get_rows(endpoint, key):
    raw = subprocess.run(["gh", "api", endpoint], capture_output=True, text=True,
                         timeout=30, check=True).stdout
    data = json.loads(raw)
    if not isinstance(data, dict) or not isinstance(data.get(key), list):
        raise ValueError("Invalid GitHub API response")
    rows = data[key]
    if any(not isinstance(row, dict) for row in rows):
        raise ValueError("Invalid GitHub API rows")
    return rows


def resolve(repo, branch, sha, fetch=get_rows, sleep=time.sleep, attempts=80):
    missing = errors = 0
    for attempt in range(attempts):
        try:
            runs = fetch(f"repos/{repo}/actions/workflows/launch-smoke.yml/runs?head_sha={sha}&per_page=100", "workflow_runs")
            matching = [r for r in runs if r.get("head_sha") == sha
                        and r.get("head_branch") == branch
                        and r.get("event") in ("push", "workflow_dispatch")]
            if not matching:
                missing += 1
                if missing >= 3:
                    return None
            else:
                missing = 0
                run = max(matching, key=lambda r: int(r["id"]))
                run_id = int(run["id"])
                artifacts = fetch(f"repos/{repo}/actions/runs/{run_id}/artifacts?per_page=100", "artifacts")
                usable = [a for a in artifacts if a.get("name") == "athlth-iphone-simulator-app"
                          and a.get("expired") is False and int(a.get("size_in_bytes", 0)) > 0]
                if len(usable) == 1:
                    return run_id
                if run.get("status") == "completed":
                    return None
            errors = 0
        except (ValueError, TypeError, KeyError, OSError, subprocess.SubprocessError):
            errors += 1
            print(f"::warning::Optional simulator artifact lookup unavailable (attempt {attempt+1}).")
            if errors >= 3:
                return None
        if attempt + 1 < attempts:
            sleep(60)
    return None


if __name__ == "__main__":
    run_id = resolve(os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_REF_NAME"],
                     os.environ["GITHUB_SHA"])
    if run_id is not None:
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            output.write(f"run_id={run_id}\n")
    else:
        print("::notice::No shareable app available; run independent iPad build.")
