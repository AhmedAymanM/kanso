#!/bin/bash
# Builds app/build/Kanso.app (release). Ad-hoc signed unless SIGN_IDENTITY is set (a "Developer ID Application: ..." name or
# SHA-1), in which case it is signed with the hardened runtime + secure timestamp that notarization requires.
# KANSO_VERSION / KANSO_BUILD override the Info.plist version strings. Run it with: open app/build/Kanso.app
# Finder's "Don't Sort with Kanso" service appears once the app is in /Applications or ~/Applications.
set -euo pipefail
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
VERSION="${KANSO_VERSION:-1.0}"
BUILD="${KANSO_BUILD:-1}"
cd "$(dirname "$0")"
swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP=build/Kanso.app
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
  <key>CFBundleName</key><string>Kanso</string>
  <key>CFBundleDisplayName</key><string>Kanso</string>
  <key>CFBundleIdentifier</key><string>app.kanso.Kanso</string>
  <key>CFBundleExecutable</key><string>Kanso</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Kanso contributors · GPL-3.0</string>
  <key>NSDesktopFolderUsageDescription</key><string>Kanso sorts new files on your Desktop onto shelves.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Kanso sorts new files in Documents onto shelves.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Kanso sorts new downloads onto shelves.</string>
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

if [ "$SIGN_IDENTITY" = "-" ]; then
  CS=(codesign --force --sign -)
else
  CS=(codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp)
fi
"${CS[@]}" "$APP/Contents/Helpers/kanso-cli"
"${CS[@]}" --entitlements ../release/entitlements.plist "$APP"
echo "built $(pwd)/$APP"
