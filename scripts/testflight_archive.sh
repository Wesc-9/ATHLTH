#!/bin/bash
set -euo pipefail

APPLE_TEAM_ID="${APPLE_TEAM_ID:-D3AX7B6RMW}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE_PATH="$ROOT_DIR/build/ATHLTH.xcarchive"

cd "$ROOT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required. Install it with: brew install xcodegen"
  exit 1
fi

echo "Generating Xcode project..."
xcodegen generate

echo "Creating signed Release archive for team $APPLE_TEAM_ID..."
rm -rf "$ARCHIVE_PATH"

xcodebuild   -project ATHLTH.xcodeproj   -scheme ATHLTH   -configuration Release   -destination 'generic/platform=iOS'   -archivePath "$ARCHIVE_PATH"   DEVELOPMENT_TEAM="$APPLE_TEAM_ID"   CODE_SIGN_STYLE=Automatic   -allowProvisioningUpdates   archive

echo
echo "Archive created:"
echo "$ARCHIVE_PATH"
echo
echo "Next:"
echo "1. Open Xcode > Window > Organizer > Archives."
echo "2. Select ATHLTH."
echo "3. Choose Distribute App."
echo "4. Choose TestFlight Internal Only for the first build."
echo "5. Keep Automatically manage signing enabled."
