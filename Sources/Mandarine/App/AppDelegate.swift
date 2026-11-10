import AppKit
import VideoToolbox
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItems: [NSStatusItem] = []
    private let monitor = DragMonitor.shared
    private static func find<V: NSView>(_ type: V.Type, in view: NSView?) -> V? {
        guard let view = view else { return nil }
        if let v = view as? V { return v }
        for sub in view.subviews { if let v = find(type, in: sub) { return v } }
        return nil
    }
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Une icône par fichier MenuBarIcon*.png|svg|pdf : permet de comparer plusieurs candidats côte à côte dans la barre de menus.
        let icons = Theme.statusImages()
        let list: [(String, NSImage)] = icons.isEmpty ? [("Mandarine", Theme.drawnStatusImage())] : icons
        for (name, image) in list.reversed() {                // ordre inversé : la barre empile les icônes de droite à gauche
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = image
            item.button?.toolTip = list.count > 1 ? L("Mandarine — \(name)") : L("Mandarine")
            item.menu = buildMenu()
            statusItems.append(item)
        }
        NotificationCenter.default.addObserver(forName: L10n.changed, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            for item in self.statusItems { item.menu = self.buildMenu() }          // le menu de la barre de menus change de langue tout de suite
        }
        SnippetStore.cleanup()
        FaceCache.purge()
        monitor.start()
        runLaunchArguments()
        if CommandLine.arguments.count < 2 { Updater.shared.start() }
        if CommandLine.arguments.count < 2 { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { FullDiskAccess.checkAtLaunch() } }
        if CommandLine.arguments.count < 2 { DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { WhatsNew.showIfNeeded() } }
        if AppSettings.shared.showWelcome && CommandLine.arguments.count < 2 {            // guide d'accueil (réglable dans le guide et les Réglages)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { HelpWindowController.show() }
        }
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        let title = NSMenuItem(title: L("Mandarine"), action: nil, keyEquivalent: "")
        title.isEnabled = false
        m.addItem(title)
        m.addItem(.separator())
        let hint = NSMenuItem(title: L("Drag a file, then tap ⇧ ⌘ or ⌃"), action: nil, keyEquivalent: "")
        hint.isEnabled = false
        m.addItem(hint)
        m.addItem(.separator())
        m.addItem(withTitle: L("All Features"), action: #selector(showFeatures), keyEquivalent: "").target = self
        m.addItem(withTitle: L("What's New"), action: #selector(showWhatsNew), keyEquivalent: "").target = self
        m.addItem(withTitle: L("Help"), action: #selector(showHelp), keyEquivalent: "?").target = self
        m.addItem(withTitle: L("Check for Updates…"), action: #selector(checkUpdates), keyEquivalent: "").target = self
        m.addItem(withTitle: L("Choose File to Process…"), action: #selector(chooseFile), keyEquivalent: "o").target = self
        m.addItem(.separator())
        m.addItem(withTitle: L("Settings…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        m.addItem(withTitle: L("Quit Mandarine"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return m
    }

    @objc private func showHelp() { HelpWindowController.show() }
    @objc private func showFeatures() { FeaturesWindowController.show() }
    @objc private func showWhatsNew() { WhatsNewWindowController.show() }
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
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 540), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = L("Mandarine Settings")
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
        if a.count >= 3, a[0] == "--batchtest" {         // test : --batchtest ext fichier… (convertit le lot et affiche la ligne de notification toutes les 0,3 s)
            let urls = a.dropFirst(2).map { URL(fileURLWithPath: $0) }
            DispatchQueue.main.async {
                Dispatcher.convert(urls, to: a[1])
                Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { t in
                    let rows = Toast.shared.center.items
                    for r in rows { print(String(format: "%@ · %@ · %@ · %.0f%%", "\(r.phase)", r.title, r.subtitle, (r.progress ?? 0) * 100)) }
                    if !rows.isEmpty, rows.allSatisfy({ $0.phase == .done || $0.phase == .failed }) { t.invalidate(); print("fini, \(rows.first?.reveal.count ?? 0) fichiers"); exit(0) }
                }
            }
            return
        }
        if a.first == "--facecachetest" {              // test de la mémoire temporaire des visages (sans modèle : visages fictifs)
            FaceCache.folder = FileManager.default.temporaryDirectory.appendingPathComponent("facecache-test-\(UUID().uuidString)")
            let img = FileManager.default.temporaryDirectory.appendingPathComponent("facecache-photo.jpg")
            try? Data("x".utf8).write(to: img)
            let ctx = CGContext(data: nil, width: 80, height: 80, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(red: 0.9, green: 0.4, blue: 0.2, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
            let vec: [Float] = (0..<128).map { Float($0) / 127 }
            let fake = [FaceHit(file: img, vector: vec, thumb: ctx.makeImage()!, score: 0.42), FaceHit(file: img, vector: vec.reversed(), thumb: ctx.makeImage()!, score: 0.1)]
            print("avant : \(FaceCache.load(img, minRelativeWidth: 0.04) == nil ? "absent" : "présent")")
            FaceCache.store(fake, for: img, minRelativeWidth: 0.04)
            let back = FaceCache.load(img, minRelativeWidth: 0.04)
            print("relu : \(back?.count ?? -1) visages · empreinte identique \(back?[0].vector == vec) · score \(back?[0].score ?? -1) · vignette \(back?[0].thumb.width ?? 0)×\(back?[0].thumb.height ?? 0)")
            print("autre réglage (largeur 0,1) : \(FaceCache.load(img, minRelativeWidth: 0.1) == nil ? "absent (bien)" : "présent (mal)")")
            try? Data("xyz".utf8).write(to: img)          // fichier modifié → ancienne analyse inutilisable
            print("fichier modifié : \(FaceCache.load(img, minRelativeWidth: 0.04) == nil ? "absent (bien)" : "présent (mal)")")
            try? Data("x".utf8).write(to: img)
            FaceCache.store(fake, for: img, minRelativeWidth: 0.04)
            let size = ((try? FileManager.default.contentsOfDirectory(at: FaceCache.folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []).compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
            print("taille d'une entrée à 2 visages : \(size) octets")
            for f in (try? FileManager.default.contentsOfDirectory(at: FaceCache.folder, includingPropertiesForKeys: nil)) ?? [] {      // vieillit les entrées de 25 h
                try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-25 * 3600)], ofItemAtPath: f.path)
            }
            print("après 25 h : \(FaceCache.load(img, minRelativeWidth: 0.04) == nil ? "expirée (bien)" : "encore là (mal)")")
            FaceCache.purge()
            print("dossier après nettoyage : \((try? FileManager.default.contentsOfDirectory(atPath: FaceCache.folder.path))?.count ?? 0) fichier(s)")
            try? FileManager.default.removeItem(at: img); try? FileManager.default.removeItem(at: FaceCache.folder)
            exit(0)
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
        if a.count >= 3, a[0] == "--scantest" {      // test : --scantest photo.jpg sortie.png [Original|Color|Grayscale|B&W]
            do {
                let (img, _) = try ImageEngine.load(URL(fileURLWithPath: a[1]), maxSide: 3000)
                let c = DocumentScanner.detectCorners(img)
                print("coins :", c.map { String(format: "(%.2f, %.2f)", $0.x, $0.y) }.joined(separator: " "))
                let f = ScanFilter(rawValue: a.count > 3 ? a[3] : "Color") ?? .color
                if let out = DocumentScanner.render(img, corners: c, filter: f) {
                    try ImageEngine.write(out, to: URL(fileURLWithPath: a[2]), ext: "png"); print("résultat \(out.width)×\(out.height) → \(a[2])")
                } else { print("ERR rendu") }
            } catch { print("ERR", error.localizedDescription) }
            exit(0)
        }
        if a.first == "--snippettest" {              // test : --snippettest "texte" (MANDARINE_SNIPPET_OUT = dossier de sortie)
            Task {
                let text = a.count > 1 ? a[1] : "Mandarine convertit vos fichiers sans internet. Glissez un texte, appuyez sur une touche, déposez-le sur un pétale."
                guard let f = SnippetStore.make(text) else { print("ERR fichier"); exit(1) }
                print("extrait :", f.path, "· type", FileKind.detect(f), "· roue ⇧:", Catalog.items(mode: .convert, urls: [f]).map(\.label), "· ⌘:", Catalog.items(mode: .tools, urls: [f]).map(\.label), "· ⌃:", Catalog.items(mode: .actions, urls: [f]).map(\.label))
                for e in ["txt", "md", "pdf", "docx", "m4a", "qr"] {
                    do { let o = try await Converter.run(urls: [f], to: e) { _ in }; print("  \(e) → \(o[0].lastPathComponent) (\(o[0].fileSize) o)") } catch { print("  \(e) ERR", error.localizedDescription) }
                }
                print("traduction possible :", SnippetEngine.canTranslate, "· résumé possible :", SnippetEngine.canSummarize, SnippetEngine.summarizeUnavailableReason)
                if SnippetEngine.canSummarize { do { print("résumé :", try await SnippetEngine.summarize(text + " " + text)) } catch { print("résumé ERR", error.localizedDescription) } }
                exit(0)
            }
            return
        }
        if a.count >= 2, a[0] == "--ziptest" {       // test : --ziptest fichier_ou_dossier…
            Task { do { let z = try await ZipEngine.make(a.dropFirst().map { URL(fileURLWithPath: $0) }); print("OK", z.path, z.fileSize, "o") } catch { print("ERR", error.localizedDescription) }; exit(0) }
            return
        }
        if a.count >= 2, a[0] == "--culltest" {      // test : --culltest image… (ouvre le tri rapide, simule des touches K, X, flèche droite, M, puis relit les étiquettes)
            let urls = a.dropFirst().map { URL(fileURLWithPath: $0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                ToolWindowController.present(.quickSort, urls: urls)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    guard let w = NSApp.windows.first(where: { $0 is ToolWindow }) else { print("pas de fenêtre"); exit(1) }
                    func key(_ ch: String, _ code: UInt16) { w.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, characters: ch, charactersIgnoringModifiers: ch, isARepeat: false, keyCode: code)!) }
                    key("e", 14); key("a", 0); key("\u{F703}", 124); key("z", 6)       // E : image 1 gardée · A : image 2 rejetée · flèche droite · Z : dernière image « peut-être »
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        for u in urls { print(u.lastPathComponent, "→", TagSelect.tags(of: u).map { "\($0.name)(\($0.color))" }.joined(separator: ", ")) }
                        exit(0)
                    }
                }
            }
            return
        }
        if a.count >= 3, a[0] == "--sizetest", let id = ToolID(rawValue: a[1]) {      // test : --sizetest outil fichier… (la fenêtre suit-elle la taille de son contenu ?)
            let urls = a.dropFirst(2).map { URL(fileURLWithPath: $0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                ToolWindowController.present(id, urls: urls)
                guard let w = NSApp.windows.first(where: { $0 is ToolWindow }), let host = w.contentView else { print("pas de fenêtre"); exit(1) }
                print("à l'ouverture : fenêtre", w.frame.size, "· contenu", host.fittingSize)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    print("3 s plus tard  : fenêtre", w.frame.size, "· contenu", host.fittingSize, "· haut de la fenêtre", w.frame.maxY, "· écran", w.screen?.visibleFrame.maxY ?? 0)
                    exit(0)
                }
            }
            return
        }
        if a.count >= 2, a[0] == "--updatetoastshot" {      // test : --updatetoastshot sortie.png (la notification « New update »)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                Updater.shared.debugAnnounce("1.3.3")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    guard let w = NSApp.windows.first(where: { $0 is NSPanel && $0.level == .statusBar && $0.frame.width > 200 }),
                          let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.bestResolution]) else { print("capture impossible"); exit(1) }
                    try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: a[1]))
                    exit(0)
                }
            }
            return
        }
        if a.count >= 2, a[0] == "--toastdragtest" {      // test : --toastdragtest fichier (événements synthétiques : la notification lance-t-elle un vrai glisser du fichier ?)
            let file = URL(fileURLWithPath: a[1])          // « - » : une notification sans fichier (elle emporte son texte)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if a[1] == "-" { Toast.shared.done("Link copied", subtitle: "https://example.com/une/adresse") }
                else { Toast.shared.done("Saved", subtitle: "\(file.lastPathComponent)\nin test", reveal: file) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    guard let w = NSApp.windows.first(where: { $0 is NSPanel && $0.level == .statusBar && $0.frame.width > 200 }),
                          let handle = Self.find(FileDragView.self, in: w.contentView) else { print("poignée introuvable"); exit(1) }
                    print("poignée trouvée, fichiers :", handle.urls.map(\.lastPathComponent), "· texte :", handle.text.replacingOccurrences(of: "\n", with: " / "), "· aide :", handle.toolTip ?? "-")
                    if let cv = w.contentView {
                        let hf = handle.convert(handle.bounds, to: nil)
                        let y = hf.midY
                        for (name, x) in [("marge gauche", hf.minX - 10), ("icône", hf.minX + 25), ("titre", hf.midX), ("bouton Show", w.frame.width - 30 - 14 - 18 - 12 - 35), ("bouton ✕", w.frame.width - 30 - 14 - 9)] {
                            let hit = cv.hitTest(cv.convert(NSPoint(x: x, y: y), from: nil))
                            print("clic sur", name, "→", hit.map { String(describing: type(of: $0)) } ?? "rien")
                        }
                        print("zone de la poignée :", hf, "· fenêtre :", w.frame.size)
                    }
                    handle.onBegin = { print("glisser commencé") }
                    handle.onEnd = { print("glisser terminé") }
                    func event(_ type: NSEvent.EventType, _ x: CGFloat) -> NSEvent {
                        let hf = handle.convert(handle.bounds, to: nil)
                        return NSEvent.mouseEvent(with: type, location: NSPoint(x: hf.midX + x, y: hf.midY), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                    }
                    w.sendEvent(event(.leftMouseDown, 0))          // par le chemin réel : fenêtre → hitTest → poignée
                    w.sendEvent(event(.leftMouseDragged, 30))
                    let urls = (NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
                    print("presse-papiers de glissement :", urls.map(\.lastPathComponent), "· texte :", NSPasteboard(name: .drag).string(forType: .string) ?? "-")
                    if let id = Toast.shared.center.items.last?.id { Toast.shared.update(id) { $0.dragging = true } }          // apparence « saisie »
                    RunLoop.current.run(until: Date().addingTimeInterval(0.8))
                    if a.count >= 3, let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.bestResolution]) {          // --toastdragtest fichier sortie.png : capture aussi la notification
                        try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: a[2]))
                    }
                    exit(0)
                }
            }
            return
        }
        if a.count >= 4, a[0] == "--webtest" {      // test : --webtest pdf|md|png adresse dossier (enregistre la page comme le fait le pétale)
            let kind: WebCaptureKind = a[1] == "pdf" ? .pdf : (a[1] == "md" ? .markdown : .screenshot)
            guard let link = URL(string: a[2]) else { print("adresse invalide"); exit(1) }
            Task {
                do {
                    let t0 = Date()
                    let out = try await WebCapture.save(link, as: kind, to: URL(fileURLWithPath: a[3]))
                    print("OK", out.path, "·", out.fileSize, "octets ·", String(format: "%.1f s", Date().timeIntervalSince(t0)))
                } catch { print("ÉCHEC :", error.localizedDescription) }
                exit(0)
            }
            return
        }
        if a.first == "--wiishot", a.count >= 3 {      // test : l'écran Wii qui plonge dans un outil, image par image. Usage : --wiishot <outil> <préfixe> [fichier]
            let tool = ToolID(rawValue: a[1]) ?? .compress
            let urls = [a.count > 3 ? URL(fileURLWithPath: a[3]) : HelpAssets.fakeImage]
            let wc = WheelController.shared, shell = WiiShell.shared
            wc.model.mode = .tools; wc.model.items = Catalog.items(mode: .tools, urls: urls); wc.model.appear = true
            wc.model.fileCount = 1; wc.model.infoLines = ["2.4 MB", "4032 × 3024", "JPG"]
            let idx = wc.model.items.firstIndex { $0.id == tool.rawValue || $0.children.contains { $0.id == tool.rawValue } } ?? 0
            let tile = WiiLayout.slotRect(idx)
            let view = ToolRegistry.view(for: tool, urls: urls, close: {})
            shell.debugPose(tool: view, panel: 1, zoom: 1, tab: 1, content: 1, tile: tile, hasMenu: true)
            let host = NSHostingView(rootView: WiiShellView(model: wc.model, shell: shell).environment(\.colorScheme, .light))
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView = host; win.appearance = NSAppearance(named: .aqua); win.backgroundColor = NSColor(white: 0.55, alpha: 1); win.orderBack(nil)
            let poses: [(String, CGFloat, CGFloat, CGFloat, Double)] = [("1-menu", 0, 0, 0, 0), ("2-zoom", 0, 0.5, 0, 0), ("3-dark", 0.05, 1, 0, 0), ("4-grow", 0.3, 1, 0, 0),
                                                                        ("5-grow", 0.65, 1, 0, 0), ("6-tab", 1, 1, 0.5, 0), ("7-done", 1, 1, 1, 1)]
            func capture(_ i: Int) {
                guard i < poses.count else { exit(0) }
                let q = poses[i]
                shell.debugPose(tool: view, panel: q.1, zoom: q.2, tab: q.3, content: q.4, tile: tile, hasMenu: true)
                shell.pointer.point = CGPoint(x: 420, y: 330); shell.pointer.closed = i % 2 == 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let st = shell.stage
                    print(q.0, "natural", shell.naturalSize, "stage", st)
                    host.frame = NSRect(origin: .zero, size: st); win.setContentSize(st)
                    host.layoutSubtreeIfNeeded()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                            host.cacheDisplay(in: host.bounds, to: rep)
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: a[2] + q.0 + ".png"))
                        }
                        capture(i + 1)
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { capture(0) }
            return
        }
        if a.first == "--wiiflow", a.count >= 3 {      // test : le vrai parcours Wii (dépôt simulé, zoom, outil, retour, sortie). Usage : MANDARINE_APPEARANCE=wii --wiiflow <outil> <préfixe>
            let tool = ToolID(rawValue: a[1]) ?? .compress
            let urls = [HelpAssets.fakeImage]
            let wc = WheelController.shared, shell = WiiShell.shared
            wc.show(mode: .tools, urls: urls, at: NSPoint(x: (NSScreen.main?.frame.midX ?? 800), y: (NSScreen.main?.frame.midY ?? 500)))
            func grab(_ name: String) {
                guard let v = shell.debugContentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { print(name, "(pas de fenêtre)"); return }
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: a[2] + name + ".png"))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard let idx = wc.model.items.firstIndex(where: { $0.id == tool.rawValue || $0.children.contains { $0.id == tool.rawValue } }) else { print("outil absent"); exit(1) }
                wc.model.hover = idx
                if let c = wc.model.items[idx].children.firstIndex(where: { $0.id == tool.rawValue }) { wc.model.hoverChild = c }
                print("drop →", wc.drop(), "shell ouvert :", shell.isOpen)
                for (i, t) in [0.12, 0.3, 0.45, 0.6, 0.8, 1.0, 1.5, 2.8].enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + t) { grab("a\(i)") }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                    print("interactif :", shell.interactive, "taille :", shell.naturalSize)
                    shell.backToMenu()
                    for (i, t) in [0.2, 0.45, 0.7, 2.0].enumerated() { DispatchQueue.main.asyncAfter(deadline: .now() + t) { grab("b\(i)") } }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                        print("après retour : interactif menu =", wc.model.wiiInteractive, "taille avant réouverture", shell.naturalSize)
                        wc.model.hover = idx; wc.model.hoverChild = nil
                        shell.chooseHovered()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            grab("c0"); print("2e ouverture, interactif :", shell.interactive, "taille :", shell.naturalSize)
                            shell.finish()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { print("fermé :", !shell.isOpen); exit(0) }
                        }
                    }
                }
            }
            return
        }
        if a.first == "--bgedit", a.count >= 3, #available(macOS 14.0, *) {      // test : gomme et pinceau sur le masque. Usage : --bgedit image sortie.png
            do {
                let (cg, _) = try ImageEngine.load(URL(fileURLWithPath: a[1]), maxSide: 800)
                let s = try BGSession(cg)
                var o = BGOptions(); o.fill = .color; o.color = NSColor.systemTeal
                o.edits = [BGStroke(points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.12)], radius: 0.05, restore: true),      // pinceau en haut : remet l'image
                           BGStroke(points: [CGPoint(x: 0.5, y: 0.45), CGPoint(x: 0.5, y: 0.7)], radius: 0.06, restore: false)]      // gomme au centre
                if a.count > 3 { o.edits = [] }                                                           // 4ᵉ argument : sans retouche, pour comparer
                let img = try s.render(o)
                try ImageEngine.write(img, properties: [:], to: URL(fileURLWithPath: a[2]), ext: "png", quality: 1)
                print("ok", img.width, img.height)
            } catch { print("ÉCHEC", error.localizedDescription) }
            exit(0)
        }
        if a.first == "--replacetest" {      // test : remplacement de l'original (Corbeille), même nom, changement d'extension, annulation
            let fm = FileManager.default
            let dir = fm.temporaryDirectory.appendingPathComponent("mandarine-replace-" + UUID().uuidString)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            func make(_ name: String, _ text: String) -> URL { let u = dir.appendingPathComponent(name); try? text.write(to: u, atomically: true, encoding: .utf8); return u }
            let o1 = make("photo.png", "ORIGINAL-1"), r1 = make("photo compressed.png", "RESULT-1")
            let o2 = make("clip.mov", "ORIGINAL-2"), r2 = make("clip converted.mp4", "RESULT-2")
            do {
                let done = try Replacer.replace(originals: [o1, o2], outputs: [r1, r2])
                print("remplacé :", done.map { $0.final.lastPathComponent }, "| photo.png =", (try? String(contentsOf: o1)) ?? "?", "| mov présent :", fm.fileExists(atPath: o2.path), "| résultats d'origine présents :", fm.fileExists(atPath: r1.path))
                print("corbeille :", done.map { fm.fileExists(atPath: $0.trashed.path) })
                try Replacer.undo(done)
                print("annulé : photo.png =", (try? String(contentsOf: o1)) ?? "?", "| résultat revenu :", fm.fileExists(atPath: r1.path), (try? String(contentsOf: r1)) ?? "?", "| mov =", (try? String(contentsOf: o2)) ?? "?", "| mp4 revenu :", fm.fileExists(atPath: r2.path))
            } catch { print("ERR", error.localizedDescription) }
            // via la file de travaux : réglage « garder » + touche inversée simulée par le paramètre explicite
            let o3 = make("doc.txt", "ORIGINAL-3")
            JobQueue.shared.add("Test", replaces: [o3], replace: true) { _ in let r = dir.appendingPathComponent("doc edited.txt"); try "RESULT-3".write(to: r, atomically: true, encoding: .utf8); return [r] }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                print("job : doc.txt =", (try? String(contentsOf: o3)) ?? "?", "| doc edited.txt présent :", fm.fileExists(atPath: dir.appendingPathComponent("doc edited.txt").path))
                let o4 = make("keep.txt", "ORIGINAL-4")
                JobQueue.shared.add("Test2", replaces: [o4], replace: false) { _ in let r = dir.appendingPathComponent("keep edited.txt"); try "RESULT-4".write(to: r, atomically: true, encoding: .utf8); return [r] }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    print("job garder : keep.txt =", (try? String(contentsOf: o4)) ?? "?", "| keep edited.txt présent :", fm.fileExists(atPath: dir.appendingPathComponent("keep edited.txt").path))
                    try? fm.removeItem(at: dir); exit(0)
                }
            }
            return
        }
        if a.first == "--entertest", a.count >= 2 {      // test : Entrée dans une fenêtre d'outil lance l'outil. Usage : --entertest image.png
            let fm = FileManager.default
            let dir = fm.temporaryDirectory.appendingPathComponent("mandarine-enter-" + UUID().uuidString)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let src = dir.appendingPathComponent("pic.png"); try? fm.copyItem(at: URL(fileURLWithPath: a[1]), to: src)
            if a.count > 2 && a[2] == "optdrop" { ReplaceMode.shared.debugCapture(held: true) }      // comme un dépôt avec ⌥ maintenue
            ToolWindowController.present(.compress, urls: [src])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard let w = NSApp.windows.first(where: { $0 is ToolWindow }) else { print("pas de fenêtre"); exit(1) }
                w.makeKeyAndOrderFront(nil)
                let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
                let handled = w.performKeyEquivalent(with: e)
                print("Entrée traitée :", handled)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    let files = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
                    print("fichiers :", files, "| fenêtre fermée :", !NSApp.windows.contains { $0 is ToolWindow && $0.isVisible })
                    try? fm.removeItem(at: dir); exit(0)
                }
            }
            return
        }
        if a.first == "--whatsnewtest" {      // test : quelles versions seraient présentées (--whatsnewtest dernière_vue version_installée)
            let last = a.count > 1 ? a[1] : "1.4.1", cur = a.count > 2 ? a[2] : ((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0")
            print("depuis", last, "→", cur, ":", WhatsNew.pending(since: last, current: cur).map(\.version))
            exit(0)
        }
        if a.first == "--swipemap" {      // test : les zones des lignes (SwiftUI) correspondent-elles à la vue AppKit sous le pointeur ?
            let t = Toast.shared, c = Toast.shared.center
            t.done("First", subtitle: "a.png\nin Downloads"); t.done("Second", subtitle: "b.png\nin Downloads")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                guard let h = t.debugHost else { print("pas de vue"); exit(1) }
                print("vue : flipped =", h.isFlipped, "bounds =", h.bounds)
                for id in c.items.map(\.id) { print("SwiftUI :", c.frames[id] ?? .zero) }
                for r in h.debugHandles() { print("AppKit  :", r) }
                exit(0)
            }
            return
        }
        if a.first == "--swipetest" {      // test : balayage vers la droite d'une notification (suite d'évènements fictifs)
            let t = Toast.shared, c = Toast.shared.center
            t.done("First", subtitle: "a.png\nin Downloads"); t.done("Second", subtitle: "b.png\nin Downloads"); t.done("Third", subtitle: "c.png\nin Downloads")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let ids = c.items.map(\.id)
                guard ids.count == 3, let f1 = c.frames[ids[0]], let f2 = c.frames[ids[1]], let f3 = c.frames[ids[2]] else { print("pas de zones", c.frames.count); exit(1) }
                func swipe(_ f: CGRect, _ steps: [(CGFloat, CGFloat)]) {
                    let p = CGPoint(x: f.midX, y: f.midY)
                    c.feedSwipe(phase: .began, dx: 0, dy: 0, at: p)
                    for s in steps { c.feedSwipe(phase: .changed, dx: s.0, dy: s.1, at: p) }
                    c.feedSwipe(phase: .ended, dx: 0, dy: 0, at: p)
                }
                swipe(f1, (0..<6).map { _ in (30, 1) })        // long balayage horizontal → la ligne part
                swipe(f2, [(8, 0), (6, 0), (4, 0)])             // court et lent → elle revient
                swipe(f3, (0..<6).map { _ in (2, 30) })         // vertical → ignoré
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    print("restantes :", c.items.map(\.title), "| décalages :", c.swipe)
                    exit(0)
                }
            }
            return
        }
        if a.first == "--l10ntest" {      // test : traductions (MANDARINE_LANG=fr)
            for t in ["Compress", "Saved 3 items", "photo.png\nin Downloads", "Unknown text"] { print(t.replacingOccurrences(of: "\n", with: "⏎"), "→", L(t).replacingOccurrences(of: "\n", with: "⏎")) }
            exit(0)
        }
        if a.first == "--etatest" {      // test : estimation du temps restant sur des relevés fictifs
            func eta(_ label: String, _ s: [(t: Double, p: Double)]) { print(label, "→", JobQueue.etaText(samples: s).isEmpty ? "(rien)" : JobQueue.etaText(samples: s)) }
            eta("début (3 s, 5 %)", [(0, 0), (3, 0.05)])
            eta("20 s, 10 % (≈ 3 min)", [(0, 0), (10, 0.05), (20, 0.1)])
            eta("60 s, 30 % (≈ 2 min)", (0...12).map { (Double($0) * 5, Double($0) * 5 / 200) })
            eta("100 s, 80 % (≈ 25 s)", (0...20).map { (Double($0) * 5, Double($0) * 5 / 125) })
            eta("1 h, 5 % (≈ 1 h 55)", (0...12).map { (Double($0) * 300, Double($0) * 300 / 72000) })
            eta("fin (99 %)", [(0, 0), (50, 0.5), (99, 0.99)])
            eta("bloqué", [(0, 0.3), (20, 0.3)])
            exit(0)
        }
        if a.first == "--linkwheel" {      // test : liens web glissés, roue ⌘ (vidéo connue, article, deux liens)
            for (label, links) in [("YouTube", ["https://www.youtube.com/watch?v=abc"]), ("article", ["https://www.lemonde.fr/article.html"]), ("deux liens", ["https://a.com/x", "https://b.org/y"])] {
                let items = Catalog.items(mode: .tools, urls: links.compactMap(URL.init(string:)))
                print(label, "→", items.map(\.label).joined(separator: " · "))
            }
            exit(0)
        }
        if a.count >= 2, a[0] == "--etashot" {      // test : --etashot sortie.png (un travail qui avance à vitesse constante ; capture la notification à 14 s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                JobQueue.shared.add("Encoding…", subtitle: "holiday.mov") { progress in
                    for i in 0..<400 { try Task.checkCancellation(); progress(Double(i) / 400); try await Task.sleep(nanoseconds: 100_000_000) }
                    return []
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 14) {
                    guard let w = NSApp.windows.first(where: { $0 is NSPanel && $0.level == .statusBar && $0.frame.width > 200 }),
                          let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.bestResolution]) else { print("capture impossible"); exit(1) }
                    try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: a[1]))
                    print("texte :", Toast.shared.center.items.map(\.eta)); exit(0)
                }
            }
            return
        }
        if a.count >= 2, a[0] == "--toastshot" {      // test : --toastshot sortie.png (capture la vraie notification, ombre comprise)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                Toast.shared.done("Selected 4 of 17 files", subtitle: "in the Finder")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    guard let w = NSApp.windows.first(where: { $0 is NSPanel && $0.level == .statusBar && $0.frame.width > 200 }),
                          let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.bestResolution]) else { print("capture impossible"); exit(1) }
                    try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: a[1]))
                    print("panneau", w.frame.size); exit(0)
                }
            }
            return
        }
        if a.count >= 4, a[0] == "--winshot", let id = ToolID(rawValue: a[1]) {      // test : --winshot outil sortie.png fichier… (capture la vraie fenêtre, ombre comprise)
            let urls = a.dropFirst(3).map { URL(fileURLWithPath: $0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                ToolWindowController.present(id, urls: urls)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    guard let w = NSApp.windows.first(where: { $0 is ToolWindow }),
                          let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.bestResolution]) else { print("capture impossible"); exit(1) }
                    try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: a[2]))
                    print("fenêtre", w.frame.size, "· image", cg.width, "×", cg.height, "· ombre système :", w.hasShadow)
                    exit(0)
                }
            }
            return
        }
        if a.first == "--bubbletest" {               // test de la détection des bulles
            func overlaps(_ q: [BubbleLayout.Spot]) -> Int {
                var count = 0
                for i in q.indices {
                    for j in q.indices where j > i {
                        let dist: CGFloat = hypot(q[i].x - q[j].x, q[i].y - q[j].y)
                        let minDist: CGFloat = (q[i].d + q[j].d) / 2
                        if dist < minDist { count += 1 }
                    }
                }
                return count
            }
            for k in [6, 8, 9, 10, 12, 14, 16, 18] {
                let q = BubbleLayout.spots(k)
                var reach: CGFloat = 0, smallest: CGFloat = 999
                for b in q { reach = max(reach, hypot(b.x, b.y) + b.d / 2); smallest = min(smallest, b.d) }
                print("anneau unique,", k, "bulles · portée", Int(reach), "· plus petite bulle", Int(smallest), "· chevauchements", overlaps(q))
            }
            let n = 9, sp = BubbleLayout.spots(n)
            print("bulles :", sp.count, "· chevauchements :", overlaps(sp))
            print("sur la bulle 3 :", BubbleLayout.hit(CGPoint(x: sp[3].x, y: sp[3].y), count: n, hoverParent: nil, childCount: 0))
            print("dans le vide   :", BubbleLayout.hit(CGPoint(x: 0, y: 0), count: n, hoverParent: nil, childCount: 0))
            let kids = BubbleLayout.childSpots(parent: sp[2], count: 3)
            print("sur une sous-bulle du groupe 2 :", BubbleLayout.hit(CGPoint(x: kids[1].x, y: kids[1].y), count: n, hoverParent: 2, childCount: 3))
            print("sur le parent, groupe 2 ouvert :", BubbleLayout.hit(CGPoint(x: sp[2].x + 20, y: sp[2].y), count: n, hoverParent: 2, childCount: 3))
            print("sous-bulle hors groupe ouvert  :", BubbleLayout.hit(CGPoint(x: kids[1].x, y: kids[1].y), count: n, hoverParent: nil, childCount: 0))
            exit(0)
        }
        if a.count >= 3, a[0] == "--panelshots" {      // test : --panelshots mode fichier… (ouvre le vrai panneau, capture deux images à 0,6 s d'écart)
            guard let m = WheelMode(rawValue: a[1]) else { exit(2) }
            let urls = a.dropFirst(2).map { URL(fileURLWithPath: $0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                WheelController.shared.show(mode: m, urls: urls, at: NSPoint(x: 900, y: 600))
                func grab(_ name: String) {
                    guard let w = NSApp.windows.first(where: { $0 is WheelPanel && $0.isVisible }) ?? { print("fenêtres :", NSApp.windows.map { "\(type(of: $0)) visible=\($0.isVisible) \($0.frame.size)" }); return nil }(),
                          let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.bestResolution]) else { print("pas de panneau"); return }
                    try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: name))
                }
                for (k, dt) in [0.12, 0.22, 0.34, 0.5].enumerated() {                                        // images en pleine animation d'entrée
                    DispatchQueue.main.asyncAfter(deadline: .now() + dt) { grab("/tmp/bub/anim\(k).png") }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    grab("/tmp/bub/real1.png")
                    // survol d'une bulle (comme le ferait le glisser)
                    WheelController.shared.bubbleHover(at: BubbleLayout.spots(WheelController.shared.model.items.count).first.map { CGPoint(x: $0.x, y: $0.y) } ?? .zero)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { grab("/tmp/bub/real2.png") }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { grab("/tmp/bub/real3.png"); print("hover :", WheelController.shared.model.hover as Any); exit(0) }
                }
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
        if a.count >= 3, a[0] == "--transcribe" {      // test sans interface : --transcribe langue fichier
            let url = URL(fileURLWithPath: a[2]), loc = Locale(identifier: a[1])
            Task {
                do {
                    let info = await FFmpeg.probe(url)
                    let words = try await Transcriber.transcribe(url, locale: loc, duration: info.duration) { _ in }
                    print("ONDEVICE", Transcriber.isOnDevice(loc)); print(Transcriber.plainText(words, locale: loc)); print(Transcriber.srt(Transcriber.cues(words, locale: loc), locale: loc))
                } catch { print("ERR", error.localizedDescription) }
                exit(0)
            }
            return
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
            if a[0] == "--batch" { Dispatcher.convert(Array(urls), to: a[1]); return }      // test : --batch ext fichiers… (lot comme un dépôt sur la roue)
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
            Toast.shared.done("Saved", subtitle: "photo.png\nin Pictures", reveal: URL(fileURLWithPath: "/tmp"))
            Toast.shared.fail("Conversion failed", subtitle: "ffmpeg a échoué (code 1).")
            Toast.shared.add(ToastItem(id: UUID(), phase: .done, title: "Saved", subtitle: "photo compressed.png\nin Downloads", reveal: [URL(fileURLWithPath: "/tmp")], action: ("Replace original", {})))
            Toast.shared.add(ToastItem(id: UUID(), phase: .done, title: "Tip: keep or replace", subtitle: "Hold ⌥ while you click the button to replace the original instead of keeping both — the old file goes to the Trash. The default is in Settings → General.", action: ("Got it", {}), sticky: true))
            let extended = Toast.shared.add(ToastItem(id: UUID(), phase: .done, title: "Saved", subtitle: "talk.txt\nin Desktop", reveal: [URL(fileURLWithPath: "/tmp")]))
            Toast.shared.extend(extended); Toast.shared.extend(extended)          // deux clics : « +1 min » et le décompte
            view = AnyView(ToastStack(center: Toast.shared.center).background(Color(white: 0.55)))
        } else if target[0] == "settings" {
            view = AnyView(SettingsView(tab: SettingsView.Tab(rawValue: target.count > 1 ? target[1] : "") ?? .general).background(Color(white: 0.55)))
        } else if target[0] == "faceselect" {
            view = AnyView(FaceSelectTool(urls: urls, close: {}).padding(30).background(Color(white: 0.55)))
        } else if target[0] == "playlist" {
            let es = (0..<14).map { YtDlp.Playlist.Entry(id: $0, url: URL(string: "https://example.com/\($0)")!, title: "Track number \($0 + 1) — a fairly long title to check truncation", duration: Double(150 + $0 * 17)) }
            view = AnyView(PlaylistTool(link: URL(string: "https://www.youtube.com/watch?v=abc&list=xyz")!, list: .init(title: "Summer mix 2026", entries: es), kind: .mp4, close: {}).padding(30).background(Color(white: 0.55)))
        } else if target[0] == "bubbles", let m = WheelMode(rawValue: target[1]) {
            let model = WheelModel()
            model.mode = m; model.items = Catalog.items(mode: m, urls: urls); model.appear = true
            model.infoLines = WheelInfo.quick(urls); model.fileCount = urls.count
            if let h = ProcessInfo.processInfo.environment["MANDARINE_HOVER"] {
                let p = h.split(separator: ",").compactMap { Int($0) }
                model.hover = p.first; model.hoverChild = p.count > 1 ? p[1] : nil
            }
            let sem = DispatchSemaphore(value: 0); var previews: [WheelPreviewItem] = []
            Task.detached { previews = await WheelPreview.make(urls); sem.signal() }
            sem.wait(); model.previews = previews
            view = AnyView(BubbleMenuView(model: model).background(Color(white: 0.55)))
        } else if target[0] == "wiitiles" {
            view = AnyView(WiiTilesDebug().background(Color(white: 0.55)))
        } else if target[0] == "toaststyles" {
            view = AnyView(ToastLab(page: Int(target.count > 1 ? target[1] : "1") ?? 1))
        } else if target[0] == "whatsnew" {
            view = AnyView(WhatsNewView(releases: WhatsNew.releases, highlighted: ["1.9.0", "1.8.2"], close: {}))
        } else if target[0] == "features" {
            view = AnyView(FeaturesView(startTab: target.count > 1 ? target[1] : "image", startQuery: target.count > 2 ? target[2] : "", close: {}))
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
