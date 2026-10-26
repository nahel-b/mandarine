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

    static func convertTargets(for kind: FileKind, inputExt: String) -> [String] {
        let e = normalized(inputExt)
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
        case .folder, .other: list = []
        }
        return list.filter { $0 != e }
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

    static func displayName(_ ext: String) -> String { ext.uppercased() }

    // MARK: Outils
    /// Pétales de sélection (photos et vidéos, plusieurs fichiers) : par étiquette et/ou par visage, selon les Réglages.
    private static func selectTools() -> [(ToolID, String, String)] {
        let s = AppSettings.shared
        switch (s.enableTagSelect, s.enableFaceSelect) {
        case (true, true): return [(.tagSelect, "TAG", "tag"), (.faceSelect, "FACE", "face.smiling")]
        case (true, false): return [(.tagSelect, "TAG", "tag")]
        case (false, true): return [(.faceSelect, "FACE", "face.smiling")]
        default: return []
        }
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
            if multi { t.append((.createCollage, "COLLAGE", "square.grid.2x2")) }
            if multi { t += selectTools() }
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
            if multi { t += selectTools() }
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
            let actions: [FileAction] = linksOnly ? [.airDrop, .float, .copy, .copyPath] : FileAction.allCases
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
                return WheelItem(id: combine ? "multi-pdf" : ext, label: displayName(ext),
                                 caption: combine ? "Combine into one PDF" : (urls.count > 1 ? "Convert \(urls.count) files to \(displayName(ext))" : "Convert to \(displayName(ext))"),
                                 symbol: nil, payload: .convert(ext),
                                 enabled: Converter.supports(kind: kind, from: first.pathExtension, to: ext))
            }
        case .tools:
            guard let kind = FileKind.common(of: urls) else {
                // Photos et vidéos mélangées : seule la sélection par tag a un sens
                let kinds = Set(urls.map(FileKind.detect))
                if urls.count > 1, kinds.isSubset(of: [.image, .video]) {
                    let children = selectTools().map { WheelItem(id: $0.0.rawValue, label: $0.1, caption: $0.0.title, symbol: $0.2, payload: .tool($0.0)) }
                    if children.count == 2 {
                        var g = WheelItem(id: "select", label: "SELECT", caption: "Select", symbol: "tag", payload: .tool(.tagSelect)); g.children = children
                        return [g]
                    }
                    return children
                }
                return []
            }
            var items: [WheelItem] = tools(for: kind, count: urls.count).map { t in
                let (id, label, symbol) = t
                return WheelItem(id: id.rawValue, label: label, caption: id.title, symbol: symbol, payload: .tool(id),
                                 enabled: ToolAvailability.isImplemented(id))
            }
            // Groupes à 2ᵉ niveau : le survol d'un pétale fait apparaître ses sous-pétales plus loin du centre.
            func group(_ ids: [ToolID], id: String, label: String, caption: String, symbol: String) {
                let found = ids.compactMap { tid in items.first(where: { $0.id == tid.rawValue }) }
                guard found.count == ids.count, let first = items.firstIndex(where: { $0.id == ids[0].rawValue || ids.map(\.rawValue).contains($0.id) }) else { return }
                var g = WheelItem(id: id, label: label, caption: caption, symbol: symbol, payload: .tool(ids[0]))
                g.children = found
                items.removeAll { item in ids.map(\.rawValue).contains(item.id) }
                items.insert(g, at: min(first, items.count))
            }
            group([.tagSelect, .faceSelect], id: "select", label: "SELECT", caption: "Select", symbol: "tag")
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
