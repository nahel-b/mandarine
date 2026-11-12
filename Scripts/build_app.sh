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
# Bibliothèque Whisper (reconnaissance vocale optionnelle) : framework universel, dans Contents/Frameworks
FW=".build/artifacts/mandarine/whisper/whisper.xcframework/macos-arm64_x86_64/whisper.framework"
[ -d "$FW" ] || { echo "whisper.framework introuvable (lancez swift package resolve)"; exit 1; }
mkdir -p "$APP/Contents/Frameworks" && cp -R "$FW" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Mandarine" 2>/dev/null || true
# Binaires optionnels embarqués (ffmpeg / ffprobe) : placez-les dans Resources/bin avant de lancer ce script.
if [ -d "Resources/bin" ]; then cp -R Resources/bin/. "$APP/Contents/Resources/bin/"; fi
if [ -d "Resources/Localization" ]; then mkdir -p "$APP/Contents/Resources/Localization" && cp -R Resources/Localization/. "$APP/Contents/Resources/Localization/"; fi
for f in Resources/*.mp3 Resources/*.wav Resources/MenuBarIcon* Resources/WiiTV*.png; do [ -f "$f" ] && cp "$f" "$APP/Contents/Resources/"; done
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
  <key>LSMinimumSystemVersion</key><string>13.3</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSpeechRecognitionUsageDescription</key><string>Mandarine transcrit vos sons et vidéos en texte et en sous-titres avec la reconnaissance vocale d’Apple.</string>
  <key>NSAppleEventsUsageDescription</key><string>Mandarine pilote Pages, Keynote et Numbers pour convertir leurs formats.</string>
</dict></plist>
PLIST
# Signature « ad hoc », mais avec une exigence stable (l'identifiant de l'app) plutôt que l'empreinte du binaire : sans cela, macOS
# oublie l'accès complet au disque (et les autres autorisations) à chaque nouvelle version.
codesign --force --deep --sign - -r='designated => identifier "com.mandarine.app"' "$APP" >/dev/null 2>&1 || codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "→ $APP"
