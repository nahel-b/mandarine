import SwiftUI
import AppKit

// MARK: Géométrie (repère : origine en haut à gauche, 700 × 452)
enum WiiLayout {
    static let size = CGSize(width: 700, height: 452)              // mise en page de référence
    static let scale: CGFloat = 0.78                              // taille d'affichage : 78 % de la mise en page
    static var displaySize: CGSize { CGSize(width: size.width * scale, height: size.height * scale) }
    static let tile = CGSize(width: 142, height: 96)
    static let gap: CGFloat = 14
    static let cols = 4
    static let originX: CGFloat = 45          // (700 − (4 × 142 + 3 × 14)) / 2
    static let originY: CGFloat = 26
    static let barTop: CGFloat = 366
    static let childTile = CGSize(width: 122, height: 80)

    static func slotRect(_ s: Int) -> CGRect {
        let c = s % cols, r = s / cols
        return CGRect(x: originX + CGFloat(c) * (tile.width + gap), y: originY + CGFloat(r) * (tile.height + gap), width: tile.width, height: tile.height)
    }
    /// Au-delà de 12 éléments, la 12ᵉ case devient la flèche « page suivante ».
    static func perPage(_ count: Int) -> Int { count > 12 ? 11 : 12 }
    static func pageCount(_ count: Int) -> Int { count > 12 ? Int((Double(count) / 11).rounded(.up)) : 1 }
    static func itemIndex(slot: Int, page: Int, count: Int) -> Int? {
        let per = perPage(count), i = page * per + slot
        return slot < per && i < count ? i : nil
    }
    static func navSlot(count: Int) -> Int? { count > 12 ? 11 : nil }

    /// Sous-éléments d'un groupe : une bulle de petites cases sous la case parent (au-dessus pour la dernière rangée).
    static func childRects(parentSlot: Int, count m: Int) -> [CGRect] {
        let p = slotRect(parentSlot)
        let total = CGFloat(m) * childTile.width + CGFloat(m - 1) * 10
        var x = p.midX - total / 2
        x = min(max(x, 22), size.width - 22 - total)
        let below = parentSlot / cols < 2
        let y = below ? p.maxY + 12 : p.minY - 12 - childTile.height
        return (0..<m).map { CGRect(x: x + CGFloat($0) * (childTile.width + 10), y: y, width: childTile.width, height: childTile.height) }
    }

    static func trayBounds(_ rects: [CGRect]) -> CGRect { rects.reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -12, dy: -12) }
}

// MARK: Textes de description
enum WiiText {
    static func description(_ item: WheelItem) -> String {
        if case .convert(let ext) = item.payload {
            return item.id == "multi-pdf" ? "Combine the selected images into one PDF, one page per image." : item.id == "m4r" ? "Save the start of the sound as an iPhone ringtone (.m4r), with a short fade out." : "Convert to \(ext.uppercased()). A new copy is saved next to the original."
        }
        let d: [String: String] = [
            "compress": "Reduce file size locally. The original stays untouched.",
            "metadata": "Inspect, change or remove the information hidden in a file.",
            "editImage": "Adjust light, color and detail with a live preview.",
            "annotateImage": "Mark up a photo with arrows, text, shapes and callouts.",
            "frameImage": "Place the photo on a gradient, a color or another image.",
            "removeBackground": "Cut the subject out. Soften edges, add a sticker outline.",
            "cropImage": "Choose the exact area and size to keep.",
            "resizeImage": "Set exact dimensions, a percentage, several sizes — or upscale with AI.",
            "rotateImage": "Rotate, flip and straighten with the EXIF orientation.",
            "redactImage": "Cover faces, text or any area with a color or blur.",
            "createCollage": "Arrange several images in one finished composition.",
            "trimVideo": "Keep one precise section of a video.",
            "cropVideo": "Reframe a video and keep its audio.",
            "changeVideoSpeed": "Create a slower or faster copy, keeping the pitch.",
            "joinVideos": "Arrange several clips and combine them into one MP4.",
            "videoSnapshots": "Pick exact frames and export them as full-size PNG.",
            "splitVideo": "Divide a video into clips at exact points.",
            "redactVideo": "Hide areas for all or part of a video.",
            "muteVideo": "Remove the audio track and keep the picture.",
            "extractAudio": "Save the audio track, without re-encoding when possible.",
            "encodeVideo": "Choose size, frame rate, quality or bitrate — like HandBrake. Colors preserved.",
            "normalizeAudio": "Bring a recording to a consistent loudness.",
            "audioToVideo": "Turn audio into a video with a waveform or an image.",
            "trimAudio": "Keep one section of a recording, with waveform control.",
            "audioChannels": "Convert to mono or stereo and set each channel's volume.",
            "redactAudio": "Replace sensitive parts of a recording with a bleep.",
            "mergePDF": "Combine several PDFs into one document.",
            "organizePDF": "Reorder, rotate, duplicate or remove pages visually.",
            "splitPDF": "Save every page as its own PDF.",
            "downloadMP4": "Download the video from this link. Playlists let you choose.",
            "downloadWAV": "Download the sound from this link as WAV, uncompressed. Playlists let you choose.",
            "downloadMP3": "Download the sound from this link as MP3. Playlists let you choose.",
            "ocr": "Read the text in a picture or a scanned PDF, then copy or save it.",
            "extractImages": "Save the pictures embedded in a PDF.",
            "extractArchive": "Unpack the archive next to itself.",
            "davinciTree": "Create a DaVinci Resolve project folder tree.",
            "openInCode": "Open in Visual Studio Code.",
            "bg": "Add a background to a photo, or remove the current one.",
            "transform": "Crop, resize, rotate and flip.",
            "edit": "Adjust the photo, annotate it or redact parts of it.",
            "quickSort": "Go through your photos and videos full screen, and mark each one Keep, Maybe or Reject.",
            "typeSelect": "Select files by extension, kind, Finder tag, size or date inside your selection.",
            "zipFiles": "Put the selected files and folders into one ZIP archive.",
            "translateText": "Translate the text into another language, on this Mac.",
            "summarizeText": "Summarize the text with the on-device Apple Intelligence model.",
            "speakText": "Read the text aloud with a voice in its language.",
            "searchWeb": "Search the web for this text.",
            "scanDocument": "Straighten a photo of a sheet of paper, clean it and save it as a PDF.",
            "document": "Scan a sheet of paper, or read the text of a picture.",
            "faceSelect": "Pick the people you want: files showing them are selected.",
            "select": "Select files by type or tag, by the people in them, or sort them one by one.",
            "vtransform": "Trim, crop, change the speed and redact.",
            "vaudio": "Mute the video or extract its audio.",
            "airDrop": "Share through the macOS recipient picker.",
            "float": "Park on a floating shelf and drag into another app.",
            "copy": "Copy to the clipboard, ready to paste in Finder.",
            "move": "Choose a destination folder and move the originals there.",
            "copyPath": "Copy the full path as text.",
            "terminal": "Open the folder in Terminal or iTerm2.",
            "switchView": "Switch the menu between the Wii screen and the wheel."
        ]
        return d[item.id] ?? item.caption
    }
}

// MARK: Horloge à segments
private struct SevenSegmentClock: View {
    let date: Date
    private static let masks: [[Bool]] = [   // a b c d e f g
        [true, true, true, true, true, true, false], [false, true, true, false, false, false, false], [true, true, false, true, true, false, true],
        [true, true, true, true, false, false, true], [false, true, true, false, false, true, true], [true, false, true, true, false, true, true],
        [true, false, true, true, true, true, true], [true, true, true, false, false, false, false], [true, true, true, true, true, true, true],
        [true, true, true, true, false, true, true]]

    var body: some View {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date), m = cal.component(.minute, from: date)      // 24 h
        let colon = cal.component(.second, from: date) % 2 == 0
        let digits: [Int?] = [h / 10, h % 10, m / 10, m % 10]
        return HStack(alignment: .bottom, spacing: 5) {
            Canvas { ctx, size in
                let w: CGFloat = 19, hgt = size.height, t: CGFloat = 4.2, gap: CGFloat = 6
                var x: CGFloat = 0
                func digit(_ d: Int?, at x: CGFloat) {
                    let mask = d.map { Self.masks[$0] } ?? [Bool](repeating: false, count: 7)
                    let mid = hgt / 2
                    let segs: [CGRect] = [
                        CGRect(x: x + t * 0.7, y: 0, width: w - t * 1.4, height: t),                      // a
                        CGRect(x: x + w - t, y: t * 0.7, width: t, height: mid - t * 1.2),                 // b
                        CGRect(x: x + w - t, y: mid + t * 0.5, width: t, height: mid - t * 1.2),           // c
                        CGRect(x: x + t * 0.7, y: hgt - t, width: w - t * 1.4, height: t),                 // d
                        CGRect(x: x, y: mid + t * 0.5, width: t, height: mid - t * 1.2),                   // e
                        CGRect(x: x, y: t * 0.7, width: t, height: mid - t * 1.2),                         // f
                        CGRect(x: x + t * 0.7, y: mid - t / 2, width: w - t * 1.4, height: t)]             // g
                    for (i, r) in segs.enumerated() {
                        let on = mask[i]
                        if d == nil { continue }
                        ctx.fill(Path(roundedRect: r, cornerRadius: t / 2), with: .color(Color(red: 0.56, green: 0.58, blue: 0.60).opacity(on ? 1 : 0.10)))
                    }
                }
                digit(digits[0], at: x); x += w + gap
                digit(digits[1], at: x); x += w + gap - 1
                for y in [hgt * 0.33, hgt * 0.67] where colon {
                    ctx.fill(Path(ellipseIn: CGRect(x: x + 1.5, y: y - 2.2, width: 4.4, height: 4.4)), with: .color(Color(red: 0.56, green: 0.58, blue: 0.60)))
                }
                x += 8
                digit(digits[2], at: x); x += w + gap
                digit(digits[3], at: x)
            }
            .frame(width: 19 * 4 + 6 * 3 + 12, height: 34)
        }
    }
}

// MARK: Formes
private struct WiiBar: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w * 0.20, y: 0))
        p.addCurve(to: CGPoint(x: w * 0.34, y: 34), control1: CGPoint(x: w * 0.26, y: 0), control2: CGPoint(x: w * 0.28, y: 34))
        p.addLine(to: CGPoint(x: w * 0.66, y: 34))
        p.addCurve(to: CGPoint(x: w * 0.80, y: 0), control1: CGPoint(x: w * 0.72, y: 34), control2: CGPoint(x: w * 0.74, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: r.height))
        p.addLine(to: CGPoint(x: 0, y: r.height))
        p.closeSubpath()
        return p
    }
}

private struct WiiBarLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w * 0.20, y: 0))
        p.addCurve(to: CGPoint(x: w * 0.34, y: 34), control1: CGPoint(x: w * 0.26, y: 0), control2: CGPoint(x: w * 0.28, y: 34))
        p.addLine(to: CGPoint(x: w * 0.66, y: 34))
        p.addCurve(to: CGPoint(x: w * 0.80, y: 0), control1: CGPoint(x: w * 0.72, y: 34), control2: CGPoint(x: w * 0.74, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        return p
    }
}

// MARK: Cases
private enum WiiPattern { case dots, rings, bubbles, waves, rays }
private enum WiiStyle: CaseIterable { case pastel, blue, green, teal, orange }

/// Les cases qui étaient simplement blanches reçoivent un pastel et un motif discret, différents selon l'outil.
private struct WiiPastel {
    let c1: Color, c2: Color, ink: Color
    let pattern: WiiPattern
    private static let sets: [((Double, Double, Double), (Double, Double, Double), (Double, Double, Double))] = [
        ((0.99, 0.93, 0.97), (0.96, 0.78, 0.90), (0.78, 0.25, 0.58)),     // rose
        ((0.93, 0.92, 1.00), (0.80, 0.78, 0.98), (0.40, 0.33, 0.80)),     // lilas
        ((0.90, 0.99, 0.94), (0.72, 0.93, 0.82), (0.12, 0.55, 0.38)),     // menthe
        ((0.91, 0.97, 1.00), (0.74, 0.90, 0.99), (0.10, 0.45, 0.78)),     // ciel
        ((1.00, 0.98, 0.88), (0.99, 0.90, 0.62), (0.65, 0.42, 0.04))]     // beurre
    private static let patterns: [WiiPattern] = [.dots, .bubbles, .rings, .waves]
    init(id: String) {
        let h = abs(id.unicodeScalars.reduce(5) { ($0 &* 31) &+ Int($1.value) })
        let t = Self.sets[h % Self.sets.count]
        c1 = Color(red: t.0.0, green: t.0.1, blue: t.0.2); c2 = Color(red: t.1.0, green: t.1.1, blue: t.1.2); ink = Color(red: t.2.0, green: t.2.1, blue: t.2.2)
        pattern = Self.patterns[(h / 5) % Self.patterns.count]
    }
}

private struct PatternLayer: View {
    let kind: WiiPattern
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            switch kind {
            case .dots:
                for (r, y) in stride(from: CGFloat(8), to: h, by: 13).enumerated() { for x in stride(from: CGFloat(r % 2 == 0 ? 8 : 14), to: w, by: 13) {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 2.2, y: y - 2.2, width: 4.4, height: 4.4)), with: .color(color)) } }
            case .rings:
                for r in stride(from: CGFloat(16), to: 170, by: 20) {
                    ctx.stroke(Path(ellipseIn: CGRect(x: w * 0.85 - r, y: h * 0.1 - r, width: r * 2, height: r * 2)), with: .color(color), lineWidth: 2.5)
                }
            case .bubbles:
                for i in 0..<8 {
                    let x = CGFloat((i * 53) % 100) / 100 * w, y = CGFloat((i * 37 + 11) % 100) / 100 * h, r = CGFloat(6 + (i * 7) % 14)
                    ctx.stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(color), lineWidth: 2)
                }
            case .rays:
                let c = CGPoint(x: w * 0.5, y: h * 1.2)
                for i in 0..<18 where i % 2 == 0 {
                    let a0 = Double(i) / 18 * .pi * 2, a1 = Double(i + 1) / 18 * .pi * 2
                    var p = Path(); p.move(to: c)
                    p.addLine(to: CGPoint(x: c.x + cos(a0) * 400, y: c.y + sin(a0) * 400)); p.addLine(to: CGPoint(x: c.x + cos(a1) * 400, y: c.y + sin(a1) * 400)); p.closeSubpath()
                    ctx.fill(p, with: .color(color))
                }
            case .waves:
                for row in 0..<5 {
                    var p = Path(); let y0 = h * (0.15 + 0.18 * CGFloat(row))
                    p.move(to: CGPoint(x: 0, y: y0))
                    for x in stride(from: CGFloat(0), through: w, by: 3) { p.addLine(to: CGPoint(x: x, y: y0 + sin((x / 14) + CGFloat(row)) * 4.5)) }
                    ctx.stroke(p, with: .color(color), lineWidth: 2.5)
                }
            }
        }
    }
}

private struct WiiTile: View {
    let item: WheelItem
    let index: Int
    let hovered: Bool
    var size = WiiLayout.tile
    var small = false

    private var style: WiiStyle { WiiStyle.allCases[index % WiiStyle.allCases.count] }
    private var pastel: WiiPastel { WiiPastel(id: item.id) }
    private var blue: Color { Color(red: 0.17, green: 0.63, blue: 0.88) }

    private var fill: LinearGradient {
        if !item.enabled { return LinearGradient(colors: [Color(white: 0.93), Color(white: 0.86)], startPoint: .top, endPoint: .bottom) }
        switch style {
        case .pastel: return LinearGradient(colors: [pastel.c1, pastel.c2], startPoint: .top, endPoint: .bottom)
        case .blue: return LinearGradient(colors: [Color(red: 0.36, green: 0.80, blue: 1.00), Color(red: 0.10, green: 0.42, blue: 0.96)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .green: return LinearGradient(colors: [Color(red: 0.62, green: 0.93, blue: 0.32), Color(red: 0.06, green: 0.62, blue: 0.40)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .teal: return LinearGradient(colors: [Color(red: 0.88, green: 0.97, blue: 0.98), Color(red: 0.62, green: 0.88, blue: 0.93)], startPoint: .top, endPoint: .bottom)
        case .orange: return LinearGradient(colors: [Color(red: 1.0, green: 0.93, blue: 0.80), Color(red: 0.98, green: 0.73, blue: 0.40)], startPoint: .top, endPoint: .bottom)
        }
    }
    private var textColor: Color {
        if !item.enabled { return Color(white: 0.55) }
        switch style {
        case .pastel: return pastel.ink
        case .blue, .green: return .white
        case .teal: return Color(red: 0.12, green: 0.45, blue: 0.62)
        case .orange: return Color(red: 0.62, green: 0.30, blue: 0.05)
        }
    }

    var body: some View {
        let isFormat = item.symbol == nil
        let r: CGFloat = small ? 13 : 17
        ZStack {
            RoundedRectangle(cornerRadius: r, style: .continuous).fill(fill)
            if item.enabled && style == .pastel {
                PatternLayer(kind: pastel.pattern, color: pastel.ink.opacity(0.13)).clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
            }
            // bleu : rayons ou bulles ; vert : ondes ou points — blancs, discrets
            if item.enabled && (style == .blue || style == .green) {
                let h = abs(item.id.unicodeScalars.reduce(3) { ($0 &* 31) &+ Int($1.value) })
                let kind: WiiPattern = style == .blue ? (h % 2 == 0 ? .rays : .bubbles) : (h % 2 == 0 ? .waves : .dots)
                PatternLayer(kind: kind, color: Color.white.opacity(0.17)).clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
            }
            // motif de losanges pour les variantes « teal » et « orange »
            if item.enabled && (style == .teal || style == .orange) {
                Canvas { ctx, sz in
                    let s: CGFloat = 22
                    for y in stride(from: 0, to: sz.height + s, by: s) { for x in stride(from: 0, to: sz.width + s, by: s) {
                        var p = Path(); p.move(to: CGPoint(x: x, y: y - 7)); p.addLine(to: CGPoint(x: x + 7, y: y)); p.addLine(to: CGPoint(x: x, y: y + 7)); p.addLine(to: CGPoint(x: x - 7, y: y)); p.closeSubpath()
                        ctx.fill(p, with: .color((style == .teal ? Color(red: 0.2, green: 0.7, blue: 0.85) : Color(red: 0.97, green: 0.55, blue: 0.2)).opacity(0.22)))
                    } }
                }.clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
            }
            VStack(spacing: small ? 3 : 5) {
                if let s = item.symbol { Image(systemName: s).font(.system(size: small ? 20 : 30, weight: .regular)) }
                Text(isFormat ? item.label : tidy(item.caption))
                    .font(.system(size: isFormat ? (small ? 20 : 30) : (small ? 11 : 13), weight: .bold, design: .rounded))
                    .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
            }
            .foregroundStyle(textColor).padding(.horizontal, 8)
            .shadow(color: (style == .blue || style == .green) && item.enabled ? Color.black.opacity(0.30) : .clear, radius: 1.5, y: 1)
            // reflet
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.42), Color.white.opacity(0.0)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.5)))
                .allowsHitTesting(false)
            // liseré : gris glacé, bleu clair au survol
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .strokeBorder(hovered ? AnyShapeStyle(blue) : AnyShapeStyle(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.62)], startPoint: .top, endPoint: .bottom)), lineWidth: hovered ? 4 : 3)
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: hovered ? blue.opacity(0.55) : Color.black.opacity(0.16), radius: hovered ? 12 : 4, y: hovered ? 0 : 2)
        .scaleEffect(hovered ? 1.05 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: hovered)
    }

    private func tidy(_ s: String) -> String { s.replacingOccurrences(of: "Convert to ", with: "") }
}

// MARK: Curseur « main »
private struct WiiHand: View {
    var body: some View {
        ZStack {
            Image(systemName: "hand.point.up.left.fill").font(.system(size: 44)).foregroundStyle(Color(white: 0.45)).blur(radius: 0.6)
            Image(systemName: "hand.point.up.left.fill").font(.system(size: 40)).foregroundStyle(
                LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .top, endPoint: .bottom))
            ZStack {
                Circle().fill(Color(red: 0.34, green: 0.72, blue: 0.93))
                Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                Text("1").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            }.frame(width: 17, height: 17).offset(x: 6, y: 13)
        }
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

// MARK: Écran
struct WiiMenuView: View {
    @ObservedObject var model: WheelModel
    @ObservedObject private var settings = AppSettings.shared
    private let blue = Color(red: 0.17, green: 0.63, blue: 0.88)
    private let ink = Color(red: 0.56, green: 0.58, blue: 0.60)

    private var per: Int { WiiLayout.perPage(model.items.count) }
    private var parentSlot: Int? { model.hover.map { $0 - model.wiiPage * per } }
    private var hoveredItem: WheelItem? {
        guard let h = model.hover, model.items.indices.contains(h) else { return nil }
        let p = model.items[h]
        if let c = model.hoverChild, p.children.indices.contains(c) { return p.children[c] }
        return p
    }
    private var modeSymbol: String { model.mode == .convert ? "⇧" : (model.mode == .tools ? "⌘" : "⌃") }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            // grille
            ForEach(0..<12, id: \.self) { slot in
                if let i = WiiLayout.itemIndex(slot: slot, page: model.wiiPage, count: model.items.count) {
                    WiiTile(item: model.items[i], index: i, hovered: model.hover == i && model.hoverChild == nil)
                        .position(x: WiiLayout.slotRect(slot).midX, y: WiiLayout.slotRect(slot).midY)
                } else if slot == WiiLayout.navSlot(count: model.items.count) {
                    nav.position(x: WiiLayout.slotRect(slot).midX, y: WiiLayout.slotRect(slot).midY)
                } else {
                    RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Color.black.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(Color.black.opacity(0.06), lineWidth: 2))
                        .frame(width: WiiLayout.tile.width, height: WiiLayout.tile.height)
                        .position(x: WiiLayout.slotRect(slot).midX, y: WiiLayout.slotRect(slot).midY)
                }
            }
            tray
            bar
            if let c = model.cursor { WiiHand().position(x: c.x + 15, y: c.y + 18).allowsHitTesting(false) }
        }
        .frame(width: WiiLayout.size.width, height: WiiLayout.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.85), lineWidth: 2))
        .scaleEffect(WiiLayout.scale, anchor: .topLeading)
        .frame(width: WiiLayout.displaySize.width, height: WiiLayout.displaySize.height, alignment: .topLeading)
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .scaleEffect(model.appear ? 1 : 0.94).opacity(model.appear ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: model.appear)
        .environment(\.colorScheme, .light)
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.97, green: 0.97, blue: 0.98), Color(red: 0.90, green: 0.91, blue: 0.93)], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                for y in stride(from: 0, to: size.height, by: 3) { ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Color.black.opacity(0.025))) }
            }
        }
    }

    private var nav: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 17, style: .continuous).fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.88)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(model.wiiNav ? blue : Color(white: 0.7), lineWidth: model.wiiNav ? 4 : 3)
            VStack(spacing: 4) {
                Image(systemName: "arrowtriangle.right.fill").font(.system(size: 30)).foregroundStyle(blue)
                Text("\(model.wiiPage + 1) / \(WiiLayout.pageCount(model.items.count))").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(ink)
            }
        }
        .frame(width: WiiLayout.tile.width, height: WiiLayout.tile.height)
        .scaleEffect(model.wiiNav ? 1.05 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: model.wiiNav)
    }

    @ViewBuilder private var tray: some View {
        if let h = model.hover, model.items.indices.contains(h), model.items[h].isGroup, let slot = parentSlot, (0..<12).contains(slot) {
            let parent = model.items[h]
            let rects = WiiLayout.childRects(parentSlot: slot, count: parent.children.count)
            let b = WiiLayout.trayBounds(rects)
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.97))
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(blue, lineWidth: 3)
            }
            .frame(width: b.width, height: b.height).shadow(color: .black.opacity(0.3), radius: 14, y: 6)
            .position(x: b.midX, y: b.midY)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
            ForEach(Array(parent.children.enumerated()), id: \.element.id) { ci, child in
                WiiTile(item: child, index: ci + 1, hovered: model.hoverChild == ci, size: WiiLayout.childTile, small: true)
                    .position(x: rects[ci].midX, y: rects[ci].midY)
            }
        }
    }

    private var bar: some View {
        let h = WiiLayout.size.height - WiiLayout.barTop
        return ZStack(alignment: .topLeading) {
            WiiBar().fill(LinearGradient(colors: [.white, Color(white: 0.89)], startPoint: .top, endPoint: .bottom))
                .frame(width: WiiLayout.size.width, height: h)
                .shadow(color: .black.opacity(0.10), radius: 5, y: -2)
            WiiBarLine().stroke(blue, lineWidth: 2.5).frame(width: WiiLayout.size.width, height: h)
            // horloge (dans la courbe) + date ou description
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                SevenSegmentClock(date: ctx.date).position(x: WiiLayout.size.width / 2, y: 12)
            }
            descriptionArea.position(x: WiiLayout.size.width / 2, y: 62)
            // gauche : bouton de mode + carte SD (infos du fichier)
            roundButton { Text(modeSymbol).font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(ink) }.position(x: 62, y: 46)
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "sdcard.fill").font(.system(size: 20)).foregroundStyle(blue)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.infoLines.prefix(3).enumerated()), id: \.offset) { i, l in
                        Text(l).font(.system(size: i == 0 ? 10.5 : 8.5, weight: i == 0 ? .bold : .medium, design: .rounded)).foregroundStyle(ink).lineLimit(1)
                    }
                }
            }.frame(width: 140, alignment: .leading).position(x: 186, y: 50)
            // droite : enveloppe avec le nombre de fichiers
            roundButton {
                VStack(spacing: 0) {
                    Image(systemName: "envelope.fill").font(.system(size: 22)).foregroundStyle(Color(white: 0.62))
                    Text("\(model.fileCount)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(ink)
                }
            }.position(x: WiiLayout.size.width - 62, y: 46)
        }
        .frame(width: WiiLayout.size.width, height: h)
        .position(x: WiiLayout.size.width / 2, y: WiiLayout.barTop + h / 2)
    }

    private func roundButton<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(blue.opacity(0.9), lineWidth: 3)
            content()
        }.frame(width: 58, height: 58).shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }

    @ViewBuilder private var descriptionArea: some View {
        if let item = hoveredItem {
            VStack(spacing: 2) {
                Text(item.caption).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(blue)
                Text(WiiText.description(item)).font(.system(size: 9.5, weight: .medium, design: .rounded)).foregroundStyle(ink)
                    .multilineTextAlignment(.center).lineLimit(2).frame(width: 330)
            }
            .transition(.opacity)
            .id(item.id)
        } else {
            Text(Self.dateText).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(ink)
        }
    }

    static var dateText: String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEEMd"); return f.string(from: Date())
    }
}

// MARK: Réception du glisser-déposer
final class WiiDropView: NSView {
    weak var controller: WheelController?
    override var isFlipped: Bool { true }              // origine en haut à gauche, comme SwiftUI

    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL, .URL, .string]) }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { self }

    private func update(_ info: NSDraggingInfo) -> NSDragOperation {
        let p = convert(info.draggingLocation, from: nil)
        controller?.wiiHover(at: CGPoint(x: p.x / WiiLayout.scale, y: p.y / WiiLayout.scale))
        return controller?.hoveredItemEnabled == true ? .copy : []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { controller?.wiiExited() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { controller?.hoveredItemEnabled == true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { _ = update(sender); return controller?.drop() ?? false }
    override func mouseUp(with event: NSEvent) { controller?.dismiss() }
}

/// Banc d'essai visuel (snapshots) : une case par motif.
struct WiiTilesDebug: View {
    var body: some View {
        let ids = ["compress", "metadata", "editImage", "transform", "annotateImage", "frameImage", "redactImage", "resizeImage"]
        HStack(alignment: .top, spacing: 14) {
            ForEach(Array(ids.enumerated()), id: \.offset) { i, id in
                WiiTile(item: WheelItem(id: id, label: id, caption: id, symbol: "star.fill", payload: .tool(.compress)), index: i, hovered: false)
            }
        }.padding(20)
    }
}
