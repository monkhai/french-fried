#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
: "${BUILD_NUMBER:?Set BUILD_NUMBER to a new numeric build number}"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo 'BUILD_NUMBER must be numeric.' >&2; exit 1; }
[[ -f Production/App/Local.xcconfig ]] || { echo 'Configure Production/App/Local.xcconfig first.' >&2; exit 1; }
command -v xcodegen >/dev/null
xcodegen generate --spec Production/App/project.yml
mkdir -p release/output
xcodebuild -project Production/App/FrenchFried.xcodeproj -scheme FrenchFried \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ROOT/release/output/FrenchFried-$BUILD_NUMBER.xcarchive" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" MARKETING_VERSION="${MARKETING_VERSION:-1.0}" \
  -allowProvisioningUpdates archive
printf 'Archive ready. Export with scripts/export-app.sh %s\n' "$BUILD_NUMBER"
