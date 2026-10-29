# Mandarine

Convertisseur de fichiers hors-ligne pour Mac, en Swift, inspiré de Tangerine (voir `FEATURES.md`).
Glissez un fichier, tapez **⇧** (convertir), **⌘** (outils) ou **⌃** (actions) : la roue apparaît au curseur, déposez sur un segment.

## Compiler et lancer
```bash
Scripts/build_app.sh release     # produit build/Mandarine.app
open build/Mandarine.app          # icône dans la barre de menus
```
Pour tester sans glisser-déposer : menu de la barre → « Try … wheel… », ou
`build/Mandarine.app/Contents/MacOS/Mandarine --wheel convert|tools|actions <fichiers>` / `--tool <ToolID> <fichiers>`.

## Moteurs
- Images : ImageIO / CoreImage / Vision (natif). WebP : `cwebp` (ou ffmpeg+libwebp).
- Vidéo / audio : **ffmpeg** (téléchargé par l'app dans Réglages → Engines, ou `brew install ffmpeg webp`).
- PDF : PDFKit. Documents : AppKit/CoreText. Archives : bsdtar/zip/gzip système.
- Présentations (PPT/PPTX) : LibreOffice si installé.

## Son et haptique
Tick synthétisé + retour haptique trackpad. Pour un autre son, placez `HighlightSound.wav` (ou `.mp3`) dans
`Resources/` avant de compiler, ou dans `~/Library/Application Support/Mandarine/`.
