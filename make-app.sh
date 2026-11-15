#!/bin/bash
# Builds "Monitor Control.app" from the MonitorControl target.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product MonitorControl

APP="build/Monitor Control.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MonitorControl "$APP/Contents/MacOS/MonitorControl"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>MonitorControl</string>
  <key>CFBundleIdentifier</key><string>io.trucue.monitorcontrol</string>
  <key>CFBundleName</key><string>Monitor Control</string>
  <key>CFBundleDisplayName</key><string>Monitor Control</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSLocalNetworkUsageDescription</key>
  <string>Monitor Control talks to Lilliput monitors on your local network (UDP 19522/19523).</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built: $APP"
