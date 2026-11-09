import Foundation
import UniformTypeIdentifiers

/// Famille d'un fichier : détermine quelles roues et quels outils sont proposés.
enum FileKind: String, CaseIterable {
    case image, video, audio, pdf, document, slides, spreadsheet, epub, subtitle, archive, folder, snippet, other

    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff", "avif", "bmp", "gif", "svg"]
    static let videoExts: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi", "wmv", "mpg", "mpeg", "gif_video"]
    static let audioExts: Set<String> = ["mp3", "m4a", "wav", "flac", "ogg", "oga", "opus", "aiff", "aif", "wma", "aac", "caf"]
    static let documentExts: Set<String> = ["docx", "pages", "md", "markdown", "txt", "rtf", "rtfd", "textclipping", "html", "htm", "doc"]
    static let slideExts: Set<String> = ["ppt", "pptx", "key"]
    static let sheetExts: Set<String> = ["xlsx", "xls", "ods", "csv", "tsv", "numbers"]
    static let subtitleExts: Set<String> = ["srt", "vtt"]
    static let archiveExts: Set<String> = ["zip", "tar", "gz", "gzip", "tgz", "rar"]

    static func detect(_ url: URL) -> FileKind {
        if SnippetStore.isSnippet(url) { return .snippet }            // texte glissé
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
           !["rtfd", "pages", "key", "numbers"].contains(url.pathExtension.lowercased()) {
            return .folder
        }
        let e = url.pathExtension.lowercased()
        if e == "pdf" { return .pdf }
        if e == "epub" { return .epub }
        if e == "gif" { return .image }      // un GIF est traité comme une image ; la roue vidéo propose GIF en sortie
        if imageExts.contains(e) { return .image }
        if videoExts.contains(e) { return .video }
        if e == "m3u8" { return HLS.isStream(url) ? .video : .other }       // flux HLS local ; une liste de lecture musicale reste « autre »
        if audioExts.contains(e) { return .audio }
        if slideExts.contains(e) { return .slides }
        if sheetExts.contains(e) { return .spreadsheet }
        if subtitleExts.contains(e) { return .subtitle }
        if archiveExts.contains(e) { return .archive }
        if documentExts.contains(e) { return .document }
        return .other
    }

    /// Type commun d'une sélection (nil si mixte).
    static func common(of urls: [URL]) -> FileKind? {
        let kinds = Set(urls.map(detect))
        return kinds.count == 1 ? kinds.first : nil
    }
}

enum WheelMode: String, CaseIterable, Identifiable {
    case convert, tools, actions
    var id: String { rawValue }
    var title: String {
        switch self {
        case .convert: return L("Convert formats")
        case .tools: return L("File tools")
        case .actions: return L("File actions")
        }
    }
}

enum ToolID: String {
    case compress, metadata, editImage, annotateImage, frameImage, cropImage, redactImage, createCollage, removeBackground, resizeImage, rotateImage, extractAudio, extractImages, quickLook, encodeVideo, openInCode, davinciTree, downloadMP3, downloadMP4, downloadWAV, savePagePDF, savePageMarkdown, savePageScreenshot, faceSelect, scanDocument, translateText, summarizeText, speakText, zipFiles, quickSort, typeSelect
    case trimVideo, cropVideo, changeVideoSpeed, joinVideos, videoSnapshots, splitVideo, redactVideo, muteVideo
    case normalizeAudio, audioToVideo, trimAudio, audioChannels, redactAudio
    case mergePDF, organizePDF, splitPDF, extractArchive, ocr

    /// Outils qui font une nouvelle version d'un fichier : leur résultat peut remplacer l'original (voir ReplaceMode).
    var replacesOriginal: Bool {
        switch self {
        case .compress, .metadata, .editImage, .annotateImage, .frameImage, .cropImage, .redactImage, .resizeImage, .rotateImage, .removeBackground,
             .trimVideo, .cropVideo, .changeVideoSpeed, .redactVideo, .muteVideo, .encodeVideo, .normalizeAudio, .trimAudio, .audioChannels, .redactAudio: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .compress: return L("Compress")
        case .metadata: return L("Metadata")
        case .editImage: return L("Edit Photo")
        case .annotateImage: return L("Annotate Photo")
        case .frameImage: return L("Add BG")
        case .cropImage: return L("Crop Image")
        case .redactImage: return L("Redact Photo")
        case .createCollage: return L("Create Collage")
        case .removeBackground: return L("Remove Background")
        case .resizeImage: return L("Resize")
        case .rotateImage: return L("Rotate & Flip")
        case .extractAudio: return L("Extract Audio")
        case .extractImages: return L("Extract Images")
        case .encodeVideo: return L("Export Video")
        case .openInCode: return L("Open in Code")
        case .davinciTree: return L("DaVinci Project")
        case .downloadMP3: return L("Download MP3")
        case .downloadMP4: return L("Download MP4")
        case .downloadWAV: return L("Download WAV")
        case .savePagePDF: return L("Save page as PDF")
        case .savePageMarkdown: return L("Save page as Markdown")
        case .savePageScreenshot: return L("Save page screenshot")
        case .faceSelect: return L("Face Select")
        case .scanDocument: return L("Scan Document")
        case .translateText: return L("Translate")
        case .summarizeText: return L("Summarize")
        case .speakText: return L("Read Aloud")
        case .zipFiles: return L("Zip")
        case .quickSort: return L("Quick Sort")
        case .typeSelect: return L("Type Select")
        case .quickLook: return L("Quick Look")
        case .trimVideo: return L("Trim Video")
        case .cropVideo: return L("Crop Video")
        case .changeVideoSpeed: return L("Change Video Speed")
        case .joinVideos: return L("Join Videos")
        case .videoSnapshots: return L("Video Snapshots")
        case .splitVideo: return L("Split Video")
        case .redactVideo: return L("Redact Video")
        case .muteVideo: return L("Mute Video")
        case .normalizeAudio: return L("Normalize Volume")
        case .audioToVideo: return L("Audio Visualizer")
        case .trimAudio: return L("Trim Audio")
        case .audioChannels: return L("Convert Audio Channels")
        case .redactAudio: return L("Bleep Audio")
        case .mergePDF: return L("Merge PDFs")
        case .organizePDF: return L("Organize PDF")
        case .splitPDF: return L("Split PDF")
        case .extractArchive: return L("Extract Archive")
        case .ocr: return L("Extract Text")
        }
    }
}

enum FileAction: String, CaseIterable {
    case airDrop, float, copy, move, copyPath, terminal, switchView, searchWeb
    var label: String {
        switch self {
        case .airDrop: return L("AIRDROP")
        case .float: return L("FLOAT")
        case .copy: return L("COPY")
        case .move: return L("MOVE")
        case .copyPath: return L("COPY PATH")
        case .terminal: return L("TERMINAL")
        case .switchView: return AppSettings.shared.appearance == .wii ? L("WHEEL VIEW") : L("WII VIEW")
        case .searchWeb: return L("SEARCH")
        }
    }
    var caption: String {
        switch self {
        case .airDrop: return L("AirDrop")
        case .float: return L("Float")
        case .copy: return L("Copy")
        case .move: return L("Move")
        case .copyPath: return L("Copy Path")
        case .terminal: return L("Terminal")
        case .switchView: return AppSettings.shared.appearance == .wii ? L("Wheel View") : L("Wii View")
        case .searchWeb: return L("Search the web")
        }
    }
    var symbol: String {
        switch self {
        case .airDrop: return L("airplayaudio")
        case .float: return L("square.stack.3d.up")
        case .copy: return L("doc.on.doc")
        case .move: return L("folder")
        case .copyPath: return L("link")
        case .terminal: return L("terminal")
        case .switchView: return L("arrow.triangle.2.circlepath")
        case .searchWeb: return L("magnifyingglass")
        }
    }
}

struct WheelItem: Identifiable, Equatable {
    enum Payload: Equatable {
        case convert(String)        // extension de sortie
        case tool(ToolID)
        case action(FileAction)
    }
    let id: String
    let label: String               // texte dans le segment
    let caption: String             // légende sous la roue
    let symbol: String?
    let payload: Payload
    var enabled: Bool = true
    /// Sous-pétales (2ᵉ niveau) qui apparaissent plus loin du centre quand on survole ce pétale.
    var children: [WheelItem] = []
    var isGroup: Bool { !children.isEmpty }
}
