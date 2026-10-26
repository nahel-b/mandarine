#!/bin/bash
# Compile Mandarine et assemble Mandarine.app dans ./build
# Usage : Scripts/build_app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
VERSION="${APP_VERSION:-$(tr -d '[:space:]' < VERSION)}"
GITHUB_REPO=""; [ -f Scripts/update.conf ] && . Scripts/update.conf
PUBKEY=""; [ -f Scripts/update_public_key.txt ] && PUBKEY="$(tr -d '[:space:]' < Scripts/update_public_key.txt)"
ARCHFLAGS=()
if [ "${MANDARINE_UNIVERSAL:-0}" = "1" ]; then ARCHFLAGS=(--arch arm64 --arch x86_64); fi
swift build -c "$CONFIG" ${ARCHFLAGS[@]+"${ARCHFLAGS[@]}"}
BIN="$(swift build -c "$CONFIG" ${ARCHFLAGS[@]+"${ARCHFLAGS[@]}"} --show-bin-path)/Mandarine"
APP="build/Mandarine.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"
cp "$BIN" "$APP/Contents/MacOS/Mandarine"
# Binaires optionnels embarqués (ffmpeg / ffprobe) : placez-les dans Resources/bin avant de lancer ce script.
if [ -d "Resources/bin" ]; then cp -R Resources/bin/. "$APP/Contents/Resources/bin/"; fi
for f in Resources/*.mp3 Resources/*.wav Resources/MenuBarIcon*; do [ -f "$f" ] && cp "$f" "$APP/Contents/Resources/"; done
[ -f logo.svg ] && cp logo.svg "$APP/Contents/Resources/logo.svg"
if [ -f "Resources/AppIcon.icns" ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Mandarine</string>
  <key>CFBundleDisplayName</key><string>Mandarine</string>
  <key>CFBundleIdentifier</key><string>com.mandarine.app</string>
  <key>CFBundleExecutable</key><string>Mandarine</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>MandarineUpdateRepo</key><string>$GITHUB_REPO</string>
  <key>MandarineUpdatePublicKey</key><string>$PUBKEY</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Mandarine pilote Pages, Keynote et Numbers pour convertir leurs formats.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "→ $APP"
