import Foundation
import UniformTypeIdentifiers

/// Famille d'un fichier : détermine quelles roues et quels outils sont proposés.
enum FileKind: String, CaseIterable {
    case image, video, audio, pdf, document, slides, spreadsheet, epub, subtitle, archive, folder, other

    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff", "avif", "bmp", "gif", "svg"]
    static let videoExts: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi", "wmv", "mpg", "mpeg", "gif_video"]
    static let audioExts: Set<String> = ["mp3", "m4a", "wav", "flac", "ogg", "oga", "opus", "aiff", "aif", "wma", "aac", "caf"]
    static let documentExts: Set<String> = ["docx", "pages", "md", "markdown", "txt", "rtf", "rtfd", "textclipping", "html", "htm", "doc"]
    static let slideExts: Set<String> = ["ppt", "pptx", "key"]
    static let sheetExts: Set<String> = ["xlsx", "xls", "ods", "csv", "tsv", "numbers"]
    static let subtitleExts: Set<String> = ["srt", "vtt"]
    static let archiveExts: Set<String> = ["zip", "tar", "gz", "gzip", "tgz", "rar"]

    static func detect(_ url: URL) -> FileKind {
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
        case .convert: return "Convert formats"
        case .tools: return "File tools"
        case .actions: return "File actions"
        }
    }
}

enum ToolID: String {
    case compress, metadata, editImage, annotateImage, frameImage, cropImage, redactImage, createCollage, removeBackground, resizeImage, rotateImage, extractAudio, extractImages, quickLook, encodeVideo, openInCode, davinciTree, downloadMP3, downloadMP4, downloadWAV, tagSelect, faceSelect
    case trimVideo, cropVideo, changeVideoSpeed, joinVideos, videoSnapshots, splitVideo, redactVideo, muteVideo
    case normalizeAudio, audioToVideo, trimAudio, audioChannels, redactAudio
    case mergePDF, organizePDF, splitPDF, extractArchive, ocr

    var title: String {
        switch self {
        case .compress: return "Compress"
        case .metadata: return "Metadata"
        case .editImage: return "Edit Photo"
        case .annotateImage: return "Annotate Photo"
        case .frameImage: return "Add BG"
        case .cropImage: return "Crop Image"
        case .redactImage: return "Redact Photo"
        case .createCollage: return "Create Collage"
        case .removeBackground: return "Remove Background"
        case .resizeImage: return "Resize"
        case .rotateImage: return "Rotate & Flip"
        case .extractAudio: return "Extract Audio"
        case .extractImages: return "Extract Images"
        case .encodeVideo: return "Export Video"
        case .openInCode: return "Open in Code"
        case .davinciTree: return "DaVinci Project"
        case .downloadMP3: return "Download MP3"
        case .downloadMP4: return "Download MP4"
        case .downloadWAV: return "Download WAV"
        case .tagSelect: return "Tag Select"
        case .faceSelect: return "Face Select"
        case .quickLook: return "Quick Look"
        case .trimVideo: return "Trim Video"
        case .cropVideo: return "Crop Video"
        case .changeVideoSpeed: return "Change Video Speed"
        case .joinVideos: return "Join Videos"
        case .videoSnapshots: return "Video Snapshots"
        case .splitVideo: return "Split Video"
        case .redactVideo: return "Redact Video"
        case .muteVideo: return "Mute Video"
        case .normalizeAudio: return "Normalize Volume"
        case .audioToVideo: return "Audio Visualizer"
        case .trimAudio: return "Trim Audio"
        case .audioChannels: return "Convert Audio Channels"
        case .redactAudio: return "Bleep Audio"
        case .mergePDF: return "Merge PDFs"
        case .organizePDF: return "Organize PDF"
        case .splitPDF: return "Split PDF"
        case .extractArchive: return "Extract Archive"
        case .ocr: return "Extract Text"
        }
    }
}

enum FileAction: String, CaseIterable {
    case airDrop, float, copy, move, copyPath, terminal, switchView
    var label: String {
        switch self {
        case .airDrop: return "AIRDROP"
        case .float: return "FLOAT"
        case .copy: return "COPY"
        case .move: return "MOVE"
        case .copyPath: return "COPY PATH"
        case .terminal: return "TERMINAL"
        case .switchView: return AppSettings.shared.appearance == .wii ? "WHEEL VIEW" : "WII VIEW"
        }
    }
    var caption: String {
        switch self {
        case .airDrop: return "AirDrop"
        case .float: return "Float"
        case .copy: return "Copy"
        case .move: return "Move"
        case .copyPath: return "Copy Path"
        case .terminal: return "Terminal"
        case .switchView: return AppSettings.shared.appearance == .wii ? "Wheel View" : "Wii View"
        }
    }
    var symbol: String {
        switch self {
        case .airDrop: return "airplayaudio"
        case .float: return "square.stack.3d.up"
        case .copy: return "doc.on.doc"
        case .move: return "folder"
        case .copyPath: return "link"
        case .terminal: return "terminal"
        case .switchView: return "arrow.triangle.2.circlepath"
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
