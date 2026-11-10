import AppKit

/// Détecte qu'un glisser-déposer de fichiers est en cours (n'importe où dans le système) et ouvre la roue
/// quand l'utilisateur tape la touche d'une des trois roues. Les modificateurs sont lus par interrogation
/// (`NSEvent.modifierFlags`), donc aucune permission d'accessibilité n'est nécessaire.
final class DragMonitor {
    static let shared = DragMonitor()
    private var monitors: [Any] = []
    private var timer: Timer?
    private var downChangeCount = 0
    private var dragging = false
    private var internalDrag = false          // le glisser vient d'une notification de Mandarine
    private var draggedURLs: [URL] = []
    private var lastRead = Date.distantPast
    private var seenCount = 0                 // état du presse-papiers de glissement lors de la dernière lecture
    private var dragText: String?             // texte déjà converti en petit fichier (évite d'en refaire un à chaque lecture)
    private var lastFlags: NSEvent.ModifierFlags = []
    private var otherKeyHeld = false          // une touche non-modificateur est enfoncée : la roue est annulée / bloquée
    private let settings = AppSettings.shared
    private let wheel = WheelController.shared

    func start() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.handle(e) }) {
            monitors.append(m)
        }
        // Filet de sécurité si la lecture d'état clavier est bloquée : un keyDown global (nécessite l'accessibilité).
        if let k = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] _ in
            guard let self = self, self.dragging else { return }
            self.otherKeyHeld = true
            if self.wheel.isVisible { self.wheel.hide() }
        }) { monitors.append(k) }
        wheel.onDismiss = { [weak self] in self?.reset() }
    }

    private func handle(_ e: NSEvent) {
        switch e.type {
        case .leftMouseDown:
            downChangeCount = NSPasteboard(name: .drag).changeCount
            reset()
        case .leftMouseDragged:
            guard !dragging else { return }
            let pb = NSPasteboard(name: .drag)
            if Self.debugLog, pb.changeCount != lastDragCount {
                lastDragCount = pb.changeCount
                Self.log("MOUSEDRAG changeCount=\(pb.changeCount) down=\(downChangeCount) types=\((pb.types ?? []).map(\.rawValue)) frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "-")")
            }
            guard pb.changeCount != downChangeCount else { return }
            guard let urls = readDraggedURLs(pb), !urls.isEmpty else { return }
            draggedURLs = urls
            seenCount = pb.changeCount
            dragging = true
            lastFlags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            startPolling()
        case .leftMouseUp: released()
        default: break
        }
    }

    /// Le bouton est relâché. Le relâchement est vu ici AVANT que la roue reçoive le dépôt : si un segment est survolé, on attend
    /// le dépôt (qui ferme la roue). Sans réponse après un court délai, on exécute le segment survolé
    /// nous-mêmes ; sinon (dépôt hors de la roue) on referme.
    private func released() {
        if wheel.isVisible {
            if wheel.hoveredItemEnabled {
                wheel.playReleaseSound()          // son et haptique au relâchement exact du bouton
                let hovered = wheel.model.hover, hoveredChild = wheel.model.hoverChild
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [wheel] in
                    if wheel.isVisible { wheel.model.hover = hovered; wheel.model.hoverChild = hoveredChild; if !wheel.drop() { wheel.dismiss() } }
                }
            } else { wheel.dismiss() }
        }
        dragging = false
        timer?.invalidate(); timer = nil
    }

    /// Glisser commencé dans Mandarine même (le fichier d'une notification) : les événements de souris de notre propre app
    /// n'arrivent pas aux moniteurs globaux, donc la notification annonce elle-même le début et la fin du glisser.
    /// La roue s'ouvre ensuite avec les touches habituelles, et le fichier peut y être déposé.
    /// `text` : sans fichier, la notification emporte son texte (traité comme un texte glissé, si ce réglage est actif).
    func beginInternalDrag(_ files: [URL], text: String) {
        reset()
        var urls = files
        if urls.isEmpty, settings.enableTextDrag, let snippet = SnippetStore.make(text) { urls = [snippet]; dragText = text }
        guard !urls.isEmpty else { return }          // rien que la roue puisse traiter (texte glissé désactivé) : le glisser reste ordinaire
        draggedURLs = urls
        seenCount = NSPasteboard(name: .drag).changeCount
        dragging = true
        internalDrag = true
        lastFlags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        startPolling()
    }

    func endInternalDrag() {
        guard internalDrag else { return }
        internalDrag = false
        released()
    }

    /// Au dépôt : une dernière lecture du presse-papiers de glissement, la plus complète. Rend `fallback` si elle n'apporte rien de plus.
    func latestURLs(fallback: [URL]) -> [URL] {
        guard !internalDrag, let fresh = readDraggedURLs(NSPasteboard(name: .drag)), fresh.count > fallback.count else { return fallback }
        return fresh
    }

    static let debugLog = ProcessInfo.processInfo.environment["MANDARINE_DRAGLOG"] != nil
    private var lastLoggedCount = -1
    private var lastDragCount = -1
    static func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

    /// Ce qui est en train d'être glissé : fichiers, sinon liens, sinon texte (petit fichier). nil si rien d'exploitable.
    private func readDraggedURLs(_ pb: NSPasteboard) -> [URL]? {
        let all = (pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        if Self.debugLog, pb.changeCount != lastLoggedCount {          // MANDARINE_DRAGLOG=1 : ce que le glisser contient vraiment
            lastLoggedCount = pb.changeCount
            let fm = FileManager.default
            Self.log("DRAG types=\((pb.types ?? []).map(\.rawValue)) urls=\(all.map { "\($0.path) exists=\(fm.fileExists(atPath: $0.path)) size=\((try? fm.attributesOfItem(atPath: $0.path)[.size]) ?? "-")" })")
            Self.log("DRAG promises=\(pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil)?.count ?? 0)")
        }
        let files = all.filter(\.isFileURL)
        let links = all.filter { $0.scheme == "http" || $0.scheme == "https" }
        var urls = files.isEmpty ? links : files       // un lien glissé depuis un navigateur ouvre aussi la roue
        if urls.isEmpty, settings.enableTextDrag,       // texte sélectionné et glissé : enregistré dans un petit fichier, traité comme un fichier
           let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), text.count >= 2 {
            if text == dragText, let known = draggedURLs.first, SnippetStore.isSnippet(known) { urls = draggedURLs }
            else if let snippet = SnippetStore.make(text) { urls = [snippet]; dragText = text }
        }
        return urls
    }

    /// Finder (surtout quand sa fenêtre n'est pas au premier plan) complète parfois le presse-papiers de glissement APRÈS le début du geste :
    /// la sélection lue au premier mouvement peut être partielle ou périmée. On surveille donc ce presse-papiers pendant tout le glissement,
    /// et la roue (déjà ouverte ou non) repart de la sélection à jour.
    private func refreshFromPasteboard() {
        let pb = NSPasteboard(name: .drag)
        // Une grosse sélection (dizaines de fichiers) peut s'allonger sans que le compteur du presse-papiers bouge :
        // on relit donc aussi à intervalle régulier, et on ne garde que ce qui a changé.
        let now = Date()
        guard pb.changeCount != seenCount || now.timeIntervalSince(lastRead) > 0.25 else { return }
        seenCount = pb.changeCount
        lastRead = now
        guard let urls = readDraggedURLs(pb), !urls.isEmpty, urls != draggedURLs else { return }
        draggedURLs = urls
        if wheel.isVisible { wheel.show(mode: wheel.model.mode, urls: urls) }          // roue ouverte : même place, contenu mis à jour
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func poll() {
        guard dragging else { return }
        refreshFromPasteboard()
        ReplaceMode.shared.refresh()
        let replacing = wheel.isVisible && ReplaceMode.shared.effective
        if wheel.model.replacing != replacing { wheel.model.replacing = replacing }
        if NSEvent.pressedMouseButtons & 1 == 0 {            // le bouton a été relâché ailleurs
            if !wheel.isVisible { reset() }
            return
        }
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let pressed = flags.subtracting(lastFlags)
        lastFlags = flags

        // Seuls ⇧ ⌘ ⌥ ⌃ ouvrent la roue. Dès qu'une autre touche s'y ajoute (ex. ⌘ Tab), la roue disparaît et reste
        // bloquée tant que cette touche est enfoncée.
        if Self.nonModifierKeyDown() {
            if !otherKeyHeld { otherKeyHeld = true; if wheel.isVisible { wheel.hide() } }
            return
        }
        otherKeyHeld = false
        guard !pressed.isEmpty else { return }
        for mode in WheelMode.allCases where pressed.contains(settings.key(for: mode).flag) {
            wheel.show(mode: mode, urls: draggedURLs)
            return
        }
    }

    /// Codes des touches modificatrices (⇧ ⌘ ⌥ ⌃ gauche/droite, fn, verr. maj.).
    private static let modifierCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
    private static func nonModifierKeyDown() -> Bool {
        for code in 0..<128 where !modifierCodes.contains(code) {
            if CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code)) { return true }
        }
        return false
    }

    private func reset() {
        wheel.model.replacing = false
        otherKeyHeld = false
        internalDrag = false
        dragging = false
        draggedURLs = []
        timer?.invalidate()
        timer = nil
    }
}
