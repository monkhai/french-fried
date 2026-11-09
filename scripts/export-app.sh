#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD_NUMBER="${1:?Usage: scripts/export-app.sh BUILD_NUMBER}"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || exit 1
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to your Apple Developer team ID}"
[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo 'Invalid team ID.' >&2; exit 1; }
mkdir -p release/output
python3 - "$APPLE_TEAM_ID" <<'PY'
import plistlib, sys
with open('release/output/ExportOptions.plist', 'wb') as f:
    plistlib.dump({'method': 'app-store-connect', 'destination': 'export',
                  'teamID': sys.argv[1], 'signingStyle': 'automatic',
                  'manageAppVersionAndBuildNumber': False}, f)
PY
xcodebuild -exportArchive \
  -archivePath "$ROOT/release/output/FrenchFried-$BUILD_NUMBER.xcarchive" \
  -exportPath "$ROOT/release/output/app-store-$BUILD_NUMBER" \
  -exportOptionsPlist "$ROOT/release/output/ExportOptions.plist" \
  -allowProvisioningUpdates
