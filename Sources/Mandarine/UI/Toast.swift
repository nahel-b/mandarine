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
}

private struct ToastRow: View {
    let item: ToastItem
    let dismiss: () -> Void
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
    private func pill(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.12)))
    }

    var body: some View {
        HStack(spacing: 0) {
            // tout ce qui est à gauche des boutons se saisit pour glisser les fichiers créés
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(failed ? Color.red.opacity(0.22) : Theme.orange.opacity(0.22)).frame(width: 30, height: 30)
                    switch item.phase {
                    case .failed:
                        Image(systemName: "exclamationmark").foregroundStyle(.red).font(.system(size: 13, weight: .bold))
                    case .waiting:
                        Image(systemName: "clock").foregroundStyle(Theme.orange).font(.system(size: 13, weight: .semibold))
                    case .running:
                        if let p = item.progress, p >= 0 {
                            Circle().trim(from: 0, to: p).stroke(Theme.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90)).frame(width: 20, height: 20)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    case .done:
                        Image(systemName: item.dragging ? "arrow.up.forward" : "checkmark").foregroundStyle(Theme.orange).font(.system(size: 13, weight: .bold))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                    // plusieurs lignes (nom du fichier, puis dossier) : chacune sur une seule ligne, le nom coupé au milieu pour garder l'extension
                    let lines = item.subtitle.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
                    if lines.count > 1 && !failed {
                        ForEach(Array(lines.prefix(3).enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    } else if !item.subtitle.isEmpty {
                        Text(item.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(failed ? 5 : 2)
                    }
                    if item.phase == .running, !item.eta.isEmpty {
                        Text(item.eta).font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(.leading, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay { FileDragHandle(urls: dragURLs, text: dragText, onBegin: dragBegan, onEnd: dragEnded) }
            HStack(spacing: 12) {
                if let a = item.action {
                    Button(action: a.run) {
                        Text(a.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.orange.opacity(0.28)))
                    }.buttonStyle(.plain)
                }
                if let cancel = item.cancel {
                    Button(action: cancel) { pill("Cancel") }.buttonStyle(.plain).help("Stop this job")
                }
                if failed && !item.detail.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.detail, forType: .string)
                    } label: { pill("Copy") }.buttonStyle(.plain).help("Copy the full error message")
                }
                if !item.reveal.isEmpty {
                    Button { NSWorkspace.shared.activateFileViewerSelecting(item.reveal) } label: {
                        Text("Show").font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.12)))
                    }.buttonStyle(.plain)
                }
                if item.phase == .done || item.phase == .failed {
                    Button(action: dismiss) {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                            .frame(width: 18, height: 18).background(Circle().fill(Color.primary.opacity(0.08)))
                    }.buttonStyle(.plain).help("Dismiss")
                }
            }
            .padding(.trailing, 14)
        }
        .frame(width: 340)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.12)))
        // saisie : la ligne se tasse, devient translucide et laisse un contour pointillé, comme une place vide d'où l'on vient de sortir quelque chose
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.orange.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .opacity(item.dragging ? 1 : 0))
        .shadow(color: .black.opacity(item.dragging ? 0.08 : 0.2), radius: item.dragging ? 5 : 16, y: item.dragging ? 2 : 6)
        .scaleEffect(item.dragging ? 0.94 : 1)
        .opacity(item.dragging ? 0.6 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.62), value: item.dragging)
    }
}

struct ToastStack: View {
    @ObservedObject var center: ToastCenter
    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(center.items.suffix(6)) { item in
                ToastRow(item: item) { Toast.shared.remove(item.id) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: center.items.map(\.id))
        .padding(.horizontal, 30).padding(.top, 20).padding(.bottom, 40)          // marge pour que l'ombre (rayon 16, décalée de 6) ne soit pas rognée
        .onHover { Toast.shared.setHovering($0) }
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
