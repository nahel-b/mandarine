import SwiftUI

/// Bouton « touche » : on clique, puis on appuie sur la nouvelle touche. Échap annule. `taken` dit si la touche sert déjà à autre chose.
struct KeyRecorder: View {
    let title: String
    @Binding var key: String
    var taken: (String) -> String?
    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        VStack(spacing: 3) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "press a key…" : key.uppercased())
                    .font(.system(size: recording ? 11 : 15, weight: .semibold, design: .rounded))
                    .frame(width: 70, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(recording ? Theme.orange.opacity(0.3) : Color.primary.opacity(0.1)))
            }.buttonStyle(.plain)
            Text(message ?? title).font(.system(size: 10)).foregroundStyle(message == nil ? Color.secondary : Color.orange).lineLimit(1)
        }
        .onDisappear { stop() }
    }

    private func start() {
        message = nil; recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil }                                           // Échap
            guard e.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let c = e.charactersIgnoringModifiers?.lowercased(), let ch = c.first, ch.isLetter || ch.isNumber || ",;:!.-/'".contains(ch) else {
                message = "use a letter or digit"; return nil
            }
            let k = String(ch)
            if let who = taken(k) { message = "already “\(who)”"; return nil }
            key = k; stop(); return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
