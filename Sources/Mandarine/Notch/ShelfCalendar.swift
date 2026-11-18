import SwiftUI
import EventKit
import Combine

/// Un rendez-vous ou un rappel, réduit à ce que l'étagère affiche.
struct CalEvent: Identifiable, Equatable {
    let id: String, title: String
    let start: Date, end: Date
    let allDay: Bool
    let color: Color
}
/// Un calendrier ou une liste de rappels, pour le choix dans les Réglages.
struct CalSource: Identifiable, Equatable {
    let id: String, title: String, account: String
    let color: Color
    let reminders: Bool
}
struct CalReminder: Identifiable, Equatable {
    let id: String, title: String
    let due: Date?
    let color: Color
}

/// Les prochains rendez-vous (Calendrier) et les rappels (Rappels) pour l'étagère « Wii » : lus avec EventKit, seulement après autorisation.
@MainActor
final class CalendarStore: ObservableObject {
    static let shared = CalendarStore()
    @Published private(set) var events: [CalEvent] = []
    @Published private(set) var reminders: [CalReminder] = []
    @Published private(set) var eventsGranted = false
    @Published private(set) var remindersGranted = false
    @Published private(set) var sources: [CalSource] = []
    @Published private(set) var denied = false          // l'utilisateur a refusé (ou c'est bloqué) : il faut passer par les Réglages Système
    private let store = EKEventStore()
    private var observing = false
    static let demo = ProcessInfo.processInfo.environment["MANDARINE_CALDEMO"] != nil          // essais : faux rendez-vous, sans rien lire

    var granted: Bool { eventsGranted || remindersGranted }

    private init() {
        // le choix des calendriers change : on relit
        _ = AppSettings.shared.$shelfCalendarsOff.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }.store(in: &bag)
    }
    private var bag: Set<AnyCancellable> = []

    private func chosen(_ type: EKEntityType) -> [EKCalendar]? {
        let off = Set(AppSettings.shared.shelfCalendarsOff)
        return store.calendars(for: type).filter { !off.contains($0.calendarIdentifier) }
    }

    private static func isGranted(_ s: EKAuthorizationStatus) -> Bool { s.rawValue == 3 }          // « authorized » (macOS 13) et « fullAccess » (macOS 14) valent 3

    private func updateAccess() {
        let e = EKEventStore.authorizationStatus(for: .event), r = EKEventStore.authorizationStatus(for: .reminder)
        eventsGranted = Self.isGranted(e); remindersGranted = Self.isGranted(r)
        denied = [e, r].contains { $0.rawValue == 1 || $0.rawValue == 2 || $0.rawValue == 4 } && !granted
    }

    /// Relit les rendez-vous et les rappels (à l'ouverture de la page, puis toutes les 30 s tant qu'elle est visible).
    func refresh() {
        if Self.demo { loadDemo(); return }
        if !observing { observing = true; NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh() } } }
        updateAccess()
        sources = (store.calendars(for: .event).map { ($0, false) } + store.calendars(for: .reminder).map { ($0, true) })
            .map { CalSource(id: $0.0.calendarIdentifier, title: $0.0.title, account: $0.0.source?.title ?? "", color: Color(cgColor: $0.0.cgColor), reminders: $0.1) }
            .sorted { ($0.reminders ? 1 : 0, $0.account, $0.title) < ($1.reminders ? 1 : 0, $1.account, $1.title) }
        if eventsGranted, let cals = chosen(.event), !cals.isEmpty {
            let now = Date(), end = Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now
            let list = store.events(matching: store.predicateForEvents(withStart: now, end: end, calendars: cals))
                .filter { $0.endDate > now }.sorted { $0.startDate < $1.startDate }          // tous les calendriers mêlés, dans l'ordre des dates
            // un événement qui se répète a le même identifiant à chaque occurrence : l'identité d'une ligne est donc « identifiant + début » ;
            // et le même rendez-vous présent dans deux calendriers (invitation, compte partagé) n'est montré qu'une fois
            var seen = Set<String>()
            events = list.compactMap { e -> CalEvent? in
                let key = "\(e.title ?? "")|\(e.startDate.timeIntervalSince1970)|\(e.endDate.timeIntervalSince1970)"
                guard seen.insert(key).inserted else { return nil }
                return CalEvent(id: "\(e.eventIdentifier ?? UUID().uuidString)@\(e.startDate.timeIntervalSince1970)", title: e.title ?? "", start: e.startDate, end: e.endDate, allDay: e.isAllDay, color: Color(cgColor: e.calendar.cgColor))
            }
            events = Array(events.prefix(60))
        } else { events = [] }
        if remindersGranted, let cals = chosen(.reminder), !cals.isEmpty {
            store.fetchReminders(matching: store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: cals)) { rs in
                let items = (rs ?? []).map { r in
                    CalReminder(id: r.calendarItemIdentifier, title: r.title ?? "", due: r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }, color: Color(cgColor: r.calendar.cgColor))
                }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
                Task { @MainActor in self.reminders = Array(items.prefix(60)) }
            }
        } else { reminders = [] }
    }

    /// Demande l'accès au Calendrier et aux Rappels (la fenêtre du système s'affiche une seule fois).
    func requestAccess() {
        NSApp.activate(ignoringOtherApps: true)
        Task {
            if #available(macOS 14, *) {
                _ = try? await store.requestFullAccessToEvents()
                _ = try? await store.requestFullAccessToReminders()
            } else {
                _ = try? await store.requestAccess(to: .event)
                _ = try? await store.requestAccess(to: .reminder)
            }
            refresh()
        }
    }

    /// Coche un rappel (il est marqué comme terminé dans l'app Rappels).
    func complete(_ r: CalReminder) {
        withAnimation(.easeOut(duration: 0.2)) { reminders.removeAll { $0.id == r.id } }
        if Self.demo { return }
        if let item = store.calendarItem(withIdentifier: r.id) as? EKReminder { item.isCompleted = true; try? store.save(item, commit: true) }
    }

    private func loadDemo() {
        eventsGranted = true; remindersGranted = true; denied = false
        sources = [CalSource(id: "d1", title: "Personnel", account: "iCloud", color: Theme.orange, reminders: false), CalSource(id: "d2", title: "Travail", account: "iCloud", color: Color(red: 0.17, green: 0.63, blue: 0.88), reminders: false),
                   CalSource(id: "d3", title: "Famille", account: "iCloud", color: Color(red: 0.2, green: 0.7, blue: 0.5), reminders: false), CalSource(id: "d4", title: "Rappels", account: "iCloud", color: Color(red: 0.55, green: 0.55, blue: 0.9), reminders: true)]
        let now = Date(), cal = Calendar.current
        func at(_ h: Int, _ m: Int, day: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: cal.date(byAdding: .day, value: day, to: now)!)! }
        events = [
            CalEvent(id: "1", title: "Réunion équipe", start: now.addingTimeInterval(12 * 60), end: now.addingTimeInterval(72 * 60), allDay: false, color: Theme.orange),
            CalEvent(id: "2", title: "Déjeuner avec Camille", start: at(12, 30, day: 1), end: at(13, 30, day: 1), allDay: false, color: Color(red: 0.2, green: 0.7, blue: 0.5)),
            CalEvent(id: "3", title: "Dentiste", start: at(9, 0, day: 2), end: at(10, 0, day: 2), allDay: false, color: Color(red: 0.55, green: 0.55, blue: 0.9)),
            CalEvent(id: "4", title: "Concert", start: at(20, 0, day: 11), end: at(23, 0, day: 11), allDay: false, color: Color(red: 0.9, green: 0.3, blue: 0.45)),
            CalEvent(id: "5", title: "Rendu du projet", start: at(0, 0, day: 5), end: at(23, 59, day: 5), allDay: true, color: Color(red: 0.17, green: 0.63, blue: 0.88)),
        ]
        reminders = [
            CalReminder(id: "a", title: "Réserver le train", due: at(18, 0), color: Theme.orange),
            CalReminder(id: "b", title: "Envoyer la facture", due: at(9, 0, day: 1), color: Color(red: 0.55, green: 0.55, blue: 0.9)),
            CalReminder(id: "c", title: "Sauvegarde du disque", due: at(9, 0, day: 10), color: Color(red: 0.2, green: 0.7, blue: 0.5)),
            CalReminder(id: "d", title: "Acheter du pain", due: nil, color: Color(red: 0.17, green: 0.63, blue: 0.88)),
        ]
    }
}

private let wBlue = Color(red: 0.17, green: 0.63, blue: 0.88)
private let wBlueLight = Color(red: 0.49, green: 0.78, blue: 0.93)
private let wInk = Color(red: 0.56, green: 0.58, blue: 0.60)
private let wDeep = Color(white: 0.30)

/// Le petit bouton de l'étagère : l'icône du calendrier avec le chiffre du jour (il ouvre la page Calendrier) — ou le plateau de l'étagère quand on est sur la page Calendrier.
struct ShelfCalendarButton: View {
    var onCalendar: Bool
    var count: Int
    var action: () -> Void
    @State private var hot = false
    var body: some View {
        Group {
            if onCalendar {
                ZStack {
                    Circle().fill(LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .top, endPoint: .bottom))
                    Circle().strokeBorder(wBlue, lineWidth: 2)
                    Image(systemName: "tray.full.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(white: 0.5))
                    if count > 0 { Text("\(count)").font(.system(size: 7.5, weight: .heavy, design: .rounded)).foregroundStyle(.white).frame(minWidth: 12, minHeight: 12).background(Circle().fill(Theme.orange)).overlay(Circle().strokeBorder(.white, lineWidth: 1)).offset(x: 8, y: 7) }
                }.frame(width: 24, height: 24)
            } else {
                VStack(spacing: 0) {          // petit : une bande bleue et le chiffre (pas de mois, qui mangeait la place)
                    UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5).fill(LinearGradient(colors: [wBlueLight, wBlue], startPoint: .top, endPoint: .bottom)).frame(height: 6)
                    Text(Self.day).font(.system(size: 12.5, weight: .heavy, design: .rounded)).foregroundStyle(Color(red: 0.42, green: 0.50, blue: 0.58)).frame(maxHeight: .infinity)
                }
                .frame(width: 22, height: 24).background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.6)], startPoint: .top, endPoint: .bottom), lineWidth: 1.8))
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 2.5, y: 1.5)
        .scaleEffect(hot ? 1.12 : 1).animation(.easeOut(duration: 0.1), value: hot)
        .contentShape(Rectangle().inset(by: -4))
        .onHover { hot = $0; if $0 { ShelfSound.hover() } }
        .onTapGesture(perform: action)
        .help(onCalendar ? L("Back to the shelf") : L("Calendar and reminders"))
    }
    private static var day: String { String(Calendar.current.component(.day, from: Date())) }
}

/// La page Calendrier de l'étagère « Wii » : la date du jour à gauche de l'encoche, puis les prochains rendez-vous (tous les calendriers choisis, dans l'ordre des dates)
/// et, à côté, les rappels sur leur papier crème. Les deux colonnes défilent (trackpad ou molette).
struct ShelfCalendarPage: View {
    @ObservedObject private var cal = CalendarStore.shared
    @ObservedObject private var controller = ShelfPanelController.shared
    @ObservedObject private var store = ShelfStore.shared
    var width: CGFloat = 470
    var notch = CGSize(width: 130, height: 24)          // la vraie encoche : la date se place à sa gauche, les colonnes sous elle
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .top) {
            Text(Self.dateLine).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(wBlue).lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: min(170, (width - notch.width) / 2 - 20), alignment: .trailing).offset(x: -((notch.width / 2 + 8) + min(170, (width - notch.width) / 2 - 20) / 2), y: max(0, notch.height / 2 - 9))          // à gauche de la vraie encoche
            HStack(alignment: .top, spacing: 10) {
                if cal.granted { eventsColumn; remindersColumn } else { permission }
            }
            .padding(.horizontal, 18).padding(.top, max(34, notch.height + 2))
            WiiProposalBar(w: width, left: "calendar", right: "checklist", footer: L(WiiMenuView.dateText), onLeft: { open("Calendar") }, onRight: { open("Reminders") })
                .frame(maxHeight: .infinity, alignment: .bottom)
            ShelfCalendarButton(onCalendar: true, count: store.items.count) { controller.toggleCalendar() }          // à gauche du bouton Rappels : retour à l'étagère
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(.trailing, 70).padding(.bottom, 19)          // même place miroir que la carte SD de l'étagère
        }
        .frame(width: width)
        .onAppear { cal.refresh() }
        .onReceive(tick) { _ in cal.refresh() }
    }

    private func open(_ app: String) { ShelfSound.press(); NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/\(app).app")) }

    private static var dateLine: String {
        let f = DateFormatter(); f.dateFormat = "EEEE d MMMM"
        let t = f.string(from: Date()); return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// Une colonne qui défile (le décalage vient de la molette : `ShelfPanelController.scrollCalendar`), avec un léger fondu en bas pour montrer qu'il y a une suite.
    private func scrolling<V: View>(height: CGFloat, offset: CGFloat, @ViewBuilder _ v: () -> V) -> some View {
        VStack(spacing: 4) { v() }.padding(.horizontal, 3).padding(.top, 3).offset(y: -offset)
            .frame(height: height, alignment: .top).clipped()
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.88), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
    }

    // MARK: Colonnes

    private var eventsColumn: some View {
        let nextID = cal.events.first { !$0.allDay }?.id
        return VStack(spacing: 4) {
            Text(L("EVENTS")).font(.system(size: 8.5, weight: .heavy, design: .rounded)).tracking(1).foregroundStyle(wBlue).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).frame(height: 14)
            scrolling(height: 112, offset: controller.eventsScroll) {
                if !cal.eventsGranted { note(L("Calendar access is off")) }
                else if cal.events.isEmpty { note(L("Nothing planned")) }
                ForEach(cal.events) { e in eventRow(e, next: e.id == nextID) }
            }
        }.frame(width: 232, height: 126, alignment: .top)          // s'arrête avant l'horloge de la barre
    }

    /// Les rappels sur un papier crème rayé, comme le Tableau de messages de la Wii : titre bleu, lignes bleutées, pastilles à cocher.
    private var remindersColumn: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(red: 1.0, green: 0.985, blue: 0.90))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(red: 0.9, green: 0.84, blue: 0.62), lineWidth: 2))
            Text(L("Reminders")).font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(wBlue).padding(.horizontal, 12).padding(.top, 7)
            VStack(spacing: 0) {
                if !cal.remindersGranted { noteInPaper(L("Reminders access is off")) }
                else if cal.reminders.isEmpty { noteInPaper(L("No reminders")) }
                ForEach(cal.reminders) { r in paperRow(r) }
            }
            .offset(y: -controller.remindersScroll)
            .frame(height: 90, alignment: .top).clipped().padding(.top, 30).padding(.horizontal, 2)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        }.frame(width: 192, height: 124)
    }

    private func note(_ t: String) -> some View {
        Text(t).font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundStyle(wInk).frame(maxWidth: .infinity, minHeight: 26, alignment: .leading).padding(.leading, 6)
    }
    private func noteInPaper(_ t: String) -> some View {
        Text(t).font(.system(size: 10.5, weight: .semibold, design: .rounded)).foregroundStyle(wInk).frame(maxWidth: .infinity, minHeight: 22, alignment: .leading).padding(.horizontal, 10)
    }

    private func eventRow(_ e: CalEvent, next: Bool) -> some View {
        let minutes = Int(e.start.timeIntervalSinceNow / 60)
        let soon = next && !e.allDay && minutes >= 0 && minutes < 60
        return HStack(spacing: 6) {
            Circle().fill(e.color).frame(width: 7, height: 7)
            Text(e.title).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(wDeep).lineLimit(1)
            Spacer(minLength: 2)
            if soon { Text("\(minutes) min").font(.system(size: 8.5, weight: .heavy, design: .rounded)).foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 1.5).background(Capsule().fill(Theme.orange)) }
            else { Text(Self.when(e)).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(next ? wBlue : wInk).lineLimit(1) }
        }
        .padding(.horizontal, 9).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(LinearGradient(colors: [.white, Color(white: 0.93)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(next ? wBlue : Color(white: 0.78), lineWidth: next ? 2.5 : 1.5)))
    }

    private func paperRow(_ r: CalReminder) -> some View {
        let hot = r.due.map { $0 < Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))! } ?? false          // pour aujourd'hui ou en retard
        return HStack(spacing: 6) {
            Circle().fill(Color.white).overlay(Circle().strokeBorder(hot ? Theme.orange : wBlue, lineWidth: 2)).frame(width: 14, height: 14)
                .contentShape(Circle().inset(by: -4)).onTapGesture { ShelfSound.press(); cal.complete(r) }
                .help(L("Mark as done"))
            Text(r.title).font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundStyle(wDeep).lineLimit(1)
            Spacer(minLength: 2)
            if let d = r.due { Text(Self.day(d)).font(.system(size: 8.5, weight: .bold, design: .rounded)).foregroundStyle(hot ? Theme.orange : wInk).lineLimit(1) }
        }
        .padding(.horizontal, 10).frame(height: 22)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(red: 0.55, green: 0.75, blue: 0.9).opacity(0.38)).frame(height: 1).padding(.horizontal, 8) }
    }

    /// « 14:30 » aujourd'hui, « dem. 09:00 », « mer. 09:00 », « toute la journée ».
    private static func when(_ e: CalEvent) -> String {
        let cal = Calendar.current
        if e.allDay { return cal.isDateInToday(e.start) ? L("all day") : dayName(e.start) }
        let t = DateFormatter(); t.dateFormat = "HH:mm"
        return cal.isDateInToday(e.start) ? t.string(from: e.start) : dayName(e.start) + " " + t.string(from: e.start)
    }
    private static func dayName(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return L("today") }
        if Calendar.current.isDateInTomorrow(d) { return L("tmrw") }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day ?? 0
        let f = DateFormatter()
        if days > 6 { f.dateFormat = "d MMM"; return f.string(from: d) }          // plus loin qu'une semaine : la date (« 5 déc. »), un « ven. » serait ambigu
        f.dateFormat = "EEE"; return f.string(from: d).replacingOccurrences(of: ".", with: "")
    }
    private static func day(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return L("today") }
        if d < Calendar.current.startOfDay(for: Date()) { return L("late") }
        return dayName(d)
    }

    // MARK: Autorisation

    private var permission: some View {
        VStack(spacing: 8) {
            Text(cal.denied ? L("Access to Calendar and Reminders is off") : L("See your next events and reminders here"))
                .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(wDeep).multilineTextAlignment(.center)
            Text(cal.denied ? L("Turn it on in System Settings → Privacy & Security.") : L("Mandarine only reads them to show them here."))
                .font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(wInk).multilineTextAlignment(.center)
            Text(cal.denied ? L("Open Settings") : L("Allow"))
                .font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 6)
                .background(Capsule().fill(LinearGradient(colors: [wBlueLight, wBlue], startPoint: .top, endPoint: .bottom))).overlay(Capsule().strokeBorder(.white, lineWidth: 1.5))
                .onTapGesture {
                    ShelfSound.press()
                    if cal.denied { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!) } else { cal.requestAccess() }
                }
        }.frame(width: 334, height: 120)
    }
}


/// Réglages → Apparence : quels calendriers et quelles listes de rappels la page de l'étagère montre.
struct ShelfCalendarsPicker: View {
    @ObservedObject private var cal = CalendarStore.shared
    @ObservedObject private var s = AppSettings.shared

    var body: some View {
        Group {
            Text(L("Calendars and reminder lists shown")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if !cal.granted {
                HStack {
                    Text(cal.denied ? L("Access to Calendar and Reminders is off") : L("Allow access to choose")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(cal.denied ? L("Open Settings") : L("Allow")) {
                        if cal.denied { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!) } else { cal.requestAccess() }
                    }
                }
            } else {
                group(L("Calendars"), cal.sources.filter { !$0.reminders })
                group(L("Reminder lists"), cal.sources.filter { $0.reminders })
            }
        }
        .onAppear { cal.refresh() }
    }

    @ViewBuilder private func group(_ title: String, _ list: [CalSource]) -> some View {
        if !list.isEmpty {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
            ForEach(list) { c in
                Toggle(isOn: Binding(get: { !s.shelfCalendarsOff.contains(c.id) },
                                     set: { on in if on { s.shelfCalendarsOff.removeAll { $0 == c.id } } else if !s.shelfCalendarsOff.contains(c.id) { s.shelfCalendarsOff.append(c.id) } })) {
                    HStack(spacing: 6) {
                        Circle().fill(c.color).frame(width: 9, height: 9)
                        Text(c.title)
                        if !c.account.isEmpty { Text(c.account).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }
}
