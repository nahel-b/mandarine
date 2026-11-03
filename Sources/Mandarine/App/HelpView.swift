import SwiftUI
import AppKit

// MARK: Ressources d'illustration
/// Fichiers factices qui servent à construire les roues des illustrations (et de la fenêtre des fonctionnalités).
enum HelpAssets {
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
    var action: (title: String, symbol: String, run: () -> Void)? = nil
    let illustration: () -> AnyView
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


// MARK: Vue principale
struct HelpView: View {
    var startPage = 0
    let close: () -> Void
    @State private var page = 0
    @ObservedObject private var settings = AppSettings.shared
    private let count = 4

    private var pages: [HelpPage] {
        [
            HelpPage(title: "Drag. Tap. Drop.",
                     subtitle: "Mandarine converts and edits files from a wheel that appears right under your cursor. No upload, no window to open: everything runs on your Mac.",
                     bullets: [Bullet(symbol: "hand.draw", title: "Drag any file", text: "From Finder, the Desktop or any app. Links, text and folders work too."),
                               Bullet(symbol: "keyboard", title: "Tap a key", text: "⇧ converts, ⌘ opens tools, ⌃ runs actions."),
                               Bullet(symbol: "tray.and.arrow.down", title: "Drop on a petal", text: "The result is saved next to the original. Nothing is ever overwritten.")],
                     illustration: { AnyView(DragDemo()) }),
            HelpPage(title: "Three wheels, three keys",
                     subtitle: "The key you tap decides what the wheel offers. Tap another key while you drag to switch: the wheel stays where it is.",
                     bullets: [Bullet(symbol: "arrow.triangle.2.circlepath", title: "⇧ Convert formats", text: "Only the formats that make sense for this file."),
                               Bullet(symbol: "slider.horizontal.3", title: "⌘ File tools", text: "Compress, crop, trim, redact, merge… Related tools are grouped: rest on a petal and its choices open further out."),
                               Bullet(symbol: "square.and.arrow.up", title: "⌃ File actions", text: "AirDrop, Float, Copy, Move, Terminal… Works on folders too.")],
                     illustration: { AnyView(Desktop {
                         HStack(spacing: 0) {
                             column(.convert, "⇧", "shift", hover: 0)
                             column(.tools, "⌘", "command", hover: 3)
                             column(.actions, "⌃", "control", hover: 2)
                         }
                     }) }),
            HelpPage(title: "Set up the engines",
                     subtitle: "Images, PDF, documents, archives and subtitles work right away. Video, audio and WebP need ffmpeg: Mandarine can download it itself, no Homebrew and no Terminal.",
                     bullets: [Bullet(symbol: "checkmark.seal", title: "Works without anything", text: "Images, PDF, documents, slides, spreadsheets, subtitles, archives."),
                               Bullet(symbol: "film", title: "Needs ffmpeg", text: "Video and audio conversion and tools, Export Video, and WebP."),
                               Bullet(symbol: "arrow.down.circle", title: "One click", text: "Also in Settings → Engines, with yt-dlp and the face model.")],
                     illustration: { AnyView(Desktop { EnginesCard() }) }),
            HelpPage(title: "You're ready",
                     subtitle: "Drag a file and tap a key. You can reopen this guide anytime from the menu bar icon → Help.",
                     bullets: [Bullet(symbol: "gearshape", title: "Settings", text: "Change the three keys, the look of the menu, and which petals appear."),
                               Bullet(symbol: "lock.shield", title: "Private by design", text: "Files are processed on your Mac and never uploaded.")],
                     action: ("Browse all features", "square.grid.2x2", { FeaturesWindowController.show() }),
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
                        Text("Version \(Updater.shared.currentVersion)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
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
                    if let act = p.action {
                        Button { act.run() } label: {
                            HStack(spacing: 8) {
                                Image(systemName: act.symbol).font(.system(size: 13, weight: .semibold))
                                Text(act.title).font(.system(size: 13, weight: .semibold))
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(Theme.orange).padding(.horizontal, 14).padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.orange.opacity(0.12)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.orange.opacity(0.35), lineWidth: 1))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain).padding(.top, 4)
                    }
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
