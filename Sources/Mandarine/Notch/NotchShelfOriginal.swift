import SwiftUI

// Quatre designs d'étagère « maison » : ils reprennent le langage visuel de Mandarine
// (pétales de verre de la roue, cases à motifs et liseré bleu de la Wii, capsules des notifications, onglet bleu des outils).

// MARK: Motifs des cases Wii

private enum ShelfPattern { case dots, rings, diamonds, rays, waves }

private struct ShelfPatternLayer: View {
    let kind: ShelfPattern
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            switch kind {
            case .dots:
                for y in stride(from: 8.0, to: size.height + 14, by: 14) { for x in stride(from: 8.0, to: size.width + 14, by: 14) {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)), with: .color(color))
                } }
            case .rings:
                for (i, r) in [10.0, 22.0, 34.0, 46.0].enumerated() {
                    ctx.stroke(Path(ellipseIn: CGRect(x: size.width * 0.82 - r, y: size.height * 0.2 - r, width: r * 2, height: r * 2)), with: .color(color), lineWidth: i % 2 == 0 ? 2 : 1.2)
                }
            case .diamonds:
                let s: CGFloat = 22
                for y in stride(from: 0, to: size.height + s, by: s) { for x in stride(from: 0, to: size.width + s, by: s) {
                    var p = Path(); p.move(to: CGPoint(x: x, y: y - 7)); p.addLine(to: CGPoint(x: x + 7, y: y)); p.addLine(to: CGPoint(x: x, y: y + 7)); p.addLine(to: CGPoint(x: x - 7, y: y)); p.closeSubpath()
                    ctx.fill(p, with: .color(color))
                } }
            case .rays:
                let c = CGPoint(x: size.width / 2, y: size.height * 0.5)
                for i in 0..<14 {
                    let a = Double(i) / 14 * .pi * 2
                    var p = Path(); p.move(to: c)
                    p.addLine(to: CGPoint(x: c.x + cos(a) * 140, y: c.y + sin(a) * 140)); p.addLine(to: CGPoint(x: c.x + cos(a + 0.12) * 140, y: c.y + sin(a + 0.12) * 140)); p.closeSubpath()
                    ctx.fill(p, with: .color(color))
                }
            case .waves:
                for k in 0..<4 {
                    var p = Path(); let y0 = 10 + CGFloat(k) * 18
                    p.move(to: CGPoint(x: 0, y: y0))
                    for x in stride(from: CGFloat(0), through: size.width, by: 4) { p.addLine(to: CGPoint(x: x, y: y0 + CGFloat(Foundation.sin(Double(x) / 9)) * 4)) }
                    ctx.stroke(p, with: .color(color), lineWidth: 1.6)
                }
            }
        }
    }
}

private extension ShelfKind {
    /// Look de case à la Wii : dégradé, motif, encre.
    var wii: (top: Color, bottom: Color, ink: Color, pattern: ShelfPattern, light: Bool) {
        switch self {
        case .image: return (Color(red: 0.93, green: 0.92, blue: 1.0), Color(red: 0.80, green: 0.78, blue: 0.98), Color(red: 0.40, green: 0.33, blue: 0.80), .rings, true)
        case .pdf: return (Color(red: 0.88, green: 0.97, blue: 0.98), Color(red: 0.62, green: 0.88, blue: 0.93), Color(red: 0.12, green: 0.45, blue: 0.62), .diamonds, true)
        case .video: return (Color(red: 0.36, green: 0.80, blue: 1.0), Color(red: 0.10, green: 0.42, blue: 0.96), .white, .rays, false)
        case .audio: return (Color(red: 0.62, green: 0.93, blue: 0.32), Color(red: 0.06, green: 0.62, blue: 0.40), .white, .waves, false)
        case .link: return (Color(red: 1.0, green: 0.93, blue: 0.80), Color(red: 0.98, green: 0.73, blue: 0.40), Color(red: 0.62, green: 0.30, blue: 0.05), .diamonds, true)
        case .text: return (Color(red: 1.0, green: 0.98, blue: 0.88), Color(red: 0.99, green: 0.90, blue: 0.62), Color(red: 0.65, green: 0.42, blue: 0.04), .dots, true)
        case .other: return (Color(white: 0.96), Color(white: 0.82), Color(white: 0.35), .dots, true)
        }
    }
}

private let wiiBlue = Color(red: 0.17, green: 0.63, blue: 0.88)
private let wiiBlueLight = Color(red: 0.49, green: 0.78, blue: 0.93)

/// Une case de chaîne Wii pour un élément de l'étagère.
private struct ShelfChannelTile: View {
    let item: ShelfItem
    var hovered = false
    var selected = false
    var w: CGFloat = 80, h: CGFloat = 58
    var body: some View {
        let look = item.kind.wii
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinearGradient(colors: [look.top, look.bottom], startPoint: .top, endPoint: .bottom))
            ShelfPatternLayer(kind: look.pattern, color: (look.light ? look.ink : Color.white).opacity(look.light ? 0.13 : 0.18)).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(spacing: 2) {
                Image(systemName: item.kind.symbol).font(.system(size: 17))
                Text(item.name).font(.system(size: 10.5, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(look.ink).padding(.horizontal, 6)
            .shadow(color: look.light ? .clear : Color.black.opacity(0.3), radius: 1.5, y: 1)
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinearGradient(colors: [Color.white.opacity(0.42), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.5)))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? AnyShapeStyle(Theme.orange) : (hovered ? AnyShapeStyle(wiiBlue) : AnyShapeStyle(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.62)], startPoint: .top, endPoint: .bottom))), lineWidth: selected || hovered ? 3.5 : 2.5)
        }
        .frame(width: w, height: h)
        .scaleEffect(hovered || selected ? 1.04 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: hovered)
    }
}

// MARK: O1 · pétales

/// L'étagère en demi-roue sous l'encoche : chaque élément est un pétale de verre, la pastille du centre dit ce qu'on survole.
struct ShelfPetalsPanel: View {
    @ObservedObject var store: ShelfStore
    var open = true                 // faux : les pétales sont rentrés vers l'encoche
    @State private var hover: UUID?
    @State private var selection: Set<UUID>
    @State private var anchor: UUID?
    private var items: [ShelfItem] { store.items }

    init(store: ShelfStore, state: ShelfState = .filled, open: Bool = true) {
        self.store = store; self.open = open
        _selection = State(initialValue: state == .action ? Set(store.items.prefix(2).map(\.id)) : [])
    }

    private let center = CGPoint(x: 220, y: 16), radius: CGFloat = 150
    private var chosen: [ShelfItem] { items.filter { selection.contains($0.id) } }
    private var current: ShelfItem? { items.first { $0.id == hover } ?? (chosen.count == 1 ? chosen.first : nil) }
    private func click(_ id: UUID, _ f: NSEvent.ModifierFlags) { ShelfSelecting.click(id, f, order: Array(items.prefix(8)).map(\.id), selection: &selection, anchor: &anchor) }
    private func group(_ it: ShelfItem) -> [ShelfItem] { selection.contains(it.id) && selection.count > 1 ? chosen : [it] }

    private func target(_ i: Int) -> CGPoint {
        let a = (12.0 + Double(i) * 156.0 / 7.0) * .pi / 180
        return CGPoint(x: center.x + CGFloat(cos(a)) * radius, y: center.y + CGFloat(sin(a)) * radius)
    }
    /// Fermé, chaque pétale est replié vers l'encoche, sur son propre rayon.
    private func position(_ i: Int) -> CGPoint {
        let t = target(i)
        return open ? t : CGPoint(x: center.x + (t.x - center.x) * 0.25, y: center.y + (t.y - center.y) * 0.25)
    }

    /// Pas de fond : seulement un voile très doux autour de l'arc (pour rester lisible sur un fond clair), qui s'efface avant les bords.
    private var halo: some View {
        Circle().fill(RadialGradient(colors: [Color.black.opacity(0.34), Color.black.opacity(0.18), Color.black.opacity(0)], center: .center, startRadius: 30, endRadius: 215))
            .frame(width: 440, height: 440).position(x: center.x, y: center.y)
            .opacity(open ? 1 : 0).animation(.easeOut(duration: 0.18), value: open)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            halo
            ForEach(0..<8, id: \.self) { i in slot(i) }
            centerPill.position(x: center.x, y: 92).opacity(open ? 1 : 0).scaleEffect(open ? 1 : 0.6, anchor: .top).animation(.spring(response: 0.3, dampingFraction: 0.82), value: open)
        }
        .frame(width: 440, height: 220, alignment: .topLeading)
        .foregroundStyle(Color.white).environment(\.colorScheme, .dark)
    }

    /// Les éléments se placent au milieu de l'arc, le plus récent à gauche ; l'étagère vide montre les huit places en pointillés.
    @ViewBuilder private func slot(_ i: Int) -> some View {
        let n = min(items.count, 8), first = (8 - n) / 2
        let k = 7 - i - first                      // rang de l'élément (0 = le plus récent) dans cette place
        Group {
            if k >= 0 && k < n {
                petal(items[k])
            } else if items.isEmpty {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    .frame(width: 46, height: 46)
            }
        }
        .scaleEffect(open ? 1 : 0.4).opacity(open ? 1 : 0)
        .position(position(i))
        .animation(open ? .spring(response: 0.3, dampingFraction: 0.84).delay(Double(i) * 0.025) : .easeOut(duration: 0.12), value: open)
    }

    private func petal(_ it: ShelfItem) -> some View {
        let active = selection.contains(it.id), hot = hover == it.id
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        return ZStack {
            shape.fill(Color.black.opacity(active ? 0 : 0.5))                                   // fond sombre translucide : lisible sans panneau derrière
            shape.fill(LinearGradient(colors: active ? [Theme.orange.opacity(0.95), Theme.orange] : [Color.white.opacity(hot ? 0.28 : 0.17), Color.white.opacity(hot ? 0.14 : 0.07)], startPoint: .top, endPoint: .bottom))
            shape.stroke(active ? Color.white.opacity(0.6) : Color.white.opacity(hot ? 0.5 : 0.3), lineWidth: active ? 1.6 : 1)
            Image(systemName: it.kind.symbol).font(.system(size: 17, weight: .semibold))
        }
        .frame(width: 46, height: 46)
        .shadow(color: active ? Theme.orange.opacity(0.55) : Color.black.opacity(0.25), radius: active ? 10 : 5, y: active ? 0 : 2)
        .scaleEffect(active || hot ? 1.06 : 1)
        .animation(.easeOut(duration: 0.1), value: hover)
        .overlay(ShelfDragSource(item: it, group: group(it), onClick: { click(it.id, $0) }, onHover: { hover = $0 ? it.id : (hover == it.id ? nil : hover) }))
    }

    @ViewBuilder private var centerPill: some View {
        if !selection.isEmpty, hover == nil || selection.contains(hover!) {
            VStack(spacing: 5) {
                if chosen.count > 1 { Text(L("\(chosen.count) items selected")).font(.system(size: 11, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 2).background(Capsule().fill(Color.black.opacity(0.55))) }
                HStack(spacing: 8) {
                    ForEach(["eye", "doc.on.doc", "trash"], id: \.self) { s in
                        Image(systemName: s).font(.system(size: 13, weight: .semibold)).frame(width: 34, height: 34)
                            .background(Circle().fill(s == "trash" ? Color.black.opacity(0.5) : Theme.orange.opacity(s == "eye" ? 1 : 0.7)))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.3)))
                            .help(s == "eye" ? L("Locate") : (s == "trash" ? L("Remove") : L("Copy")))
                            .onTapGesture {
                                switch s {
                                case "eye": ShelfActions.reveal(chosen)
                                case "doc.on.doc": ShelfActions.copy(chosen)
                                default: store.remove(selection); selection = []; anchor = nil; ShelfSound.remove()
                                }
                            }
                    }
                }
            }
        } else {
            VStack(spacing: 2) {
                if let it = current { Text(it.name).font(.system(size: 13, weight: .semibold)).lineLimit(1); Text(it.detail).font(.system(size: 11)).foregroundStyle(Color(white: 0.82)).lineLimit(1) }
                else if items.isEmpty { Text(L("Drop here")).font(.system(size: 13, weight: .semibold)); Text(L("Items appear around")).font(.system(size: 11)).foregroundStyle(Color(white: 0.82)) }
                else { Text(L("\(items.count) items")).font(.system(size: 13, weight: .semibold)); Text(L("Drag one out")).font(.system(size: 11)).foregroundStyle(Color(white: 0.82)) }
            }
            .frame(width: 140, height: 46)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.5)).overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.08))).overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.28))))
            .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
        }
    }
}

// MARK: Ouverture au survol

/// Garde l'étagère ouverte tant que la souris reste dans la zone (même entre deux pétales) ; elle se referme un instant après qu'on en sort.
/// Fermée, seule la petite zone de l'encoche réagit.
struct ShelfHoverHost<Content: View>: View {
    var openSize = CGSize(width: 460, height: 236)
    var closedSize = CGSize(width: 240, height: 36)
    var startOpen = false
    @ViewBuilder let content: (Bool) -> Content
    @State private var open = false
    @State private var pending: DispatchWorkItem?

    var body: some View {
        ZStack(alignment: .top) {
            content(open)
            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black).frame(width: 130, height: 24).offset(y: -2)      // l'encoche
            if !open { Capsule().fill(Theme.orange).frame(width: 50, height: 2).opacity(0.55).offset(y: 24) }                      // le repère, tout discret
        }
        .frame(width: open ? openSize.width : closedSize.width, height: open ? openSize.height : closedSize.height, alignment: .top)
        .contentShape(Rectangle())
        .onHover { inside in
            pending?.cancel()
            let w = DispatchWorkItem { withAnimation(.easeOut(duration: 0.12)) { open = inside } }
            pending = w
            DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.08 : 0.35), execute: w)      // entrer : presque tout de suite ; sortir : un délai de grâce
        }
        .onAppear { open = startOpen }
    }
}

// MARK: O2 · chaînes Wii (écran à tube)

/// L'étagère comme le menu Wii de l'app : cases à motifs, places vides en relief, et la barre du bas (carte SD, horloge à segments, date,
/// boutons ronds). Le tout derrière une vitre de tube cathodique : lignes de balayage, bords sombres, reflet. À l'ouverture l'écran
/// « s'allume » depuis son milieu : un trait horizontal s'étire, puis l'image se déploie.
struct ShelfChannelsPanel: View {
    @ObservedObject var store: ShelfStore
    var open = true
    @State private var hover: UUID?
    @State private var selection: Set<UUID>
    @State private var anchor: UUID?
    @State private var sx: CGFloat
    @State private var sy: CGFloat
    @State private var flash = 0.0
    private var items: [ShelfItem] { store.items }
    private let ink = Color(red: 0.56, green: 0.58, blue: 0.60)

    init(store: ShelfStore, state: ShelfState = .filled, open: Bool = true) {
        self.store = store; self.open = open
        _selection = State(initialValue: state == .action ? Set(store.items.prefix(2).map(\.id)) : [])
        _sx = State(initialValue: open ? 1 : 0.02); _sy = State(initialValue: open ? 1 : 0.02)
    }

    var body: some View {
        screen
            .frame(width: 380, height: 252)
            .clipShape(NotchShape(radius: 34))
            .overlay(NotchShape(radius: 34).fill(Color.white.opacity(flash)).allowsHitTesting(false))          // le coup de lumière de l'allumage
            .scaleEffect(x: sx, y: sy, anchor: .center)                                                       // depuis le milieu
            .opacity(sx > 0.05 ? 1 : 0)
            .environment(\.colorScheme, .light)
            .onChange(of: open) { on in turn(on) }
    }

    /// Allumage / extinction du tube.
    private func turn(_ on: Bool) {
        if on {
            withAnimation(.easeOut(duration: 0.11)) { sx = 1; sy = 0.03; flash = 0.9 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { sy = 1 }
                withAnimation(.easeOut(duration: 0.25)) { flash = 0 }
            }
        } else {
            withAnimation(.easeIn(duration: 0.10)) { sy = 0.03; flash = 0.5 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { withAnimation(.easeIn(duration: 0.09)) { sx = 0.02; flash = 0 } }
        }
    }

    private var screen: some View {
        ZStack(alignment: .top) {
            NotchShape(radius: 34).fill(LinearGradient(colors: [Color(white: 0.99), Color(red: 0.90, green: 0.91, blue: 0.93)], startPoint: .top, endPoint: .bottom))
            grid.padding(.top, 38).padding(.horizontal, 20)
            bar.frame(height: 78).frame(maxHeight: .infinity, alignment: .bottom)
            // la vitre
            WiiCRT().clipShape(NotchShape(radius: 34))
            RadialGradient(colors: [.clear, Color.black.opacity(0.20)], center: .center, startRadius: 120, endRadius: 270).clipShape(NotchShape(radius: 34)).allowsHitTesting(false)
            NotchShape(radius: 34).stroke(Color.white.opacity(0.7), lineWidth: 2).allowsHitTesting(false)
            NotchShape(radius: 34).stroke(Color.black.opacity(0.25), lineWidth: 1).allowsHitTesting(false)
        }
    }

    // MARK: Cases

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), spacing: 8), count: 4), spacing: 8) {
            ForEach(0..<8, id: \.self) { i in
                if i < items.count { tile(items[i]) } else { emptySlot }
            }
        }
    }

    private var emptySlot: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.black.opacity(0.07), lineWidth: 2))
            .frame(width: 84, height: 58)
    }

    private func tile(_ it: ShelfItem) -> some View {
        ShelfChannelTile(item: it, hovered: hover == it.id, selected: selection.contains(it.id), w: 84, h: 58)
            .overlay(ShelfDragSource(item: it, group: group(it), onClick: { f in ShelfSelecting.click(it.id, f, order: Array(items.prefix(8)).map(\.id), selection: &selection, anchor: &anchor) },
                                     onHover: { hover = $0 ? it.id : (hover == it.id ? nil : hover) }))
    }

    // MARK: Barre du bas (celle du menu Wii)

    private var chosen: [ShelfItem] { items.filter { selection.contains($0.id) } }
    private var current: ShelfItem? { items.first { $0.id == hover } ?? (chosen.count == 1 ? chosen.first : nil) }
    private func group(_ it: ShelfItem) -> [ShelfItem] { selection.contains(it.id) && selection.count > 1 ? chosen : [it] }

    private var bar: some View {
        ZStack(alignment: .topLeading) {
            WiiBar().fill(LinearGradient(colors: [.white, Color(white: 0.89)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.10), radius: 5, y: -2)
            WiiBarLine().stroke(wiiBlue, lineWidth: 2.5)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in SevenSegmentClock(date: ctx.date).scaleEffect(0.8).position(x: 190, y: 9) }
            description.position(x: 190, y: 57)
            roundButton("eye").position(x: 34, y: 46)
                .onTapGesture { let t = chosen.isEmpty ? current.map { [$0] } ?? [] : chosen; if !t.isEmpty { ShelfSound.press(); ShelfActions.reveal(t) } }
            sdInfo.position(x: 100, y: 49)
            roundButton("trash").position(x: 346, y: 46)
                .onTapGesture { if !selection.isEmpty { ShelfSound.remove(); store.remove(selection); selection = []; anchor = nil } }
        }
        .frame(width: 380, height: 78)
    }

    @ViewBuilder private var description: some View {
        if let it = current {
            VStack(spacing: 1) {
                Text(it.name).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(wiiBlue).lineLimit(1)
                Text(it.detail + " · " + it.agoText).font(.system(size: 9.5, weight: .medium, design: .rounded)).foregroundStyle(ink).lineLimit(1)
            }.frame(width: 190)
        } else if chosen.count > 1 {
            VStack(spacing: 1) {
                Text(L("\(chosen.count) items selected")).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(wiiBlue)
                Text(L("Drag them out together")).font(.system(size: 9.5, weight: .medium, design: .rounded)).foregroundStyle(ink)
            }.frame(width: 190)
        } else {
            Text(L(WiiMenuView.dateText)).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(ink)
        }
    }

    private var sdInfo: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "sdcard.fill").font(.system(size: 17)).foregroundStyle(wiiBlue)
            VStack(alignment: .leading, spacing: 0) {
                Text(items.isEmpty ? L("Empty") : L("\(items.count) items")).font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundStyle(ink)
                Text(items.first?.agoText ?? L("Drop here")).font(.system(size: 8.5, weight: .medium, design: .rounded)).foregroundStyle(ink)
            }
        }.frame(width: 84, alignment: .leading)
    }

    private func roundButton(_ symbol: String) -> some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(wiiBlue.opacity(0.9), lineWidth: 3)
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Color(white: 0.55))
        }.frame(width: 44, height: 44).shadow(color: .black.opacity(0.18), radius: 4, y: 2).contentShape(Circle())
    }
}

// MARK: O3 · capsules (comme les notifications)

/// L'étagère comme la file de notifications : des capsules blanches empilées, pastille de couleur, titre, détail, boutons ronds.
struct ShelfCapsulesPanel: View {
    let state: ShelfState
    @State private var items: [ShelfItem]
    @State private var open: UUID?

    init(state: ShelfState) {
        self.state = state
        let all = state == .empty ? [] : ShelfSample.items
        _items = State(initialValue: all)
        _open = State(initialValue: state == .action ? all.first?.id : nil)
    }

    var body: some View {
        VStack(spacing: 8) {
            if items.isEmpty {
                capsuleShell { HStack(spacing: 12) {
                    Circle().fill(Color(white: 0.9)).frame(width: 34, height: 34).overlay(Image(systemName: "tray").foregroundStyle(Color(white: 0.45)))
                    VStack(alignment: .leading, spacing: 1) { Text(L("Shelf is empty")).font(.system(size: 13, weight: .bold)); Text(L("Drop files, links or text here")).font(.system(size: 11)).foregroundStyle(Color(white: 0.4)) }
                    Spacer()
                }.frame(height: 48) }
            } else {
                ForEach(Array(items.prefix(open == nil ? 4 : 3))) { row($0) }
                if items.count > (open == nil ? 4 : 3) {
                    Text(L("+ \(items.count - (open == nil ? 4 : 3)) more")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 3).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.orange)).overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white, lineWidth: 1.5))
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 16)
        .frame(width: 380)
        .background(NotchShape(radius: 34).fill(Color.black))
        .environment(\.colorScheme, .light)
    }

    private func capsuleShell<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c().padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 23, style: .continuous).fill(Color(white: 0.97)))
            .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(Color.white, lineWidth: 1))
    }

    private func row(_ it: ShelfItem) -> some View {
        let isOpen = open == it.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Circle().fill(it.kind.color).frame(width: 34, height: 34).overlay(Image(systemName: it.kind.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 1) {
                    Text(it.title ?? it.name).font(.system(size: 13, weight: .bold)).foregroundStyle(Color(white: 0.1)).lineLimit(1)
                    Text(it.detail + " · " + it.age).font(.system(size: 11)).foregroundStyle(Color(white: 0.42)).lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "eye").font(.system(size: 12)).foregroundStyle(Color(white: 0.4)).frame(width: 30, height: 30).background(Circle().fill(Color.white))
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(white: 0.4)).frame(width: 26, height: 26).background(Circle().fill(Color(white: 0.9)))
                    .onTapGesture { items.removeAll { $0.id == it.id } }
            }
            .frame(height: 48)
            if isOpen {
                HStack(spacing: 8) {
                    ForEach(it.kind.isLink ? ["MP3", "MP4", L("Page PDF")] : [L("Compress"), L("Convert")], id: \.self) { a in
                        Text(a).font(.system(size: 12, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 16).frame(height: 30)
                            .background(Capsule().fill(a == "MP3" || a == L("Compress") ? Color(white: 0.12) : Color(white: 0.45)))
                    }
                }.padding(.leading, 46).padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 23, style: .continuous).fill(Color(white: 0.97)))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(Color.white, lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        .onTapGesture { open = isOpen ? nil : it.id }
    }
}

// MARK: O4 · onglet bleu (fenêtre d'outil)

/// L'étagère comme une fenêtre d'outil de Mandarine : verre blanc, onglet bleu du titre en haut à droite, lignes en pilules, bande beige en bas.
struct ShelfTabPanel: View {
    let state: ShelfState
    @State private var items: [ShelfItem]
    @State private var selected: Set<UUID>

    init(state: ShelfState) {
        self.state = state
        let all = state == .empty ? [] : ShelfSample.items
        _items = State(initialValue: all)
        _selected = State(initialValue: state == .action ? Set(all.prefix(2).map(\.id)) : [])
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                VStack(spacing: 7) {
                    if items.isEmpty {
                        pill { HStack(spacing: 10) { Image(systemName: "tray").foregroundStyle(Color(white: 0.5)); Text(L("Drop files, links or text here")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(white: 0.35)); Spacer() } }
                    } else {
                        ForEach(items.prefix(4)) { row($0) }
                        if items.count > 4 { Text(L("+ \(items.count - 4) more")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(white: 0.5)) }
                    }
                }
                .padding(.horizontal, 22).padding(.top, 52).padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                footer
            }
            tab
            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black).frame(width: 130, height: 24).offset(y: -2)
        }
        .frame(width: 380, height: 338)
        .background(LinearGradient(colors: [.white, Color(red: 0.93, green: 0.94, blue: 0.95)], startPoint: .top, endPoint: .bottom))
        .clipShape(NotchShape(radius: 30))
        .environment(\.colorScheme, .light)
    }

    /// Onglet bleu du titre, bord gauche en S : le même que celui des outils.
    private var tab: some View {
        HStack { Spacer()
            WiiTabShape().fill(LinearGradient(colors: [Color(red: 0.40, green: 0.82, blue: 0.97), Color(red: 0.16, green: 0.62, blue: 0.90)], startPoint: .top, endPoint: .bottom))
                .overlay(WiiTabShape().stroke(Color.white.opacity(0.55), lineWidth: 1.2))
                .overlay(alignment: .trailing) {
                    Text(L("Shelf") + (items.isEmpty ? "" : " · \(items.count)")).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        .shadow(color: Color(red: 0.1, green: 0.4, blue: 0.7).opacity(0.6), radius: 1, y: 1).padding(.trailing, 30)
                }
                .frame(width: 170, height: 40)
        }.frame(maxHeight: .infinity, alignment: .top)
    }

    private func pill<C: View>(selected on: Bool = false, @ViewBuilder _ c: () -> C) -> some View {
        c().padding(.horizontal, 14).frame(height: 40)
            .background(ZStack {
                RoundedRectangle(cornerRadius: 19, style: .continuous).fill(on ? Color(red: 0.86, green: 0.84, blue: 0.99) : Color.white)
                RoundedRectangle(cornerRadius: 17, style: .continuous).fill(LinearGradient(colors: [Color.white.opacity(0.7), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55))).padding(3)
            })
            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).strokeBorder(on ? Theme.orange : wiiBlueLight, lineWidth: on ? 3 : 2.5))
    }

    private func row(_ it: ShelfItem) -> some View {
        let on = selected.contains(it.id)
        return pill(selected: on) {
            HStack(spacing: 10) {
                Circle().fill(it.kind.color).frame(width: 24, height: 24).overlay(Image(systemName: it.kind.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white))
                Text(it.name).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Color(white: 0.2)).lineLimit(1)
                Spacer(minLength: 4)
                Text(it.detail).font(.system(size: 11, design: .rounded)).foregroundStyle(Color(white: 0.5)).lineLimit(1)
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 16)).foregroundStyle(on ? Theme.orange : Color(white: 0.75))
            }
        }
        .onTapGesture { if on { selected.remove(it.id) } else { selected.insert(it.id) } }
    }

    /// La bande beige du bas, avec les boutons en pilules.
    private var footer: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.89, green: 0.88, blue: 0.84), Color(red: 0.82, green: 0.81, blue: 0.77)], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color(white: 0.55).opacity(0.55)).frame(height: 1.2)
            HStack(spacing: 12) {
                footerButton(selected.isEmpty ? L("Remove all") : L("Remove"), main: false).onTapGesture {
                    if selected.isEmpty { items = [] } else { items.removeAll { selected.contains($0.id) }; selected = [] }
                }
                Spacer()
                footerButton(selected.isEmpty ? L("Process all") : L("Process \(selected.count)"), main: true)
            }.padding(.horizontal, 24).frame(maxHeight: .infinity)
        }.frame(height: 66)
    }

    private func footerButton(_ t: String, main: Bool) -> some View {
        Text(t).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(Color(white: main ? 0.1 : 0.22)).lineLimit(1).fixedSize()
            .padding(.horizontal, 24).frame(height: 38)
            .background(ZStack {
                Capsule().fill(wiiBlueLight.opacity(0.9))
                Capsule().fill(LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .top, endPoint: .bottom)).padding(3)
                Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.55), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55))).padding(4)
            })
    }
}
