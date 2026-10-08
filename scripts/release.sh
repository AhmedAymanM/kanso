#!/bin/bash
# End-to-end release: build -> sign -> DMG -> notarize -> staple -> verify. Run on a Mac.
# Usage: scripts/release.sh VERSION [BUILD]     e.g. scripts/release.sh 1.0.0 1
# env (see RELEASE.md): SIGN_IDENTITY, APPLE_API_KEY_ID, APPLE_API_ISSUER_ID, APPLE_API_PRIVATE_KEY | APPLE_API_KEY_PATH
set -euo pipefail
cd "$(dirname "$0")/.."
export KANSO_VERSION="${1:?version}" KANSO_BUILD="${2:-1}"
: "${SIGN_IDENTITY:?set SIGN_IDENTITY to your \"Developer ID Application: Name (TEAMID)\"}"
(cd app && swift test)
app/build.sh
DMG="app/build/Kanso-$KANSO_VERSION.dmg"
scripts/make-dmg.sh "$DMG"
scripts/notarize.sh "$DMG"
scripts/verify-release.sh "$DMG"
echo "ready to publish: $DMG"
