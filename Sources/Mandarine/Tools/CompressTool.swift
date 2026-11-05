import SwiftUI

struct CompressTool: View {
    let urls: [URL]
    let close: () -> Void

    @State private var strong = false
    @State private var sizeChoice = 0
    @State private var useTarget = false
    @State private var targetMB = 1.0
    @State private var asArchive: Bool          // plusieurs fichiers : une seule archive ZIP (par défaut si les types sont mélangés), ou un fichier compressé à la fois

    init(urls: [URL], close: @escaping () -> Void) {
        self.urls = urls; self.close = close
        _asArchive = State(initialValue: urls.count > 1 && FileKind.common(of: urls) == nil)
    }

    private var mixed: Bool { FileKind.common(of: urls) == nil }
    private var kind: FileKind { FileKind.common(of: urls) ?? .other }
    private var total: Int64 { urls.reduce(0) { $0 + $1.fileSize } }
    private var sizeOptions: [(String, Double?, Int?)] {
        [("Keep original dimensions", nil, nil), ("75%", 0.75, nil), ("50%", 0.5, nil), ("25%", 0.25, nil),
         ("Max 3840 px", nil, 3840), ("Max 2048 px", nil, 2048), ("Max 1280 px", nil, 1280)]
    }
    private var supportsTarget: Bool { [.image, .video, .audio].contains(kind) }
    private var supportsPreset: Bool { mixed || (kind != .folder && kind != .other) }

    var body: some View {
        ToolShell(title: L("Compress"), close: close) {
            VStack(alignment: .leading, spacing: 14) {
                Text(urls.count == 1 ? urls[0].lastPathComponent : L("\(urls.count) files"))
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                Text(L("Original size: \(total.humanSize)")).font(.system(size: 15, weight: .medium))
                if urls.count > 1 {
                    Toggle(L("Put everything in one ZIP archive"), isOn: $asArchive)
                    Text(asArchive ? L("Creates a single Archive.zip with all the files.") : L("Each file is compressed on its own, with the options below."))
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                if supportsPreset && !asArchive {
                    Text(L("Compression preset")).font(.system(size: 16, weight: .semibold))
                    PillPicker(options: [(false, "Balanced"), (true, "Strong")], selection: $strong)
                    Text(strong ? L("Much smaller files, with visible quality loss.") : L("Smaller files with less quality loss."))
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                if (kind == .image || kind == .video) && !asArchive {
                    HStack {
                        Text(kind == .image ? L("Image size") : L("Video size")).font(.system(size: 15))
                        Picker("", selection: $sizeChoice) {
                            ForEach(Array(sizeOptions.enumerated()), id: \.offset) { Text(L($1.0)).tag($0) }
                        }.labelsHidden().frame(maxWidth: 230)
                    }
                }
                if supportsTarget && !asArchive {
                    Divider()
                    Toggle(L("Compress to target file size"), isOn: $useTarget)
                    if useTarget {
                        HStack {
                            Slider(value: $targetMB, in: 0.05...max(0.1, Double(total) / 1_000_000), step: 0.05)
                            Text(String(format: L("%.2f MB"), targetMB)).font(.system(size: 12).monospacedDigit()).frame(width: 70, alignment: .trailing)
                        }
                    }
                }
                if mixed && !asArchive {
                    Text(L("Each file is compressed according to its type: photos, videos, sounds and PDFs.")).font(.system(size: 12)).foregroundStyle(Theme.muted)
                } else if (kind == .other || kind == .folder) && !asArchive {
                    Text(L("This item will be compressed into a ZIP archive.")).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 400, alignment: .leading)
        } footer: {
            ReplaceButton(L("Compress")) { run() }
        }
        .onAppear { targetMB = max(0.05, min(targetMB, Double(total) / 2_000_000)) }
    }

    private func run() {
        var o = CompressOptions(strong: strong)
        let c = sizeOptions[sizeChoice]
        o.scale = c.1; o.maxSide = c.2
        if useTarget && supportsTarget { o.targetBytes = Int64(targetMB * 1_000_000) }
        let files = urls
        let archive = asArchive && files.count > 1
        close()
        if archive {
            Dispatcher.job(L("Zipping…"), subtitle: L("\(files.count) files")) { _ in [try await ZipEngine.make(files)] }
            return
        }
        Dispatcher.job(L("Compressing…"), subtitle: files.count == 1 ? files[0].lastPathComponent : L("\(files.count) files"), count: files.count, replaces: files) { progress in
            var outs: [URL] = []
            for (i, f) in files.enumerated() {
                let o = try await Compressor.run(f, options: o) { p in progress((Double(i) + p) / Double(files.count)) }
                outs.append(o)
            }
            return outs
        }
    }
}
