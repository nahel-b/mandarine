import SwiftUI

enum ToolRegistry {
    static func view(for id: ToolID, urls: [URL], close: @escaping () -> Void) -> AnyView {
        switch id {
        case .compress: return AnyView(CompressTool(urls: urls, close: close))
        case .editImage: return AnyView(EditPhotoTool(urls: urls, close: close))
        case .annotateImage: return AnyView(AnnotateTool(urls: urls, close: close))
        case .frameImage: return AnyView(FrameImageTool(urls: urls, close: close))
        case .createCollage: return AnyView(CollageTool(urls: urls, close: close))
        case .metadata: return AnyView(MetadataTool(urls: urls, close: close))
        case .trimVideo: return AnyView(TrimVideoTool(urls: urls, close: close))
        case .cropVideo: return AnyView(CropVideoTool(urls: urls, close: close))
        case .changeVideoSpeed: return AnyView(SpeedVideoTool(urls: urls, close: close))
        case .joinVideos: return AnyView(JoinVideosTool(urls: urls, close: close))
        case .videoSnapshots: return AnyView(SnapshotsTool(urls: urls, close: close))
        case .splitVideo: return AnyView(SplitVideoTool(urls: urls, close: close))
        case .redactVideo: return AnyView(RedactVideoTool(urls: urls, close: close))
        case .normalizeAudio: return AnyView(NormalizeTool(urls: urls, close: close))
        case .audioToVideo: return AnyView(VisualizerTool(urls: urls, close: close))
        case .trimAudio: return AnyView(TrimAudioTool(urls: urls, close: close))
        case .audioChannels: return AnyView(ChannelsTool(urls: urls, close: close))
        case .redactAudio: return AnyView(BleepTool(urls: urls, close: close))
        case .removeBackground: return AnyView(RemoveBGTool(urls: urls, close: close))
        case .resizeImage: return AnyView(ResizeImageTool(urls: urls, close: close))
        case .rotateImage: return AnyView(RotateImageTool(urls: urls, close: close))
        case .extractAudio: return AnyView(ExtractAudioTool(urls: urls, close: close))
        case .encodeVideo: return AnyView(EncodeVideoTool(urls: urls, close: close))
        case .davinciTree: return AnyView(DaVinciTreeTool(urls: urls, close: close))
        case .quickLook: return AnyView(QuickLookTool(urls: urls, close: close))
        case .cropImage: return AnyView(CropImageTool(urls: urls, close: close))
        case .redactImage: return AnyView(RedactImageTool(urls: urls, close: close))
        case .ocr: return AnyView(OCRTool(urls: urls, close: close))
        case .scanDocument: return AnyView(ScanTool(urls: urls, close: close))
        case .translateText: return AnyView(TranslateTool(urls: urls, close: close))
        case .summarizeText: return AnyView(SummarizeTool(urls: urls, close: close))
        case .faceSelect: return AnyView(FaceSelectTool(urls: urls, close: close))
        case .mergePDF: return AnyView(MergePDFTool(urls: urls, close: close))
        case .organizePDF: return AnyView(OrganizePDFTool(url: urls[0], close: close))
        case .splitPDF, .extractArchive, .muteVideo, .extractImages, .openInCode, .downloadMP3, .downloadMP4, .downloadWAV, .tagSelect, .speakText:
            return AnyView(DirectToolView(id: id, urls: urls, close: close))
        default:
            return AnyView(ComingSoonTool(id: id, close: close))
        }
    }
}

struct ComingSoonTool: View {
    let id: ToolID
    let close: () -> Void
    var body: some View {
        ToolShell(title: id.title, close: close) {
            Text("This tool is not available yet.").foregroundStyle(Theme.muted).frame(width: 360, height: 80)
        } footer: { Button("Close", action: close).buttonStyle(PillButtonStyle()) }
    }
}

/// Outils sans réglages : lancent leur travail dès l'ouverture, puis ferment la fenêtre.
struct DirectToolView: View {
    let id: ToolID
    let urls: [URL]
    let close: () -> Void
    var body: some View {
        Color.clear.frame(width: 1, height: 1).onAppear {
            close()
            let files = urls
            switch id {
            case .splitPDF:
                Dispatcher.job("Splitting PDF…", light: true) { _ in try files.map { try PDFEngine.split($0) } }
            case .extractArchive:
                Dispatcher.job("Extracting…", light: true) { _ in try files.map { try ArchiveEngine.extractNextTo($0) } }
            case .downloadMP3, .downloadMP4, .downloadWAV:
                DownloadFlow.start(links: files, kind: id == .downloadMP3 ? .mp3 : (id == .downloadWAV ? .wav : .mp4))
            case .tagSelect:
                TagSelect.start(files)
            case .speakText:
                SnippetSpeaker.shared.speak(files.map { SnippetStore.text(of: $0) }.joined(separator: "\n\n"))
            case .openInCode:
                VSCode.open(files)
            case .extractImages:
                Dispatcher.job("Extracting images…", light: true) { _ in
                    var outs: [URL] = []
                    for f in files {
                        let dir = OutputNaming.folder(of: f, suffix: "images")
                        let n = try await Task.detached { try PDFImageExtractor.extract(f, into: dir) }.value
                        if n == 0 { try? FileManager.default.removeItem(at: dir); throw MandarineError("Aucune image intégrée dans \(f.lastPathComponent).") }
                        outs.append(dir)
                    }
                    return outs
                }
            case .removeBackground:
                Dispatcher.job("Removing background…") { progress in
                    var outs: [URL] = []
                    for (i, f) in files.enumerated() {
                        outs.append(try await Task.detached { try BackgroundRemover.run(f) }.value)
                        progress(Double(i + 1) / Double(files.count))
                    }
                    return outs
                }
            case .muteVideo:
                Dispatcher.job("Removing audio…") { progress in
                    var outs: [URL] = []
                    for f in files {
                        let out = OutputNaming.sibling(of: f, suffix: " muted")
                        let info = await FFmpeg.probe(f)
                        try await FFmpeg.run(["-i", f.path, "-c:v", "copy", "-an", out.path], duration: info.duration, progress: progress)
                        outs.append(out)
                    }
                    return outs
                }
            default: break
            }
        }
    }
}
