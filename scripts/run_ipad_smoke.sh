#!/usr/bin/env bash
# Reuse the single canonical iPad smoke suite from both CI entrypoints.
# Do not build the app here: pass ATHLTH_IPAD_SMOKE_APP from the build job.
set -euo pipefail

RUNTIME=$(xcrun simctl list runtimes -j | python3 -c '
import json,sys
data=json.load(sys.stdin)
runtimes=[
    r for r in data["runtimes"]
    if r.get("isAvailable")
    and r.get("platform")=="iOS"
]
if not runtimes:
    runtimes=[
        r for r in data["runtimes"]
        if r.get("isAvailable")
        and "iOS" in r.get("name","")
    ]
if not runtimes:
    raise SystemExit("No iOS runtime is available")
print(runtimes[-1]["identifier"])
')

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

DEVICE_TYPES_JSON="$RUNNER_TEMP/ipad-device-types.json"
xcrun simctl list devicetypes -j > "$DEVICE_TYPES_JSON"

DEVICE_TYPE=$(python3 - "$DEVICE_TYPES_JSON" <<'PY'
import json,sys

with open(sys.argv[1]) as fh:
    data=json.load(fh)

ipads=[
    d for d in data["devicetypes"]
    if d.get("name","").startswith("iPad")
]

if not ipads:
    raise SystemExit("No iPad simulator device type is available")

preferred_names=[
    "iPad Pro 11-inch (M5)",
    "iPad Pro 11-inch (M4)",
    "iPad Air 11-inch (M3)",
    "iPad Air 11-inch (M2)",
    "iPad (A16)",
    "iPad (10th generation)",
]

by_name={d["name"]:d for d in ipads}

for name in preferred_names:
    if name in by_name:
        print(by_name[name]["identifier"])
        raise SystemExit(0)

eleven=[
    d for d in ipads
    if "11-inch" in d["name"]
    or "11 inch" in d["name"]
]
chosen=(eleven or ipads)[-1]
print(chosen["identifier"])
PY
)

UDID=$(xcrun simctl create "ATHLTH-iPad" "$DEVICE_TYPE" "$RUNTIME")

cleanup() {
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"

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
LARGE_DEVICE_TYPE=$(python3 - "$DEVICE_TYPES_JSON" <<'PY'
import json,sys
with open(sys.argv[1]) as fh:
    devices=json.load(fh)["devicetypes"]
preferred=[
    "iPad Pro 13-inch (M5)",
    "iPad Pro 13-inch (M4)",
    "iPad Air 13-inch (M3)",
    "iPad Air 13-inch (M2)",
]
by_name={item["name"]:item["identifier"] for item in devices}
for name in preferred:
    if name in by_name:
        print(by_name[name])
        break
else:
    options=[
        item["identifier"] for item in devices
        if item["name"].startswith("iPad")
        and ("13-inch" in item["name"] or "13 inch" in item["name"])
    ]
    print(options[-1] if options else "")
PY
)

if [ -n "$LARGE_DEVICE_TYPE" ]; then
  echo "Rendering the first Studio screen on a 13-inch iPad."
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
  UDID=$(xcrun simctl create "ATHLTH-iPad-13" "$LARGE_DEVICE_TYPE" "$RUNTIME")
  xcrun simctl boot "$UDID"
  xcrun simctl bootstatus "$UDID" -b
  xcrun simctl install "$UDID" "$APP"
  xcrun simctl launch "$UDID" com.wesc9.athlth \
    --athlth-compatibility-preview \
    "--athlth-compatibility-tab=0"
  validate_screen "13-inch-home"
  xcrun simctl terminate "$UDID" com.wesc9.athlth || true
else
  echo "::warning::No 13-inch iPad simulator exists on this runner; 11-inch screenshots are available."
fi

echo "ATHLTH onboarding, five tabs, five inline library pages and 13-inch Home checked for blank frames."
