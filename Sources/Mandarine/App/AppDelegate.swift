import AppKit
import VideoToolbox
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItems: [NSStatusItem] = []
    private let monitor = DragMonitor()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Une icône par fichier MenuBarIcon*.png|svg|pdf : permet de comparer plusieurs candidats côte à côte dans la barre de menus.
        let icons = Theme.statusImages()
        let list: [(String, NSImage)] = icons.isEmpty ? [("Mandarine", Theme.drawnStatusImage())] : icons
        for (name, image) in list.reversed() {                // ordre inversé : la barre empile les icônes de droite à gauche
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = image
            item.button?.toolTip = list.count > 1 ? "Mandarine — \(name)" : "Mandarine"
            item.menu = buildMenu()
            statusItems.append(item)
        }
        monitor.start()
        runLaunchArguments()
        if CommandLine.arguments.count < 2 { Updater.shared.start() }
        if AppSettings.shared.showWelcome && CommandLine.arguments.count < 2 {            // guide d'accueil (réglable dans le guide et les Réglages)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { HelpWindowController.show() }
        }
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        let title = NSMenuItem(title: "Mandarine", action: nil, keyEquivalent: "")
        title.isEnabled = false
        m.addItem(title)
        m.addItem(.separator())
        let hint = NSMenuItem(title: "Drag a file, then tap ⇧ ⌘ or ⌃", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        m.addItem(hint)
        m.addItem(.separator())
        m.addItem(withTitle: "Help", action: #selector(showHelp), keyEquivalent: "?").target = self
        m.addItem(withTitle: "Check for Updates…", action: #selector(checkUpdates), keyEquivalent: "").target = self
        m.addItem(withTitle: "Choose File to Process…", action: #selector(chooseFile), keyEquivalent: "o").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        m.addItem(withTitle: "Quit Mandarine", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return m
    }

    @objc private func showHelp() { HelpWindowController.show() }
    @objc private func checkUpdates() { Task { await Updater.shared.check(userInitiated: true) } }

    @objc private func chooseFile() {
        pickFiles { urls in
            let screen = NSScreen.main?.frame ?? .zero
            WheelController.shared.show(mode: .tools, urls: urls, at: NSPoint(x: screen.midX, y: screen.midY))
        }
    }

    private func pickFiles(_ done: @escaping ([URL]) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        p.begin { r in if r == .OK, !p.urls.isEmpty { DispatchQueue.main.async { done(p.urls) } } }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 380), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Mandarine Settings"
            w.contentView = NSHostingView(rootView: SettingsView())
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate {
    /// Usage : Mandarine --wheel convert|tools|actions fichier…   ou   Mandarine --tool <id> fichier…
    /// (pratique pour tester sans glisser-déposer)
    func runLaunchArguments() {
        let a = Array(CommandLine.arguments.dropFirst())
        if a.count >= 4, a[0] == "--snapshot" { snapshot(a); return }
        if a.count >= 3, a[0] == "--upscale" {      // test : --upscale fichier facteur
            Task {
                do {
                    let (cg, _) = try ImageEngine.load(URL(fileURLWithPath: a[1]))
                    print("AI factors:", Upscaler.aiFactors, "input:", cg.width, "x", cg.height)
                    let f = Int(a[2]) ?? 2
                    if #available(macOS 26.0, *), let c = VTSuperResolutionScalerConfiguration(frameWidth: cg.width, frameHeight: cg.height, scaleFactor: f, inputType: .image, usePrecomputedFlow: false, qualityPrioritization: .normal, revision: VTSuperResolutionScalerConfiguration.defaultRevision) {
                        print("src attrs:", c.sourcePixelBufferAttributes); print("dst attrs:", c.destinationPixelBufferAttributes)
                        print("model status:", c.configurationModelStatus.rawValue)
                    }
                    if #available(macOS 26.0, *), Upscaler.canUseAI(CGSize(width: cg.width, height: cg.height), factor: f) {
                        let t = Date()
                        let out = try await Upscaler.ai(cg, factor: f)
                        let dest = OutputNaming.sibling(of: URL(fileURLWithPath: a[1]), suffix: " ai x\(f)", ext: "png")
                        try ImageEngine.write(out, to: dest, ext: "png")
                        print("AI OK", out.width, "x", out.height, String(format: "%.1fs", Date().timeIntervalSince(t)), dest.lastPathComponent)
                    } else { print("AI non utilisable pour ce facteur / cette taille") }
                } catch { print("AI ERR:", error.localizedDescription) }
                exit(0)
            }
            return
        }
        if a.count >= 2, a[0] == "--extract-images" {
            let f = URL(fileURLWithPath: a[1]); let d = OutputNaming.folder(of: f, suffix: "images")
            do { print("OK", try PDFImageExtractor.extract(f, into: d), "images →", d.path) } catch { print("ERR", error.localizedDescription) }
            exit(0)
        }
        if a.count >= 2, a[0] == "--bgtest" {       // options de détourage : contour sticker + fond couleur + recadrage
            if #available(macOS 14.0, *) {
                do {
                    let f = URL(fileURLWithPath: a[1]); let (cg, _) = try ImageEngine.load(f)
                    let s = try BGSession(cg); var o = BGOptions()
                    o.fill = .color; o.color = NSColor(calibratedRed: 0.2, green: 0.5, blue: 0.9, alpha: 1); o.outline = true; o.outlineWidth = 10; o.soften = 2; o.cropToSubject = true
                    let img = try s.render(o)
                    let dest = OutputNaming.sibling(of: f, suffix: " bgtest", ext: "png"); try ImageEngine.write(img, to: dest, ext: "png")
                    print("OK", img.width, "x", img.height, "subjects:", s.instanceIDs, dest.lastPathComponent)
                } catch { print("ERR", error.localizedDescription) }
            }
            exit(0)
        }
        if a.count >= 3, a[0] == "--menuicon" {      // test : --menuicon entrée.svg sortie.png
            if let img = Theme.templateImage(from: URL(fileURLWithPath: a[1])), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: a[2])); print("OK")
            } else { print("ERR") }
            exit(0)
        }
        if a.count >= 3, a[0] == "--canceltest" {    // test : --canceltest source sortie (lance un encodage, l'annule après 1 s)
            let t = Task {
                do { try await FFmpeg.run(["-i", a[1], "-c:v", "libx264", "-preset", "veryslow", a[2]]); print("terminé (pas annulé)") }
                catch is CancellationError { print("annulé proprement; sortie existe:", FileManager.default.fileExists(atPath: a[2])) }
                catch { print("erreur", error.localizedDescription) }
                exit(0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { t.cancel() }
            return
        }
        if a.count >= 2, a[0] == "--playlist" {      // test : --playlist lien (liste lue sans rien télécharger)
            Task {
                if let l = await YtDlp.playlist(URL(string: a[1])!) { print("playlist « \(l.title) » : \(l.entries.count) éléments"); for e in l.entries.prefix(5) { print(" ", e.id + 1, e.title, e.duration ?? 0, e.url.absoluteString) } }
                else { print("pas une liste (ou lecture impossible)") }
                exit(0)
            }
            return
        }
        if a.count >= 2, a[0] == "--ytupdate" {      // test : --ytupdate dossier (télécharge, vérifie l'empreinte, installe dans ce dossier)
            Task { @MainActor in
                YtDlpUpdater.destination = URL(fileURLWithPath: a[1])
                do { print("dernière version :", try await YtDlpUpdater.latestVersion()); print("installé :", try await YtDlpUpdater.downloadAndInstall()) }
                catch { print("ERR", error.localizedDescription) }
                exit(0)
            }
            return
        }
        if a.count >= 2, a[0] == "--dragtest" {      // test : --dragtest fichier.pdf (simule un glissement dans la barre de titre)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                ToolWindowController.present(.mergePDF, urls: [URL(fileURLWithPath: a[1]), URL(fileURLWithPath: a[1])])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    guard let w = NSApp.windows.first(where: { $0 is ToolWindow }) else { print("pas de fenêtre"); exit(1) }
                    let before = w.frame.origin
                    let h = w.contentView!.bounds.height
                    func ev(_ t: NSEvent.EventType, _ dx: CGFloat, _ dy: CGFloat) -> NSEvent {
                        NSEvent.mouseEvent(with: t, location: NSPoint(x: 200 + dx, y: h - 24 + dy), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                    }
                    w.postEvent(ev(.leftMouseDragged, 60, -40), atStart: false)
                    w.postEvent(ev(.leftMouseUp, 60, -40), atStart: false)
                    w.sendEvent(ev(.leftMouseDown, 0, 0))
                    print("avant", before, "après", w.frame.origin, "déplacée:", w.frame.origin != before)
                    exit(0)
                }
            }
            return
        }
        if a.first == "--ordertest" {                   // test de la logique de déplacement des lignes (Merge PDFs…)
            let l = ["a", "b", "c", "d", "e", "f"]
            func t(_ rows: [Int], _ row: Int) { let (r, g) = OrderList.move(l, rows: rows, to: row); print(rows, "→ devant", row, ":", r.joined(), g) }
            t([1], 4); t([4], 1); t([1, 3], 5); t([0, 1], 6); t([2, 4], 0); t([2, 3], 3); t([5], 0)
            exit(0)
        }
        if a.count >= 2, a[0] == "--tags" {          // test : --tags fichier… (étiquettes Finder lues)
            for g in TagSelect.groups(a.dropFirst().map { URL(fileURLWithPath: $0) }) { print(g.tag.name, "couleur", g.tag.color, "→", g.files.map(\.lastPathComponent).joined(separator: ", ")) }
            exit(0)
        }
        if a.count >= 2, a[0] == "--facetest" {      // test : --facetest dossier_avec_un_sous-dossier_par_personne [seuil]
            Task {
                do {
                    if !FaceModel.isInstalled { print("téléchargement du modèle…"); try await FaceModel.download { _ in } }
                    let fm = FileManager.default
                    let people = ((try? fm.contentsOfDirectory(atPath: a[1])) ?? []).sorted().filter { !$0.hasPrefix(".") }
                    var urls: [URL] = [], owner: [URL: String] = [:]
                    for p in people { for f in ((try? fm.contentsOfDirectory(atPath: a[1] + "/" + p)) ?? []).sorted() where f.hasSuffix(".jpg") { let u = URL(fileURLWithPath: a[1] + "/" + p + "/" + f); urls.append(u); owner[u] = p } }
                    let t0 = Date()
                    let hits = try await FaceScanner.scan(urls) { _, _, _ in }
                    print("fichiers \(urls.count) → visages \(hits.count) en \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
                    // Mesures : paires de visages de la même personne / de personnes différentes
                    var same: [Float] = [], diff: [Float] = []
                    for i in hits.indices { for j in hits.indices where j > i { let s = FaceScanner.cosine(hits[i].vector, hits[j].vector); if owner[hits[i].file] == owner[hits[j].file] { same.append(s) } else { diff.append(s) } } }
                    func pct(_ v: [Float], _ p: Double) -> Float { let s = v.sorted(); return s.isEmpty ? 0 : s[min(s.count - 1, Int(Double(s.count) * p))] }
                    print("même personne : médiane \(pct(same, 0.5)) · 5 % le plus bas \(pct(same, 0.05)) | personnes différentes : médiane \(pct(diff, 0.5)) · 99,9 % \(pct(diff, 0.999)) · max \(diff.max() ?? 0)")
                    for th in [Float(0.30), 0.35, 0.40, 0.45, 0.50] {
                        let cl = FaceScanner.cluster(hits, threshold: Double(a.count > 2 ? a[2] : "0").map { Float($0) } ?? th)
                        _ = cl
                        let clusters = FaceScanner.cluster(hits, threshold: th)
                        var impure = 0, total = 0
                        for c in clusters { let names = c.members.map { owner[hits[$0].file] ?? "?" }; let top = Dictionary(grouping: names, by: { $0 }).values.map(\.count).max() ?? 0; impure += names.count - top; total += names.count }
                        let perPerson = Dictionary(grouping: clusters.flatMap { c in Set(c.members.map { owner[hits[$0].file] ?? "?" }) }, by: { $0 }).mapValues(\.count)
                        let split = perPerson.values.filter { $0 > 1 }.count
                        print("seuil \(th): \(clusters.count) groupes pour \(people.count) personnes · visages mal rangés \(impure)/\(total) · personnes coupées en plusieurs groupes \(split)/\(people.count)")
                    }
                } catch { print("ERR", error.localizedDescription) }
                exit(0)
            }
            return
        }
        if a.count >= 3, a[0] == "--installtest" {   // test : --installtest ffmpeg|cwebp dossier (télécharge, vérifie, essaie, installe dans ce dossier)
            Task { @MainActor in
                EngineInstaller.destination = URL(fileURLWithPath: a[2])
                do {
                    var last = -1
                    let prog: (Double) -> Void = { p in let v = Int(p * 100) / 25; if v != last { last = v; print("  \(Int(p * 100)) %") } }
                    if a[1] == "ffmpeg" { try await EngineInstaller.installFFmpeg(progress: prog) } else { try await EngineInstaller.installCwebp(progress: prog) }
                    print("OK →", ((try? FileManager.default.contentsOfDirectory(atPath: a[2])) ?? []).joined(separator: ", "))
                } catch { print("ERR", error.localizedDescription) }
                exit(0)
            }
            return
        }
        if a.count >= 2, a[0] == "--embedtest" {     // test : --embedtest image112.png (empreinte du modèle, à comparer à onnxruntime)
            do {
                let (img, _) = try ImageEngine.load(URL(fileURLWithPath: a[1]))
                var chw = [Float](repeating: 0, count: 3 * 112 * 112)
                let ctx = CGContext(data: nil, width: 112, height: 112, bitsPerComponent: 8, bytesPerRow: 448, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: 112, height: 112))
                let px = ctx.data!.bindMemory(to: UInt8.self, capacity: 112 * 112 * 4)
                for i in 0..<(112 * 112) { for c in 0..<3 { chw[c * 112 * 112 + i] = Float(px[i * 4 + c]) } }
                let t0 = Date(); let v = try FaceEmbedder.get().embed(chw); let t1 = Date(); _ = try FaceEmbedder.get().embed(chw)
                print(v.prefix(8).map { String(format: "%.5f", $0) }.joined(separator: " "), "… première passe \(String(format: "%.0f", t1.timeIntervalSince(t0) * 1000)) ms, suivante \(String(format: "%.1f", Date().timeIntervalSince(t1) * 1000)) ms")
            } catch { print("ERR", error.localizedDescription) }
            exit(0)
        }
        if a.first == "--updatetest" {               // test : variables MANDARINE_UPDATE_API / _PUBKEY / _TARGET / _NORELAUNCH (flux local)
            Task { @MainActor in
                let u = Updater.shared
                print("version actuelle", u.currentVersion, "· configuré:", u.isConfigured)
                await u.check(userInitiated: false)
                print("état après vérification :", u.state)
                if case .available = u.state { await u.install(); print("état après installation :", u.state) }
                exit(0)
            }
            return
        }
        if a.count >= 2, a[0] == "--ocr" {           // test : --ocr fichier (texte reconnu)
            do { print(OCREngine.join(try OCREngine.pages(of: URL(fileURLWithPath: a[1])), keepLineBreaks: true)) } catch { print("ERR", error.localizedDescription) }
            exit(0)
        }
        if a.count >= 2, a[0] == "--info" {          // test : --info fichier… (lignes affichées au centre de la roue)
            let urls = a.dropFirst().map { URL(fileURLWithPath: $0) }
            Task { print("rapide  :", WheelInfo.quick(Array(urls))); print("complet :", await WheelInfo.detailed(Array(urls))); exit(0) }
            return
        }
        if a.count >= 4, a[0] == "--ytdl" {          // test : --ytdl lien mp3|mp4 dossier
            Task {
                do {
                    var last = -1
                    let f = try await YtDlp.download(URL(string: a[1])!, audio: a[2] != "mp4", audioFormat: a[2] == "wav" ? "wav" : "mp3", to: URL(fileURLWithPath: a[3])) { p in let v = Int(p * 100); if v / 25 != last / 25 { last = v; print("  \(v)%") } }
                    print("OK", f.lastPathComponent, f.fileSize.humanSize)
                } catch { print("ERR", error.localizedDescription) }
                exit(0)
            }
            return
        }
        if a.count >= 1, a[0] == "--engines" {       // où l'app trouve ses moteurs
            for n in ["ffmpeg", "ffprobe", "cwebp"] { print(n, "→", FFmpeg.locate(n)?.path ?? "introuvable") }
            print("yt-dlp →", YtDlp.url?.path ?? "introuvable")
            print("dossier manuel :", FFmpeg.enginesFolder.path); exit(0)
        }
        if a.count >= 3, a[0] == "--snap" {          // test : --snap fichier t1 [t2…] (même code que « Video Snapshots »)
            let file = URL(fileURLWithPath: a[1]); let times = a.dropFirst(2).compactMap(Double.init)
            Task {
                do {
                    let dir = times.count > 1 ? OutputNaming.folder(of: file, suffix: "frames") : file.deletingLastPathComponent()
                    for t in times {
                        let name = file.deletingPathExtension().lastPathComponent + " " + timecode(t).replacingOccurrences(of: ":", with: "-")
                        let out = OutputNaming.unique(folder: dir, base: name, ext: "png")
                        if let cg = await VideoFrames.native(file, at: t) { try ImageEngine.write(cg, to: out, ext: "png"); print("natif", terminator: " ") }
                        else { try await FFmpeg.run(["-ss", String(t), "-i", file.path, "-frames:v", "1", out.path]); print("ffmpeg", terminator: " ") }
                        print("OK", out.lastPathComponent, out.fileSize)
                    }
                } catch { print("ERR", error.localizedDescription) }
                exit(0)
            }
            return
        }
        if a.count >= 3, a[0] == "--encode" {        // test : --encode fichier quality|bitrate|hardware
            Task {
                var o = EncodeOptions()
                VideoEncoder.presets[0].apply(&o)
                switch a[2] { case "4k": VideoEncoder.presets.first { $0.id == "prores-4k" }?.apply(&o); o.preset = "veryfast"
                              case "bitrate": o.mode = .bitrate; o.bitrateKbps = 6000; o.twoPass = true; o.preset = "veryfast"
                              case "hardware": o.encoder = .hardware264; o.mode = .bitrate; o.bitrateKbps = 8000
                              default: o.preset = "veryfast" }
                let f = URL(fileURLWithPath: a[1]); let out = OutputNaming.sibling(of: f, suffix: " test-\(a[2])", ext: "mp4")
                do {
                    let t = Date(); try await VideoEncoder.encode(o, input: f, output: out) { _ in }
                    let i = await FFmpeg.probe(out)
                    print("OK", out.lastPathComponent, "\(i.width)x\(i.height)", String(format: "%.2f fps", i.fps), i.codec, i.profile, i.pixFmt, "color:", i.colorSpace, i.colorPrimaries, i.colorTransfer, i.colorRange, "size:", out.fileSize.humanSize, String(format: "%.1fs", Date().timeIntervalSince(t)))
                } catch { print("ERR", error.localizedDescription) }
                exit(0)
            }
            return
        }
        if a.count >= 2, a[0] == "--removebg" {
            do { print("OK", try BackgroundRemover.run(URL(fileURLWithPath: a[1])).path) } catch { print("ERR", error.localizedDescription) }
            exit(0)
        }
        if a.count >= 3, a[0] == "--convert" {      // test sans interface : --convert ext fichier
            let url = URL(fileURLWithPath: a[2])
            Task {
                do { let o = try await Converter.run(urls: [url], to: a[1]) { _ in }; print("OK", o.map(\.path)) }
                catch { print("ERR", error.localizedDescription) }
                exit(0)
            }
            return
        }
        guard a.count >= 3 else { return }
        let urls = a.dropFirst(2).map { URL(fileURLWithPath: $0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if a[0] == "--wheel", let m = WheelMode(rawValue: a[1]) {
                let s = NSScreen.main?.frame ?? .zero
                WheelController.shared.show(mode: m, urls: urls, at: NSPoint(x: s.midX, y: s.midY))
            } else if a[0] == "--tool", let id = ToolID(rawValue: a[1]) {
                ToolWindowController.present(id, urls: urls)
            }
        }
    }
}

extension AppDelegate {
    /// Usage : Mandarine --snapshot wheel:<mode>|tool:<id> sortie.png fichier…  (rend la vue hors écran, puis quitte)
    func snapshot(_ a: [String]) {
        let urls = a.dropFirst(3).map { URL(fileURLWithPath: $0) }
        let target = a[1].split(separator: ":").map(String.init)
        let view: AnyView
        if target[0] == "wheel", let m = WheelMode(rawValue: target[1]) {
            let model = WheelController.shared.model
            model.items = Catalog.items(mode: m, urls: urls)
            model.mode = m
            model.appear = true
            model.infoLines = WheelInfo.quick(urls)
            model.hover = a.count > 3 ? 1 : nil
            if let h = ProcessInfo.processInfo.environment["MANDARINE_HOVER"] {      // ex. "7,1" = pétale 7, sous-pétale 1
                let p = h.split(separator: ",").compactMap { Int($0) }
                model.hover = p.first; model.hoverChild = p.count > 1 ? p[1] : nil
                if let h = p.first, model.items.indices.contains(h), model.items[h].isGroup { model.blobParent = h; model.blobCount = model.items[h].children.count; model.blobT = Double(ProcessInfo.processInfo.environment["MANDARINE_BLOB"] ?? "1") ?? 1 }
            }
            view = AnyView(WheelView(model: model).padding(20).background(Color(white: 0.55)))
        } else if target[0] == "wii", let m = WheelMode(rawValue: target[1]) {
            let model = WheelModel()
            model.mode = m; model.items = Catalog.items(mode: m, urls: urls); model.appear = true
            model.infoLines = WheelInfo.quick(urls); model.fileCount = urls.count
            if let h = ProcessInfo.processInfo.environment["MANDARINE_HOVER"] {
                let p = h.split(separator: ",").compactMap { Int($0) }
                model.hover = p.first; model.hoverChild = p.count > 1 ? p[1] : nil
            }
            if let c = ProcessInfo.processInfo.environment["MANDARINE_CURSOR"] {
                let p = c.split(separator: ",").compactMap { Double($0) }
                if p.count == 2 { model.cursor = CGPoint(x: p[0], y: p[1]) }
            }
            view = AnyView(WiiMenuView(model: model).padding(30).background(Color(white: 0.55)))
        } else if target[0] == "toasts" {          // test de la file : 2 travaux lourds en cours, 2 en attente, 1 léger ; le 1er est annulé
            func fake(_ n: Double) -> JobQueue.Work { { progress in for i in 0..<300 { try Task.checkCancellation(); progress(min(0.99, Double(i) / 300 * n)); try await Task.sleep(nanoseconds: 100_000_000) }; return [] } }
            let ids = (1...4).map { JobQueue.shared.add("Encoding clip \($0)…", subtitle: "clip\($0).mov", work: fake(Double($0))) }
            JobQueue.shared.add("Saving text…", subtitle: "notes.png", light: true, work: fake(1))
            JobQueue.shared.cancel(ids[0])
            Toast.shared.done("Saved photo.png", subtitle: "/Users/me/Pictures", reveal: URL(fileURLWithPath: "/tmp"))
            Toast.shared.fail("Conversion failed", subtitle: "ffmpeg a échoué (code 1).")
            view = AnyView(ToastStack(center: Toast.shared.center).background(Color(white: 0.55)))
        } else if target[0] == "settings" {
            view = AnyView(SettingsView().padding(10).background(Color(white: 0.55)))
        } else if target[0] == "tagselect" {
            view = AnyView(TagSelectTool(total: urls.count, groups: TagSelect.groups(urls), close: {}).padding(30).background(Color(white: 0.55)))
        } else if target[0] == "faceselect" {
            view = AnyView(FaceSelectTool(urls: urls, close: {}).padding(30).background(Color(white: 0.55)))
        } else if target[0] == "playlist" {
            let es = (0..<14).map { YtDlp.Playlist.Entry(id: $0, url: URL(string: "https://example.com/\($0)")!, title: "Track number \($0 + 1) — a fairly long title to check truncation", duration: Double(150 + $0 * 17)) }
            view = AnyView(PlaylistTool(link: URL(string: "https://www.youtube.com/watch?v=abc&list=xyz")!, list: .init(title: "Summer mix 2026", entries: es), kind: .mp4, close: {}).padding(30).background(Color(white: 0.55)))
        } else if target[0] == "wiitiles" {
            view = AnyView(WiiTilesDebug().background(Color(white: 0.55)))
        } else if target[0] == "help" {
            view = AnyView(HelpView(startPage: Int(target[1]) ?? 0, close: {}))
        } else if target[0] == "tool", let id = ToolID(rawValue: target[1]) {
            view = AnyView(ToolRegistry.view(for: id, urls: urls, close: {}).padding(30).background(Color(white: 0.55)))
        } else { exit(2) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let host = NSHostingView(rootView: view.environment(\.colorScheme, .light))
            let size = host.fittingSize
            host.frame = NSRect(origin: .zero, size: size)
            let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView = host
            win.appearance = NSAppearance(named: .aqua)
            win.orderBack(nil)
            host.layoutSubtreeIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(ProcessInfo.processInfo.environment["MANDARINE_SNAPDELAY"] ?? "") ?? 1.0)) {
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: a[2]))
                }
                exit(0)
            }
        }
    }
}
