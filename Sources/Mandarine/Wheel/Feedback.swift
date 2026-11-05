import AppKit
import AVFoundation

/// Retour haptique (trackpad) + petit son, à l'apparition de la roue et à chaque segment survolé.
/// Son : `HighlightSound.wav|mp3` dans Resources de l'app ou dans ~/Library/Application Support/Mandarine/,
/// sinon un « tick » synthétisé.
final class Feedback {
    static let shared = Feedback()
    private var players: [AVAudioPlayer] = []
    private var dropPlayers: [AVAudioPlayer] = []
    private var dropNext = 0
    private var next = 0
    private var lastPlay = Date.distantPast
    // sons du style « Wii » : survol, relâchement, ouverture
    private var wiiHover: [AVAudioPlayer] = [], wiiDrop: [AVAudioPlayer] = [], wiiOpen: [AVAudioPlayer] = []
    private var wiiHoverNext = 0
    private var wiiTool: [AVAudioPlayer] = [], wiiDoneP: [AVAudioPlayer] = [], wiiCloseP: [AVAudioPlayer] = [], wiiBtnHoverP: [AVAudioPlayer] = [], wiiPressP: [AVAudioPlayer] = [], wiiReleaseP: [AVAudioPlayer] = [], wiiSlideP: [AVAudioPlayer] = []
    private var lastSlide = Date.distantPast, lastBtnHover = Date.distantPast
    private var isWii: Bool { AppSettings.shared.appearance == .wii }

    private init() {
        let data = Feedback.loadCustomSound() ?? Feedback.synthesizedTick()
        for _ in 0..<4 {
            if let p = try? AVAudioPlayer(data: data) {
                p.volume = 0.5
                p.prepareToPlay()
                players.append(p)
            }
        }
        func pool(_ name: String, _ n: Int, _ volume: Float) -> [AVAudioPlayer] {
            guard let d = Feedback.loadSound([name]) else { return [] }
            return (0..<n).compactMap { _ in (try? AVAudioPlayer(data: d)).map { $0.volume = volume; $0.prepareToPlay(); return $0 } }
        }
        wiiHover = pool("WiiHover.mp3", 4, 0.6); wiiDrop = pool("WiiDrop.mp3", 2, 0.7); wiiOpen = pool("WiiOpen.mp3", 2, 0.28)
        // Écran Wii : ouverture d'un outil (fichier fourni), puis clic, relâchement et curseur qui glisse sur les réglages des outils (synthétisés, sauf fichier WiiClick/WiiRelease/WiiSlide)
        wiiTool = pool("WiiTool.mp3", 2, 0.6)
        wiiDoneP = pool("WiiDone.mp3", 2, 0.6)
        wiiCloseP = pool("WiiClose.mp3", 2, 0.6)
        wiiBtnHoverP = pool("WiiButtonHover.mp3", 3, 0.5)
        func tone(_ names: [String], _ freqs: [(Double, Double)], _ dur: Double, _ decay: Double, _ n: Int, _ volume: Float) -> [AVAudioPlayer] {
            let d = Feedback.loadSound(names) ?? Feedback.synthesized(freqs, duration: dur, decay: decay)
            return (0..<n).compactMap { _ in (try? AVAudioPlayer(data: d)).map { $0.volume = volume; $0.prepareToPlay(); return $0 } }
        }
        wiiPressP = tone(["WiiClick.mp3", "WiiClick.wav"], [(1150, 0.65), (2300, 0.35)], 0.07, 55, 3, 0.6)
        wiiReleaseP = tone(["WiiRelease.mp3", "WiiRelease.wav"], [(1750, 0.65), (3500, 0.35)], 0.05, 85, 3, 0.32)
        wiiSlideP = tone(["WiiSlide.mp3", "WiiSlide.wav"], [(2700, 1.0)], 0.025, 170, 4, 0.22)
        if let d = Feedback.loadSound(["DropSound.mp3", "DropSound.wav"]) {
            for _ in 0..<2 { if let p = try? AVAudioPlayer(data: d) { p.volume = 0.6; p.prepareToPlay(); dropPlayers.append(p) } }
        }
    }

    /// Dépôt sur un segment : son de relâchement + haptique « succès » (différent du hover).
    func drop() {
        let h = NSHapticFeedbackManager.defaultPerformer
        h.perform(.levelChange, performanceTime: .now)
        h.perform(.generic, performanceTime: .default)
        if isWii, let p = wiiDrop.first(where: { !$0.isPlaying }) ?? wiiDrop.first { p.currentTime = 0; p.play(); return }
        guard !dropPlayers.isEmpty else { return }
        let p = dropPlayers[dropNext % dropPlayers.count]
        dropNext += 1
        p.currentTime = 0
        p.play()
    }

    private func playFirst(_ pool: [AVAudioPlayer]) {
        guard let p = pool.first(where: { !$0.isPlaying }) ?? pool.first else { return }
        p.currentTime = 0; p.play()
    }

    /// Ouverture d'un outil dans l'écran Wii.
    func toolOpen() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        if wiiTool.isEmpty { drop() } else { playFirst(wiiTool) }
    }
    /// Retour de l'outil à l'accueil (« Wii Menu ») ou fermeture de l'écran.
    func wiiClose() { playFirst(wiiCloseP) }
    /// Le pointeur arrive sur un bouton ou un choix d'un outil.
    func wiiButtonHover() {
        guard Date().timeIntervalSince(lastBtnHover) > 0.06 else { return }
        lastBtnHover = Date(); playFirst(wiiBtnHoverP)
    }

    /// Un travail s'est terminé avec succès : même son pour tous les styles de menu.
    func done() { playFirst(wiiDoneP) }

    /// Appui sur un élément d'un outil (bouton, case, curseur…), relâchement, et déplacement d'un curseur ou d'une poignée.
    func wiiPress() { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now); playFirst(wiiPressP) }
    func wiiRelease() { playFirst(wiiReleaseP) }
    func wiiSlide() {
        guard Date().timeIntervalSince(lastSlide) > 0.045 else { return }
        lastSlide = Date(); playFirst(wiiSlideP)
    }

    /// Apparition de la roue / de l'écran : son d'ouverture en style Wii, sinon le « tick » habituel.
    func open() {
        guard isWii else { tick(); return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        if let p = wiiOpen.first(where: { !$0.isPlaying }) ?? wiiOpen.first { p.currentTime = 0; p.play() }
    }

    func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        if isWii, !wiiHover.isEmpty {
            guard Date().timeIntervalSince(lastPlay) > 0.04 else { return }
            lastPlay = Date()
            let p = wiiHover[wiiHoverNext % wiiHover.count]; wiiHoverNext += 1
            p.currentTime = 0; p.play(); return
        }
        guard !players.isEmpty, Date().timeIntervalSince(lastPlay) > 0.02 else { return }
        lastPlay = Date()
        let p = players[next % players.count]
        next += 1
        p.currentTime = 0
        p.play()
    }

    private static func loadCustomSound() -> Data? {
        loadSound(["HoverSound.mp3", "HoverSound.wav", "HighlightSound.wav", "HighlightSound.mp3"])
    }

    /// Cherche un fichier son dans Resources de l'app, puis dans ~/Library/Application Support/Mandarine/.
    private static func loadSound(_ names: [String]) -> Data? {
        var dirs: [URL] = []
        if let r = Bundle.main.resourceURL { dirs.append(r) }
        if let s = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            dirs.append(s.appendingPathComponent("Mandarine"))
        }
        for d in dirs {
            for n in names {
                if let data = try? Data(contentsOf: d.appendingPathComponent(n)) { return data }
            }
        }
        return nil
    }

    private static func synthesizedTick() -> Data { synthesized([(1900, 0.7), (3800, 0.3)], duration: 0.05, decay: 90) }

    /// WAV mono 16 bits, 44,1 kHz : quelques sinusoïdes (fréquence, poids) très brèves à décroissance exponentielle.
    static func synthesized(_ tones: [(Double, Double)], duration: Double, decay: Double) -> Data {
        let rate = 44100, n = Int(Double(rate) * duration)
        var pcm = [Int16](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / Double(rate)
            let env = exp(-t * decay)
            let v = tones.reduce(0.0) { $0 + sin(2 * .pi * $1.0 * t) * $1.1 } * env
            pcm[i] = Int16(max(-1, min(1, v)) * 0.6 * Double(Int16.max))
        }
        func le32(_ v: Int) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        func le16(_ v: Int) -> [UInt8] { (0..<2).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        var d = Data("RIFF".utf8)
        d.append(contentsOf: le32(36 + n * 2)); d.append(Data("WAVEfmt ".utf8))
        d.append(contentsOf: le32(16)); d.append(contentsOf: le16(1)); d.append(contentsOf: le16(1))
        d.append(contentsOf: le32(rate)); d.append(contentsOf: le32(rate * 2)); d.append(contentsOf: le16(2)); d.append(contentsOf: le16(16))
        d.append(Data("data".utf8)); d.append(contentsOf: le32(n * 2))
        pcm.withUnsafeBytes { d.append(contentsOf: $0) }
        return d
    }
}
