#!/usr/bin/env bash
# Same unsigned physical-device Release archive for preflight and TestFlight.
set -euo pipefail
: "${RUNNER_TEMP:?}"
LOG="$RUNNER_TEMP/athlth-release-archive.log"
START=$(date +%s)
echo "Release archive started; CPU and memory:"
sysctl hw.logicalcpu hw.memsize
xcodebuild -version
# Fresh, job-local output. No cross-commit compiled app cache.
GARMIN_FLAGS=()
if [ "${ATHLTH_GARMIN_INTERNAL_TEST:-0}" = "1" ]; then
  test "${GITHUB_REF:-}" = "refs/heads/release/v3.0.2"
  GARMIN_FLAGS+=('SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) ATHLTH_GARMIN_PERSONAL ATHLTH_GARMIN_INTERNAL_TEST')
fi
xcodebuild \
  -project ATHLTH.xcodeproj \
  -scheme ATHLTH \
  -clonedSourcePackagesDirPath "$RUNNER_TEMP/ATHLTHSourcePackages" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$RUNNER_TEMP/ATHLTHReleaseDerivedData" \
  -archivePath "$RUNNER_TEMP/ATHLTH.xcarchive" \
  -showBuildTimingSummary \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  DEVELOPMENT_TEAM="${APPLE_TEAM_ID:-D3AX7B6RMW}" \
  "${GARMIN_FLAGS[@]}" \
  archive > "$LOG" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' INT TERM EXIT
while kill -0 "$pid" 2>/dev/null; do
  sleep 30
  if kill -0 "$pid" 2>/dev/null; then
    echo "::notice::Release archive still running after $((($(date +%s)-START)/60)) min"
    tail -n 6 "$LOG" | cut -c 1-500
  fi
done
status=0
wait "$pid" || status=$?
trap - INT TERM EXIT
tail -n 160 "$LOG" | cut -c 1-2000
echo "Release archive elapsed seconds: $(($(date +%s)-START))"
if [ "$status" -ne 0 ]; then exit "$status"; fi
test -d "$RUNNER_TEMP/ATHLTH.xcarchive/Products/Applications/ATHLTH.app"
