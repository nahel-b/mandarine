import SwiftUI

/// Forme de l'encoche : noire, collée en haut, coins du bas arrondis.
struct NotchShape: Shape {
    var radius: CGFloat = 30
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Le panneau ouvert de l'encoche, avec l'étagère dans l'un des quatre designs.
struct NotchShelfPanel: View {
    let design: ShelfDesign
    let state: ShelfState
    var interactive = false         // vrai : s'ouvre au survol de l'encoche et reste ouvert tant que la souris est autour
    @State private var items: [ShelfItem]
    @StateObject private var demo: ShelfStore

    init(design: ShelfDesign, state: ShelfState, interactive: Bool = false) {
        self.design = design; self.state = state; self.interactive = interactive
        _items = State(initialValue: state == .empty ? [] : ShelfSample.items)
        _demo = StateObject(wrappedValue: ShelfStore(persist: false, sample: state))
    }

    var body: some View {
        switch design {
        case .petals:
            if interactive { ShelfHoverHost { open in ShelfPetalsPanel(store: demo, state: state, open: open) } } else { ShelfPetalsPanel(store: demo, state: state) }
        case .channels:
            if interactive { ShelfHoverHost(openSize: CGSize(width: 400, height: 252), closedSize: CGSize(width: 240, height: 36)) { open in ShelfChannelsPanel(store: demo, state: state).scaleEffect(open ? 1 : 0.6, anchor: .top).opacity(open ? 1 : 0).animation(.spring(response: 0.3, dampingFraction: 0.82), value: open) } }
            else { ShelfChannelsPanel(store: demo, state: state) }
        case .capsules: ShelfCapsulesPanel(state: state)
        case .tab: ShelfTabPanel(state: state)
        default: blackPanel
        }
    }

    private var blackPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                tab(L("Shelf") + (items.isEmpty ? "" : " · \(items.count)"), on: true)
                tab(L("Jobs"), on: false)
                tab(L("Recent"), on: false)
                Spacer()
                if design == .grid, !items.isEmpty { ShelfPill(text: L("Process all"), main: true) }
            }
            .padding(.top, 28)
            Group {
                switch design {
                case .grid: ShelfGrid(items: $items, preselect: state == .action)
                case .list: ShelfList(items: $items, preselect: state == .action)
                case .pile: ShelfPile(items: $items, openFirst: state == .action)
                case .carousel: ShelfCarousel(items: $items, linksFirst: state == .action)
                default: EmptyView()
                }
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 16)
        .frame(width: 380, alignment: .topLeading)
        .background(NotchShape().fill(Color.black))
        .foregroundStyle(Color.white)
        .environment(\.colorScheme, .dark)
    }

    private func tab(_ t: String, on: Bool) -> some View {
        Text(t).font(.system(size: 12)).foregroundStyle(on ? Color.white : Color(white: 0.78))
            .padding(.horizontal, 12).frame(height: 24)
            .background(Capsule().fill(on ? Color.white.opacity(0.18) : .clear))
    }
}

// MARK: Éléments communs

struct ShelfPill: View {
    let text: String
    var main = false
    var small = false
    var body: some View {
        Text(text).font(.system(size: small ? 11 : 12, weight: .semibold)).lineLimit(1).fixedSize()
            .padding(.horizontal, small ? 10 : 12).frame(height: small ? 22 : 26)
            .background(Capsule().fill(main ? Theme.orange : Color.white.opacity(0.16)))
            .foregroundStyle(Color.white)
    }
}

private struct ShelfEmptyDrop: View {
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "tray").font(.system(size: 22)).foregroundStyle(Color(white: 0.78))
            Text(L("Drop files, links or text here")).font(.system(size: 13))
            Text(L("They stay here until you remove them")).font(.system(size: 11)).foregroundStyle(Color(white: 0.78))
        }
        .frame(maxWidth: .infinity).frame(height: 104)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }
}

private func shelfBadge(_ symbol: String, fill: Color, ink: Color = .white) -> some View {
    Image(systemName: symbol).font(.system(size: 9, weight: .heavy)).foregroundStyle(ink)
        .frame(width: 18, height: 18).background(Circle().fill(fill))
}

// MARK: E1 · grille de vignettes

private struct ShelfGrid: View {
    @Binding var items: [ShelfItem]
    let preselect: Bool
    @State private var selected: Set<UUID> = []
    @State private var hovered: UUID?

    var body: some View {
        if items.isEmpty { ShelfEmptyDrop() } else {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(56), spacing: 8), count: 5), alignment: .leading, spacing: 8) {
                    ForEach(selected.isEmpty ? items : Array(items.prefix(5))) { tile($0) }
                    if selected.isEmpty {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .frame(width: 56, height: 56).overlay(Image(systemName: "plus").foregroundStyle(Color(white: 0.78)))
                    }
                }
                .padding(.horizontal, 14)
                if !selected.isEmpty { actionBar }
            }
            .onAppear { if preselect, selected.isEmpty { selected = Set(items.prefix(2).map(\.id)) } }
        }
    }

    private func tile(_ it: ShelfItem) -> some View {
        let on = selected.contains(it.id), dim = !selected.isEmpty && !on
        return VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(it.kind.color)
                    .overlay(Image(systemName: it.kind.symbol).font(.system(size: 22)).foregroundStyle(.white))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Theme.orange : (hovered == it.id ? Color.white : .clear), lineWidth: 2.5))
                if on { shelfBadge("checkmark", fill: Theme.orange).offset(x: 5, y: -5) }
                else if hovered == it.id { shelfBadge("xmark", fill: .white, ink: .black).offset(x: 5, y: -5).onTapGesture { items.removeAll { $0.id == it.id } } }
            }
            .frame(width: 56, height: 56)
            Text(it.name).font(.system(size: 11)).foregroundStyle(Color(white: 0.82)).lineLimit(1).frame(width: 56)
        }
        .opacity(dim ? 0.45 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if on { selected.remove(it.id) } else { selected.insert(it.id) } }
        .onHover { hovered = $0 ? it.id : (hovered == it.id ? nil : hovered) }
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            Text(L("\(selected.count) selected")).font(.system(size: 12)).lineLimit(1).fixedSize()
            Spacer(minLength: 6)
            ShelfPill(text: L("Compress"), main: true)
            ShelfPill(text: L("Convert"))
            ShelfPill(text: L("Remove")).onTapGesture { items.removeAll { selected.contains($0.id) }; selected = [] }
        }
        .padding(.leading, 16).padding(.trailing, 8).frame(height: 44)
        .background(Capsule().fill(Color(white: 0.14)).overlay(Capsule().strokeBorder(Color.white.opacity(0.12))))
    }
}

// MARK: E2 · liste rangée par type

private struct ShelfList: View {
    @Binding var items: [ShelfItem]
    let preselect: Bool
    @State private var expanded: UUID?

    var body: some View {
        if items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Empty shelf")).font(.system(size: 14, weight: .semibold))
                Text(L("Drop here to keep things at hand, then take them back when you want.")).font(.system(size: 12)).foregroundStyle(Color(white: 0.78)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    chip("doc", L("Files")); chip("link", L("Links")); chip("text.alignleft", L("Text"))
                }.padding(.top, 6)
            }.padding(.horizontal, 2).padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                section(L("Files"), items.filter { $0.kind.isFile })
                section(L("Links"), items.filter { $0.kind.isLink })
                section(L("Text"), items.filter { $0.kind == .text })
            }
            .onAppear { if preselect, expanded == nil { expanded = items.first { $0.kind.isLink }?.id } }
        }
    }

    private func chip(_ symbol: String, _ t: String) -> some View {
        HStack(spacing: 6) { Image(systemName: symbol).font(.system(size: 12)); Text(t).font(.system(size: 12)) }
            .padding(.horizontal, 11).frame(height: 26).background(Capsule().fill(Color.white.opacity(0.1)))
    }

    @ViewBuilder private func section(_ title: String, _ list: [ShelfItem]) -> some View {
        if !list.isEmpty {
            Text(title).font(.system(size: 11)).foregroundStyle(Color(white: 0.78)).padding(.horizontal, 8).frame(height: 18, alignment: .leading)
            ForEach(list) { row($0) }
        }
    }

    private func row(_ it: ShelfItem) -> some View {
        let open = expanded == it.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(it.kind.color).frame(width: 22, height: 22)
                    .overlay(Image(systemName: it.kind.symbol).font(.system(size: 11)).foregroundStyle(.white))
                Text(it.name).font(.system(size: 12)).lineLimit(1)
                Spacer(minLength: 6)
                Text(it.detail).font(.system(size: 11)).foregroundStyle(Color(white: 0.78)).lineLimit(1)
            }
            .frame(height: 32 - (open ? 8 : 0))
            if open {
                HStack(spacing: 6) {
                    ForEach(actions(it), id: \.self) { a in
                        ShelfPill(text: a, main: a == actions(it).first, small: true)
                            .onTapGesture { if a == L("Remove") { items.removeAll { $0.id == it.id } } }
                    }
                }.padding(.leading, 32)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, open ? 6 : 0)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(open ? 0.12 : 0)))
        .contentShape(Rectangle())
        .onTapGesture { expanded = open ? nil : it.id }
    }

    private func actions(_ it: ShelfItem) -> [String] {
        switch it.kind {
        case .link: return ["MP3", "MP4", L("Open"), L("Remove")]
        case .image: return [L("Compress"), L("Convert"), L("Remove")]
        case .pdf: return [L("Compress"), L("Open"), L("Remove")]
        case .video: return [L("Compress"), L("Transcribe"), L("Remove")]
        case .audio: return [L("Transcribe"), L("Convert"), L("Remove")]
        case .text: return [L("Open"), L("Remove")]
        case .other: return [L("Open"), L("Remove")]
        }
    }
}

// MARK: E3 · pile de cartes

private struct ShelfPile: View {
    @Binding var items: [ShelfItem]
    let openFirst: Bool
    @State private var order: [ShelfItem] = []      // la dernière est devant
    @State private var open = false
    private let angles: [Double] = [-9, -4, 1, 6]

    var body: some View {
        Group {
            if items.isEmpty { ghosts } else if open, let front = order.last { detail(front) } else { pile }
        }
        .frame(height: 150, alignment: .top)
        .onAppear { if order.isEmpty { order = items.reversed(); if openFirst { open = true } } }
        .onChange(of: items) { new in order = order.filter { o in new.contains { $0.id == o.id } } }
    }

    private var ghosts: some View {
        ZStack {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: 132, height: 128).rotationEffect(.degrees([-8.0, -2, 5][i])).offset(x: CGFloat(i - 1) * 56, y: 0)
            }
            Text(L("Drop to start a stack")).font(.system(size: 12)).foregroundStyle(Color(white: 0.78)).offset(y: 70)
        }.frame(maxWidth: .infinity)
    }

    private var pile: some View {
        let shown = Array(order.suffix(4))
        return HStack(alignment: .top, spacing: 0) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, it in
                    card(it, w: 132, h: 128)
                        .rotationEffect(.degrees(angles[min(i + 4 - shown.count, 3)]))
                        .offset(x: CGFloat(i) * 46, y: CGFloat(4 - shown.count + i) * -2)
                }
            }
            .frame(width: 230, height: 140, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture { open = true }
            .gesture(DragGesture(minimumDistance: 14).onEnded { v in
                guard order.count > 1 else { return }
                if v.translation.width < 0, let f = order.last { order.removeLast(); order.insert(f, at: 0) }
                else if let b = order.first { order.removeFirst(); order.append(b) }
            })
            VStack(alignment: .trailing, spacing: 6) {
                Text(L("Newest in front")).font(.system(size: 12)).foregroundStyle(Color(white: 0.78))
                if let f = order.last {
                    Text(f.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(L("\(f.age) ago")).font(.system(size: 11)).foregroundStyle(Color(white: 0.78))
                }
                Spacer()
                Text(L("Swipe the stack")).font(.system(size: 11)).foregroundStyle(Color(white: 0.7))
            }.frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 28)
        }
    }

    private func card(_ it: ShelfItem, w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(it.kind.color)
            Image(systemName: it.kind.symbol).font(.system(size: w > 150 ? 34 : 24)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: w > 150 ? .center : .topLeading).padding(12)
            Text(w > 150 ? it.name + " · " + (it.detail.components(separatedBy: " · ").last ?? "") : it.name).font(.system(size: 12)).lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).background(Color.black.opacity(0.55))
        }
        .frame(width: w, height: h).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 5, y: 3)
    }

    private func detail(_ it: ShelfItem) -> some View {
        HStack(alignment: .top, spacing: 18) {
            card(it, w: 190, h: 150).onTapGesture { open = false }
            VStack(alignment: .leading, spacing: 8) {
                Text(it.detail.components(separatedBy: " · ").first ?? "").font(.system(size: 12)).foregroundStyle(Color(white: 0.78))
                Text(L("\(it.age) ago")).font(.system(size: 12)).foregroundStyle(Color(white: 0.78))
                ShelfPill(text: L("Process"), main: true).frame(maxWidth: .infinity)
                ShelfPill(text: L("Preview")).frame(maxWidth: .infinity)
                ShelfPill(text: L("Remove")).frame(maxWidth: .infinity).onTapGesture {
                    items.removeAll { $0.id == it.id }; order.removeAll { $0.id == it.id }; open = false
                }
            }
        }
    }
}

// MARK: E4 · carrousel d'aperçus

private struct ShelfCarousel: View {
    @Binding var items: [ShelfItem]
    let linksFirst: Bool
    private enum Filter: CaseIterable { case all, images, media, links, docs
        var title: String { switch self { case .all: return L("All"); case .images: return L("Images"); case .media: return L("Media"); case .links: return L("Links"); case .docs: return L("Docs") } }
        func matches(_ k: ShelfKind) -> Bool {
            switch self {
            case .all: return true
            case .images: return k == .image
            case .media: return k == .video || k == .audio
            case .links: return k == .link
            case .docs: return k == .pdf || k == .text
            }
        }
    }
    @State private var filter: Filter = .all
    @State private var applied = false

    private var shown: [ShelfItem] { items.filter { filter.matches($0.kind) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Filter.allCases, id: \.self) { f in
                        let n = items.filter { f.matches($0.kind) }.count
                        HStack(spacing: 5) { Text(f.title); Text("\(n)").font(.system(size: 11)).opacity(0.7) }
                            .font(.system(size: 12, weight: filter == f ? .semibold : .regular)).padding(.horizontal, 11).frame(height: 24)
                            .background(Capsule().fill(filter == f ? Color.white : Color.white.opacity(0.1)))
                            .foregroundStyle(filter == f ? Color.black : Color(white: 0.84)).opacity(n == 0 && f != .all ? 0.5 : 1)
                            .onTapGesture { filter = f }
                    }
                }
            }
            if items.isEmpty {
                HStack(spacing: 10) { Image(systemName: "tray").font(.system(size: 18)); Text(L("Drop here: previews will appear")).font(.system(size: 12)) }
                    .foregroundStyle(Color(white: 0.84)).frame(maxWidth: .infinity).frame(height: 76)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            } else if filter == .links {
                VStack(spacing: 8) { ForEach(shown) { linkCard($0) } }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) { ForEach(shown) { preview($0) } }
                }.frame(height: 110)
            }
        }
        .onAppear { if linksFirst, !applied { filter = .links; applied = true } }
    }

    private func preview(_ it: ShelfItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    switch it.kind {
                    case .image:
                        Color(red: 0.29, green: 0.44, blue: 0.70)
                        Triangle().fill(Color(red: 0.43, green: 0.56, blue: 0.82)).frame(width: 98, height: 52).offset(y: 17)
                        Circle().fill(Color(red: 0.96, green: 0.82, blue: 0.48)).frame(width: 16, height: 16).offset(x: -30, y: -22)
                    case .video:
                        Color(white: 0.14); Image(systemName: "play.circle").font(.system(size: 32, weight: .light)).foregroundStyle(.white)
                    case .pdf:
                        Color(white: 0.95)
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.1)).frame(width: 50, height: 5)
                            ForEach(0..<4) { _ in RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.78)).frame(width: 66, height: 3) }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(14)
                    default:
                        it.kind.color; Image(systemName: it.kind.symbol).font(.system(size: 26)).foregroundStyle(.white)
                    }
                }
                if it.kind == .video || it.kind == .audio || it.kind == .pdf {
                    Text(it.detail.components(separatedBy: " · ").first ?? "").font(.system(size: 11)).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.black.opacity(0.65))).padding(6)
                }
            }
            .frame(width: 98, height: 86).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(it.name).font(.system(size: 11)).foregroundStyle(Color(white: 0.82)).lineLimit(1).frame(width: 98, alignment: .leading)
        }
    }

    private func linkCard(_ it: ShelfItem) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(it.kind.color).frame(width: 56, height: 56)
                .overlay(Image(systemName: "play.circle").font(.system(size: 22)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text(it.title ?? it.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(it.name.components(separatedBy: "/").first! + " · " + it.detail + " · " + L("\(it.age) ago")).font(.system(size: 11)).foregroundStyle(Color(white: 0.78)).lineLimit(1)
                HStack(spacing: 5) {
                    ShelfPill(text: "MP3", main: true, small: true); ShelfPill(text: "MP4", small: true); ShelfPill(text: L("Open"), small: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8).frame(height: 72).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.1)))
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.width * 0.35, y: r.minY)); p.addLine(to: CGPoint(x: r.width * 0.6, y: r.height * 0.55))
        p.addLine(to: CGPoint(x: r.width * 0.8, y: r.height * 0.25)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.closeSubpath()
        return p
    }
}

// MARK: Fenêtre d'essai

/// Un faux bureau avec l'encoche ouverte et deux sélecteurs : pour voir et essayer les quatre designs.
struct NotchDemoView: View {
    @State var design: ShelfDesign = .grid
    @State var state: ShelfState = .filled

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.81, green: 0.85, blue: 0.89)
            Rectangle().fill(Color.white.opacity(0.55)).frame(height: 22).frame(maxHeight: .infinity, alignment: .top)
            NotchShelfPanel(design: design, state: state, interactive: true).id("\(design.rawValue)-\(state.rawValue)").padding(.top, 0)
            VStack {
                Spacer()
                HStack(spacing: 16) {
                    Picker(L("Design"), selection: $design) {
                        Section(L("My designs")) { ForEach(ShelfDesign.allCases.filter(\.isOriginal)) { Text($0.title).tag($0) } }
                        Section(L("First tries")) { ForEach(ShelfDesign.allCases.filter { !$0.isOriginal }) { Text($0.title).tag($0) } }
                    }.pickerStyle(.menu).frame(width: 190)
                    Picker(L("State"), selection: $state) { ForEach(ShelfState.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).frame(width: 240)
                }
                .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous)).padding(.bottom, 16)
            }
        }
        .frame(width: 760, height: 520)
    }
}
