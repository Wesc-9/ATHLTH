#!/bin/bash
set -euo pipefail

APPLE_TEAM_ID="${APPLE_TEAM_ID:-D3AX7B6RMW}"

XCODE_27_PATH="/Applications/Xcode_27.0.app/Contents/Developer"
if [[ -d "$XCODE_27_PATH" ]]; then
  export DEVELOPER_DIR="$XCODE_27_PATH"
fi

XCODE_VERSION="$(xcodebuild -version | head -n 1)"
echo "Using $XCODE_VERSION"

if [[ "$XCODE_VERSION" != Xcode\ 27* ]]; then
  echo "ATHLTH TestFlight archives should be built with Xcode 27."
  echo "Install/select Xcode 27, then run this script again."
  exit 1
fi

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
