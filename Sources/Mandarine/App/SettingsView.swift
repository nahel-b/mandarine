import SwiftUI

/// Réglages : onglets à gauche, contenu à droite.
struct SettingsView: View {
    @ObservedObject var s = AppSettings.shared
    @ObservedObject var yt = YtDlpUpdater.shared
    @ObservedObject var installer = EngineInstaller.shared
    @ObservedObject var updater = Updater.shared
    @State private var tab: Tab

    enum Tab: String, CaseIterable, Identifiable {
        case general, appearance, wheel, petals, engines, updates
        var id: String { rawValue }
        var title: String {
            switch self { case .general: return "General"; case .appearance: return "Appearance"; case .wheel: return "Wheel keys"; case .petals: return "Petals"; case .engines: return "Engines"; case .updates: return "Updates" }
        }
        var symbol: String {
            switch self { case .general: return "gearshape"; case .appearance: return "paintpalette"; case .wheel: return "circle.hexagongrid"; case .petals: return "leaf"; case .engines: return "wrench.and.screwdriver"; case .updates: return "arrow.triangle.2.circlepath" }
        }
    }

    init(tab: Tab = .general) { _tab = State(initialValue: tab) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 168)
            Divider()
            Form { content }.formStyle(.grouped)
        }
        .frame(width: 720, height: 540)
        .task { await yt.refreshCurrent() }          // la version de yt-dlp est lue dès l'ouverture, quel que soit l'onglet
    }

    private static let checkFormat: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; f.doesRelativeDateFormatting = true; return f
    }()

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Tab.allCases) { t in
                Button { tab = t } label: {
                    HStack(spacing: 9) {
                        Image(systemName: t.symbol).frame(width: 20)
                        Text(t.title)
                        Spacer()
                        if t == .updates, case .available = updater.state { Circle().fill(Theme.orange).frame(width: 8, height: 8) }
                    }
                    .font(.system(size: 13, weight: tab == t ? .semibold : .regular))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tab == t ? Theme.orange.opacity(0.22) : .clear))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Spacer()
            Text("Mandarine \(updater.currentVersion)").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10)
        }
        .padding(10)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .general:
            Section("General") {
                Toggle("Launch at login", isOn: $s.launchAtLogin)
                Toggle("Show the welcome guide at startup", isOn: $s.showWelcome)
                Toggle("Reveal results in Finder", isOn: $s.revealAfterSave)
                Picker("Terminal", selection: $s.terminalApp) {
                    ForEach(TerminalApp.allCases) { Text($0.title).tag($0) }
                }
            }
        case .appearance:
            Section("Appearance") {
                Picker("Menu style", selection: $s.appearance) { ForEach(MenuAppearance.allCases) { Text($0.title).tag($0) } }
                Text(s.appearance == .wii ? "A small Wii-style screen: every tool is a channel, with a clock, a pointer hand and a description line." : s.appearance.isBubbles ? "Tools are round bubbles floating around your logo." : "The radial wheel.")
                    .font(.caption).foregroundStyle(.secondary)
                if s.appearance == .wheel {
                    Picker("Opening animation", selection: $s.wheelEntrance) { ForEach(WheelEntrance.allCases) { Text($0.title).tag($0) } }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Accent color")
                        Spacer()
                        ColorPicker("", selection: Binding(get: { s.accentColor }, set: { s.accentHex = NSColor($0).hexString }), supportsOpacity: false).labelsHidden()
                        if !s.isDefaultAccent { Button("Reset") { s.accentHex = AppSettings.defaultAccent }.controlSize(.small) }
                    }
                    HStack(spacing: 8) {
                        ForEach(Self.accents, id: \.1) { name, hex in
                            Button { s.accentHex = hex } label: {
                                Circle().fill(Color(nsColor: NSColor(hex: hex)!)).frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(Color.primary.opacity(0.9), lineWidth: s.accentHex.uppercased() == hex ? 2.5 : 0).padding(-3))
                            }.buttonStyle(.plain).help(name)
                        }
                    }
                    Text("The highlight of the wheel, buttons and progress in every window. Windows already open keep their color.").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Window style", selection: $s.toolStyle) { ForEach(ToolStyle.available) { Text($0.title).tag($0) } }
                }
            }
        case .wheel:
            Section("Wheel keys") {
                Text("Start dragging a file, then tap a key. The wheel stays open until you drop.")
                    .font(.caption).foregroundStyle(.secondary)
                keyPicker("Convert formats", $s.convertKey)
                keyPicker("File tools", $s.toolsKey)
                keyPicker("File actions", $s.actionsKey)
                if Set([s.convertKey, s.toolsKey, s.actionsKey]).count < 3 {
                    Label("Each wheel needs its own key.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
                }
            }
        case .petals:
            Section("Photos & videos") {
                Toggle("Face Select", isOn: $s.enableFaceSelect)
                Text("Pick people by their face. Needs a small model (\(FaceModel.sizeText)), downloaded once; see Engines.").font(.caption).foregroundStyle(.secondary)
                Toggle("Quick Sort", isOn: $s.enableCull)
                Text("Go through the photos and videos full screen and mark each one Keep, Maybe or Reject with a key. The marks are Finder tags.").font(.caption).foregroundStyle(.secondary)
                if s.enableCull {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Quick Sort keys — click one, then press the new key").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 14) {
                            KeyRecorder(title: "No · reject", key: $s.cullRejectKey, taken: { cullKeyOwner($0, except: \.cullRejectKey) })
                            KeyRecorder(title: "Maybe", key: $s.cullMaybeKey, taken: { cullKeyOwner($0, except: \.cullMaybeKey) })
                            KeyRecorder(title: "Yes · keep", key: $s.cullKeepKey, taken: { cullKeyOwner($0, except: \.cullKeepKey) })
                            KeyRecorder(title: "Clear", key: $s.cullClearKey, taken: { cullKeyOwner($0, except: \.cullClearKey) })
                            Spacer()
                            Button("A · Z · E · R") { s.resetCullKeys() }.controlSize(.small)
                        }
                        Text("Arrow keys always work: ← → browse, ↑ keep, ↓ reject.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("Type Select", isOn: $s.enableTypeSelect)
                Text("With several items selected, keep only some extensions, kinds, Finder tags, sizes or dates (JPG, MP4, red tag, bigger than 100 MB…).").font(.caption).foregroundStyle(.secondary)
                Toggle("Document scan (photos)", isOn: $s.enableScan)
                Text("Straighten and clean a photo of a sheet of paper, and save it as a PDF.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Conversion (⇧ wheel)") {
                Toggle("Ringtone — audio & video", isOn: $s.enableRingtone)
                Text("Adds a RINGTONE petal that saves the start of the sound as an iPhone ringtone (.m4r) with a short fade out.").font(.caption).foregroundStyle(.secondary)
                if s.enableRingtone {
                    Stepper("Ringtone length: \(s.ringtoneSeconds) s", value: $s.ringtoneSeconds, in: 5...40, step: 5)
                }
            }
            Section("Dragged text") {
                Toggle("Wheel for selected text", isOn: $s.enableTextDrag)
                Text("Drag a text selection (from Safari, Notes, Mail…) and tap a key: translate, summarize, read aloud, save as a file, make a QR code.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Folders") {
                Toggle("Code", isOn: $s.enableCode)
                Toggle("DaVinci project", isOn: $s.enableDavinci)
            }
        case .engines:
            Section("Engines") {
                engine("ffmpeg (video, audio)", FFmpeg.ffmpeg?.path, install: .ffmpeg)
                engine("ffprobe", FFmpeg.ffprobe?.path, install: .ffmpeg)
                engine("cwebp (WebP)", FFmpeg.locate("cwebp")?.path, install: .cwebp)
                engine("Face model (Face Select, \(FaceModel.sizeText))", FaceModel.isInstalled ? FaceModel.file.path : nil, install: .faceModel)
                engine("yt-dlp (video and music links)", YtDlp.url?.path)
                ytDlpUpdate
                engine("LibreOffice (slides)", Converter.libreOffice?.path)
                HStack {
                    Text("Install manually (no Homebrew): drop ffmpeg and ffprobe in this folder.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Engines Folder") {
                        try? FileManager.default.createDirectory(at: FFmpeg.enginesFolder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(FFmpeg.enginesFolder)
                    }
                }
            }
        case .updates:
            Section("Updates") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mandarine \(updater.currentVersion)")
                        Text("Last checked: " + (updater.lastChecked.map { Self.checkFormat.string(from: $0) } ?? "never"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    switch updater.state {
                    case .checking, .downloading, .installing: ProgressView().controlSize(.small)
                    case .available: Button("Update now") { Task { await updater.install() } }
                    default: Button("Check for updates") { Task { await updater.check(userInitiated: true) } }
                    }
                }
                Toggle("Check for updates automatically", isOn: $s.autoCheckUpdates)
                Toggle("Install them automatically when Mandarine is idle", isOn: $s.autoInstallUpdates)
                Text(updater.isConfigured ? "Updates come from the project's GitHub releases and are checked against a signature before they are installed." : "This build has no update source yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Version installée + bouton pour vérifier / installer la dernière version.
    private var ytDlpUpdate: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(YtDlp.url == nil ? "Not installed" : (yt.current.isEmpty ? "Reading the version…" : "Version \(yt.current)")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                switch yt.state {
                case .checking, .installing:
                    ProgressView().controlSize(.small)
                case .available(let v):
                    Button(YtDlp.url == nil ? "Install yt-dlp \(v)" : "Update to \(v)") { Task { await yt.install() } }
                default:
                    Button(YtDlp.url == nil ? "Install yt-dlp" : "Check for updates") { Task { await (YtDlp.url == nil ? yt.install() : yt.check()) } }
                }
            }
            switch yt.state {
            case .checking: Text("Checking…").font(.caption).foregroundStyle(.secondary)
            case .installing: Text("Downloading and checking the official release…").font(.caption).foregroundStyle(.secondary)
            case .upToDate: Label("yt-dlp is up to date.", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
            case .available(let v): Text("A newer version is available: \(v).").font(.caption).foregroundStyle(.orange)
            case .installed(let v): Label("Installed \(v). It is used from now on.", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
            case .failed(let m): Text(m).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            case .idle: Text("Sites change often: if a download stops working, update yt-dlp here. The copy is kept in Mandarine's engines folder.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Qui utilise déjà cette touche dans le tri rapide ? (nil si personne)
    private func cullKeyOwner(_ k: String, except: KeyPath<AppSettings, String>) -> String? {
        let all: [(String, KeyPath<AppSettings, String>)] = [("reject", \.cullRejectKey), ("maybe", \.cullMaybeKey), ("keep", \.cullKeepKey), ("clear", \.cullClearKey)]
        return all.first { $0.1 != except && s[keyPath: $0.1] == k }?.0
    }

    static let accents: [(String, String)] = [("Orange", "F35B28"), ("Red", "E0343A"), ("Pink", "E8488B"), ("Purple", "8E5CD9"), ("Indigo", "4F5BD5"),
                                              ("Blue", "2D7FF0"), ("Teal", "14A39A"), ("Green", "3FA34D"), ("Gold", "E0A100"), ("Graphite", "5B6068")]

    private func keyPicker(_ title: String, _ b: Binding<TriggerKey>) -> some View {
        Picker(title, selection: b) { ForEach(TriggerKey.allCases) { Text($0.title).tag($0) } }
    }

    /// Ligne d'un moteur : trouvé / introuvable, avec un bouton pour le télécharger s'il manque.
    private func engine(_ name: String, _ path: String?, install e: EngineInstaller.Engine? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                Spacer()
                if let e = e, path == nil {
                    switch installer.state(e) {
                    case .working(let p):
                        ProgressView(value: p).frame(width: 90)
                    default:
                        Button("Download") { installer.install(e) }.controlSize(.small)
                    }
                }
                if e == .faceModel, path != nil {
                    Button("Remove") { FaceModel.remove(); installer.objectWillChange.send() }.controlSize(.small)
                }
                Text(path == nil ? "not found" : "found").foregroundStyle(path == nil ? .orange : .green).font(.caption)
            }
            if let e = e, case .failed(let m) = installer.state(e), path == nil {
                Text(m).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
