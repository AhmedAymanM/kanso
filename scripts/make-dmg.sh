#!/bin/bash
# Packages app/build/Kanso.app into a styled DMG (background, icon placement, Applications link) with create-dmg.
# Usage: scripts/make-dmg.sh [OUT.dmg]   env: SIGN_IDENTITY (signs the DMG itself when set and not "-")
set -euo pipefail
cd "$(dirname "$0")/.."
APP=app/build/Kanso.app
OUT="${1:-app/build/Kanso.dmg}"
[ -d "$APP" ] || { echo "missing $APP: run app/build.sh first" >&2; exit 1; }
command -v create-dmg >/dev/null || brew install create-dmg

BG=app/build/dmg-background.png
swift release/dmg-background.swift "$BG"
STAGE=$(mktemp -d); cp -R "$APP" "$STAGE/"
rm -f "$OUT"
create-dmg --volname "Kanso" --background "$BG" \
  --window-pos 200 120 --window-size 660 400 --icon-size 112 \
  --icon "Kanso.app" 180 235 --app-drop-link 480 235 \
  --hide-extension "Kanso.app" --format UDZO --no-internet-enable "$OUT" "$STAGE"
rm -rf "$STAGE"
if [ "${SIGN_IDENTITY:--}" != "-" ]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$OUT"
fi
echo "built $OUT"
