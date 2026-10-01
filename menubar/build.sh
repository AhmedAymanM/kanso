#!/bin/bash
# Builds menubar/build/Tidy.app, wired to this checkout's `tidy` CLI.
set -euo pipefail
cd "$(dirname "$0")"
CLI="$(cd .. && pwd)/.venv/bin/tidy"
[ -x "$CLI" ] || (cd .. && uv sync)

APP=build/Tidy.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos13 Tidy.swift -o "$APP/Contents/MacOS/Tidy"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Tidy</string>
  <key>CFBundleIdentifier</key><string>com.tidy.menubar</string>
  <key>CFBundleExecutable</key><string>Tidy</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>TidyCLI</key><string>$CLI</string>
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>Don't Sort with Tidy</string></dict>
      <key>NSMessage</key><string>skipFiles</string>
      <key>NSPortName</key><string>Tidy</string>
      <key>NSRequiredContext</key><dict/>
      <key>NSSendFileTypes</key><array><string>public.item</string></array>
    </dict>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>Allow Tidy to Sort</string></dict>
      <key>NSMessage</key><string>allowFiles</string>
      <key>NSPortName</key><string>Tidy</string>
      <key>NSRequiredContext</key><dict/>
      <key>NSSendFileTypes</key><array><string>public.item</string></array>
    </dict>
  </array>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"

# Finder only offers services from installed apps
DEST="$HOME/Applications/Tidy.app"
pkill -x Tidy || true
mkdir -p "$HOME/Applications" && rm -rf "$DEST" && cp -R "$APP" "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
/System/Library/CoreServices/pbs -update
open "$DEST"
echo "installed $DEST"
