#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
: "${ASC_APP_ID:?Set ASC_APP_ID to the App Store Connect app ID}"
IPA="${1:?Usage: scripts/upload-app.sh path/to/FrenchFried.ipa}"
[[ -f "$IPA" ]] || { echo 'IPA not found.' >&2; exit 1; }
ASC_BIN="${ASC_BIN:-$ROOT/.tools/asc}"
"$ASC_BIN" auth status --validate
"$ASC_BIN" builds upload --app "$ASC_APP_ID" --ipa "$IPA" --wait
# Uploading does not submit for review or release the app.
