# Mandarine — spec (reproduction de « Tangerine for Mac », relevée sur tangerineformac.com)

Utilitaire de barre de menus, hors-ligne. On **glisse un fichier**, puis on **tape une touche** pendant le drag :
une **roue radiale** apparaît au curseur ; on dépose le fichier sur un segment. La roue reste ouverte
jusqu'au drop (même après relâchement de la touche). Touches configurables dans Réglages.

| Touche (défaut) | Roue | Contenu |
|---|---|---|
| ⇧ Shift   | Convert formats | formats de sortie selon le type de fichier |
| ⌘ Command | File tools      | outils de fichier selon le type |
| ⌃ Control | File actions    | AirDrop, Float, Copy, Move, Copy Path, Terminal (dossiers et sélections mixtes OK) |

Conversions/éditions : **toujours une copie** à côté de l'original (jamais d'écrasement). Les actions de fichier ne
consomment pas le quota de conversion. 275 chemins de conversion, 26 outils, 6 actions.
Apple silicon, macOS 13+. Tout est local.

## Roue « Convert » (Shift) par type d'entrée
- **Images** (in : JPG PNG WebP HEIC TIFF AVIF BMP, SVG en entrée seulement) → PNG, WEBP, HEIC, TIFF, AVIF, BMP, PDF (+ JPG)
- **Vidéo** (MP4 MOV MKV WebM AVI WMV GIF) → MP4, MKV, WEBM, AVI, WMV, GIF, MP3 (export audio)
- **Audio** (MP3 M4A WAV FLAC OGG Opus AIFF WMA) → M4A, WAV, FLAC, OGG, OPUS, AIFF, WMA (+ MP3)
- **PDF** → DOCX, PAGES, PPTX, XLSX, JPG, PNG, EPUB, TXT, MD (toutes les pages, images 300 DPI)
- **Documents** (DOCX PAGES MD TXT EPUB ; RTF/RTFD/text clippings en entrée) → PAGES, PDF, TXT, MD, HTML, EPUB, PNG, JPG
- **Slides** (PPT/PPTX en entrée) → PDF, JPG, PNG
- **Spreadsheets** (XLSX ODS CSV TSV ; XLS en entrée) → ODS, CSV, TSV, PDF
- **EPUB** → PDF, DOCX, PAGES, TXT, MD, HTML
- **Subtitles** (SRT VTT) → VTT/SRT, TXT
- **Archives** (ZIP TAR GZIP ; RAR en entrée) → TAR, GZIP, ZIP
- Plusieurs images → **Create a PDF** (une page par image, formats mixtes)

## Roue « File tools » (Cmd)
- **Images** : COMPRESS, METADATA, EDIT, ANNOTATE, ADD BG, CROP, REDACT, TEXT (OCR) (+ Collage sur sélection multiple)
- **Vidéo** : COMPRESS, METADATA, MUTE, TRIM, CROP, SPEED, SNAPSHOT, SPLIT, REDACT (+ Join sur sélection)
- **Audio** : COMPRESS, METADATA, NORMALIZE, VISUALIZE, TRIM, CHANNELS, BLEEP
- **PDF** : COMPRESS, METADATA, SPLIT, ORGANIZE (+ Merge sur sélection)
- **Archives** : EXTRACT

## Les 25 fenêtres d'outils (UI : en-tête avec ✕ rond à gauche + titre centré, pied avec bouton d'action à droite)
1. **Compress** (tout fichier) — preset Balanced/Strong ; Image size (Keep original dimensions…) ; case « Compress to target file size » ; % de réduction ; taille d'origine affichée ; bouton Compress.
2. **Metadata** (tout fichier) — champ « Search metadata », champs groupés (ExifIFD, File, par piste/chapitre), valeurs éditables, ⊖ par ligne pour supprimer ; « Remove All » (efface aussi données caméra/traitement cachées ; HDR/portrait peuvent changer) et « Save ».
3. **Edit Photo** — aperçu live ; Light (Exposure, Brightness, Contrast, Highlights, Shadows, Whites, Blacks, Gamma) ; Color (Temperature, Tint, Saturation, Vibrance, Hue) ; Detail (Clarity, Dehaze, Grain, Noise reduction, Sharpen…) ; Effects ; ↺ reset par curseur ; « Save Edited Copy ».
4. **Annotate Photo** — outils : flèche, plume/stylo, texte (Aa), rectangle, cercle, surligneur, numéro (callout), loupe, image ; couleur ; undo/supprimer ; déplacer une annotation ; « Reset » / « Save Annotated Copy ».
5. **Add BG** — fond : dégradés prédéfinis, couleurs unies, autre image ; Padding, Corners, Shadow (+ flou) ; Ratio Auto/1:1/16:9/4:5 ; Reset / « Save with Background ».
6. **Crop Image** — cadre orange à poignées ; ratio Free/1:1/16:9/9:16/4:3/3:4 ; W×H px exacts ; Reset / Apply.
**Extract Text (OCR)** — images et PDF scannés (⌘ → TEXT) : lecture hors ligne via Vision, langue détectée automatiquement, texte modifiable, « Keep line breaks », Copy Text / Save as .txt.
7. **Redact Photo** — Style Solid/Blur ; couleur ; Detect Faces / Text (Vision, local) ; zones multiples déplaçables ; Reset / « Save Redacted Copy ».
8. **Create Collage** — Style (Grid/Row/Column/Featured), Columns, Canvas (Square 1:1…), Width (2 048 px…), Image fit (Fill cells / Fit), « Spacing & background », « Image order », Reset Layout, Create Collage.
9. **Trim Video** — lecteur ; frise de vignettes avec poignées ; Start/End timecodes éditables ; pas image par image ◁ ▷ ; lecture ; durée sélectionnée ; Apply.
10. **Crop Video** — comme Crop Image + scrub temporel + image par image ; garde l'audio.
11. **Change Video Speed** — curseur 0.25×, 0.5×, 1×, 1.5×, 2×, 4× ; garde la hauteur du son ; marche sans audio ; Apply.
12. **Join Videos** — liste « Playback order », vignette + nom + flèches ↑↓ ; MP4/MOV/MKV mixables ; 1er clip = canevas ; « Join Videos » → MP4.
13. **Video Snapshots** — scrubber, image par image, « Add Frame », vignettes avec timecode et ✕ ; « Save N Frame(s) » → PNG pleine résolution.
14. **Split Video** — « N split points », « Add Split », frise, « Equal clips » (stepper + Set) ; tous les clips dans un dossier ; Split Video.
15. **Redact Video** — Style Solid/Blur ; couleur ; timeline « Redactions » : chaque zone a sa plage de temps (barres « Box 1 »…, « Drag to add »), rangée de vignettes ; « Save Redacted Copy ».
16. **Normalize Volume** — forme d'onde ; Target loudness (−16 LUFS), Loudness range (11 LU), True peak limit (−1.5 dBTP) ; comparaison entrée/sortie ; « Normalize Audio ».
17. **Audio Visualizer** — Style Waveform / image fixe ; Shape Landscape 16:9 / Portrait / Square ; « Create Visualization » → MP4.
18. **Trim Audio** — onde avec poignées ; Start/End ; « Trim silent ends automatically » ; « Play Selected Range » ; Apply.
19. **Convert Audio Channels** — aperçu L/R ; Output Mono/Stereo ; Left/Right volume 0–100 % ; Play Output ; Apply.
20. **Bleep Audio** — couche « Bleep » (glisser pour ajouter, déplacer/ajuster) au-dessus de l'onde ; aperçu Original / With Bleeps ; « Save Bleeped Copy ».
21. **Merge PDFs** — « Document order » (ordre du Finder), ↑↓ ; Merge PDFs.
22. **Organize PDF** — grille de pages, pastille numérotée, rotation par page, dupliquer, supprimer, glisser pour réordonner ; « Reset Order » ; « Make all pages the same width » ; « Save Organized PDF ».
23. **Remove BG** (ajout Mandarine, absent de Tangerine) — Vision `VNGenerateForegroundInstanceMaskRequest`, macOS 14+, PNG transparent.
24. **Split PDF**, **Extract Archive**, **Mute video** : petits outils sans fenêtre dédiée sur le site.

## Design
- Police DM Sans (repli SF), fond `#f4f4f4`, contenu `#fff`, accent orange `#f35b28`, texte `#282b29`, gris `#828782`, filets `#e9ece8`.
- Fenêtres d'outils : coins très arrondis (~26 pt), matière claire translucide, ✕ en pastille ronde grise, boutons gris clair à coins arrondis, segments « pill » (Balanced | Strong), aperçu sur fond #151515.
- Roue : anneau segmenté gris clair, segment survolé en orange plein + texte blanc, disque central blanc avec le format survolé, légende sous la roue (« Convert to BMP »).
- Réglages : touches des 3 roues, lancement à la connexion.

## Hors périmètre (volontairement)
Nom, icône, textes marketing et captures de Tangerine : non reprises (le projet s'appelle Mandarine).


## File d'attente des travaux
Chaque travail a sa ligne dans la pile de notifications (en haut à droite) : en attente (horloge), en cours (progression + Cancel), terminé (Show + ✕) ou en erreur (Copy + ✕). Au plus 2 travaux lourds (encodage, IA, téléchargement, conversion) tournent en même temps ; les travaux courts (PDF, métadonnées, recadrage, texte…) démarrent tout de suite. Cancel arrête ffmpeg / yt-dlp et supprime le fichier à moitié écrit. La pile reste affichée tant que la souris est dessus.

## Liens web et playlists (yt-dlp)
La roue ⌘ propose MP4 / MP3 pour tout lien web : sites connus (YouTube, Vimeo, X, TikTok, Reddit, SoundCloud, Bandcamp, Twitch…) ou « Try » pour les autres. Un lien de liste (playlist, album, chaîne) ouvre une fenêtre de choix : cases à cocher, qualité (Best/1080p/720p/480p pour la vidéo), « This video only » si le lien désigne aussi une vidéo. Téléchargement dans un nouveau dossier de Téléchargements, fichiers numérotés ; une seule ligne dans la pile (« 3 of 27 — titre »), un titre en échec n'arrête pas les autres. Ne contourne pas les DRM.
Formats des liens : MP4, MP3 (VBR V0 ≈ 250 kb/s) et WAV (non compressé, sans pochette). Réglages → Engines : version de yt-dlp, « Check for updates » / « Update » (exécutable officiel vérifié par SHA-256, essayé avant remplacement, installé dans le dossier des moteurs de Mandarine qui prime sur Homebrew).

## Roue ⌘ des photos : groupes et Tag Select
Photos : groupe EDIT (Adjust, Annotate, Redact) et groupe TRANSFORM (Crop, Resize, Rotate). TAG SELECT (photos et vidéos, plusieurs fichiers, même mélangés) : ne garde que les fichiers portant une étiquette Finder et les sélectionne dans le Finder. Une seule étiquette présente : sélection directe ; plusieurs : petite fenêtre avec un rond de couleur par étiquette (bord blanc = prise, estompé = ignorée), nombre de fichiers par étiquette. Réglages → « Optional petals » : Tag Select, Code et DaVinci activables / désactivables.

## Face Select (groupe « TAG SELECT » → TAG / FACE)
Photos et vidéos (plusieurs fichiers) : le pétale TAG SELECT devient un groupe à deux sous-pétales. FACE détecte les visages (Vision), les redresse d'après 5 repères (yeux, nez, coins de la bouche), calcule une empreinte de 128 nombres avec le modèle SFace (OpenCV Zoo, ONNX, exécuté sur le GPU par un lecteur ONNX intégré + MPSGraph) et regroupe les visages par ressemblance. Fenêtre : un rond par personne (bord blanc = choisie), curseur « Same person » (souple ↔ strict), « Select N files » sélectionne dans le Finder les fichiers où apparaissent les personnes choisies. Vidéos : une image toutes les ~2 s (40 au plus). Le modèle (37 Mo) se télécharge à la demande (SHA-256 vérifié). Réglages → « Optional petals » : Tag Select et Face Select activables séparément.

## Téléchargement des moteurs (Réglages → Engines)
Bouton « Download » pour ffmpeg + ffprobe (versions statiques de ffmpeg.martin-riedl.de, empreinte SHA-256 publiée vérifiée), cwebp (libwebp officiel de Google, empreinte épinglée), le modèle de visages et yt-dlp. Installés dans ~/Library/Application Support/Mandarine ; le programme est essayé avant installation (signature locale si macOS le refuse sur Apple Silicon).
Qualité mesurée (504 photos de 42 personnes, jeu LFW, images 125×94) : 417 visages détectés ; similarité médiane 0,65 pour une même personne contre 0,13 entre personnes différentes ; seuil par défaut 0,50 → 44 groupes pour 42 personnes, 0 visage mal rangé. Le curseur « Same person » règle ce seuil (0,38–0,65). Les photos très petites ou de profil peuvent ne pas être détectées.
