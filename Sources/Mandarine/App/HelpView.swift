import SwiftUI
import AppKit

// MARK: Ressources d'illustration
/// Image d'exemple tirée du logo (SVG) : sert de « photo » aux démonstrations, sans dépendre d'aucun fichier de l'utilisateur.
enum HelpAssets {
    static let sampleURL: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Mandarine-Help", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("tangerine.png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let size = NSSize(width: 900, height: 900)
        let img = NSImage(size: size)
        img.lockFocus()
        if let r = Bundle.main.resourceURL?.appendingPathComponent("logo.svg"), let svg = NSImage(contentsOf: r) {
            svg.draw(in: NSRect(origin: .zero, size: size))
        } else {
            NSColor(calibratedRed: 0.02, green: 0.43, blue: 0.74, alpha: 1).setFill(); NSRect(origin: .zero, size: size).fill()
            NSColor.orange.setFill(); NSBezierPath(ovalIn: NSRect(x: 150, y: 150, width: 600, height: 560)).fill()
        }
        img.unlockFocus()
        if let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t), let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: url) }
        return url
    }()
    static let fakeImage = URL(fileURLWithPath: "/Mandarine/photo.jpg")      // n'existe pas : sert seulement à construire les roues
    /// Vrai dossier (vide) : la roue d'actions propose « CODE » seulement pour un dossier existant.
    static let fakeFolder: URL = {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("Mandarine-Help/project", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
}

// MARK: Éléments visuels
private struct Keycap: View {
    let symbol: String, name: String
    var pressed = false
    var body: some View {
        VStack(spacing: 2) {
            Text(symbol).font(.system(size: 17, weight: .medium))
            Text(name).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
        }
        .frame(width: 58, height: 52)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(pressed ? Theme.orange : Color.white.opacity(0.92)))
        .foregroundStyle(pressed ? Color.white : Theme.text)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.black.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: pressed ? 2 : 6, y: pressed ? 1 : 4)
        .scaleEffect(pressed ? 0.96 : 1)
    }
}

/// Fond « bureau » sombre sur lequel on pose les illustrations.
private struct Desktop<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.12, blue: 0.24), Color(red: 0.22, green: 0.12, blue: 0.20), Color(red: 0.55, green: 0.24, blue: 0.14)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Theme.orange.opacity(0.25)).frame(width: 300).blur(radius: 70).offset(x: 140, y: 110)
            Circle().fill(Color.blue.opacity(0.25)).frame(width: 260).blur(radius: 70).offset(x: -170, y: -110)
            content()
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

/// La vraie roue de l'app, figée dans un état donné.
private struct WheelPicture: View {
    let model: WheelModel
    let scale: CGFloat
    init(mode: WheelMode, urls: [URL] = [HelpAssets.fakeImage], hover: Int? = nil, child: Int? = nil, scale: CGFloat = 0.6) {
        let m = WheelModel()
        m.mode = mode
        m.items = Catalog.items(mode: mode, urls: urls)
        m.appear = true
        m.sizeLabel = "2.4 MB"
        m.infoLines = urls.first.map { FileKind.detect($0) == .folder ? ["48 items", "1.2 GB"] : ["2.4 MB", "4032 × 3024", "JPG"] } ?? []
        m.hover = hover; m.hoverChild = child
        if let h = hover, m.items.indices.contains(h), m.items[h].isGroup { m.blobParent = h; m.blobCount = m.items[h].children.count; m.blobT = 1 }
        model = m; self.scale = scale
    }
    var body: some View {
        WheelView(model: model).frame(width: WheelGeometry.size, height: WheelGeometry.size)
            .scaleEffect(scale).frame(width: WheelGeometry.size * scale, height: WheelGeometry.size * scale)
    }
}

/// Fenêtre d'outil réelle (aperçu non interactif, réduit).
private struct ToolPicture<V: View>: View {
    let width: CGFloat, height: CGFloat, scale: CGFloat
    @ViewBuilder var content: () -> V
    var body: some View {
        content().environment(\.colorScheme, .light)
            .fixedSize()
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width * scale, height: height * scale, alignment: .topLeading)
            .allowsHitTesting(false)
            .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
    }
}

private struct FileChip: View {
    let name: String
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "photo.fill").font(.system(size: 26)).foregroundStyle(.white)
                .frame(width: 46, height: 46).background(RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [Color.blue, Color.cyan], startPoint: .top, endPoint: .bottom)))
            Text(name).font(.system(size: 9, weight: .medium)).foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 1)
                .background(Capsule().fill(Color.blue.opacity(0.85)))
        }
    }
}

// MARK: Démo animée : glisser, taper, déposer
private struct DragDemo: View {
    @State private var t = 0.0
    @State private var model = WheelModel()
    private let timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()
    private let cycle = 7.0
    private let center = CGPoint(x: 270, y: 190)

    private func ease(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }
    private func mix(_ a: CGPoint, _ b: CGPoint, _ p: Double) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p) }

    private var filePos: CGPoint {
        let start = CGPoint(x: 70, y: 285), target = CGPoint(x: center.x, y: center.y - 54 * 1.0)
        if t < 1.5 { return mix(start, center, ease(t / 1.5)) }
        if t < 3.2 { return center }
        if t < 4.1 { return mix(center, target, ease((t - 3.2) / 0.9)) }
        return target
    }

    var body: some View {
        Desktop {
            ZStack {
                // roue
                WheelView(model: model).frame(width: WheelGeometry.size, height: WheelGeometry.size)
                    .scaleEffect(0.62).position(center)
                // clavier
                HStack(spacing: 10) {
                    Keycap(symbol: "⇧", name: "shift", pressed: t > 1.7 && t < 5.2)
                    Keycap(symbol: "⌘", name: "command")
                    Keycap(symbol: "⌃", name: "control")
                }.position(x: 270, y: 330)
                // fichier glissé
                if t < 4.6 {
                    FileChip(name: "photo.jpg").position(filePos).scaleEffect(t > 4.2 ? max(0.01, 1 - (t - 4.2) / 0.4) : 1)
                }
                // résultat
                if t > 4.6 && t < 6.6 {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.orange)
                        VStack(alignment: .leading, spacing: 1) { Text("Saved photo.png").font(.system(size: 12, weight: .semibold)); Text("next to the original").font(.system(size: 10)).foregroundStyle(.secondary) }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial).environment(\.colorScheme, .light))
                    .foregroundStyle(Theme.text)
                    .position(x: 400, y: 48)
                    .transition(.opacity)
                    .opacity(t < 4.9 ? (t - 4.6) / 0.3 : (t > 6.2 ? max(0, (6.6 - t) / 0.4) : 1))
                }
            }
        }
        .onAppear { configure() }
        .onReceive(timer) { _ in
            t = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
            let shown = t > 1.9 && t < 4.5
            if model.appear != shown { withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { model.appear = shown } }
            let hover: Int? = (t > 3.6 && t < 4.5) ? 0 : nil
            if model.hover != hover { model.hover = hover }
        }
    }

    private func configure() {
        model.mode = .convert
        model.items = Catalog.items(mode: .convert, urls: [HelpAssets.fakeImage])
        model.sizeLabel = "2.4 MB"
        model.infoLines = ["2.4 MB", "4032 × 3024", "JPG"]
    }
}

// MARK: Pages
private struct Bullet: Identifiable { let id = UUID(); let symbol: String; let title: String; let text: String }

private struct HelpPage {
    let title: String
    let subtitle: String
    let bullets: [Bullet]
    let illustration: () -> AnyView
}

private struct FamilyCard: View {
    let symbol: String, title: String, formats: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.orange)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(formats).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }
}

private struct StatusRow: View {
    let name: String, detail: String, ok: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "minus.circle").foregroundStyle(ok ? Color.green : Theme.muted)
            Text(name).font(.system(size: 12, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(Theme.muted)
            Spacer()
        }
    }
}

private struct BeforeAfter: View {
    @State private var after: NSImage?
    @State private var failed = false
    var body: some View {
        HStack(spacing: 14) {
            tile("Before") { Image(nsImage: NSImage(contentsOf: HelpAssets.sampleURL) ?? NSImage()).resizable().scaledToFill() }
            Image(systemName: "arrow.right").font(.system(size: 18, weight: .bold)).foregroundStyle(.white.opacity(0.8))
            tile("After") {
                ZStack {
                    Canvas { ctx, size in
                        let s: CGFloat = 12
                        for y in 0..<Int(size.height / s) + 1 { for x in 0..<Int(size.width / s) + 1 {
                            ctx.fill(Path(CGRect(x: CGFloat(x) * s, y: CGFloat(y) * s, width: s, height: s)), with: .color((x + y) % 2 == 0 ? Color(white: 0.95) : Color(white: 0.8)))
                        } }
                    }
                    if let a = after { Image(nsImage: a).resizable().scaledToFit().padding(8) }
                    else if failed { Text("—").foregroundStyle(.gray) } else { ProgressView().controlSize(.small) }
                }
            }
        }
        .padding(18)
        .task { await render() }
    }

    private func tile<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        ZStack(alignment: .topLeading) {
            content().frame(width: 190, height: 190).clipped()
            Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.6))).padding(8)
        }
        .frame(width: 190, height: 190).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
    }

    private func render() async {
        guard #available(macOS 14.0, *) else { failed = true; return }
        let url = HelpAssets.sampleURL
        let img: CGImage? = await Task.detached {
            guard let (cg, _) = try? ImageEngine.load(url, maxSide: 900), let s = try? BGSession(cg) else { return nil }
            var o = BGOptions(); o.outline = true; o.outlineWidth = 9; o.soften = 1.5; o.cropToSubject = true
            return try? s.render(o)
        }.value
        if let img = img { after = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height)) } else { failed = true }
    }
}

private struct EnginesCard: View {
    @State private var tab = Int(ProcessInfo.processInfo.environment["MANDARINE_ENGINES_TAB"] ?? "") ?? 0     // 0 = Homebrew, 1 = sans Homebrew (téléchargement par l'app)
    @State private var tick = 0
    @State private var copied = ""

    static let homebrew = "brew install ffmpeg webp yt-dlp"
    static let homebrewInstall = "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    @ObservedObject private var installer = EngineInstaller.shared
    @ObservedObject private var yt = YtDlpUpdater.shared

    /// Une ligne de téléchargement fait par l'app elle-même (dossier des moteurs de Mandarine, aucun droit administrateur).
    private func downloadRow(_ title: String, _ detail: String, ready: Bool, working: Double?, error: String?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 11, weight: .semibold))
                    Text(detail).font(.system(size: 9.5)).foregroundStyle(Theme.muted)
                }
                Spacer()
                if ready {
                    Label("Installed", systemImage: "checkmark.circle.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(.green)
                } else if let w = working {
                    if w > 0 { ProgressView(value: w).frame(width: 80) } else { ProgressView().controlSize(.small) }
                } else {
                    Button(action: action) {
                        Label("Download", systemImage: "arrow.down.circle.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Theme.orange))
                    }.buttonStyle(.plain)
                }
            }
            if let e = error { Text(e).font(.system(size: 9.5)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.94))).foregroundStyle(Theme.text)
    }

    private func installerRow(_ title: String, _ detail: String, _ e: EngineInstaller.Engine, ready: Bool) -> some View {
        var working: Double?
        var error: String?
        switch installer.state(e) {
        case .working(let p): working = p
        case .failed(let m): error = m
        default: break
        }
        return downloadRow(title, detail, ready: ready, working: working, error: error) { installer.install(e) }
    }

    private var ytRow: some View {
        var working: Double?
        var error: String?
        switch yt.state {
        case .installing, .checking: working = 0
        case .failed(let m): error = m
        default: break
        }
        return downloadRow("yt-dlp", "For links (YouTube, Instagram, SoundCloud…). The app checks the official release before using it.", ready: YtDlp.url != nil, working: working, error: error) { Task { await yt.install() } }
    }

    private func block(_ id: String, _ title: String, _ code: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                Spacer()
                Button {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string)
                    copied = id; DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { if copied == id { copied = "" } }
                } label: {
                    Label(copied == id ? "Copied" : "Copy", systemImage: copied == id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.94)))
                }.buttonStyle(.plain)
            }
            Text(code).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(Color(white: 0.92))
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PillPicker(options: [(0, "With Homebrew"), (1, "Without Homebrew")], selection: $tab)
                .padding(3).background(Capsule().fill(Color.white.opacity(0.94))).environment(\.colorScheme, .light)
            if tab == 0 {
                block("brew", "1 · Paste in Terminal", Self.homebrew)
                block("brewinstall", "No Homebrew yet? Install it first (official script)", Self.homebrewInstall)
            } else {
                installerRow("ffmpeg + ffprobe", "Video and audio. Downloaded by Mandarine into its own folder — nothing else to install.", .ffmpeg, ready: FFmpeg.ffmpeg != nil && FFmpeg.ffprobe != nil)
                installerRow("WebP", "Needed to create .webp images.", .cwebp, ready: FFmpeg.locate("cwebp") != nil || FFmpeg.hasEncoder("libwebp"))
                ytRow
            }
            VStack(spacing: 6) {
                StatusRow(name: "ffmpeg", detail: FFmpeg.ffmpeg?.deletingLastPathComponent().path ?? "not found", ok: FFmpeg.ffmpeg != nil)
                StatusRow(name: "ffprobe", detail: FFmpeg.ffprobe?.deletingLastPathComponent().path ?? "not found", ok: FFmpeg.ffprobe != nil)
                StatusRow(name: "yt-dlp", detail: YtDlp.url?.deletingLastPathComponent().path ?? "not found", ok: YtDlp.url != nil)
                StatusRow(name: "WebP", detail: (FFmpeg.locate("cwebp") != nil || FFmpeg.hasEncoder("libwebp")) ? "available" : "not available yet", ok: FFmpeg.locate("cwebp") != nil || FFmpeg.hasEncoder("libwebp"))
            }
            .padding(10).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.94))).foregroundStyle(Theme.text)
            HStack {
                Button { NSWorkspace.shared.open(FFmpeg.enginesFolder.deletingLastPathComponent()) } label: {
                    Label("Open folder", systemImage: "folder").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Color.white.opacity(0.94)))
                }.buttonStyle(.plain)
                Spacer()
                Button { tick += 1 } label: {
                    Label("Check again", systemImage: "arrow.clockwise").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Color.white.opacity(0.94)))
                }.buttonStyle(.plain)
            }
        }
        .id(tick)
        .padding(18)
    }
}

private struct TimelineMock: View {
    var body: some View {
        VStack(spacing: 14) {
            card("Trim audio") {
                TimeRangeSelector(duration: 3, start: .constant(0.55), end: .constant(2.2), playhead: nil) {
                    ZStack { Theme.orange.opacity(0.08); WaveformView(peaks: (0..<90).map { i in
                        let burst = (i > 12 && i < 38) || (i > 52 && i < 80)
                        return burst ? Float(0.45 + 0.5 * abs(sin(Double(i) * 0.9))) : 0.02 }) }
                }.frame(height: 78)
            }
            card("Trim video") {
                TimeRangeSelector(duration: 4, start: .constant(0.8), end: .constant(3.1), playhead: nil) {
                    HStack(spacing: 0) {
                        ForEach(0..<10, id: \.self) { i in
                            LinearGradient(colors: [Color(hue: 0.05 + Double(i) * 0.02, saturation: 0.7, brightness: 0.8), Color(hue: 0.02 + Double(i) * 0.02, saturation: 0.8, brightness: 0.45)], startPoint: .top, endPoint: .bottom)
                        }
                    }
                }.frame(height: 62)
            }
        }
        .padding(22)
        .environment(\.colorScheme, .light)
    }

    private func card<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
            content()
        }
        .padding(14).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.94)))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }
}

// MARK: Vue principale
struct HelpView: View {
    var startPage = 0
    let close: () -> Void
    @State private var page = 0
    @ObservedObject private var settings = AppSettings.shared
    private let count = 10

    private var sample: URL { HelpAssets.sampleURL }

    private var pages: [HelpPage] {
        [
            HelpPage(title: "First, set up the engines",
                     subtitle: "Images, PDF, documents, archives and subtitles work right away. Video, audio and WebP need ffmpeg: Mandarine can download it itself (“Without Homebrew”), or you can use Homebrew.",
                     bullets: [Bullet(symbol: "checkmark.seal", title: "Works without anything", text: "Convert and edit images, PDF, documents, slides, spreadsheets, subtitles, archives."),
                               Bullet(symbol: "film", title: "Needs ffmpeg", text: "Video and audio conversion and tools, Export Video, and WebP."),
                               Bullet(symbol: "arrow.down.circle", title: "One-click download", text: "Mandarine downloads ffmpeg, WebP, yt-dlp and the face model into its own folder — no Homebrew, no Terminal. Same buttons in Settings → Engines."),
                               Bullet(symbol: "arrow.clockwise", title: "Then check", text: "The status below turns green. You can skip this and come back via Help.")],
                     illustration: { AnyView(Desktop { EnginesCard() }) }),
            HelpPage(title: "Drag. Tap. Drop.",
                     subtitle: "Mandarine converts and edits files from a wheel that appears right under your cursor. No upload, no window to open: everything runs on your Mac.",
                     bullets: [Bullet(symbol: "hand.draw", title: "Drag any file", text: "From Finder, the Desktop or any app."),
                               Bullet(symbol: "keyboard", title: "Tap a key", text: "⇧ converts, ⌘ opens tools, ⌃ runs actions."),
                               Bullet(symbol: "tray.and.arrow.down", title: "Drop on a petal", text: "The result is saved next to the original. Nothing is ever overwritten.")],
                     illustration: { AnyView(DragDemo()) }),
            HelpPage(title: "Three wheels, three keys",
                     subtitle: "The key you tap decides what the wheel offers. Tap another key while you drag to switch: the wheel stays where it is.",
                     bullets: [Bullet(symbol: "arrow.triangle.2.circlepath", title: "⇧ Convert formats", text: "Only the formats that make sense for this file."),
                               Bullet(symbol: "slider.horizontal.3", title: "⌘ File tools", text: "Compress, crop, trim, redact, merge and more."),
                               Bullet(symbol: "square.and.arrow.up", title: "⌃ File actions", text: "AirDrop, Float, Copy, Move, Terminal… Works on folders too.")],
                     illustration: { AnyView(Desktop {
                         HStack(spacing: 0) {
                             column(.convert, "⇧", "shift", hover: 0)
                             column(.tools, "⌘", "command", hover: 3)
                             column(.actions, "⌃", "control", hover: 2)
                         }
                     }) }),
            HelpPage(title: "Convert anything",
                     subtitle: "275 conversion paths across images, video, audio, documents, slides, spreadsheets, subtitles and archives. Only valid choices are shown for each file.",
                     bullets: [Bullet(symbol: "photo.on.rectangle.angled", title: "Several images, one PDF", text: "Select many images and drop on PDF."),
                               Bullet(symbol: "checkmark.shield", title: "Grayed petals", text: "A format your Mac or installed apps can't produce is dimmed."),
                               Bullet(symbol: "internaldrive", title: "100% local", text: "Your files never leave your Mac.")],
                     illustration: { AnyView(Desktop {
                         LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                             FamilyCard(symbol: "photo", title: "Images", formats: "PNG WEBP HEIC TIFF AVIF BMP PDF")
                             FamilyCard(symbol: "film", title: "Video", formats: "MP4 MKV WEBM AVI WMV GIF MP3")
                             FamilyCard(symbol: "waveform", title: "Audio", formats: "M4A WAV FLAC OGG OPUS AIFF")
                             FamilyCard(symbol: "doc.richtext", title: "PDF", formats: "DOCX PPTX XLSX JPG PNG EPUB")
                             FamilyCard(symbol: "doc.text", title: "Documents", formats: "PAGES PDF TXT MD HTML EPUB")
                             FamilyCard(symbol: "rectangle.on.rectangle", title: "Slides", formats: "PDF JPG PNG")
                             FamilyCard(symbol: "tablecells", title: "Spreadsheets", formats: "ODS CSV TSV XLSX PDF")
                             FamilyCard(symbol: "text.bubble", title: "Subtitles", formats: "SRT VTT TXT")
                             FamilyCard(symbol: "archivebox", title: "Archives", formats: "ZIP TAR GZIP")
                         }.padding(22)
                     }) }),
            HelpPage(title: "Real tools, live previews",
                     subtitle: "Every tool has its own window with a live preview, so you never work blind.",
                     bullets: [Bullet(symbol: "photo", title: "Images", text: "Edit, annotate, background, crop, resize, rotate, upscale, collage."),
                               Bullet(symbol: "film", title: "Video", text: "Trim, crop, speed, join, split, snapshots, redact, HandBrake-style export."),
                               Bullet(symbol: "folder.badge.gearshape", title: "Folders & code", text: "DaVinci project tree, open in VS Code. The ⌃ wheel can switch between the wheel and the Wii menu.")],
                     illustration: { AnyView(Desktop {
                         HStack(alignment: .top, spacing: 14) {
                             ToolPicture(width: 432, height: 700, scale: 0.43) { FrameImageTool(urls: [sample], close: {}) }
                             ToolPicture(width: 432, height: 640, scale: 0.43) { ResizeImageTool(urls: [sample], close: {}) }
                         }.padding(.top, 22)
                     }) }),
            HelpPage(title: "Petals within petals",
                     subtitle: "Related tools are grouped. Rest on a group petal and its choices open further out, on their own background.",
                     bullets: [Bullet(symbol: "crop.rotate", title: "Transform", text: "Crop · Resize · Rotate & flip."),
                               Bullet(symbol: "photo.on.rectangle", title: "BG", text: "Add a background, or remove the current one."),
                               Bullet(symbol: "arrow.up.right", title: "Slide outward", text: "Move over the petal, then onto its choice, and drop.")],
                     illustration: { AnyView(Desktop {
                         HStack(spacing: -62) {
                             WheelPicture(mode: .tools, urls: [HelpAssets.fakeImage], hover: 3, child: 1, scale: 0.58)
                             WheelPicture(mode: .tools, urls: [HelpAssets.fakeImage], hover: 5, child: 0, scale: 0.58)
                         }
                     }) }),
            HelpPage(title: "Remove backgrounds",
                     subtitle: "Apple's on-device vision finds the subject. Then style the result before saving.",
                     bullets: [Bullet(symbol: "circle.dashed", title: "Transparent, color or blur", text: "Replace the background with what you want."),
                               Bullet(symbol: "scissors", title: "Edges and outline", text: "Soften, grow or shrink the edge, add a sticker outline."),
                               Bullet(symbol: "person.2", title: "Pick the subject", text: "With several subjects, choose which to keep.")],
                     illustration: { AnyView(Desktop { BeforeAfter() }) }),
            HelpPage(title: "File actions",
                     subtitle: "Quick things you do with a file, without opening anything. They work on folders and mixed selections too.",
                     bullets: [Bullet(symbol: "airplayaudio", title: "AirDrop & Float", text: "Send it, or park it on a floating shelf to drag into another app."),
                               Bullet(symbol: "doc.on.doc", title: "Copy · Copy path · Move", text: "Copy the file, its path, or move it to a chosen folder."),
                               Bullet(symbol: "terminal", title: "Terminal · Preview · Code", text: "Open the folder in Terminal, preview it, or open a folder in VS Code.")],
                     illustration: { AnyView(Desktop {
                         HStack(spacing: -52) {
                             WheelPicture(mode: .actions, urls: [HelpAssets.fakeImage], hover: 2, scale: 0.56)
                             WheelPicture(mode: .actions, urls: [HelpAssets.fakeFolder], hover: 7, scale: 0.56)
                         }
                     }) }),
            HelpPage(title: "Video & audio, frame by frame",
                     subtitle: "Drag the orange bars to trim. The cut happens on the inside edge of each bar, and the preview matches the saved result.",
                     bullets: [Bullet(symbol: "scissors", title: "Trim, split, join", text: "Frame-accurate for video, waveform for audio."),
                               Bullet(symbol: "speaker.wave.3", title: "Normalize, channels, bleep", text: "Loudness targets, left/right volume up to 300%, bleep sections."),
                               Bullet(symbol: "film.stack", title: "Export Video", text: "ProRes 4K → H.264 at 4K or 1080p: quality (RF) or bitrate, frame rate, original colors kept.")],
                     illustration: { AnyView(Desktop { TimelineMock() }) }),
            HelpPage(title: "You're ready",
                     subtitle: "Drag a file and tap a key. You can reopen this guide anytime from the menu bar icon → Help.",
                     bullets: [Bullet(symbol: "gearshape", title: "Settings", text: "Change the three keys, the terminal app, and launch at login."),
                               Bullet(symbol: "lock.shield", title: "Private by design", text: "Files are processed on your Mac and never uploaded."),
                               Bullet(symbol: "questionmark.circle", title: "Help", text: "Menu bar icon → Help reopens this guide.")],
                     illustration: { AnyView(statusCard) })
        ]
    }

    private func column(_ mode: WheelMode, _ symbol: String, _ name: String, hover: Int) -> some View {
        VStack(spacing: 0) {
            Keycap(symbol: symbol, name: name, pressed: true).scaleEffect(0.8)
            WheelPicture(mode: mode, urls: [HelpAssets.fakeImage], hover: hover, scale: 0.5).frame(height: 150)
            Text(mode.title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
        }.frame(width: 172)
    }

    private var statusCard: some View {
        Desktop {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading) {
                        Text("Mandarine").font(.system(size: 20, weight: .bold))
                        Text("Version 0.1").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    }
                }.foregroundStyle(.white)
                VStack(spacing: 8) {
                    StatusRow(name: "Video & audio engine", detail: FFmpeg.isAvailable ? "ffmpeg found" : "download it in Settings → Engines", ok: FFmpeg.isAvailable)
                    StatusRow(name: "Apple AI upscale", detail: Upscaler.aiAvailable ? "available (×4)" : "needs macOS 26", ok: Upscaler.aiAvailable)
                    StatusRow(name: "Pages · Keynote · Numbers", detail: (AppleApps.App.pages.isInstalled && AppleApps.App.keynote.isInstalled) ? "installed" : "optional, for .pages and slides", ok: AppleApps.App.pages.isInstalled && AppleApps.App.keynote.isInstalled)
                    StatusRow(name: "Visual Studio Code", detail: VSCode.url != nil ? "found" : "optional, for the Code tool", ok: VSCode.url != nil)
                }
                .padding(14).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.94))).foregroundStyle(Theme.text)
                Text("Apple apps may ask permission to be controlled the first time (System Settings → Privacy → Automation).")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            }.padding(26)
        }
    }

    var body: some View {
        let p = pages[page]
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(page + 1) / \(count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.orange)
                    Text(p.title).font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                    Text(p.subtitle).font(.system(size: 14)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(p.bullets) { b in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: b.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.orange)
                                    .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.orange.opacity(0.12)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                                    Text(b.text).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }.padding(.top, 6)
                    Spacer(minLength: 0)
                }
                .frame(width: 330, alignment: .leading)
                .padding(.leading, 38).padding(.trailing, 20).padding(.top, 52)
                p.illustration()
                    .id(page)
                    .frame(width: 520, height: 430)
                    .padding(.trailing, 36).padding(.top, 36).padding(.bottom, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            .frame(maxHeight: .infinity)
            footer
        }
        .frame(width: 940, height: 600)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .onAppear { page = min(max(startPage, 0), count - 1) }
        .background(KeyCatcher(left: { go(-1) }, right: { go(1) }, escape: close))
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Toggle("Show at startup", isOn: $settings.showWelcome).toggleStyle(.checkbox).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule().fill(i == page ? Theme.orange : Color.black.opacity(0.14)).frame(width: i == page ? 20 : 7, height: 7)
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { page = i } }
                }
            }
            Spacer()
            Button("Back") { go(-1) }.buttonStyle(PillButtonStyle()).opacity(page == 0 ? 0 : 1).disabled(page == 0)
            if page == count - 1 { Button("Start using Mandarine") { close() }.buttonStyle(PillButtonStyle(prominent: true)) }
            else { Button("Next") { go(1) }.buttonStyle(PillButtonStyle(prominent: true)) }
        }
        .padding(.horizontal, 38).padding(.vertical, 16)
        .overlay(Divider().opacity(0.6), alignment: .top)
    }

    private func go(_ d: Int) {
        let n = min(max(page + d, 0), count - 1)
        if n != page { withAnimation(.easeInOut(duration: 0.22)) { page = n } }
    }
}

/// Flèches ← → et Échap pour naviguer au clavier.
private struct KeyCatcher: NSViewRepresentable {
    let left: () -> Void, right: () -> Void, escape: () -> Void
    func makeNSView(context: Context) -> NSView {
        let v = CatcherView(); v.left = left; v.right = right; v.escape = escape
        DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        guard let v = v as? CatcherView else { return }
        v.left = left; v.right = right; v.escape = escape
    }
    final class CatcherView: NSView {
        var left: () -> Void = {}, right: () -> Void = {}, escape: () -> Void = {}
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with e: NSEvent) {
            switch e.keyCode { case 123: left(); case 124, 49, 36: right(); case 53: escape(); default: super.keyDown(with: e) }
        }
    }
}

// MARK: Fenêtre
final class HelpWindowController: NSObject, NSWindowDelegate {
    static let shared = HelpWindowController()
    private var window: NSWindow?

    static func show(page: Int = 0) { shared.present(page) }

    private func present(_ page: Int) {
        if let w = window { NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil); return }
        let host = NSHostingView(rootView: HelpView(startPage: page, close: { [weak self] in self?.window?.close() }))
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 600), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.backgroundColor = .white
        w.appearance = NSAppearance(named: .aqua)
        w.contentView = host
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
    }
}
