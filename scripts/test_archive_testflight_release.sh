#!/usr/bin/env bash
# Exercise both archive variants without Xcode, credentials or network access.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
cat > "$tmp/bin/xcodebuild" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "-version" ]; then echo "mock Xcode"; exit 0; fi
printf '%s\n' "$@" > "$RUNNER_TEMP/args"
if [ "${MOCK_ARCHIVE_FAIL:-0}" = "1" ]; then exit 73; fi
mkdir -p "$RUNNER_TEMP/ATHLTH.xcarchive/Products/Applications/ATHLTH.app"
MOCK
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/sysctl"
printf '#!/usr/bin/env bash\n/bin/sleep 0.01\n' > "$tmp/bin/sleep"
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH"
script="$root/scripts/archive_testflight_release.sh"
bash -n "$script"

for mode in 0 1; do
  export RUNNER_TEMP="$tmp/run$mode"
  export ATHLTH_GARMIN_INTERNAL_TEST="$mode"
  export GITHUB_REF=refs/heads/release/v3.0.2
  mkdir "$RUNNER_TEMP"
  bash "$script"
  grep -Fx 'archive' "$RUNNER_TEMP/args"
  grep -Fx 'CODE_SIGNING_ALLOWED=NO' "$RUNNER_TEMP/args"
  if [ "$mode" = "1" ]; then
    grep -Fx 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) ATHLTH_GARMIN_PERSONAL ATHLTH_GARMIN_INTERNAL_TEST' "$RUNNER_TEMP/args"
  else
    if grep -q GARMIN "$RUNNER_TEMP/args"; then exit 1; fi
  fi
  echo "PASS archive mode $mode"
done

export RUNNER_TEMP="$tmp/wrong-branch"
export GITHUB_REF=refs/heads/main ATHLTH_GARMIN_INTERNAL_TEST=1
mkdir "$RUNNER_TEMP"
if bash "$script"; then exit 1; fi
test ! -f "$RUNNER_TEMP/args"
echo "PASS Garmin internal archive rejected on wrong branch"

export RUNNER_TEMP="$tmp/failure"
export GITHUB_REF=refs/heads/release/v3.0.2 ATHLTH_GARMIN_INTERNAL_TEST=0 MOCK_ARCHIVE_FAIL=1
mkdir "$RUNNER_TEMP"
status=0
bash "$script" || status=$?
test "$status" = "73"
echo "PASS archive exit status propagated"
