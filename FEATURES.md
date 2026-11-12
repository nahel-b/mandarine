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

## Réglages à onglets
Fenêtre de réglages avec une barre d'onglets à gauche : General, Appearance (style du menu, couleur de tinte, style des fenêtres), Wheel keys (touches), Petals (pétales facultatifs), Engines (moteurs à télécharger), Updates.

## Scan de document (roue ⌘ des photos, groupe DOCUMENT → SCAN / TEXT)
Détecte la feuille sur une photo (Vision), redresse la perspective, rétablit le vrai rapport largeur/hauteur (estimation par la géométrie des quatre coins, calée sur A4 / Lettre quand c'est proche), nettoie l'éclairage (le fond devient blanc). Quatre coins déplaçables à la souris, aperçu du résultat, filtres Original / Color / Grayscale / B&W, plusieurs photos = plusieurs pages ; sortie PDF ou images JPG. Les quatre touches (A Z E R par défaut, selon la disposition du clavier) se changent dans Réglages → Petals (clic sur la touche, puis appui sur la nouvelle ; doublons refusés). Désactivable dans Réglages → Petals.

## Sonnerie (roue ⇧ des sons et vidéos)
Pétale RINGTONE : début du son (30 s par défaut, réglable 5–40 s), fondu de sortie d'une seconde, AAC dans un fichier .m4r. Actif par défaut, désactivable dans Réglages → Petals.

## Texte glissé
Sélectionner du texte (Safari, Notes, Mail…), le glisser et taper ⇧ ⌘ ou ⌃ : le texte devient un petit fichier temporaire que la roue traite comme un fichier. ⇧ : enregistrer en TXT / MD / PDF / DOCX, lire dans un fichier audio (SPEECH, voix de la langue du texte), QR CODE (PNG). ⌘ : READ ALOUD (voix du système, bouton Stop), TRANSLATE (framework Translation, macOS 15+, langue du Mac par défaut), SUMMARIZE (modèle Apple Intelligence du Mac, macOS 26). ⌃ : COPY (texte brut), SEARCH (recherche web). Résultats enregistrés sur le Bureau. Désactivable dans Réglages → Petals.

## Sélection de types mélangés (roue ⌘)
Plusieurs fichiers de types différents ouvrent maintenant une roue commune : COMPRESS et METADATA (si tout est photo, vidéo, son ou PDF ; chaque fichier est traité selon son type), ZIP (tout, dossiers compris : une archive « Archive.zip » à côté du premier élément), et TYPE (sélection par type, extension, étiquette, taille, date). Photos + vidéos mélangées gardent aussi FACE et SORT.

## Tri rapide (groupe SELECT → SORT)
Photos et vidéos (plusieurs fichiers) en grand dans une fenêtre, au clavier : E / ↑ garder = oui (étiquette Finder verte), Z peut-être = je ne sais pas (jaune), A / ↓ / Supprimer rejeter = non (rouge), R effacer la marque, ← → parcourir, barre de couleurs cliquable. Les marques sont écrites tout de suite comme étiquettes Finder (les autres étiquettes sont conservées ; couleurs et noms du système). Pied de fenêtre : « Select kept in Finder » et « Move rejects to the Trash… » (confirmation, récupérable dans la Corbeille). Désactivable dans Réglages → Petals.

## Type Select (groupe SELECT → TYPE, et pétale seul sur les autres roues)
Pour toute sélection de plusieurs éléments : fenêtre avec une pastille par extension (nombre de fichiers, « folder » pour les dossiers), des raccourcis par catégorie (Photos, Videos, Audio, PDF, Documents, Archives, Folders), un filtre de taille (plus grand / plus petit que 1 Mo … 1 Go) et de date de modification (aujourd'hui, 7 / 30 jours, un an, plus vieux). Le nombre de résultats se met à jour en direct ; « Select N items » les sélectionne dans le Finder. Désactivable dans Réglages → Petals (actif par défaut).

## Les étiquettes Finder sont dans Type Select
Le pétale TAG n'existe plus : la fenêtre Type Select a une section « Finder tags » avec un rond de couleur par étiquette présente dans la sélection (couleurs du Finder, bord blanc = choisie, nombre de fichiers dessous) et un rond « No tag » pour les fichiers sans étiquette. Plusieurs étiquettes choisies = fichiers qui portent au moins l'une d'elles ; le filtre se combine avec les extensions, la taille et la date. Le groupe SELECT contient donc FACE, SORT et TYPE (TYPE seul sur les roues sans photos ni vidéos).

## Style des fenêtres d'outils (Réglages → Appearance → Window style)
Cinq cadres au choix pour toutes les fenêtres qui s'ouvrent depuis un pétale (le contenu reste clair) : Classic (par défaut), Tangerine (bandeau orange), Graphite (cadre sombre), Minimal (plat et clair, ✕ à droite), Wii (liseré bleu, boutons ronds à contour bleu). Six autres styles changent la structure, pas seulement les couleurs : Rail (titre et boutons dans une colonne à gauche), Islands (titre, contenu et boutons en trois cartes flottantes), Folder (onglet de chemise cartonnée), Brutalist (gros traits noirs, ombre dure, police à chasse fixe), Retro (fenêtre de Mac classique : bandeau rayé, case de fermeture carrée) et Capsule (titre et barre de boutons en pastilles flottantes à cheval sur les bords). Le glissement de la fenêtre passe par des zones déclarées par chaque style (barre de titre, rail, onglet…), le ✕ n'en fait jamais partie. Capsule est le style par défaut ; Classic reste disponible dans les Réglages. Six styles de plus : Sticky (pense-bête jaune, punaise, coin replié), Notepad (bloc-notes à spirale), Stamp (timbre-poste dentelé), Bubble (bulle de dialogue), Polaroid (cadre photo, légende manuscrite) et Ticket (talon avec encoches et pointillés). Le style s'applique aux fenêtres ouvertes ensuite.

## Couleur de tinte
Réglages → Appearance → « Accent color » : dix pastilles (Orange par défaut, Red, Pink, Purple, Indigo, Blue, Teal, Green, Gold, Graphite) et un sélecteur de couleur libre ; « Reset » revient à l'orange. La tinte colore le pétale survolé de la roue, les boutons principaux, les puces et la progression des fenêtres et des notifications. Les fenêtres déjà ouvertes gardent leur couleur.

## Styles de fenêtres proposés
Réglages → Appearance → Window style : **Capsule** (par défaut), **Classic** et **Islands** (les autres styles restent dans le code mais ne sont plus proposés). Les boutons des fenêtres sont centrés (Capsule, Classic) ou collés à droite de la carte du bas (Islands) et, en Capsule et Islands, entièrement arrondis comme leur fond. Seul Classic utilise l'ombre de fenêtre du système (les autres dessinent la leur, pour éviter un liseré gris irrégulier).

## Liseré des pétales survolés
Un pétale survolé (et un sous-pétale) a un liseré de la couleur de tinte en plus claire (à peine plus claire : 20 % de blanc, trait de 1,6 pt) au lieu du liseré blanc translucide.

## Menu « Bulles » (essai) — Réglages → Appearance → Menu style → Bubbles
Troisième apparence du menu, à côté de la roue et du menu Wii : la bulle du logo au centre, les outils en bulles rondes de tailles variées qui flottent doucement autour. Le nom de la bulle survolée (ou, sans survol, les infos de la sélection) s'affiche dans une petite capsule horizontale juste sous la bulle du logo, comme la barre de boutons du style Capsule. Un groupe (TRANSFORM, SELECT…) montre ses sous-bulles en éventail vers l'extérieur ; la bulle survolée prend la couleur de tinte, avec son liseré un peu plus clair et un halo. Mêmes touches (⇧ ⌘ ⌃), mêmes sons et même dépôt que la roue.

Mise à jour du menu Bulles : bulles plus grosses (84–100 px) et serrées contre la bulle du centre (un anneau, ou deux au-delà de 8 outils, rayons calculés pour que rien ne se chevauche) ; la bulle du centre montre l'aperçu des fichiers choisis (1 : plein cercle ; 2 : moitiés ; 3–4 : quartiers ; « +N » au-delà) avec leurs données par-dessus ; le nom de chaque outil est écrit à l'extérieur de sa bulle ; les sous-bulles d'un groupe jaillissent de leur parent, presque collées, et on peut glisser du parent à l'enfant (détection sur la bulle, sur les sous-bulles et sur le « pont » qui les relie) ; au survol, la bulle rebondit (ressort peu amorti), les bulles voisines s'écartent, et la bulle se laisse attirer légèrement vers le pointeur.

Menu Bulles, 3ᵉ version : le centre est beaucoup plus petit (122 pt) — une pile de cadres aux coins arrondis, tournés et décalés « en vrac » (photo, image de vidéo, page de PDF ; jusqu'à 4, « +N » au-delà), ou, quand il n'y a pas d'aperçu, une carte de format colorée avec l'extension en gros (HEIC bleu, PDF rouge, XLSX vert…) ; les données de la sélection sont en dessous de la pile. Les bulles ne sont plus noires : chaque outil et chaque format a sa couleur, et quatre aspects au choix dans Réglages → Appearance → Bubble look (visible quand le style de menu est Bubbles) : Gel (dégradé et reflet brillant, par défaut), Glass (verre teinté translucide), Paper (carte claire à bande de couleur), Night (sombre à liseré lumineux coloré). La bulle survolée garde la teinte de l'accent dans tous les aspects.

Glisser depuis un Finder en arrière-plan : le presse-papiers de glissement est surveillé pendant tout le geste (60 fois par seconde). Si Finder le complète ou le change après le premier mouvement, la liste des fichiers est relue ; si la roue est déjà ouverte elle se met à jour sur place (même position). Un texte glissé déjà converti en petit fichier n'est pas recréé.

Lots de fichiers : une seule ligne de notification pour tout le lot (« 3 of 10 done », anneau de progression globale, un seul Cancel). La conversion de plusieurs fichiers (Shift) tourne par deux à la fois ; un fichier qui échoue n'arrête pas les autres : « Saved 8 of 10 — 2 failed » avec le détail copiable et le bouton Show sur ce qui a réussi. Les outils qui traitent plusieurs fichiers dans un même travail (Compress, Encode, Resize, Rotate, Upscale, Remove background, Extract / remove audio, Normalize) affichent le même « x of n done ».

Face Select — mémoire temporaire : le résultat de l'analyse de chaque photo/vidéo (visages, empreintes, vignettes) est gardé dans ~/Library/Caches/Mandarine/faces, clé = chemin + date de modification + taille + réglage (un fichier modifié est réanalysé). Relancer sur les mêmes fichiers saute la détection (mesuré : 1,1 s → 0,1 s sur 8 photos sans visage ; le gain est bien plus grand avec des visages). Effacé 24 h après sa création, plafonné à 60 Mo (les plus anciennes entrées partent d'abord), nettoyé au lancement et à chaque analyse ; macOS peut aussi vider le dossier Caches à tout moment.

Compress avec plusieurs fichiers : case « Put everything in one ZIP archive » (cochée par défaut quand les types sont mélangés, décochée quand ils sont tous du même type). Cochée : une seule Archive.zip (les réglages de compression disparaissent) ; décochée : un fichier compressé à la fois avec les réglages habituels. La notification de mise à jour est réduite à « New update » + le numéro de version.

Fichiers d'une notification : sur une ligne terminée (celle qui a un bouton Show), on attrape la ligne n'importe où (sauf les boutons Show et ✕) et on glisse ailleurs les fichiers créés (ou, pour « Selected 2 of 2 files » et « Copied », les fichiers concernés ; pour toute autre notification, son texte, qui devient un texte glissé sur la roue si ce réglage est actif) ; pendant le glisser la ligne se tasse, devient translucide, s'entoure d'un contour pointillé orange et son coche devient une flèche : Mail, un navigateur, un dossier du Finder (copie). Pendant ce glisser, ⇧ ⌘ ⌥ ⌃ ouvrent la roue comme pour un fichier du Finder : on peut déposer le résultat sur n'importe quel pétale ou bulle (conversion, outils, actions comme Copy). Les notifications restent plus longtemps : 12 s (60 s avec le bouton Show), 45 s pour une erreur ; elles ne disparaissent pas tant que la souris est dessus ou qu'on glisse un fichier, puis 6 s après.

Titres de notification courts : le titre dit seulement ce qui s'est passé (« Saved », « Copied », « Moved », « Saved 3 items », « Failed »), le nom du fichier et le dossier passent dans la description, sur une ligne chacun (nom coupé au milieu pour garder l'extension). Le glisser du fichier d'une notification passe par une vue d'accueil dédiée (ToastHostingView) : sans elle, SwiftUI absorbait le clic avant la poignée.

Pages web depuis un lien glissé : la roue ⌘ d'un lien propose, en plus de MP4 / MP3 / WAV, trois pétales : PDF (la page entière en une seule longue page), MARKDOWN (le texte principal de l'article : titres, listes, liens, tableaux, code, images en liens ; sans menus ni pubs) et SCREENSHOT (une image PNG de toute la page, défilée pour charger les images différées). Les bandeaux de cookies et fenêtres surgissantes les plus courants sont retirés. Pour un site de vidéo connu (YouTube…) les téléchargements viennent en premier, sinon les pétales de page (c'est sans doute un article). Le fichier est enregistré dans Téléchargements, nommé d'après le titre de la page ; un lien = une ligne dans la pile. La page est chargée par WebKit dans une fenêtre invisible, sans connexion ni cookies : seul le contenu public est enregistré. Une page très longue est coupée à 14 000 pt.

Temps restant : un travail long (au moins 6 s de calcul, plus de 10 s à attendre) affiche « About 3 min left » sous sa description. L'estimation suit la vitesse des 30 dernières secondes, est arrondie (5 s, puis minutes, puis heures) et disparaît au début, à la fin ou si le travail est bloqué. Les travaux sans progression chiffrée (enregistrement de page, vérification d'un lien) n'en affichent pas.


## Fenêtre « All features »
Menu de la barre de menus → **All Features** (ou bouton « Browse all features » à la dernière page du guide). Un onglet par type de fichier
(images, vidéos, audio, PDF, documents, slides, tableurs, EPUB, sous-titres, archives, dossiers, texte glissé, liens web, sélections mixtes),
avec les formats (⇧), les outils (⌘) et les actions (⌃), chacun avec sa description ; les groupes de pétales montrent leurs sous-pétales et les
fonctions réservées à 2+ fichiers sont étiquetées. La liste est construite à partir du vrai `Catalog` et de `WiiText.description` : un nouvel outil
y apparaît seul. Recherche en haut (nom, description, format, type de fichier). Code : `App/FeaturesView.swift`.

## Guide d'aide raccourci
4 pages (glisser-taper-déposer, trois roues, moteurs, prêt) au lieu de 10 ; le détail des outils est dans « All features ».

## Réglages → Download
Lit les releases GitHub du dépôt (sans identifiant) : dernière version, versions précédentes, taille, date, lien vers les notes ; « Download » /
« Get » enregistre le .dmg dans Téléchargements (avec progression) puis le montre dans le Finder. Code : `App/DownloadTab.swift`.

## Style Wii : les outils s'ouvrent dans l'écran Wii
Quand on dépose sur un outil à fenêtre en style Wii, l'écran Wii **reste** : la caméra zoome sur la case (écran qui s'assombrit), puis un panneau de
« chaîne » grandit depuis la case jusqu'à remplir l'écran, l'onglet bleu du titre glisse en haut à droite et le contenu apparaît (séquence relevée sur la
vraie console). En bas, une bande beige : **Wii Menu** (retour à la grille, qui reste cliquable : on peut choisir un autre outil, la page suivante, ou
fermer avec le bouton rond) et les boutons de l'outil, en pilules Wii. Quand l'outil lance son travail, l'écran se retire. Un outil ouvert depuis un autre
(« Edit… » dans Resize) prend la place du courant. Les outils sans réglages (Zip, téléchargements…) gardent leur fonctionnement. Les autres styles ne changent pas.
Code : `Wheel/WiiShell.swift` (cadre `WiiToolFrame` appliqué par `ToolShell` via l'environnement `wiiHost`). Essais : `--wiishot <outil> <préfixe> [image]`.

## Notifications : temps restant stable
« About 15 s left » ne disparaît plus puis ne revient plus à 10 s : l'estimation est lissée, elle décompte entre deux relevés et reste jusqu'à la fin
(« Almost done » sous 8 s).

## Video Snapshots
Plus d'image prise d'avance : on ajoute soi-même les images voulues (« Add Frame »).

## Wii : entrée plus nette, look CRT, accès complet au disque
- Entrée d'un outil : la caméra plonge sur la case (les autres s'éteignent), la case devient un panneau blanc qui grandit d'un seul mouvement, aux proportions
  de l'écran final (aucune déformation), pendant que l'écran passe au noir ; puis l'onglet du titre glisse et le contenu apparaît. La taille de l'écran ne bouge
  plus pendant l'entrée.
- Look de vieux téléviseur sur les outils en style Wii : lignes de balayage, bords assombris, reflet de la vitre, bande claire qui descend lentement (`WiiCRT`).
- Accès complet au disque : demandé **une seule fois** au premier lancement (explication, ouverture du bon réglage, app montrée dans le Finder) ; état et
  raccourci dans Réglages → General. L'app est signée « ad hoc » avec une exigence stable (`identifier "com.mandarine.app"`, voir `Scripts/build_app.sh`) pour
  que macOS garde l'autorisation d'une version à l'autre.

## Wii : main, sons ; Trim Audio
- Après le dépôt, la main de la télécommande reste le pointeur sur l'écran Wii (le curseur système est caché au-dessus de l'écran) : doigt pointé au repos,
  **poing fermé** tant que le bouton est enfoncé (appui, glissement d'un curseur ou d'une poignée).
- Sons : `WiiTool.mp3` à l'ouverture d'un outil ; appui, relâchement et petits tics pendant un glissement sur les réglages des outils (synthétisés ; on peut les
  remplacer par `WiiClick`, `WiiRelease`, `WiiSlide` .mp3/.wav dans Resources).
- Trim Audio : un clic sur la forme d'onde place la tête de lecture (visible même à l'arrêt) au lieu de la remettre au début ; la sélection ne bouge qu'après un
  vrai glissement. Case « Keep trimming » : après « Apply & Keep Going », l'outil reste ouvert, la sélection repart après l'extrait enregistré et le compteur
  de clips enregistrés s'affiche.

## Wii : cases à cocher et choix multiples ; Remove Background : gomme et pinceau
- Dans l'écran Wii, les cases à cocher et les choix multiples (Transparent / Color / Blur, PNG / WebP…) deviennent des pilules de liste à la Wii : blanches à liseré
  bleu clair, lavande quand elles sont choisies, **quatre coins rouges** sous le pointeur (cases à cocher : pastille ✓). Code : `WiiChoiceRow`, `WiiToggleStyle`,
  `WiiChoiceGroup` (`PillPicker` les utilise dans ce style). Les menus déroulants restent natifs.
- Remove Background → « Touch up » : **Eraser** (rend transparent ce qu'on peint) et **Brush** (remet l'image d'origine, même ce que la détection avait écarté) ;
  taille réglable, Undo, Clear. Les traits suivent l'image (même résultat à l'export qu'à l'aperçu ; pendant la retouche l'aperçu montre l'image entière).
  Une seule image à la fois. Moteur : `BGStroke` / `BGOptions.edits` dans `BackgroundRemoval.swift`. Essai : `--bgedit image sortie.png`.

## Wii : sons fournis, poing redessiné, clics, CRT sur le menu
- Sons : `WiiClick.mp3` (appui), `WiiTool.mp3` (ouverture d'un outil), `WiiDone.mp3` (travail terminé avec succès, style Wii seulement). Plus de son au relâchement du bouton ;
  les petits tics pendant un glissement sur un réglage restent.
- Poing fermé redessiné (quatre doigts repliés, pouce en travers, poignet, contours nets).
- Un voile presque invisible couvre tout l'écran Wii : macOS laisse passer les clics sur les pixels entièrement transparents d'une fenêtre (c'était alors le Finder derrière
  qui les recevait).
- Plage d'un Trim : une pause en gardant le bouton enfoncé ne réinitialise plus le glissement (le déplacement était compté deux fois).
- Le look CRT couvre aussi le menu Wii.

## Wii : fenêtre stable quand le contenu change
Une case qui révèle un réglage (ex. « Compress to target file size ») ne fait plus trembler la fenêtre : la taille du contenu est mesurée à sa taille idéale (elle ne dépend plus de la
place offerte, d'où l'ancienne boucle), la fenêtre ne fait que grandir tant que l'outil est ouvert, et le panneau s'adapte en douceur (sans rebond).

## Wii : outil rouvert
Rouvrir le même outil après « Wii Menu » (même taille que la fois précédente) n'envoyait aucune mesure : le panneau restait à sa taille par défaut, contenu coupé en haut et en bas et réglages
hors du panneau (donc curseurs inutilisables). Les mesures sont maintenant oubliées à chaque ouverture d'outil.

## Wii : sélecteur de fichier
Quand une autre fenêtre de l'app passe au-dessus de l'écran Wii (sélecteur « Custom image », notification…), la main s'efface et le vrai curseur reparaît au-dessus d'elle.

## Wii : sons de survol / retour, boutons qui grossissent
`WiiButtonHover.mp3` quand le pointeur arrive sur un bouton ou un choix d'un outil, `WiiClose.mp3` au retour à l'accueil (« Wii Menu ») et à la fermeture de l'écran. Les boutons grossissent un peu
sous le pointeur (ressort léger), y compris ceux du contenu des outils (`WiiHoverGrow`).

## Export Video : vidéos HDR et 10 bits
Une source HDR (HLG/PQ, films d'iPhone) exportée en H.264 8 bits donnait une image grise et délavée, et le H.264 10 bits n'est lisible ni par QuickTime ni par l'Aperçu (image grise/verte).
Ces deux cas passent maintenant en HEVC 10 bits (couleurs et étiquettes HDR conservées) ; une note l'indique dans l'outil. Code : `VideoEncoder.effective`.

## Garder ou remplacer l'original
- Réglages → General → « Original file » : **Keep it** (défaut) ou **Replace it**. La touche **⌥** inverse le réglage : maintenue au moment où l'on clique sur le bouton d'un outil, ou où l'on dépose sur un pétale
  (si une roue utilise déjà ⌥, c'est la première touche libre parmi ⌃ ⇧ ⌘). Code : `Core/ReplaceMode.swift`, `Core/Replacer.swift`.
- Le bouton principal des outils qui modifient un fichier (Compress, Metadata, Edit, Annotate, Add BG, Crop, Redact, Resize/Upscale, Rotate, Remove Background, Trim/Crop/Speed/Redact vidéo, Export,
  Normalize, Trim Audio, Channels, Bleep) devient **« Replace original »** (et orange) tant que le remplacement est actif (`ReplaceButton`). Même chose pour les conversions de la roue, Mute et Remove BG directs.
- Pendant un glisser, avec ⌥ maintenue : voyant « Replaces the original » au centre de la roue, des bulles, et dans la barre de l'écran Wii.
- L'original va à la **Corbeille** (jamais supprimé) ; le résultat prend son nom (avec sa nouvelle extension si le format change). Remplacement seulement si chaque original a exactement un résultat
  (donc pas pour les découpes, fusions ou tailles multiples ; pas pour Trim Audio en mode « Keep trimming »).
- Notification : sans remplacement, un bouton **« Replace original »** ; après remplacement, **« Undo »** qui remet tout. Le bouton d'action des notifications a maintenant sa propre ligne.
- Astuce unique à la première ouverture d'un outil concerné (`ReplaceTip`). Essai : `--replacetest`.

## What's New
Fenêtre « What's New » affichée une fois après une mise à jour (pas à la première installation), et depuis le menu de la barre de menus : **toutes les versions**, de la plus récente à la 1.0.0, dans une liste qui défile ; celles apparues depuis la dernière ouverture portent « NEW ».
Les notes sont dans `App/WhatsNew.swift` (`WhatsNew.releases`) : **à compléter à chaque version**.

## Notifications : deux styles
Réglages → General → Notifications : **Capsule** (défaut, « B1 » : une ligne, liseré blanc épais, l'icône du fichier seule entourée d'un arc vert qui avance avec le travail ; une fois fini, une coche blanche sur rond vert ; œil = Show, pastille graphite = action,
✕ rond au coin) ou **Card** (« A1 » : carte avec légende, titre, barre de progression et boutons en bas). Le glisser des fichiers, le temps restant, « Replace original » / « Undo », Copy et Cancel marchent dans les deux.
Le son de fin de travail joue dans tous les styles de menu. Les maquettes sont dans `UI/ToastLab.swift` (`--snapshot toaststyles:1…5`) ; `MANDARINE_NOTIFSTYLE=card` force un style pour les essais.

## ⌥ au dépôt, Entrée dans les fenêtres
- Déposer sur un outil à fenêtre **en tenant ⌥** : la fenêtre s'ouvre en mode « remplacer » (bouton « Replace original ») ; **⌥ au clic** y repasse à « garder » (le réglage est inversé par rapport à la fenêtre,
  pas par rapport aux Réglages). Sans ⌥ au dépôt, la base est le réglage. Code : `ReplaceMode.baseForNewWindow`, environnement `replaceBase`, `ReplaceButton`. Essai : `--entertest image.png [optdrop]`.
- **Entrée** lance l'outil dans toutes les fenêtres (bouton principal en `keyboardShortcut(.defaultAction)`), classiques ou dans l'écran Wii. Exceptions : outils à zone de texte (Extract Text, Translate, Summarize),
  Quick Sort, Quick Look. Dans Metadata, Entrée = « Save » (pas « Remove All »).

## Balayer une notification
Deux doigts vers la droite sur une notification terminée (résultat ou erreur) : elle suit les doigts et part si on a assez glissé (ou d'un coup sec) ; sinon elle revient. Un geste plutôt vertical est ignoré,
la molette d'une souris ne fait rien, et les travaux en cours ne se balaient pas. Code : `ToastCenter.feedSwipe`, `ToastHostingView.scrollWheel`. Essai : `--swipetest`.

## AirDrop vers une personne : impossible pour une app tierce (essayé, retiré)
Idée : sous-pétales AirDrop avec les personnes proches. Le framework privé `Sharing` (SFBrowser) démarre bien et `sharingd` découvre l'iPhone voisin, mais refuse de le transmettre à Mandarine :
« is not entitled to do AirDrop discovery » (droit réservé aux apps signées par Apple). Aucun contournement propre ; le code a été retiré. Pistes restantes : implémenter le protocole AirDrop soi-même (type OpenDrop, seulement
pour les appareils en mode « Tout le monde »), ou un pétale « Partage » via les services publics (Messages, Mail avec destinataire).

## Langue (Réglages → General → Language)
System / English / Français. Tous les textes passent par `L("…")` (Core/L10n.swift) ; le français vient de `Resources/Localization/fr.json` (clé = texte anglais, `%@` = partie variable), copié dans l'app par `build_app.sh`. Les menus se reconstruisent au changement, les nouvelles fenêtres suivent tout de suite. Pour voir les textes oubliés : `MANDARINE_LANG=fr MANDARINE_L10NLOG=1` affiche `L10N-MISS …` sur stderr.

## Apple ProRes
Roue ⇧ d'une vidéo : pétale PRORES (ProRes 422 HQ dans un .mov « nom ProRes.mov », son PCM, MPEG entrelacé désentrelacé). Export Video : codec « Apple ProRes » avec profil Proxy / LT / 422 / 422 HQ / 4444 et deux préréglages. Test sans interface : `--convert prores fichier`, ou `--batch prores fichiers…` (lot).

## Lots
Un fichier en échec n'arrête plus le lot (outils Compress, Export Video, Redimensionner, Pivoter, Agrandir, Extraire l'audio, Normaliser, Supprimer l'arrière-plan, Couper le son : classe `Batch` de JobQueue.swift) : la notification dit « Saved 8 of 10 — 2 failed ». Le Mac ne se met plus en veille et App Nap est désactivé tant qu'un travail tourne.

## Arborescence DaVinci personnalisable
Réglages → DaVinci : nom du projet par défaut (ou nom du fichier déposé s'il est seul), rangement automatique des fichiers déposés activé ou non, et éditeur d'arborescence (3 niveaux) : case « créé par défaut », renommer, ajouter un dossier / sous-dossier, monter / descendre, supprimer, choisir quel dossier reçoit les vidéos, sons ou images déposés, rétablir les dossiers par défaut. Enregistré en JSON (`davinciFolders`). La fenêtre de l'outil reprend ces cases (dossiers et sous-dossiers) comme point de départ.

## Vidéos HLS locales (.m3u8)
Un `.m3u8` local qui est un vrai flux HLS (balises `#EXT-X-TARGETDURATION` / `#EXT-X-STREAM-INF`) est traité comme une vidéo : roue de conversion, outils, captures. Une liste de lecture musicale en .m3u8 reste « autre ». Taille affichée = playlist + segments locaux. Les sorties sont des MP4 (jamais .m3u8). AVFoundation lit une copie MP4 sans réencodage (`HLS.playable`, en cache). Si la lecture échoue : message clair pour les segments distants (web) ou manquants. Pas de conversion vers m3u8.
Playlist HLS téléchargée sans ses fichiers (ex. playlist maîtresse seule, relative) : Mandarine lit l'adresse de téléchargement enregistrée par macOS (métadonnée « Provenance », `kMDItemWhereFroms`) et lit le flux à cette adresse (`HLS.origin`, remplacement dans les arguments de ffmpeg / ffprobe). Si ça échoue (lien expiré, connexion demandée) : message clair.

## Transcription (TRANSCRIBE)
Pétale TRANSCRIBE sur les roues ⌘ des sons et des vidéos (plusieurs fichiers possibles) : parole → `.txt` (paragraphes aux silences) et `.srt` (sous-titres : ≤ 80 caractères et ≈ 6 s, coupés aux silences et fins de phrase, deux lignes équilibrées). Reconnaissance vocale d'Apple (`SFSpeechRecognizer`) : langue au choix (dernière choisie mémorisée, sinon langue de l'app / du Mac), sur le Mac si la langue est téléchargée (Dictée), sinon envoi à Apple par morceaux de 50 s (indiqué dans la fenêtre). L'audio est d'abord extrait par ffmpeg en WAV mono 16 kHz. Autorisation « Reconnaissance vocale » demandée au premier usage (`NSSpeechRecognitionUsageDescription`). Test : lancer l'app avec `open -n -W --stdout out.txt build/Mandarine.app --args --transcribe fr-FR fichier` (depuis un terminal directement, macOS interrompt le processus faute d'autorisation de l'app parente).

## Notifications : garder plus longtemps
Un clic sur le corps d'une notification terminée (pas sur ses boutons) lui ajoute 30 s à l'écran ; chaque clic en ajoute 30 de plus. Une pastille « +30 s · 0:42 » (puis « +1 min », « +1 min 30 s »…) affiche le temps ajouté et le décompte. Le décompte est en pause tant que la souris est sur la pile et repart ensuite (6 s au moins).
Transcription, phrases multiples : la reconnaissance d'Apple repart d'une phrase neuve après chaque silence (le résultat ne contient plus que la dernière phrase, sans horodatage tant qu'elle n'est pas close). `Transcriber.recognize` garde donc chaque phrase close (horodatage définitif), et une phrase jamais close avec un horodatage estimé. Journal du flux brut : variable `MANDARINE_STTLOG=1`.

## Capture d'écran en cours (miniature)
La miniature qui apparaît après une capture est une **promesse de fichier** : son fichier temporaire (`TemporaryItems`) existe mais n'est pas lisible (« Operation not permitted ») tant que la promesse n'est pas honorée. `WheelController.drop(from:)` reçoit donc la promesse (`NSFilePromiseReceiver`) dans le dossier des captures (réglage macOS ; sinon un dossier temporaire), puis traite la copie. Diagnostic : `MANDARINE_DRAGLOG=1` journalise le contenu du glisser (types, URL, promesses). Test : `--stagetest fichier dossier`.

## Style Wii dans un téléviseur
L'écran Wii (menu et outils) est montré dans un vieux téléviseur transparent (`Resources/WiiTV.png`, alpha d'origine conservé : la coque reste semi-transparente). Réglage : Réglages → Apparence → « Montrer l'écran dans un téléviseur » (`wiiTV`, activé par défaut ; `MANDARINE_WIITV=0` pour les essais).
- L'image a un trou transparent à la place de l'écran ; `WiiTVScreen.png` est le masque exact de ce trou (+3 px sous le cadre noir, aucun jour). Le contenu est rogné par ce masque (`WiiTV.swift` : `WiiTV.hole`, `maskRect`, `Geometry`, `WiiTVSet`).
- L'écran prend les proportions exactes de la vitre : la grille du menu est un peu plus haute (`WiiLayout.inTV`), le panneau d'un outil remplit toute la vitre (pas de cadre noir ni de bandes). Les boutons ronds du bas sont rentrés pour les coins du tube.
- La fenêtre est centrée sur la vitre (`WiiTV.Geometry.stage`) ; la main (pointeur Wii) n'existe que sur la vitre. Si le téléviseur ne tient pas dans la zone visible (gros outil), la télé a TOUJOURS la taille du menu : le panneau d'un outil est mis en page à sa taille naturelle puis réduit pour tenir dans la vitre ; `Geometry.fit` ne réduit que si le menu lui-même ne tient pas dans la zone visible.
- Les deux images sont copiées dans l'app par `Scripts/build_app.sh`.

## Transcription avec Whisper (optionnel)
Second moteur de « Transcrire », à côté de la reconnaissance d'Apple : Whisper large-v3-turbo quantifié q5_0 (≈ 570 Mo, `ggml-large-v3-turbo-q5_0.bin` de whisper.cpp sur Hugging Face).
- Le modèle n'est PAS dans l'app : bouton « Télécharger » dans l'outil (choix Apple / Whisper) ou dans Réglages → Engines (`WhisperModel`, `EngineInstaller.Engine.whisperModel`, vérifié par taille + SHA-256, rangé dans `~/Library/Application Support/Mandarine/models`, bouton Remove).
- Le moteur est la bibliothèque officielle whisper.cpp (`whisper.xcframework` précompilé, MIT, Metal + Accelerate, arm64 + Intel), ajoutée à `Package.swift` en `binaryTarget` (version b5454, checksum fixé). `Scripts/build_app.sh` copie `whisper.framework` dans `Contents/Frameworks` et ajoute le rpath. Macros : macOS 13.3 minimum (celui de la bibliothèque).
- `WhisperEngine.transcribe` lit le WAV 16 kHz mono, lance `whisper_full` (Metal, flash attention, glouton), renvoie les segments découpés en mots (temps répartis selon la longueur) : `plainText`, `cues`, `srt` de `Transcriber` sont réutilisés tels quels. Les silences/musique annoncés (`[BLANK_AUDIO]`, `♪`) sont retirés. Annulation par `abort_callback`.
- Langue « Détecter automatiquement » (Whisper seulement) ; la langue trouvée règle la mise en forme.
- Test : `--transcribe <langue|auto> fichier whisper` (avec `open -n -W --stdout …`, comme pour Apple).
