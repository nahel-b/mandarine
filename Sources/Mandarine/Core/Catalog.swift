import Foundation

/// Table de tout ce que propose chaque roue, par type de fichier. Reprend l'ordre (sens horaire depuis le haut) du site.
enum Catalog {
    // MARK: Conversions
    private static let imageTargets = ["png", "webp", "heic", "tiff", "avif", "bmp", "pdf", "jpg"]
    private static let videoTargets = ["mp4", "mkv", "webm", "avi", "wmv", "gif", "mp3"]
    private static let audioTargets = ["m4a", "wav", "flac", "ogg", "opus", "aiff", "wma", "mp3"]
    private static let pdfTargets = ["docx", "pages", "pptx", "xlsx", "jpg", "png", "epub", "txt", "md"]
    private static let docTargets = ["docx", "pages", "pdf", "txt", "md", "html", "epub", "png", "jpg"]
    private static let slideTargets = ["pdf", "jpg", "png"]
    private static let sheetTargets = ["ods", "csv", "tsv", "pdf", "xlsx"]
    private static let epubTargets = ["pdf", "docx", "pages", "txt", "md", "html"]
    private static let subtitleTargets = ["vtt", "srt", "txt"]
    private static let archiveTargets = ["tar", "gzip", "zip"]

    private static let snippetTargets = ["txt", "md", "pdf", "docx", "m4a", "qr"]

    static func convertTargets(for kind: FileKind, inputExt: String) -> [String] {
        let e = kind == .snippet ? "" : normalized(inputExt)
        let list: [String]
        switch kind {
        case .image: list = imageTargets
        case .video: list = videoTargets
        case .audio: list = audioTargets
        case .pdf: list = pdfTargets
        case .document: list = docTargets
        case .slides: list = slideTargets
        case .spreadsheet: list = sheetTargets
        case .epub: list = epubTargets
        case .subtitle: list = subtitleTargets
        case .archive: list = archiveTargets
        case .snippet: list = snippetTargets
        case .folder, .other: list = []
        }
        var targets = list.filter { $0 != e }
        // Sonnerie iPhone (.m4r) : depuis un son ou une vidéo, si l'option est active dans les Réglages
        if (kind == .audio || kind == .video) && AppSettings.shared.enableRingtone && e != "m4r" { targets.append("m4r") }
        return targets
    }

    static func normalized(_ ext: String) -> String {
        switch ext.lowercased() {
        case "jpeg": return "jpg"
        case "tif": return "tiff"
        case "gz": return "gzip"
        case "markdown": return "md"
        case "htm": return "html"
        case "aif": return "aiff"
        case "m4v": return "mp4"
        case "mpeg": return "mpg"
        case let x: return x
        }
    }

    static func displayName(_ ext: String) -> String { ext == "m4r" ? "RINGTONE" : ext.uppercased() }

    // MARK: Outils
    /// Sélection par visage (photos et vidéos, plusieurs fichiers), selon les Réglages. Les étiquettes Finder se choisissent dans Type Select.
    private static func selectTools() -> [(ToolID, String, String)] {
        AppSettings.shared.enableFaceSelect ? [(.faceSelect, "FACE", "face.smiling")] : []
    }

    /// Tri rapide (photos et vidéos, plusieurs fichiers), rangé dans le groupe SELECT.
    private static func sortTools() -> [(ToolID, String, String)] {
        AppSettings.shared.enableCull ? [(.quickSort, "SORT", "hand.thumbsup")] : []
    }

    /// Roue ⌘ d'une sélection de types mélangés : ce qui a un sens pour tous les fichiers.
    private static func mixedTools(_ kinds: Set<FileKind>) -> [(ToolID, String, String)] {
        var t: [(ToolID, String, String)] = []
        if kinds.isSubset(of: [.image, .video, .audio, .pdf]) {
            t += [(.compress, "COMPRESS", "arrow.down.right.and.arrow.up.left"), (.metadata, "METADATA", "eye.slash")]
        }
        t.append((.zipFiles, "ZIP", "doc.zipper"))
        if kinds.isSubset(of: [.image, .video]) { t += selectTools() + sortTools() }
        return t
    }

    static func tools(for kind: FileKind, count: Int) -> [(ToolID, String, String)] {
        let multi = count > 1
        switch kind {
        case .image:
            var t: [(ToolID, String, String)] = [
                (.compress, "COMPRESS", "arrow.down.right.and.arrow.up.left"),
                (.metadata, "METADATA", "eye.slash"),
                (.editImage, "ADJUST", "slider.horizontal.3"),
                (.resizeImage, "RESIZE", "arrow.up.left.and.arrow.down.right"),      // à côté de EDIT
                (.rotateImage, "ROTATE", "rotate.right"),
                (.cropImage, "CROP", "crop"),
                (.annotateImage, "ANNOTATE", "pencil.tip"),
                (.frameImage, "ADD BG", "photo.on.rectangle"),
                (.removeBackground, "REMOVE BG", "wand.and.stars"),                 // à côté de ADD BG
                (.redactImage, "REDACT", "eye.slash.circle"),
                (.ocr, "TEXT", "text.viewfinder")
            ]
            if AppSettings.shared.enableScan { t.append((.scanDocument, "SCAN", "doc.viewfinder")) }
            if multi { t.append((.createCollage, "COLLAGE", "square.grid.2x2")) }
            if multi { t += selectTools() + sortTools() }
            return t
        case .video:
            var t: [(ToolID, String, String)] = [
                (.compress, "COMPRESS", "arrow.down.right.and.arrow.up.left"),
                (.metadata, "METADATA", "eye.slash"),
                (.muteVideo, "MUTE", "speaker.slash"),
                (.trimVideo, "TRIM", "scissors"),
                (.cropVideo, "CROP", "crop"),
                (.changeVideoSpeed, "SPEED", "gauge.with.dots.needle.67percent"),
                (.videoSnapshots, "SNAPSHOT", "camera"),
                (.splitVideo, "SPLIT", "rectangle.split.2x1"),
                (.redactVideo, "REDACT", "eye.slash.circle"),
                (.extractAudio, "EXTRACT", "waveform"),
                (.encodeVideo, "EXPORT", "film.stack")
            ]
            if multi { t.append((.joinVideos, "JOIN", "rectangle.stack")) }
            if multi { t += selectTools() + sortTools() }
            return t
        case .audio:
            return [
                (.compress, "COMPRESS", "arrow.down.right.and.arrow.up.left"),
                (.metadata, "METADATA", "eye.slash"),
                (.normalizeAudio, "NORMALIZE", "waveform.path"),
                (.audioToVideo, "VISUALIZE", "waveform"),
                (.trimAudio, "TRIM", "scissors"),
                (.audioChannels, "CHANNELS", "speaker.wave.2"),
                (.redactAudio, "BLEEP", "speaker.slash.circle")
            ]
        case .pdf:
            var t: [(ToolID, String, String)] = [
                (.compress, "COMPRESS", "arrow.down.right.and.arrow.up.left"),
                (.metadata, "METADATA", "eye.slash"),
                (.splitPDF, "SPLIT", "rectangle.split.2x1"),
                (.organizePDF, "ORGANIZE", "square.grid.2x2"),
                (.extractImages, "IMAGES", "photo.on.rectangle.angled"),
                (.ocr, "TEXT", "text.viewfinder")
            ]
            if multi { t.append((.mergePDF, "MERGE", "doc.on.doc")) }
            return t
        case .archive:
            return [(.extractArchive, "EXTRACT", "archivebox")]
        case .snippet:
            return [(.speakText, "READ ALOUD", "speaker.wave.2"), (.translateText, "TRANSLATE", "character.bubble"), (.summarizeText, "SUMMARIZE", "text.alignleft")]
        case .document, .slides, .spreadsheet, .epub, .subtitle, .folder, .other:
            return [(.compress, "COMPRESS", "arrow.down.right.and.arrow.up.left"),
                    (.metadata, "METADATA", "eye.slash")]
        }
    }

    // MARK: Construction des roues
    static func items(mode: WheelMode, urls: [URL]) -> [WheelItem] {
        let linksOnly = !urls.isEmpty && urls.allSatisfy { !$0.isFileURL }
        // Liens web : la roue ⌘ propose le téléchargement en MP4 ou en MP3 (yt-dlp). Sites connus : affirmatif ; les autres sont « tentés ».
        if linksOnly && mode == .tools && urls.allSatisfy(YtDlp.isWebLink) {
            let known = urls.allSatisfy(YtDlp.isKnownSite)
            return [WheelItem(id: ToolID.downloadMP4.rawValue, label: "MP4", caption: known ? "Download MP4" : "Try to download MP4", symbol: "film", payload: .tool(.downloadMP4)),
                    WheelItem(id: ToolID.downloadMP3.rawValue, label: "MP3", caption: known ? "Download MP3" : "Try to download MP3", symbol: "music.note", payload: .tool(.downloadMP3)),
                    WheelItem(id: ToolID.downloadWAV.rawValue, label: "WAV", caption: known ? "Download WAV" : "Try to download WAV", symbol: "waveform", payload: .tool(.downloadWAV))]
        }
        if linksOnly && mode != .actions { return [] }
        switch mode {
        case .actions:
            let isText = urls.count == 1 && FileKind.detect(urls[0]) == .snippet
            let actions: [FileAction] = isText ? [.copy, .searchWeb, .switchView]
                : linksOnly ? [.airDrop, .float, .copy, .copyPath] : FileAction.allCases.filter { $0 != .searchWeb }
            return actions.map {
                let isLink = linksOnly && $0 == .copyPath
                return WheelItem(id: $0.rawValue, label: isLink ? "COPY LINK" : $0.label, caption: isLink ? "Copy Link" : $0.caption,
                                 symbol: $0.symbol, payload: .action($0))
            }
        case .convert:
            guard let kind = FileKind.common(of: urls), let first = urls.first else { return [] }
            // Plusieurs fichiers du même type : chacun est converti (un travail par fichier, dans la file).
            // Seule exception : plusieurs images → PDF = un seul PDF qui les réunit.
            let sameExt = Set(urls.map { normalized($0.pathExtension) }).count == 1
            return convertTargets(for: kind, inputExt: sameExt ? first.pathExtension : "").map { ext in
                let combine = urls.count > 1 && kind == .image && ext == "pdf"
                let label = kind == .snippet ? (ext == "m4a" ? "SPEECH" : ext == "qr" ? "QR CODE" : displayName(ext)) : displayName(ext)
                return WheelItem(id: combine ? "multi-pdf" : ext, label: label,
                                 caption: kind == .snippet ? (ext == "qr" ? "Make a QR code" : ext == "m4a" ? "Read it into an audio file" : "Save as \(displayName(ext))") : ext == "m4r" ? "Save as a \(AppSettings.shared.ringtoneSeconds) s ringtone" : combine ? "Combine into one PDF" : (urls.count > 1 ? "Convert \(urls.count) files to \(displayName(ext))" : "Convert to \(displayName(ext))"),
                                 symbol: nil, payload: .convert(ext),
                                 enabled: Converter.supports(kind: kind, from: first.pathExtension, to: ext))
            }
        case .tools:
            // Types mélangés : une roue commune (compresser, métadonnées, zip, étiquettes…). Un texte glissé ne se mélange à rien.
            let common = FileKind.common(of: urls)
            let kinds = Set(urls.map(FileKind.detect))
            if common == nil && (urls.count < 2 || kinds.contains(.snippet)) { return [] }
            let kind = common ?? .other
            var list = common == nil ? mixedTools(kinds) : tools(for: kind, count: urls.count)
            // Sélection par type (extension, catégorie, taille, date) : pour toute sélection de plusieurs éléments
            if urls.count > 1, AppSettings.shared.enableTypeSelect { list.append((.typeSelect, "TYPE", "line.3.horizontal.decrease.circle")) }
            var items: [WheelItem] = list.map { t in
                let (id, label, symbol) = t
                return WheelItem(id: id.rawValue, label: label, caption: id.title, symbol: symbol, payload: .tool(id),
                                 enabled: ToolAvailability.isImplemented(id))
            }
            // Groupes à 2ᵉ niveau : le survol d'un pétale fait apparaître ses sous-pétales plus loin du centre.
            func group(_ ids: [ToolID], id: String, label: String, caption: String, symbol: String) {
                let found = ids.compactMap { tid in items.first(where: { $0.id == tid.rawValue }) }
                guard found.count >= 2, let first = items.firstIndex(where: { ids.map(\.rawValue).contains($0.id) }), case .tool(let firstTool) = found[0].payload else { return }
                var g = WheelItem(id: id, label: label, caption: caption, symbol: symbol, payload: .tool(firstTool))
                g.children = found
                items.removeAll { item in ids.map(\.rawValue).contains(item.id) }
                items.insert(g, at: min(first, items.count))
            }
            group([.scanDocument, .ocr], id: "document", label: "DOCUMENT", caption: "Document", symbol: "doc.viewfinder")
            group([.faceSelect, .quickSort, .typeSelect], id: "select", label: "SELECT", caption: "Select", symbol: "line.3.horizontal.decrease.circle")
            group([.editImage, .annotateImage, .redactImage], id: "edit", label: "EDIT", caption: "Edit", symbol: "slider.horizontal.3")
            group([.cropImage, .resizeImage, .rotateImage], id: "transform", label: "TRANSFORM", caption: "Transform", symbol: "crop.rotate")
            group([.frameImage, .removeBackground], id: "bg", label: "BG", caption: "Background", symbol: "photo.on.rectangle")
            // Vidéo : Trim / Crop / Speed dans un groupe, Mute / Extract audio dans « AUDIO »
            group([.trimVideo, .cropVideo, .changeVideoSpeed, .redactVideo], id: "vtransform", label: "TRANSFORM", caption: "Transform", symbol: "slider.horizontal.below.rectangle")
            group([.muteVideo, .extractAudio], id: "vaudio", label: "AUDIO", caption: "Audio", symbol: "speaker.wave.2")
            // Ajouts transversaux de la roue ⌘ : projet DaVinci (dossiers et médias) et ouverture dans VS Code (tout fichier ou dossier)
            // Ajouts réservés aux dossiers : projet DaVinci et ouverture dans VS Code
            if kind == .folder {
                if AppSettings.shared.enableDavinci {
                    items.append(WheelItem(id: ToolID.davinciTree.rawValue, label: "DAVINCI", caption: "DaVinci Project", symbol: "folder.badge.gearshape", payload: .tool(.davinciTree)))
                }
                if VSCode.url != nil && AppSettings.shared.enableCode {
                    items.append(WheelItem(id: ToolID.openInCode.rawValue, label: "CODE", caption: "Code", symbol: "chevron.left.forwardslash.chevron.right", payload: .tool(.openInCode)))
                }
            }
            return items
        }
    }
}
