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

# Use an existing available iPad before creating another CoreSimulator.
# Device selection is read-only and each command has a hard timeout.
select_registered_ipad() {
  python3 - "$1" <<'PY'
import subprocess, sys
try:
    listed = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"],
                            capture_output=True, text=True, check=True, timeout=40)
    found = subprocess.run([sys.executable, "scripts/select_ipad_simulators.py",
                            "--size", sys.argv[1]], input=listed.stdout,
                           capture_output=True, text=True, timeout=12)
except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
    print(f"::warning::Existing iPad discovery failed: {error}", file=sys.stderr)
    raise SystemExit(1)
if found.stderr:
    print(found.stderr, end="", file=sys.stderr)
if found.returncode or not found.stdout.strip():
    raise SystemExit(1)
print(found.stdout.strip())
PY
}

# Prefer iPad models that can actually be created by the installed runtime.
# simctl lists new models even when the local iOS runtime rejects them (403).
create_compatible_ipad() {
  python3 - "$1" "$2" <<'PY'
import json, re, subprocess, sys
size, name = int(sys.argv[1]), sys.argv[2]
def listing(kind):
    result = subprocess.run(["xcrun", "simctl", "list", kind, "-j"],
                            capture_output=True, text=True, check=True, timeout=35)
    return json.loads(result.stdout)
runtimes = [r for r in listing("runtimes").get("runtimes", [])
            if r.get("isAvailable") and
            re.search(r"\.SimRuntime\.iOS-\d+(?:-\d+)*$", r.get("identifier", ""))]
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

# CI executes 11- and 13-inch layouts as independent jobs on fresh Macs.
# The legacy 'all' mode remains available for manual smoke runs.
IPAD_SIZE="${ATHLTH_IPAD_SMOKE_SIZE:-all}"
case "$IPAD_SIZE" in
  11|13|all) ;;
  *) echo "::error::Unsupported ATHLTH_IPAD_SMOKE_SIZE: $IPAD_SIZE"; exit 64 ;;
esac
CURRENT_SIZE="$IPAD_SIZE"
if [ "$CURRENT_SIZE" = "all" ]; then CURRENT_SIZE=11; fi
IPAD_SIMULATOR_OWNED=0
if UDID=$(select_registered_ipad "$CURRENT_SIZE"); then
  echo "::notice::Reusing registered ${CURRENT_SIZE}-inch iPad $UDID"
else
  UDID=$(create_compatible_ipad "$CURRENT_SIZE" "ATHLTH-iPad-${CURRENT_SIZE}")
  IPAD_SIMULATOR_OWNED=1
  echo "::notice::Created temporary ${CURRENT_SIZE}-inch iPad $UDID"
fi
cleanup() {
  # Only delete simulators that this test created.
  if [ "$IPAD_SIMULATOR_OWNED" = "1" ]; then
    simctl_bounded "shutdown temporary iPad" 35 shutdown "$UDID" >/dev/null 2>&1 || true
    simctl_bounded "delete temporary iPad" 35 delete "$UDID" >/dev/null 2>&1 || true
  else
    echo "::notice::Preserving pre-existing simulator $UDID"
  fi
}
trap cleanup EXIT
# An already booted registered simulator can report a nonzero boot status.
# Only a responsive launchctl probe is accepted below.
simctl_bounded "boot ${CURRENT_SIZE}-inch iPad" 100 boot "$UDID" || true
# Hosted Xcode 27 simulators sometimes finish booting after bootstatus -b
# itself stalls. Verify the device is genuinely Booted and its launch services
# respond before attempting installation; never treat a timeout alone as success.
wait_for_ipad_services() {
  local size="$1" attempt
  for attempt in 1 2 3; do
    # On hosted Xcode 27, bootstatus can stall while launchd already works.
    # Neither a Booted label nor a timeout alone is evidence of success.
    if simctl_bounded "probe already-responsive ${size}-inch iPad" 30 spawn "$UDID" launchctl list; then
      return 0
    fi
    if ! simctl_bounded "wait for ${size}-inch iPad boot (attempt ${attempt})" 150 bootstatus "$UDID" -b; then
      echo "::warning::bootstatus incomplete; probing launch services regardless."
    fi
    if simctl_bounded "probe ${size}-inch iPad launch services (attempt ${attempt})" 45 spawn "$UDID" launchctl list; then
      return 0
    fi
    echo "::warning::CoreSimulator not responsive after boot attempt ${attempt}; collecting diagnostics."
    {
      date -u
      simctl_bounded "diagnose booted simulators" 25 list devices booted || true
      simctl_bounded "diagnose available runtimes" 25 list runtimes || true
    } >> "$RUNNER_TEMP/athlth-ipad-diagnostics.txt" 2>&1 || true
    if [ "$attempt" -eq 3 ]; then
      echo "::error::iPad simulator failed to become responsive after three attempts."
      return 1
    fi
    simctl_bounded "shutdown ${size}-inch iPad after boot stall" 65 shutdown "$UDID" || true
    simctl_bounded "restart ${size}-inch iPad after boot stall" 120 boot "$UDID"
  done
}
if ! wait_for_ipad_services "$CURRENT_SIZE"; then
  if [ "$IPAD_SIMULATOR_OWNED" = "1" ]; then
    echo "::error::Temporary iPad never became responsive; refusing to pass."
    exit 1
  fi
  echo "::warning::Registered simulator unresponsive; trying a fresh isolated device."
  UDID=$(create_compatible_ipad "$CURRENT_SIZE" "ATHLTH-iPad-fallback")
  IPAD_SIMULATOR_OWNED=1
  simctl_bounded "boot fresh fallback iPad" 100 boot "$UDID"
  wait_for_ipad_services "$CURRENT_SIZE"
fi
# CoreSimulator on fresh hosted Macs sometimes reports boot complete while its
# installation service is still initializing. A single 180s timeout is not
# evidence of an app crash. Retry once after a bounded service restart, but
# never pass the smoke test without a real install, launch and screenshot.
install_ipad_app() {
  local size="$1"
  if simctl_bounded "install ATHLTH on ${size}-inch iPad (first attempt)" 240 install "$UDID" "$APP"; then
    return 0
  fi

  echo "::warning::CoreSimulator installation failed; collecting diagnostics before one retry."
  simctl_bounded "diagnose install device state" 30 list devices booted > "$RUNNER_TEMP/athlth-ipad-diagnostics.txt" 2>&1 || true
  simctl_bounded "diagnose install services" 40 spawn "$UDID" launchctl list >> "$RUNNER_TEMP/athlth-ipad-diagnostics.txt" 2>&1 || true
  # A hung install may leave installd unresponsive. Restart the simulator
  # instead of assuming that simply repeating install will make progress.
  simctl_bounded "shutdown ${size}-inch iPad before retry" 60 shutdown "$UDID" || true
  simctl_bounded "reboot ${size}-inch iPad before retry" 120 boot "$UDID"
  wait_for_ipad_services "$size"
  simctl_bounded "install ATHLTH on ${size}-inch iPad (final attempt)" 300 install "$UDID" "$APP"
}
install_ipad_app "$CURRENT_SIZE"

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
    simctl_bounded "screenshot iPad $label" 50 io "$UDID" screenshot "$screenshot"
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
  simctl_bounded "capture rendering error logs" 65 spawn "$UDID" log show --last 3m --style compact \
    --predicate 'process == "ATHLTH" OR eventMessage CONTAINS "com.wesc9.athlth"' \
    2>&1 | tail -n 250 || true
  return 1
}

if [ "$IPAD_SIZE" = "13" ]; then
  # A separate runner with the real 13-inch layout must exercise the
  # Studio destinations most vulnerable to environment and split-view
  # regressions, not just a single Home frame.
  preview_13_inch() {
    local label="$1"
    local argument="$2"
    local output
    local pid

    output=$(simctl_bounded "launch 13-inch $label" 65 launch "$UDID" com.wesc9.athlth \
      --athlth-compatibility-preview "$argument" 2>&1)
    echo "$output"
    pid=$(echo "$output" | awk -F': ' '/com\.wesc9\.athlth:/ {print $2}')
    sleep 5
    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
      echo "::error::ATHLTH 13-inch $label exited before rendering."
      return 1
    fi
    validate_screen "13-inch-$label"
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "::error::ATHLTH 13-inch $label crashed after rendering."
      return 1
    fi
    simctl_bounded "terminate 13-inch preview" 35 terminate "$UDID" com.wesc9.athlth || true
  }

  preview_13_inch "home" "--athlth-compatibility-tab=0"
  preview_13_inch "plan-studio" "--athlth-compatibility-tab=1"
  preview_13_inch "library-exercises" "--athlth-compatibility-library=exercises"
  preview_13_inch "profile" "--athlth-compatibility-sidebar=profile"
  echo "ATHLTH 13-inch iPad Home, Plan Studio, library, and Profile passed."
  exit 0
fi

LAUNCH_OUTPUT=$(simctl_bounded "launch iPad onboarding" 65 launch "$UDID" com.wesc9.athlth)
echo "$LAUNCH_OUTPUT"
LAUNCH_PID=$(echo "$LAUNCH_OUTPUT" | awk -F': ' '/com\.wesc9\.athlth:/ {print $2}')
sleep 5
if [ -z "$LAUNCH_PID" ] || ! kill -0 "$LAUNCH_PID" 2>/dev/null; then
  echo "::error::ATHLTH iPad onboarding exited before rendering."
  exit 1
fi
validate_screen "onboarding"
if ! kill -0 "$LAUNCH_PID" 2>/dev/null; then
  echo "::error::ATHLTH iPad onboarding exited after rendering."
  exit 1
fi
simctl_bounded "terminate iPad preview" 35 terminate "$UDID" com.wesc9.athlth || true

for TAB in 0 1 2 3 4; do
  echo "Rendering ATHLTH iPad tab $TAB"

  TAB_OUTPUT=$(simctl_bounded "launch iPad tab $TAB" 65 launch "$UDID" com.wesc9.athlth \
    --athlth-compatibility-preview \
    "--athlth-compatibility-tab=$TAB" 2>&1)
  echo "$TAB_OUTPUT"

  TAB_PID=$(echo "$TAB_OUTPUT" | awk -F': ' '/com\.wesc9\.athlth:/ {print $2}')
  sleep 5

  if [ -z "$TAB_PID" ] || ! kill -0 "$TAB_PID" 2>/dev/null; then
    echo "::error::ATHLTH iPad tab $TAB exited after launch."
    simctl_bounded "capture iPad crash logs" 65 spawn "$UDID" log show --last 3m --style compact --predicate 'process == "ATHLTH" OR eventMessage CONTAINS "com.wesc9.athlth"' || true
    exit 1
  fi

  validate_screen "tab-$TAB"
  simctl_bounded "terminate iPad preview" 35 terminate "$UDID" com.wesc9.athlth || true
done

# Verify the new native Studio library pages on the iPad, not
# just the five top-level tabs. A missing source/empty layout must
# no longer be hidden behind the full-screen Train overlay.
for LIBRARY in overview exercises workouts trainingPlans routes; do
  echo "Rendering inline ATHLTH iPad library: $LIBRARY"

  LIBRARY_OUTPUT=$(simctl_bounded "launch iPad library $LIBRARY" 65 launch "$UDID" com.wesc9.athlth \
    --athlth-compatibility-preview \
    "--athlth-compatibility-library=$LIBRARY" 2>&1)
  echo "$LIBRARY_OUTPUT"

  LIBRARY_PID=$(echo "$LIBRARY_OUTPUT" | awk -F': ' '/com\.wesc9\.athlth:/ {print $2}')
  sleep 5

  if [ -z "$LIBRARY_PID" ] || ! kill -0 "$LIBRARY_PID" 2>/dev/null; then
    echo "::error::ATHLTH iPad library $LIBRARY exited after launch."
    simctl_bounded "capture iPad crash logs" 65 spawn "$UDID" log show --last 3m --style compact --predicate 'process == "ATHLTH"' || true
    exit 1
  fi

  validate_screen "library-$LIBRARY"
  simctl_bounded "terminate iPad preview" 35 terminate "$UDID" com.wesc9.athlth || true
done

# Profile previously crashed with SwiftUI EnvironmentObject.error()
# when selected from the real iPad sidebar. Verify it stays alive.
PROFILE_OUTPUT=$(simctl_bounded "launch iPad profile" 65 launch "$UDID" com.wesc9.athlth \
  --athlth-compatibility-preview \
  "--athlth-compatibility-sidebar=profile" 2>&1)
echo "$PROFILE_OUTPUT"
PROFILE_PID=$(echo "$PROFILE_OUTPUT" | awk -F': ' '/com\.wesc9\.athlth:/ {print $2}')
sleep 5
if [ -z "$PROFILE_PID" ] || ! kill -0 "$PROFILE_PID" 2>/dev/null; then
  echo "::error::ATHLTH iPad sidebar Profile crashed during presentation."
  simctl_bounded "capture iPad profile crash logs" 65 spawn "$UDID" log show --last 3m --style compact --predicate 'process == "ATHLTH"' || true
  exit 1
fi
validate_screen "sidebar-profile"
if ! kill -0 "$PROFILE_PID" 2>/dev/null; then
  echo "::error::ATHLTH iPad sidebar Profile crashed after rendering."
  exit 1
fi
simctl_bounded "terminate iPad preview" 35 terminate "$UDID" com.wesc9.athlth || true

# The 11-inch matrix job is complete after these 12 validated screens.
# A separate 13-inch job tests the larger layout on a fresh runner.
if [ "$IPAD_SIZE" = "11" ]; then
  echo "ATHLTH 11-inch iPad onboarding, tabs, libraries and profile passed."
  exit 0
fi

# Check the actual first logged-in Studio frame on a larger iPad,
# in addition to the 11-inch device tested above. Keep the PNG for
# visual inspection; entropy alone cannot prove layout quality.
if UDID_13=$(create_compatible_ipad 13 "ATHLTH-iPad-13"); then
  echo "Rendering the first Studio screen on a 13-inch iPad."
  if [ "$IPAD_SIMULATOR_OWNED" = "1" ]; then
    simctl_bounded "shutdown previous temporary iPad" 35 shutdown "$UDID" >/dev/null 2>&1 || true
    simctl_bounded "delete previous temporary iPad" 35 delete "$UDID" >/dev/null 2>&1 || true
  fi
  UDID="$UDID_13"
  IPAD_SIMULATOR_OWNED=1
  simctl_bounded "boot 13-inch iPad" 100 boot "$UDID"
  simctl_bounded "wait for 13-inch iPad boot" 160 bootstatus "$UDID" -b
  install_ipad_app 13
  simctl_bounded "launch 13-inch iPad home" 65 launch "$UDID" com.wesc9.athlth \
    --athlth-compatibility-preview \
    "--athlth-compatibility-tab=0"
  validate_screen "13-inch-home"
  simctl_bounded "terminate iPad preview" 35 terminate "$UDID" com.wesc9.athlth || true
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
