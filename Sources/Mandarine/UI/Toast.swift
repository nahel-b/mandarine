import AppKit
import SwiftUI
import Combine

/// Une ligne de la pile de notifications : travail en attente, en cours, terminé ou en erreur, ou simple message.
struct ToastItem: Identifiable {
    enum Phase { case waiting, running, done, failed }
    let id: UUID
    var phase: Phase
    var title: String
    var subtitle = ""
    var progress: Double? = nil          // nil ou < 0 : indéterminé
    var reveal: [URL] = []               // fichiers créés → bouton « Show »
    var detail = ""                      // texte complet d'une erreur, copiable
    var cancel: (() -> Void)? = nil      // présent tant que le travail peut être annulé
    var action: (title: String, run: () -> Void)? = nil      // bouton d'action (ex. « Update »)
    var sticky = false                   // ne disparaît pas seule
    var eta = ""                          // « About 2 min left » : estimation du temps restant d'un travail long
    var files: [URL] = []                // fichiers que la ligne concerne sans les avoir créés (sélection, copie…) : glissables eux aussi
    var dragging = false                 // ses fichiers sont en train d'être glissés ailleurs : la ligne change d'apparence
}

final class ToastCenter: ObservableObject {
    @Published var items: [ToastItem] = []
    @Published var swipe: [UUID: CGFloat] = [:]          // décalage vers la droite d'une ligne qu'on est en train de balayer au trackpad
    var frames: [UUID: CGRect] = [:]                      // zone de chaque ligne dans la pile : pour savoir laquelle est sous les doigts

    /// Ligne terminée (résultat ou erreur) sous ce point, s'il y en a une : seules celles-là se balaient pour disparaître.
    func swipeableRow(at p: CGPoint) -> UUID? {
        items.first { ($0.phase == .done || $0.phase == .failed) && (frames[$0.id]?.contains(p) ?? false) }?.id
    }

    /// Balayage de deux doigts vers la droite sur une ligne : elle suit les doigts, et part si on a assez glissé (ou qu'on a lancé d'un coup sec).
    private var swipeID: UUID?, swipeX: CGFloat = 0, lastDX: CGFloat = 0, decided = false, locked = false, travel: CGPoint = .zero
    func feedSwipe(phase: NSEvent.Phase, dx: CGFloat, dy: CGFloat, at p: CGPoint) {
        if phase.contains(.began) || phase.contains(.mayBegin) {
            swipeID = swipeableRow(at: p); swipeX = 0; lastDX = 0; decided = false; locked = false; travel = .zero
            return
        }
        guard let id = swipeID else { return }
        if phase.contains(.changed) {
            if locked { return }
            if !decided {
                travel.x += dx; travel.y += dy
                guard abs(travel.x) + abs(travel.y) > 5 else { return }
                if abs(travel.x) > abs(travel.y) * 1.2 { decided = true; swipeX = travel.x } else { locked = true; return }     // plutôt vertical : on laisse tomber
            } else { swipeX += dx }
            lastDX = dx
            swipe[id] = swipeX < 0 ? swipeX / 5 : swipeX          // vers la gauche : résistance
        } else if phase.contains(.ended) || phase.contains(.cancelled) {
            defer { swipeID = nil; decided = false; locked = false }
            guard decided else { return }
            if swipeX > 90 || (swipeX > 30 && lastDX > 9) {
                withAnimation(.easeOut(duration: 0.2)) { swipe[id] = 460 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in Toast.shared.remove(id); self?.swipe[id] = nil }
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { swipe[id] = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.swipe[id] = nil }
            }
        }
    }
}

/// Petits éléments communs aux deux styles de notification.
private enum ToastInk {
    static let text = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let muted = Color(red: 0.55, green: 0.55, blue: 0.57)
    static let eta = Color(red: 0.30, green: 0.30, blue: 0.33)        // « About 40 s left » : un peu plus foncé que le reste du texte
    static let sage = Color(red: 0.34, green: 0.62, blue: 0.47)
    static let danger = Color(red: 0.76, green: 0.31, blue: 0.28)
}

private struct ToastPill: View {
    let text: String
    var symbol: String? = nil
    var fill: Color = Color(white: 0.17)    // bouton principal : graphite, sans couleur (le vert de l'état est déjà à gauche)
    var ink: Color = .white
    var height: CGFloat = 26
    var body: some View {
        HStack(spacing: 4) {
            if let s = symbol { Image(systemName: s).font(.system(size: 10.5, weight: .semibold)) }
            Text(L(text)).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(ink).padding(.horizontal, 11).frame(height: height)
        .background(Capsule().fill(fill)).shadow(color: fill.opacity(0.28), radius: 4, y: 2)
    }
}

private struct ToastRound: View {
    let symbol: String
    var size: CGFloat = 28
    var fill: Color = .white
    var ink: Color = ToastInk.muted
    var rim: Bool = false
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.4, weight: .heavy)).foregroundStyle(ink)
            .frame(width: size, height: size).background(Circle().fill(fill))
            .overlay(Circle().strokeBorder(rim ? Color.white : .clear, lineWidth: 3.5)).shadow(color: .black.opacity(0.10), radius: 3, y: 1)
    }
}

/// Arc qui tourne : travail dont on ne connaît pas l'avancement.
private struct SpinningArc: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            Circle().trim(from: 0, to: 0.27).stroke(ToastInk.sage, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360))
        }
    }
}

private struct ToastRow: View {
    let item: ToastItem
    var swipe: CGFloat = 0
    let dismiss: () -> Void
    @ObservedObject private var settings = AppSettings.shared
    /// Ce qu'on emporte en glissant : les fichiers créés, sinon les fichiers concernés, sinon le texte de la notification.
    private var dragURLs: [URL] { item.reveal.isEmpty ? item.files : item.reveal }
    private var dragText: String { [item.title, item.detail.isEmpty ? item.subtitle : item.detail].filter { !$0.isEmpty }.joined(separator: "\n") }
    private func dragBegan() {
        Toast.shared.setHovering(true); Toast.shared.update(item.id) { $0.dragging = true }
        DragMonitor.shared.beginInternalDrag(dragURLs, text: dragText)
    }
    private func dragEnded() {
        DragMonitor.shared.endInternalDrag(); Toast.shared.update(item.id) { $0.dragging = false }
        Toast.shared.setHovering(false)
    }

    private var failed: Bool { item.phase == .failed }
    private var finished: Bool { item.phase == .done || item.phase == .failed }
    private var lines: [String] { item.subtitle.split(separator: "\n", omittingEmptySubsequences: true).map { L(String($0)) } }
    /// Message libre (erreur, astuce…) : son texte s'affiche en entier ; sinon ce sont des lignes « fichier / dossier / remarque ».
    private var isMessage: Bool { failed || item.sticky || lines.isEmpty }
    private var shortAction: String { item.action.map { $0.title == L("Replace original") ? L("Replace") : $0.title } ?? "" }

    private func copyError() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.detail, forType: .string) }
    private func show() { NSWorkspace.shared.activateFileViewerSelecting(item.reveal) }

    private var swipeFade: Double { 1 - Double(min(max(swipe, 0) / 300, 1)) * 0.8 }
    private var lift: Double { item.dragging ? 0.06 : 0.11 }

    var body: some View {
        content
            .environment(\.colorScheme, .light)
            // saisie : la ligne se tasse, devient translucide, comme une place vide d'où l'on vient de sortir quelque chose
            .shadow(color: .black.opacity(lift), radius: item.dragging ? 4 : 10, y: item.dragging ? 1 : 4)
            .scaleEffect(item.dragging ? 0.94 : 1)
            .opacity(item.dragging ? 0.6 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: item.dragging)
            .offset(x: swipe)
            .opacity(swipeFade)
    }

    @ViewBuilder private var content: some View {
        if settings.notificationStyle == .card { card } else { capsule }
    }

    // MARK: Style capsule (par défaut) : icône entourée d'un arc vert, texte, boutons à droite

    private var capsule: some View {
        let r: CGFloat = 27
        return HStack(spacing: 8) {
            HStack(spacing: 9) {
                statusIcon
                VStack(alignment: .leading, spacing: 0) {
                    Text(L(item.title)).font(.system(size: 12.5, weight: .bold)).foregroundStyle(ToastInk.text).lineLimit(1)
                    capsuleCaption
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay { FileDragHandle(urls: dragURLs, text: dragText, onBegin: dragBegan, onEnd: dragEnded) }
            HStack(spacing: 6) {
                if let cancel = item.cancel { Button(action: cancel) { ToastRound(symbol: "xmark", size: 22, fill: Color(white: 0.9)) }.buttonStyle(.plain).help(L("Stop this job")) }
                if failed && !item.detail.isEmpty { Button(action: copyError) { ToastPill(text: L("Copy"), fill: Color(white: 0.4)) }.buttonStyle(.plain).help(L("Copy the full error message")) }
                if !item.reveal.isEmpty { Button(action: show) { ToastRound(symbol: "eye", size: 26) }.buttonStyle(.plain).help(L("Show in Finder")) }
                if let a = item.action { Button(action: a.run) { ToastPill(text: shortAction) }.buttonStyle(.plain).help(a.title) }
            }
        }
        .padding(.leading, 13).padding(.trailing, 11).padding(.vertical, 7)
        .frame(width: 340).frame(minHeight: 52)
        .background(ZStack {
            RoundedRectangle(cornerRadius: r, style: .continuous).fill(Color.white)
            RoundedRectangle(cornerRadius: r - 4, style: .continuous).fill(Color(white: 0.955)).padding(4)
        })
        .overlay(alignment: .topTrailing) { if finished { Button(action: dismiss) { ToastRound(symbol: "xmark", size: 19, fill: Color(white: 0.6), ink: .white, rim: true) }.buttonStyle(.plain).help(L("Dismiss")).offset(x: 3, y: -6) } }
        .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(Theme.orange.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).opacity(item.dragging ? 1 : 0))
    }

    @ViewBuilder private var capsuleCaption: some View {
        if isMessage && !lines.isEmpty {
            Text(L(item.subtitle)).font(.system(size: 10.5)).foregroundStyle(ToastInk.muted).lineLimit(failed || item.sticky ? 5 : 2).fixedSize(horizontal: false, vertical: true)
        } else {
            let first = Array(lines.prefix(2)).joined(separator: " · ")
            let eta = item.phase == .running ? item.eta : ""
            if !first.isEmpty || !eta.isEmpty {
                (Text(first).foregroundColor(ToastInk.muted) + Text((first.isEmpty || eta.isEmpty ? "" : " · ") + eta).foregroundColor(ToastInk.eta).fontWeight(.medium))
                    .font(.system(size: 10.5)).lineLimit(1).truncationMode(.middle)
            }
            if lines.count > 2 { Text(lines.dropFirst(2).joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(ToastInk.muted.opacity(0.85)).lineLimit(1).truncationMode(.middle) }
        }
    }

    /// L'icône du fichier, seule (pas de pastille de couleur), avec un arc vert autour : il avance avec le travail, se ferme quand c'est fini.
    private var statusIcon: some View {
        let symbol = item.dragging ? "arrow.up.forward" : (failed ? "exclamationmark.triangle" : (item.phase == .waiting ? "clock" : "doc.text"))
        return ZStack {
            switch item.phase {
            case .done:                                                        // fini : une coche blanche sur un rond vert
                Circle().fill(ToastInk.sage)
                Image(systemName: item.dragging ? "arrow.up.forward" : "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
            case .running:
                Circle().stroke(ToastInk.sage.opacity(0.18), lineWidth: 2.2)
                if let p = item.progress, p >= 0 { Circle().trim(from: 0, to: max(0.03, p)).stroke(ToastInk.sage, style: StrokeStyle(lineWidth: 2.2, lineCap: .round)).rotationEffect(.degrees(-90)) }
                else { SpinningArc() }
            case .waiting: Circle().stroke(Color.black.opacity(0.12), style: StrokeStyle(lineWidth: 2.2, dash: [3, 4]))
            case .failed: EmptyView()
            }
            if item.phase != .done { Image(systemName: symbol).font(.system(size: 13, weight: .regular)).foregroundStyle(failed ? ToastInk.danger : Color(white: 0.45)) }
        }
        .frame(width: 32, height: 32)
    }

    // MARK: Style carte : liseré blanc, légende, titre, boutons en bas

    private var card: some View {
        // « légende » au-dessus, « titre » en gros dessous : pour un travail, le type de travail puis le fichier ; pour un message, le titre puis le texte
        let caption = isMessage ? "" : item.title
        let headline = isMessage ? item.title : lines[0]
        let extra = isMessage ? "" : lines.dropFirst().joined(separator: " · ")
        let eta = !isMessage && item.phase == .running ? item.eta : ""
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Group {
                    if item.phase == .done {
                        Image(systemName: item.dragging ? "arrow.up.forward" : "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white).frame(width: 22, height: 22).background(Circle().fill(ToastInk.sage))
                    } else {
                        Image(systemName: failed ? "exclamationmark.triangle" : (item.phase == .waiting ? "clock" : "doc.text")).font(.system(size: 15)).foregroundStyle(failed ? ToastInk.danger : Color(white: 0.6)).frame(width: 22)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    if !caption.isEmpty { Text(L(caption)).font(.system(size: 10, weight: .medium)).foregroundStyle(ToastInk.muted).lineLimit(1) }
                    Text(L(headline)).font(.system(size: 14.5, weight: .bold)).foregroundStyle(ToastInk.text).lineLimit(1).truncationMode(.middle)
                    if isMessage && !lines.isEmpty { Text(L(item.subtitle)).font(.system(size: 10.5)).foregroundStyle(ToastInk.muted).lineLimit(failed || item.sticky ? 5 : 2).fixedSize(horizontal: false, vertical: true).padding(.top, 1) }
                    else if !extra.isEmpty || !eta.isEmpty {
                        (Text(extra).foregroundColor(ToastInk.muted) + Text((extra.isEmpty || eta.isEmpty ? "" : " · ") + eta).foregroundColor(ToastInk.eta).fontWeight(.medium))
                            .font(.system(size: 10.5)).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }
            .overlay { FileDragHandle(urls: dragURLs, text: dragText, onBegin: dragBegan, onEnd: dragEnded) }
            if item.phase == .running || item.phase == .waiting {
                HStack(spacing: 10) {
                    if let p = item.progress, p >= 0 {
                        ZStack(alignment: .leading) { Capsule().fill(Color.black.opacity(0.08)); GeometryReader { g in Capsule().fill(ToastInk.sage).frame(width: g.size.width * p) } }.frame(height: 5)
                    } else { ProgressView().progressViewStyle(.linear).tint(ToastInk.sage) }
                    if let cancel = item.cancel { Button(action: cancel) { ToastPill(text: L("Cancel"), fill: Color(white: 0.9), ink: ToastInk.text) }.buttonStyle(.plain).help(L("Stop this job")) }
                }
            } else if !item.reveal.isEmpty || item.action != nil || (failed && !item.detail.isEmpty) {
                HStack(spacing: 6) {
                    if !item.reveal.isEmpty { Button(action: show) { ToastPill(text: L("Show"), symbol: "eye", fill: .white, ink: ToastInk.muted) }.buttonStyle(.plain) }
                    Spacer(minLength: 4)
                    if failed && !item.detail.isEmpty { Button(action: copyError) { ToastPill(text: L("Copy error"), symbol: "doc.on.doc", fill: Color(white: 0.4)) }.buttonStyle(.plain) }
                    if let a = item.action { Button(action: a.run) { ToastPill(text: a.title, symbol: a.title.hasPrefix("Replace") ? "arrow.triangle.2.circlepath" : nil) }.buttonStyle(.plain) }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(width: 300)
        .background(ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white)
            RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Color(white: 0.955)).padding(5)
        })
        .overlay(alignment: .topTrailing) { if finished { Button(action: dismiss) { ToastRound(symbol: "xmark", size: 21, fill: Color(white: 0.6), ink: .white, rim: true) }.buttonStyle(.plain).help(L("Dismiss")).offset(x: 4, y: -7) } }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.orange.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).opacity(item.dragging ? 1 : 0))
    }
}

struct ToastStack: View {
    @ObservedObject var center: ToastCenter
    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(center.items.suffix(6)) { item in
                ToastRow(item: item, swipe: center.swipe[item.id] ?? 0) { Toast.shared.remove(item.id) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .background(GeometryReader { g in
                        let f = g.frame(in: .named("toastStack"))
                        Color.clear.onAppear { center.frames[item.id] = f }.onChange(of: f) { center.frames[item.id] = $0 }
                    })
            }
        }
        .animation(.easeOut(duration: 0.2), value: center.items.map(\.id))
        .padding(.horizontal, 30).padding(.top, 20).padding(.bottom, 40)          // marge pour que l'ombre (rayon 16, décalée de 6) ne soit pas rognée
        .onHover { Toast.shared.setHovering($0) }
        .coordinateSpace(name: "toastStack")
    }
}

/// Pile de pastilles en haut à droite : une ligne par travail (file d'attente, progression, résultat) ou message.
/// À utiliser depuis le thread principal.
final class Toast {
    static let shared = Toast()
    let center = ToastCenter()
    private var panel: NSPanel?
    private var host: ToastHostingView?
    private var timers: [UUID: DispatchWorkItem] = [:]
    private var hovering = false
    private var bag = Set<AnyCancellable>()

    var debugHost: ToastHostingView? { host }

    private func ensurePanel() {
        if panel != nil { return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 90),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let h = ToastHostingView(rootView: ToastStack(center: center))
        p.contentView = h
        host = h; panel = p
        center.$items.receive(on: DispatchQueue.main).sink { [weak self] _ in DispatchQueue.main.async { self?.place() } }.store(in: &bag)
    }

    private func place() {
        guard let p = panel, let h = host else { return }
        guard !center.items.isEmpty, let f = NSScreen.main?.visibleFrame else { p.orderOut(nil); return }
        let size = h.fittingSize
        p.setFrame(NSRect(x: f.maxX - size.width, y: f.maxY - size.height, width: size.width, height: size.height), display: true)
        p.orderFrontRegardless()
    }

    // MARK: Gestion des lignes

    @discardableResult
    func add(_ item: ToastItem) -> UUID {
        ensurePanel()
        center.items.append(item)
        arm(item)
        return item.id
    }

    /// Modifie une ligne ; la minuterie de disparition est recalculée selon son nouvel état.
    func update(_ id: UUID, _ change: (inout ToastItem) -> Void) {
        guard let i = center.items.firstIndex(where: { $0.id == id }) else { return }
        var item = center.items[i]
        change(&item)
        center.items[i] = item
        arm(item)
    }

    func remove(_ id: UUID) {
        timers[id]?.cancel(); timers[id] = nil
        center.items.removeAll { $0.id == id }
    }

    /// Les lignes terminées disparaissent seules (plus tard s'il y a un bouton Show, bien plus tard pour une erreur).
    private func arm(_ item: ToastItem) {
        timers[item.id]?.cancel(); timers[item.id] = nil
        guard item.phase == .done || item.phase == .failed, !hovering, !item.sticky else { return }
        schedule(item, after: item.phase == .failed ? 45 : (item.reveal.isEmpty ? 12 : 60))
    }

    private func schedule(_ item: ToastItem, after s: Double) {
        let id = item.id
        let w = DispatchWorkItem { [weak self] in self?.remove(id) }
        timers[id] = w
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: w)
    }

    /// Rien ne disparaît tant que la souris est sur la pile.
    func setHovering(_ on: Bool) {
        hovering = on
        if on { timers.values.forEach { $0.cancel() }; timers.removeAll() }
        else { for item in center.items where (item.phase == .done || item.phase == .failed) && !item.sticky { schedule(item, after: 6) } }
    }

    // MARK: Messages simples

    func done(_ title: String, subtitle: String = "", reveal: [URL] = [], files: [URL] = []) {
        Feedback.shared.done()
        add(ToastItem(id: UUID(), phase: .done, title: title, subtitle: subtitle, reveal: reveal, files: files))
    }

    func done(_ title: String, subtitle: String = "", reveal: URL) { done(title, subtitle: subtitle, reveal: [reveal]) }

    func fail(_ title: String, subtitle: String) {
        add(ToastItem(id: UUID(), phase: .failed, title: title, subtitle: subtitle, detail: subtitle))
    }
}
