import SwiftUI

struct SettingsView: View {
    @ObservedObject var s = AppSettings.shared
    @ObservedObject var yt = YtDlpUpdater.shared
    @ObservedObject var installer = EngineInstaller.shared
    @ObservedObject var updater = Updater.shared

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Menu style", selection: $s.appearance) { ForEach(MenuAppearance.allCases) { Text($0.title).tag($0) } }
                Text(s.appearance == .wii ? "A small Wii-style screen: every tool is a channel, with a clock, a pointer hand and a description line." : "The radial wheel.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
            Section("Updates") {
                HStack {
                    Text("Mandarine \(updater.currentVersion)")
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
            Section("Optional petals (⌘ wheel)") {
                Toggle("Tag Select — photos & videos", isOn: $s.enableTagSelect)
                Text("With several files selected, keep only the ones that carry a Finder tag, and choose which tags.").font(.caption).foregroundStyle(.secondary)
                Toggle("Face Select — photos & videos", isOn: $s.enableFaceSelect)
                Text("Pick people by their face. Needs a small model (\(FaceModel.sizeText)), downloaded once; shown in Engines below.").font(.caption).foregroundStyle(.secondary)
                Toggle("Code — folders", isOn: $s.enableCode)
                Toggle("DaVinci project — folders", isOn: $s.enableDavinci)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $s.launchAtLogin)
                Toggle("Show the welcome guide at startup", isOn: $s.showWelcome)
                Toggle("Reveal results in Finder", isOn: $s.revealAfterSave)
                Picker("Terminal", selection: $s.terminalApp) {
                    ForEach(TerminalApp.allCases) { Text($0.title).tag($0) }
                }
            }
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
        }
        .formStyle(.grouped)
        .frame(width: 440)
    }

    /// Version installée + bouton pour vérifier / installer la dernière version.
    private var ytDlpUpdate: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(yt.current.isEmpty ? "Not installed" : "Version \(yt.current)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                switch yt.state {
                case .checking, .installing:
                    ProgressView().controlSize(.small)
                case .available(let v):
                    Button(yt.current.isEmpty ? "Install yt-dlp \(v)" : "Update to \(v)") { Task { await yt.install() } }
                default:
                    Button(yt.current.isEmpty ? "Install yt-dlp" : "Check for updates") { Task { await (yt.current.isEmpty ? yt.install() : yt.check()) } }
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
        .task { await yt.refreshCurrent() }
    }

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
