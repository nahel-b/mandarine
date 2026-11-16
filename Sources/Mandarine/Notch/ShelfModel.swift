import SwiftUI

/// Essai de design : l'étagère de l'encoche (éléments gardés sous la main : fichiers, liens, texte).
/// Données d'exemple seulement pour l'instant ; rien n'est branché sur les vrais glisser-déposer.
enum ShelfKind {
    case image, pdf, video, audio, link, text, other

    var symbol: String {
        switch self {
        case .image: return "photo"
        case .pdf: return "doc.fill"
        case .video: return "play.rectangle.fill"
        case .audio: return "waveform"
        case .link: return "link"
        case .text: return "text.alignleft"
        case .other: return "doc"
        }
    }
    var color: Color {
        switch self {
        case .image: return Color(red: 0.29, green: 0.44, blue: 0.70)
        case .pdf: return Color(red: 0.54, green: 0.54, blue: 0.56)
        case .video: return Color(red: 0.23, green: 0.23, blue: 0.25)
        case .audio: return Color(red: 0.42, green: 0.31, blue: 0.64)
        case .link: return Color(red: 0.18, green: 0.49, blue: 0.43)
        case .text: return Color(red: 0.64, green: 0.38, blue: 0.17)
        case .other: return Color(red: 0.45, green: 0.47, blue: 0.50)
        }
    }
    var isLink: Bool { self == .link }
    var isFile: Bool { self != .link && self != .text }
}

/// Ce que l'élément est vraiment : un fichier (on garde son chemin), un lien, du texte.
enum ShelfPayload: Equatable { case file(URL), link(URL), text(String) }

struct ShelfItem: Identifiable, Equatable {
    var id = UUID()
    var payload: ShelfPayload? = nil    // nil : donnée d'exemple (essais de design)
    var kind: ShelfKind
    var name: String
    var detail: String          // taille, durée, pages…
    var age: String
    var title: String? = nil    // titre d'un lien
}

extension ShelfItem {
    /// « il y a 2 min », ou « à l'instant ».
    var agoText: String { age == L("now") ? age : L("\(age) ago") }
}

enum ShelfSample {
    static var items: [ShelfItem] {[
        ShelfItem(kind: .image, name: "photo.jpg", detail: "2400 × 1600 · 3,1 MB", age: "2 min"),
        ShelfItem(kind: .pdf, name: "rapport.pdf", detail: "12 pages · 840 KB", age: "9 min"),
        ShelfItem(kind: .video, name: "clip.mp4", detail: "0:32 · 9,7 MB", age: "20 min"),
        ShelfItem(kind: .link, name: "youtu.be/dQw4w9", detail: "Video · 3:32", age: "3 min", title: "Titre de la vidéo en cours de lecture"),
        ShelfItem(kind: .text, name: "note", detail: "Text · 240 characters", age: "1 h"),
        ShelfItem(kind: .image, name: "logo.png", detail: "512 × 512 · 48 KB", age: "1 h"),
        ShelfItem(kind: .audio, name: "voix.m4a", detail: "1:12 · 1,1 MB", age: "2 h"),
        ShelfItem(kind: .link, name: "lemonde.fr/article", detail: "Web page", age: "1 h", title: "Un article à relire plus tard"),
    ]}
}

enum ShelfDesign: String, CaseIterable, Identifiable {
    case grid, list, pile, carousel               // premiers essais : encoche noire
    case petals, channels, capsules, tab          // designs « maison » : reprennent la roue, la Wii, les notifications, les outils
    var id: String { rawValue }
    var isOriginal: Bool { self == .petals || self == .channels || self == .capsules || self == .tab }
    var title: String {
        switch self {
        case .grid: return L("Grid")
        case .list: return L("List")
        case .pile: return L("Stack")
        case .carousel: return L("Carousel")
        case .petals: return L("Petals")
        case .channels: return L("Channels")
        case .capsules: return L("Capsules")
        case .tab: return L("Blue tab")
        }
    }
}

enum ShelfState: String, CaseIterable, Identifiable {
    case empty, filled, action
    var id: String { rawValue }
    var title: String {
        switch self {
        case .empty: return L("Empty")
        case .filled: return L("Filled")
        case .action: return L("Action")
        }
    }
}
