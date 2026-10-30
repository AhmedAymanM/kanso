#!/bin/bash
# Builds app/build/Kanso.app (release). Run it with: open app/build/Kanso.app
# Finder's "Don't Sort with Kanso" service appears once the app is in /Applications or ~/Applications.
#
# Environment (all optional; with none set the app is ad-hoc signed):
#   KANSO_VERSION     marketing version (default: latest git tag, else 1.0)
#   KANSO_REPO_URL    project page (default https://github.com/AhmedAymanM/kanso)
#   KANSO_DONATE_URL  donation page; empty hides the Buy Me a Coffee card
#   SIGN_ID           Developer ID Application identity; enables --timestamp
#   NOTARY_PROFILE    notarytool keychain profile; notarizes and staples (needs SIGN_ID)
#   MAKE_DMG=1        also writes build/Kanso.dmg
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP=build/Kanso.app
ENT=Kanso.entitlements

# Versions: the marketing version comes from KANSO_VERSION or the latest tag; the build number counts commits.
GIT_TAG=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)
VERSION="${KANSO_VERSION:-$GIT_TAG}"
VERSION="${VERSION:-1.0}"
BUILD=$(git rev-list --count HEAD 2>/dev/null || true)
BUILD="${BUILD:-1}"
REPO_URL="${KANSO_REPO_URL:-https://github.com/AhmedAymanM/kanso}"
DONATE_URL="${KANSO_DONATE_URL:-}"
# XML-escape values that go into the plist.
xml() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp "$BIN/Kanso" "$APP/Contents/MacOS/Kanso"
cp "$BIN/kanso-cli" "$APP/Contents/Helpers/kanso-cli"

# App icon, rendered by the app itself
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
"$BIN/Kanso" --icon build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Kanso</string>
  <key>CFBundleDisplayName</key><string>Kanso</string>
  <key>CFBundleIdentifier</key><string>app.kanso.Kanso</string>
  <key>CFBundleExecutable</key><string>Kanso</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$(xml "$VERSION")</string>
  <key>CFBundleVersion</key><string>$(xml "$BUILD")</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Kanso contributors · GPL-3.0</string>
  <key>NSDesktopFolderUsageDescription</key><string>Kanso sorts new files on your Desktop onto shelves.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Kanso sorts new files in Documents onto shelves.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Kanso sorts new downloads onto shelves.</string>
  <key>NSRemovableVolumesUsageDescription</key><string>Kanso sorts files in watched folders on removable drives, and ejects a mounted disk image (Smart Eject) once its app is installed.</string>
  <key>NSNetworkVolumesUsageDescription</key><string>Kanso sorts files in watched folders on network volumes.</string>
  <key>KansoRepoURL</key><string>$(xml "$REPO_URL")</string>
  <key>KansoDonateURL</key><string>$(xml "$DONATE_URL")</string>
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>Don't Sort with Kanso</string></dict>
      <key>NSMessage</key><string>skipFiles</string>
      <key>NSPortName</key><string>Kanso</string>
      <key>NSRequiredContext</key><dict/>
      <key>NSSendFileTypes</key><array><string>public.item</string></array>
    </dict>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>Add to Kanso Tray</string></dict>
      <key>NSMessage</key><string>addToTray</string>
      <key>NSPortName</key><string>Kanso</string>
      <key>NSRequiredContext</key><dict/>
      <key>NSSendFileTypes</key><array><string>public.item</string></array>
    </dict>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>Allow Kanso to Sort</string></dict>
      <key>NSMessage</key><string>allowFiles</string>
      <key>NSPortName</key><string>Kanso</string>
      <key>NSRequiredContext</key><dict/>
      <key>NSSendFileTypes</key><array><string>public.item</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# Signing: helpers first, the app last, never --deep. Ad-hoc unless SIGN_ID is set.
SIGN_FLAGS=(--force --options runtime --entitlements "$ENT" --sign "${SIGN_ID:--}")
if [ -n "${SIGN_ID:-}" ]; then SIGN_FLAGS+=(--timestamp); fi
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/Helpers/kanso-cli"
codesign "${SIGN_FLAGS[@]}" "$APP"

# Notarization: submit a zip, wait, then staple the ticket to the app itself.
if [ -n "${NOTARY_PROFILE:-}" ]; then
  if [ -z "${SIGN_ID:-}" ]; then
    echo "NOTARY_PROFILE needs SIGN_ID (a Developer ID Application identity)" >&2
    exit 1
  fi
  ZIP=build/Kanso-notarize.zip
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
fi

if [ "${MAKE_DMG:-0}" = "1" ]; then
  rm -f build/Kanso.dmg
  hdiutil create -volname Kanso -srcfolder build/Kanso.app -ov -format UDZO build/Kanso.dmg
fi
echo "built $(pwd)/$APP (version $VERSION, build $BUILD)"
