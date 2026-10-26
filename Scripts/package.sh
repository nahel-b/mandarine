#!/bin/bash
# Prépare Mandarine pour un ami : dist/Mandarine.dmg (+ .zip).
#
# Usage :
#   Scripts/package.sh                       # arm64, signature « ad hoc » (l'ami doit autoriser l'app une fois, voir LISEZ-MOI)
#   UNIVERSAL=1 Scripts/package.sh           # fonctionne aussi sur Mac Intel
#   SIGN_ID="Developer ID Application: Nom (TEAMID)" NOTARY_PROFILE=monprofil Scripts/package.sh
#                                            # signature + notarisation Apple : aucun avertissement chez l'ami (compte développeur payant)
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "${UNIVERSAL:-0}" = "1" ]; then export MANDARINE_UNIVERSAL=1; fi
Scripts/build_app.sh release
APP="build/Mandarine.app"

if [ -n "${SIGN_ID:-}" ]; then
  echo "→ signature avec « $SIGN_ID »"
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$APP"
  codesign --verify --deep --strict "$APP"
fi

rm -rf dist && mkdir -p dist/staging
cp -R "$APP" dist/staging/
ln -s /Applications dist/staging/Applications
cat > dist/staging/LISEZ-MOI.txt <<'TXT'
Mandarine — installation

1. Glissez Mandarine dans le dossier Applications.
2. Ouvrez-le. Si macOS dit qu'il ne peut pas vérifier l'app :
   Réglages Système → Confidentialité et sécurité → descendez → « Ouvrir quand même » (à faire une seule fois).
   (Ou dans le Terminal : xattr -dr com.apple.quarantine /Applications/Mandarine.app)
3. Pour les vidéos, l'audio et le WebP, il faut ffmpeg. Collez dans le Terminal :
   - avec Homebrew :
       brew install ffmpeg webp
   - sans Homebrew (télécharge ffmpeg + ffprobe, les installe et les autorise) :
       D=~/Library/Application\ Support/Mandarine/bin; mkdir -p "$D"; cd "$D"
       for t in ffmpeg ffprobe; do curl -sL "$(curl -s https://evermeet.cx/ffmpeg/info/$t/release | plutil -extract download.zip.url raw -o - -)" -o $t.zip && unzip -oq $t.zip && rm $t.zip; done
       chmod +x ffmpeg ffprobe; xattr -dr com.apple.quarantine .
       ./ffmpeg -version | head -1
     (Apple silicon, si le Terminal répond « Bad CPU type » : sudo softwareupdate --install-rosetta --agree-to-license)
   Pour télécharger des liens YouTube en MP3/MP4 (roue ⌘ sur un lien) : brew install yt-dlp
   ou, sans Homebrew :
       D=~/Library/Application\ Support/Mandarine/bin; mkdir -p "$D"
       curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos -o "$D/yt-dlp"
       chmod +x "$D/yt-dlp"; xattr -dr com.apple.quarantine "$D"
   (Plus simple : Réglages → Engines → Download télécharge ffmpeg, WebP, yt-dlp et le modèle de visages.)
4. Glissez un fichier, puis tapez ⇧ (convertir), ⌘ (outils) ou ⌃ (actions).
5. Les mises à jour se font ensuite toutes seules (Réglages → Updates).
TXT
hdiutil create -volname "Mandarine" -srcfolder dist/staging -ov -format UDZO dist/Mandarine.dmg >/dev/null
ditto -c -k --keepParent "$APP" dist/Mandarine.zip
rm -rf dist/staging

if [ -n "${SIGN_ID:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "→ notarisation (quelques minutes)…"
  xcrun notarytool submit dist/Mandarine.dmg --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple dist/Mandarine.dmg
fi

echo; echo "Prêt :"; ls -lh dist/Mandarine.dmg dist/Mandarine.zip | awk '{print "  " $9 "  " $5}'
shasum -a 256 dist/Mandarine.dmg | awk '{print "  SHA-256 " $1}'
