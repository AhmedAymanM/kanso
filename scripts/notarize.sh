#!/bin/bash
# Submits a DMG to Apple's notary service with an App Store Connect API key, waits, and staples the ticket.
# Usage: scripts/notarize.sh Kanso.dmg
# env: APPLE_API_KEY_ID, APPLE_API_ISSUER_ID, and APPLE_API_PRIVATE_KEY (PEM text of the .p8) or APPLE_API_KEY_PATH
set -euo pipefail
DMG="$1"
: "${APPLE_API_KEY_ID:?}" "${APPLE_API_ISSUER_ID:?}"
if [ -z "${APPLE_API_KEY_PATH:-}" ]; then
  : "${APPLE_API_PRIVATE_KEY:?set APPLE_API_PRIVATE_KEY or APPLE_API_KEY_PATH}"
  KEYFILE=$(mktemp); trap 'rm -f "$KEYFILE"' EXIT
  printf '%s\n' "$APPLE_API_PRIVATE_KEY" > "$KEYFILE"
else
  KEYFILE="$APPLE_API_KEY_PATH"
fi
xcrun notarytool submit "$DMG" --key "$KEYFILE" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID" --wait --output-format json | tee notary.json
grep -q '"status" *: *"Accepted"' notary.json || { echo "notarization not accepted" >&2; exit 1; }
xcrun stapler staple "$DMG"
