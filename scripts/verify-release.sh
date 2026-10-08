#!/bin/bash
# Gatekeeper-level checks on a finished release DMG: signature, assessment, stapled ticket.
# Usage: scripts/verify-release.sh Kanso.dmg
set -euo pipefail
DMG="$1"
MNT=$(mktemp -d)
hdiutil attach "$DMG" -mountpoint "$MNT" -nobrowse -readonly -quiet
trap 'hdiutil detach "$MNT" -quiet || true' EXIT
APP="$MNT/Kanso.app"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "flags=.*runtime" >/dev/null || { echo "hardened runtime missing" >&2; exit 1; }
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
xcrun stapler validate "$DMG"
echo "release verified: $DMG"
