#!/usr/bin/env bash
# Reuse the single canonical iPad smoke suite from both CI entrypoints.
# Do not build the app here: pass ATHLTH_IPAD_SMOKE_APP from the build job.
set -euo pipefail

# Log every CoreSimulator transition, and fail an individual stuck command
# rather than silently consuming the entire runner's job timeout.
simctl_bounded() {
  local step="$1" seconds="$2"
  shift 2
  python3 - "$step" "$seconds" "$@" <<'PY'
import subprocess, sys
step = sys.argv[1]
timeout = int(sys.argv[2])
command = ["xcrun", "simctl", *sys.argv[3:]]
print(f"::notice::iPad simulator: {step} (limit {timeout}s)", file=sys.stderr, flush=True)
try:
    result = subprocess.run(
        command, capture_output=True, text=True, timeout=timeout, check=False
    )
except subprocess.TimeoutExpired:
    print(f"::error::iPad simulator timed out at: {step} after {timeout}s", file=sys.stderr, flush=True)
    raise SystemExit(124)
if result.stdout:
    print(result.stdout, end="", flush=True)
if result.stderr:
    print(result.stderr, end="", file=sys.stderr, flush=True)
if result.returncode:
    print(f"::error::iPad simulator: {step} failed ({result.returncode})", file=sys.stderr, flush=True)
raise SystemExit(result.returncode)
PY
}

# Prefer iPad models that can actually be created by the installed runtime.
# simctl lists new models even when the local iOS runtime rejects them (403).
create_compatible_ipad() {
  python3 - "$1" "$2" <<'PY'
import json, subprocess, sys
size, name = int(sys.argv[1]), sys.argv[2]
def listing(kind):
    result = subprocess.run(["xcrun", "simctl", "list", kind, "-j"],
                            capture_output=True, text=True, check=True, timeout=35)
    return json.loads(result.stdout)
runtimes = [r for r in listing("runtimes").get("runtimes", [])
            if r.get("isAvailable") and
            (r.get("platform") == "iOS" or "iOS" in r.get("name", ""))]
def version(r):
    parts = [int(x) for x in str(r.get("version", "0")).split(".") if x.isdigit()]
    return tuple((parts + [0, 0, 0])[:3])
runtimes.sort(key=version, reverse=True)
preferred = (
    ["iPad Pro 11-inch (M4)", "iPad Air 11-inch (M3)",
     "iPad Air 11-inch (M2)", "iPad (A16)",
     "iPad (10th generation)", "iPad Pro 11-inch (M5)"]
    if size == 11 else
    ["iPad Pro 13-inch (M4)", "iPad Air 13-inch (M3)",
     "iPad Air 13-inch (M2)", "iPad Pro 13-inch (M5)"]
)
devices = [
    d for d in listing("devicetypes").get("devicetypes", [])
    if d.get("name", "").startswith("iPad") and (
        ("11-inch" in d["name"] or "11 inch" in d["name"] or
         d["name"] in ("iPad (A16)", "iPad (10th generation)"))
        if size == 11 else
        ("13-inch" in d["name"] or "13 inch" in d["name"])
    )
]
rank = {name: idx for idx, name in enumerate(preferred)}
devices.sort(key=lambda d: (rank.get(d["name"], len(preferred)), d["name"]))
if not devices:
    print(f"::warning::No {size}-inch iPad type installed", file=sys.stderr)
    sys.exit(66)
if not runtimes:
    print("::error::No iOS runtime is available", file=sys.stderr)
    sys.exit(67)
for runtime in runtimes:
    for device in devices:
        try:
            result = subprocess.run(
                ["xcrun", "simctl", "create", name,
                 device["identifier"], runtime["identifier"]],
                capture_output=True, text=True, check=False, timeout=45
            )
        except subprocess.TimeoutExpired:
            print(f"::warning::Timed out creating {device['name']}", file=sys.stderr)
            continue
        if result.returncode == 0 and result.stdout.strip():
            print(f"::notice::Using {device['name']} on {runtime['identifier']}",
                  file=sys.stderr)
            print(result.stdout.strip())
            sys.exit(0)
        reason = " ".join(result.stderr.split())[:220]
        print(f"::warning::Rejected {device['name']} on {runtime['identifier']}: "
              f"{reason}", file=sys.stderr)
print(f"::error::No compatible {size}-inch iPad/runtime pair", file=sys.stderr)
sys.exit(67)
PY
}

# Use an app already compiled and XCTest-verified by Build ATHLTH.
# A manual/legacy run can still use its local build.
if [ -n "${ATHLTH_IPAD_SMOKE_APP:-}" ]; then
  APP="$ATHLTH_IPAD_SMOKE_APP"
else
  APP=$(find "$RUNNER_TEMP/DerivedData/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name 'ATHLTH.app' -print -quit)
fi
test -n "$APP"
test -d "$APP"
echo "Launching prebuilt simulator app: $APP"

UDID=$(create_compatible_ipad 11 "ATHLTH-iPad")

cleanup() {
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

simctl_bounded "boot 11-inch iPad" 100 boot "$UDID"
simctl_bounded "wait for 11-inch iPad boot" 160 bootstatus "$UDID" -b
simctl_bounded "install ATHLTH on 11-inch iPad" 180 install "$UDID" "$APP"

validate_screen() {
  local label="$1"
  local screenshot="$RUNNER_TEMP/athlth-ipad-$label.png"
  local entropy="0"

  # Fresh iPad simulators can continue rendering their launch
  # surface after simctl launch returns a PID. Do not mistake one
  # unfinished frame for an application-level rendering failure.
  # Still fail when every sample stays visually blank.
  for attempt in 1 2 3 4; do
    sleep 8
    xcrun simctl io "$UDID" screenshot "$screenshot"
    test -s "$screenshot"

    entropy=$(magick "$screenshot" -colorspace Gray -format "%[entropy]" info:)
    echo "iPad $label screenshot entropy (attempt $attempt): $entropy"

    if python3 - "$entropy" <<'PY'
import sys
raise SystemExit(0 if float(sys.argv[1]) >= 0.025 else 1)
PY
    then
      return 0
    fi
  done

  echo "::error::ATHLTH iPad $label stayed visually blank after four frames (entropy=$entropy)."
  # A live PID is not sufficient evidence that a SwiftUI surface
  # rendered. Capture simulator diagnostics when the image remains
  # blank; retain the PNG even on failure for visual inspection.
  xcrun simctl spawn "$UDID" log show --last 3m --style compact \
    --predicate 'process == "ATHLTH" OR eventMessage CONTAINS "com.wesc9.athlth"' \
    2>&1 | tail -n 250 || true
  return 1
}

LAUNCH_OUTPUT=$(xcrun simctl launch "$UDID" com.wesc9.athlth 2>&1)
echo "$LAUNCH_OUTPUT"
validate_screen "onboarding"
xcrun simctl terminate "$UDID" com.wesc9.athlth || true

for TAB in 0 1 2 3 4; do
  echo "Rendering ATHLTH iPad tab $TAB"

  TAB_OUTPUT=$(xcrun simctl launch "$UDID" com.wesc9.athlth \
    --athlth-compatibility-preview \
    "--athlth-compatibility-tab=$TAB" 2>&1)
  echo "$TAB_OUTPUT"

  TAB_PID=$(echo "$TAB_OUTPUT" | awk -F': ' '/com\.wesc9\.athlth:/ {print $2}')
  sleep 5

  if [ -z "$TAB_PID" ] || ! kill -0 "$TAB_PID" 2>/dev/null; then
    echo "::error::ATHLTH iPad tab $TAB exited after launch."
    xcrun simctl spawn "$UDID" log show --last 3m --style compact --predicate 'process == "ATHLTH" OR eventMessage CONTAINS "com.wesc9.athlth"' || true
    exit 1
  fi

  validate_screen "tab-$TAB"
  xcrun simctl terminate "$UDID" com.wesc9.athlth || true
done

# Verify the new native Studio library pages on the iPad, not
# just the five top-level tabs. A missing source/empty layout must
# no longer be hidden behind the full-screen Train overlay.
for LIBRARY in overview exercises workouts trainingPlans routes; do
  echo "Rendering inline ATHLTH iPad library: $LIBRARY"

  LIBRARY_OUTPUT=$(xcrun simctl launch "$UDID" com.wesc9.athlth \
    --athlth-compatibility-preview \
    "--athlth-compatibility-library=$LIBRARY" 2>&1)
  echo "$LIBRARY_OUTPUT"

  LIBRARY_PID=$(echo "$LIBRARY_OUTPUT" | awk -F': ' '/com\.wesc9\.athlth:/ {print $2}')
  sleep 5

  if [ -z "$LIBRARY_PID" ] || ! kill -0 "$LIBRARY_PID" 2>/dev/null; then
    echo "::error::ATHLTH iPad library $LIBRARY exited after launch."
    xcrun simctl spawn "$UDID" log show --last 3m --style compact --predicate 'process == "ATHLTH"' || true
    exit 1
  fi

  validate_screen "library-$LIBRARY"
  xcrun simctl terminate "$UDID" com.wesc9.athlth || true
done

# Profile previously crashed with SwiftUI EnvironmentObject.error()
# when selected from the real iPad sidebar. Verify it stays alive.
PROFILE_OUTPUT=$(xcrun simctl launch "$UDID" com.wesc9.athlth \
  --athlth-compatibility-preview \
  "--athlth-compatibility-sidebar=profile" 2>&1)
echo "$PROFILE_OUTPUT"
PROFILE_PID=$(echo "$PROFILE_OUTPUT" | awk -F': ' '/com\.wesc9\.athlth:/ {print $2}')
sleep 5
if [ -z "$PROFILE_PID" ] || ! kill -0 "$PROFILE_PID" 2>/dev/null; then
  echo "::error::ATHLTH iPad sidebar Profile crashed during presentation."
  xcrun simctl spawn "$UDID" log show --last 3m --style compact --predicate 'process == "ATHLTH"' || true
  exit 1
fi
validate_screen "sidebar-profile"
if ! kill -0 "$PROFILE_PID" 2>/dev/null; then
  echo "::error::ATHLTH iPad sidebar Profile crashed after rendering."
  exit 1
fi
xcrun simctl terminate "$UDID" com.wesc9.athlth || true

# Check the actual first logged-in Studio frame on a larger iPad,
# in addition to the 11-inch device tested above. Keep the PNG for
# visual inspection; entropy alone cannot prove layout quality.
if UDID_13=$(create_compatible_ipad 13 "ATHLTH-iPad-13"); then
  echo "Rendering the first Studio screen on a 13-inch iPad."
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
  UDID="$UDID_13"
  simctl_bounded "boot 13-inch iPad" 100 boot "$UDID"
  simctl_bounded "wait for 13-inch iPad boot" 160 bootstatus "$UDID" -b
  simctl_bounded "install ATHLTH on 13-inch iPad" 180 install "$UDID" "$APP"
  xcrun simctl launch "$UDID" com.wesc9.athlth \
    --athlth-compatibility-preview \
    "--athlth-compatibility-tab=0"
  validate_screen "13-inch-home"
  xcrun simctl terminate "$UDID" com.wesc9.athlth || true
else
  code=$?
  if [ "$code" -eq 66 ]; then
    echo "::warning::No 13-inch iPad simulator type available; 11-inch tested."
  else
    echo "::error::13-inch iPad simulator setup failed (exit $code)"
    exit "$code"
  fi
fi

echo "ATHLTH onboarding, five tabs, five inline library pages and 13-inch Home checked for blank frames."
