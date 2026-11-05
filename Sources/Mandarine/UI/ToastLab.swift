import SwiftUI

/// Banc d'essai des styles de notification (captures : `--snapshot toaststyles:1|2|3`). Rien de ce fichier n'est utilisé par les vraies notifications.
struct LabSample {
    enum State { case running, done, failed }
    let state: State
    let caption: String
    let title: String
    var progress: Double? = nil
    var eta = ""
    var primary = ""          // bouton principal (action)
    var secondary = ""        // bouton secondaire

    static let all: [LabSample] = [
        LabSample(state: .running, caption: "Converting to WebP · 2 of 5", title: "holiday photos", progress: 0.42, eta: "About 40 s left", primary: "Cancel"),
        LabSample(state: .done, caption: "Saved · 3 s ago · Downloads", title: "photo compressed.png", primary: "Replace original", secondary: "Show"),
        LabSample(state: .failed, caption: "Failed · ffmpeg", title: "Couldn't read file", primary: "Copy error")
    ]
}

private enum Ink {
    static let text = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let muted = Color(red: 0.55, green: 0.55, blue: 0.57)
    static let page = Color(red: 0.945, green: 0.945, blue: 0.945)
}

private struct Pill: View {
    let text: String
    var symbol: String? = nil
    var fill: AnyShapeStyle = AnyShapeStyle(Color.white)
    var ink: Color = Ink.muted
    var height: CGFloat = 36
    var size: CGFloat = 14
    var shadow: Color = Color.black.opacity(0.10)
    var body: some View {
        HStack(spacing: 6) {
            if let s = symbol { Image(systemName: s).font(.system(size: size - 1, weight: .semibold)) }
            Text(text).font(.system(size: size, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(ink).padding(.horizontal, 15).frame(height: height)
        .background(Capsule().fill(fill)).shadow(color: shadow, radius: 5, y: 2)
    }
}

private struct RoundGlyph: View {
    let symbol: String
    var size: CGFloat = 30
    var fill: Color = Color(white: 0.62)
    var ink: Color = .white
    var rim: Color? = nil
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.4, weight: .heavy)).foregroundStyle(ink)
            .frame(width: size, height: size).background(Circle().fill(fill))
            .overlay(Circle().strokeBorder(rim ?? .clear, lineWidth: 4)).shadow(color: .black.opacity(0.10), radius: 3, y: 1)
    }
}

private func stateSymbol(_ s: LabSample.State) -> String { s == .running ? "arrow.triangle.2.circlepath" : (s == .done ? "checkmark" : "exclamationmark") }

// MARK: A — carte empilée, gros titre, bouton principal coloré (comme la maquette)
private struct StyleA: View {
    let s: LabSample
    var stacked = false
    private let green = Color(red: 0.30, green: 0.66, blue: 0.46)
    var body: some View {
        ZStack(alignment: .top) {
            if stacked {
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.white).frame(width: 330, height: 130).offset(y: 22).shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.white).frame(width: 360, height: 130).offset(y: 11).shadow(color: .black.opacity(0.07), radius: 6, y: 2)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.white).shadow(color: .black.opacity(0.10), radius: 12, y: 4)
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(white: 0.955)).padding(8)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: s.state == .running ? "doc.on.doc" : (s.state == .done ? "doc.text" : "exclamationmark.triangle")).font(.system(size: 25)).foregroundStyle(Color(white: 0.6)).frame(width: 34)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(s.caption).font(.system(size: 13, weight: .medium)).foregroundStyle(Ink.muted).lineLimit(1)
                            Text(s.title).font(.system(size: 24, weight: .bold)).foregroundStyle(Ink.text).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    if s.state == .running {
                        HStack(spacing: 10) {
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.black.opacity(0.08))
                                GeometryReader { g in Capsule().fill(green).frame(width: g.size.width * (s.progress ?? 0)) }
                            }.frame(height: 9)
                            Text(s.eta).font(.system(size: 12, weight: .medium)).foregroundStyle(Ink.muted).fixedSize()
                        }
                    } else {
                        HStack {
                            if !s.secondary.isEmpty { Pill(text: s.secondary, symbol: "eye", fill: AnyShapeStyle(LinearGradient(colors: [.white, Color(white: 0.93)], startPoint: .top, endPoint: .bottom))) }
                            Spacer()
                            Pill(text: s.primary, symbol: s.state == .failed ? "doc.on.doc" : "arrow.triangle.2.circlepath",
                                 fill: AnyShapeStyle(LinearGradient(colors: s.state == .failed ? [Color(white: 0.45), Color(white: 0.32)] : [Color(red: 0.36, green: 0.74, blue: 0.52), green], startPoint: .top, endPoint: .bottom)),
                                 ink: .white, shadow: (s.state == .failed ? Color.black : green).opacity(0.35))
                        }
                    }
                }.padding(.horizontal, 24).padding(.vertical, 20)
            }
            .frame(width: 390, height: 140)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 4) { RoundGlyph(symbol: "ellipsis", size: 30, rim: .white); RoundGlyph(symbol: "xmark", size: 30, rim: .white) }.offset(x: 6, y: -9)
            }
        }
        .frame(width: 400, height: stacked ? 162 : 140, alignment: .top)
    }
}

// MARK: B — capsule compacte, boutons réduits à des icônes
private struct StyleB: View {
    let s: LabSample
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Ink.text).frame(width: 34, height: 34)
                if s.state == .running, let p = s.progress {
                    Circle().trim(from: 0, to: p).stroke(Color(red: 0.95, green: 0.55, blue: 0.25), style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 34, height: 34)
                    Text("\(Int(p * 100))").font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                } else {
                    Image(systemName: stateSymbol(s.state)).font(.system(size: 13, weight: .bold)).foregroundStyle(s.state == .failed ? Color(red: 1, green: 0.5, blue: 0.45) : .white)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(s.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Ink.text).lineLimit(1)
                Text(s.state == .running ? s.eta + " · " + s.caption.components(separatedBy: " · ").last! : s.caption).font(.system(size: 11)).foregroundStyle(Ink.muted).lineLimit(1)
            }
            Spacer(minLength: 6)
            if s.state == .done {
                RoundGlyph(symbol: "eye", size: 28, fill: Color(white: 0.9), ink: Ink.text.opacity(0.7))
                RoundGlyph(symbol: "arrow.triangle.2.circlepath", size: 28, fill: Ink.text, ink: .white)
            } else if s.state == .failed { RoundGlyph(symbol: "doc.on.doc", size: 28, fill: Color(white: 0.9), ink: Ink.text.opacity(0.7)) }
            else { RoundGlyph(symbol: "stop.fill", size: 28, fill: Color(white: 0.9), ink: Ink.text.opacity(0.7)) }
            RoundGlyph(symbol: "xmark", size: 22, fill: .clear, ink: Ink.muted)
        }
        .padding(.horizontal, 12).frame(width: 380, height: 58)
        .background(ZStack { Capsule().fill(Color.black.opacity(0.07)); Capsule().fill(Color.white).padding(1) })
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

// MARK: C — sombre et dense, boutons en texte
private struct StyleC: View {
    let s: LabSample
    private let peach = Color(red: 1.0, green: 0.72, blue: 0.5)
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.state == .done ? "SAVED" : (s.state == .running ? "WORKING" : "FAILED")).font(.system(size: 10, weight: .heavy)).tracking(1.2)
                    .foregroundStyle(s.state == .failed ? Color(red: 1, green: 0.55, blue: 0.5) : peach)
                Text(s.caption.components(separatedBy: " · ").dropFirst().joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                Spacer()
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.45))
            }
            Text(s.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            if s.state == .running {
                HStack {
                    Text(s.eta).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)); Spacer()
                    Text("Cancel").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                }
            } else {
                HStack(spacing: 18) {
                    if !s.secondary.isEmpty { Text(s.secondary).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white.opacity(0.85)) }
                    Text(s.primary).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(s.state == .failed ? .white.opacity(0.85) : peach)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 13).padding(.bottom, s.state == .running ? 15 : 13)
        .frame(width: 350, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(red: 0.13, green: 0.13, blue: 0.145)))
        .overlay(alignment: .bottomLeading) {
            if s.state == .running, let p = s.progress {
                GeometryReader { g in Capsule().fill(peach).frame(width: (g.size.width - 36) * p, height: 3).offset(x: 18, y: g.size.height - 7) }
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 12, y: 5)
    }
}

// MARK: D — vignette du fichier à gauche, boutons pleine largeur en bas
private struct StyleD: View {
    let s: LabSample
    private let slate = Color(red: 0.31, green: 0.40, blue: 0.56)
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 13) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinearGradient(colors: [Color(red: 0.86, green: 0.89, blue: 0.94), Color(red: 0.74, green: 0.80, blue: 0.90)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 58, height: 58)
                    .overlay(Image(systemName: s.state == .failed ? "exclamationmark.triangle" : "photo").font(.system(size: 22)).foregroundStyle(slate))
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.caption).font(.system(size: 11.5)).foregroundStyle(Ink.muted).lineLimit(1)
                    Text(s.title).font(.system(size: 17, weight: .bold)).foregroundStyle(Ink.text).lineLimit(1)
                    if s.state == .running { Text(s.eta).font(.system(size: 11.5, weight: .medium)).foregroundStyle(slate) }
                }
                Spacer(minLength: 0)
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Ink.muted).frame(width: 22, height: 22).background(Circle().fill(Color.black.opacity(0.06)))
            }
            if s.state == .running {
                ZStack(alignment: .leading) {
                    Capsule().fill(slate.opacity(0.14))
                    GeometryReader { g in Capsule().fill(slate).frame(width: g.size.width * (s.progress ?? 0)) }
                }.frame(height: 6)
            } else {
                HStack(spacing: 8) {
                    if !s.secondary.isEmpty { btn(s.secondary, "eye", filled: false) }
                    btn(s.primary, s.state == .failed ? "doc.on.doc" : "arrow.triangle.2.circlepath", filled: s.state != .failed)
                }
            }
        }
        .padding(14).frame(width: 360)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.black.opacity(0.05), lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
    }
    private func btn(_ t: String, _ sym: String, filled: Bool) -> some View {
        HStack(spacing: 6) { Image(systemName: sym).font(.system(size: 12, weight: .semibold)); Text(t).font(.system(size: 13, weight: .semibold)) }
            .foregroundStyle(filled ? .white : slate).frame(maxWidth: .infinity).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(filled ? slate : slate.opacity(0.12)))
    }
}

// MARK: E — papier chaud, boutons empilés à droite
private struct StyleE: View {
    let s: LabSample
    private let terracotta = Color(red: 0.78, green: 0.40, blue: 0.28)
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(s.caption).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color(red: 0.55, green: 0.48, blue: 0.42)).lineLimit(1)
                Text(s.title).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Color(red: 0.2, green: 0.16, blue: 0.13)).lineLimit(2)
                if s.state == .running {
                    ZStack(alignment: .leading) {
                        Capsule().fill(terracotta.opacity(0.16))
                        GeometryReader { g in Capsule().fill(terracotta).frame(width: g.size.width * (s.progress ?? 0)) }
                    }.frame(height: 6)
                    Text(s.eta).font(.system(size: 11)).foregroundStyle(Color(red: 0.55, green: 0.48, blue: 0.42))
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 7) {
                if s.state == .done {
                    small(s.primary, filled: true)
                    small(s.secondary, filled: false)
                } else { small(s.primary, filled: s.state == .failed) }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 15).frame(width: 380)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(red: 0.995, green: 0.975, blue: 0.94)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color(red: 0.88, green: 0.82, blue: 0.74), lineWidth: 1))
        .overlay(alignment: .topLeading) { Circle().fill(s.state == .failed ? Color(red: 0.8, green: 0.25, blue: 0.2) : terracotta).frame(width: 8, height: 8).offset(x: 8, y: 8) }
        .shadow(color: Color(red: 0.4, green: 0.3, blue: 0.2).opacity(0.14), radius: 10, y: 4)
    }
    private func small(_ t: String, filled: Bool) -> some View {
        Text(t).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(filled ? .white : terracotta).frame(width: 128, height: 30)
            .background(Capsule().fill(filled ? terracotta : terracotta.opacity(0.13)))
    }
}

// MARK: F — liseré de couleur à gauche, liens soulignés
private struct StyleF: View {
    let s: LabSample
    private let teal = Color(red: 0.20, green: 0.52, blue: 0.54)
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(s.state == .failed ? Color(red: 0.78, green: 0.30, blue: 0.28) : teal).frame(width: 5)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(s.title).font(.system(size: 15.5, weight: .bold)).foregroundStyle(Ink.text).lineLimit(1)
                    Spacer()
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Ink.muted)
                }
                Text(s.state == .running ? s.caption + " — " + s.eta : s.caption).font(.system(size: 12)).foregroundStyle(Ink.muted).lineLimit(1)
                if s.state == .running {
                    ZStack(alignment: .leading) { Rectangle().fill(teal.opacity(0.15)); GeometryReader { g in Rectangle().fill(teal).frame(width: g.size.width * (s.progress ?? 0)) } }.frame(height: 3).padding(.top, 2)
                } else {
                    HStack(spacing: 16) {
                        Text(s.primary).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(s.state == .failed ? Ink.text : teal).underline()
                        if !s.secondary.isEmpty { Text(s.secondary).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Ink.muted).underline() }
                    }.padding(.top, 2)
                }
            }.padding(.horizontal, 14).padding(.vertical, 12)
        }
        .frame(width: 340)
        .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.black.opacity(0.07), lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
    }
}


// MARK: Variantes entre A et B

/// A1 — carte fine : liseré blanc, titre plus petit, boutons plus bas, un seul ✕ rond. Vert sauge.
private struct StyleA1: View {
    let s: LabSample
    private let sage = Color(red: 0.34, green: 0.62, blue: 0.47)
    var body: some View {
        ZStack(alignment: .top) {
            if s.state == .done {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white).frame(width: 316, height: 100).offset(y: 16).shadow(color: .black.opacity(0.06), radius: 5, y: 2)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white).shadow(color: .black.opacity(0.10), radius: 10, y: 3)
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(white: 0.955)).padding(6)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: s.state == .failed ? "exclamationmark.triangle" : "doc.text").font(.system(size: 19)).foregroundStyle(Color(white: 0.6)).frame(width: 26)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(s.caption).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Ink.muted).lineLimit(1)
                            Text(s.title).font(.system(size: 18, weight: .bold)).foregroundStyle(Ink.text).lineLimit(1)
                        }
                    }
                    if s.state == .running {
                        HStack(spacing: 8) {
                            ZStack(alignment: .leading) { Capsule().fill(Color.black.opacity(0.08)); GeometryReader { g in Capsule().fill(sage).frame(width: g.size.width * (s.progress ?? 0)) } }.frame(height: 7)
                            Text(s.eta).font(.system(size: 11, weight: .medium)).foregroundStyle(Ink.muted).fixedSize()
                        }
                    } else {
                        HStack(spacing: 8) {
                            if !s.secondary.isEmpty { Pill(text: s.secondary, symbol: "eye", height: 30, size: 12.5) }
                            Spacer()
                            Pill(text: s.primary, symbol: s.state == .failed ? "doc.on.doc" : "arrow.triangle.2.circlepath",
                                 fill: AnyShapeStyle(s.state == .failed ? Color(white: 0.4) : sage), ink: .white, height: 30, size: 12.5, shadow: sage.opacity(0.3))
                        }
                    }
                }.padding(.horizontal, 18).padding(.vertical, 13)
            }
            .frame(width: 350, height: s.state == .running ? 92 : 104)
            .overlay(alignment: .topTrailing) { RoundGlyph(symbol: "xmark", size: 26, rim: .white).offset(x: 5, y: -8) }
        }
        .frame(width: 370, height: s.state == .done ? 120 : (s.state == .running ? 92 : 104), alignment: .top)
    }
}

/// A2 — carte une ligne : le gros titre à gauche, le bouton principal à droite sur la même ligne ; graphite et blanc.
private struct StyleA2: View {
    let s: LabSample
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.white).shadow(color: .black.opacity(0.10), radius: 12, y: 4)
            RoundedRectangle(cornerRadius: 21, style: .continuous).fill(Color(white: 0.955)).padding(7)
            VStack(alignment: .leading, spacing: 6) {
                Text(s.caption).font(.system(size: 12, weight: .medium)).foregroundStyle(Ink.muted).lineLimit(1)
                HStack(spacing: 10) {
                    Text(s.title).font(.system(size: 22, weight: .bold)).foregroundStyle(Ink.text).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 4)
                    if s.state == .running { Text(s.eta).font(.system(size: 12, weight: .medium)).foregroundStyle(Ink.muted).fixedSize() }
                    else {
                        if !s.secondary.isEmpty { RoundGlyph(symbol: "eye", size: 32, fill: .white, ink: Ink.muted, rim: nil) }
                        Pill(text: s.state == .failed ? "Copy" : "Replace", symbol: s.state == .failed ? "doc.on.doc" : "arrow.triangle.2.circlepath",
                             fill: AnyShapeStyle(Ink.text), ink: .white, height: 32, size: 13, shadow: .black.opacity(0.25))
                    }
                }
                if s.state == .running {
                    ZStack(alignment: .leading) { Capsule().fill(Color.black.opacity(0.08)); GeometryReader { g in Capsule().fill(Ink.text).frame(width: g.size.width * (s.progress ?? 0)) } }.frame(height: 6).padding(.top, 2)
                }
            }.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 380, height: s.state == .running ? 100 : 92)
        .overlay(alignment: .topTrailing) { RoundGlyph(symbol: "xmark", size: 26, fill: Color(white: 0.55), rim: .white).offset(x: 6, y: -8) }
    }
}

/// A3 — carte avec pastille d'état et mot-clé en capitales ; bleu ardoise.
private struct StyleA3: View {
    let s: LabSample
    private let slate = Color(red: 0.30, green: 0.40, blue: 0.56)
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.white).shadow(color: .black.opacity(0.10), radius: 12, y: 4)
            RoundedRectangle(cornerRadius: 23, style: .continuous).fill(Color(red: 0.95, green: 0.955, blue: 0.965)).padding(7)
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text(s.state == .done ? "SAVED" : (s.state == .running ? "WORKING" : "FAILED")).font(.system(size: 10, weight: .heavy)).tracking(1)
                        .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(s.state == .failed ? Color(red: 0.76, green: 0.30, blue: 0.28) : slate))
                    Text(s.caption.components(separatedBy: " · ").dropFirst().joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(Ink.muted).lineLimit(1)
                    Spacer()
                }
                Text(s.title).font(.system(size: 21, weight: .bold)).foregroundStyle(Ink.text).lineLimit(1)
                if s.state == .running {
                    HStack(spacing: 8) {
                        ZStack(alignment: .leading) { Capsule().fill(slate.opacity(0.15)); GeometryReader { g in Capsule().fill(slate).frame(width: g.size.width * (s.progress ?? 0)) } }.frame(height: 7)
                        Text(s.eta).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Ink.muted).fixedSize()
                    }
                } else {
                    HStack(spacing: 8) {
                        if !s.secondary.isEmpty { Pill(text: s.secondary, symbol: "eye", fill: AnyShapeStyle(slate.opacity(0.12)), ink: slate, height: 32, size: 13, shadow: .clear) }
                        Pill(text: s.primary, symbol: s.state == .failed ? "doc.on.doc" : "arrow.triangle.2.circlepath", fill: AnyShapeStyle(s.state == .failed ? Color(white: 0.4) : slate), ink: .white, height: 32, size: 13, shadow: slate.opacity(0.3))
                        Spacer()
                    }
                }
            }.padding(.horizontal, 24).padding(.vertical, 17)
        }
        .frame(width: 370, height: s.state == .running ? 120 : 122)
        .overlay(alignment: .topTrailing) { HStack(spacing: 4) { RoundGlyph(symbol: "xmark", size: 28, fill: Color(white: 0.6), rim: .white) }.offset(x: 6, y: -9) }
    }
}

/// B1 — capsule avec le liseré blanc épais de A et un vrai bouton vert à droite.
private struct StyleB1: View {
    let s: LabSample
    private let sage = Color(red: 0.34, green: 0.62, blue: 0.47)
    var body: some View {
        ZStack {
            Capsule().fill(Color.white).shadow(color: .black.opacity(0.10), radius: 10, y: 3)
            Capsule().fill(Color(white: 0.955)).padding(5)
            HStack(spacing: 11) {
                ZStack {
                    Circle().fill(s.state == .failed ? Color(red: 0.78, green: 0.32, blue: 0.3) : sage).frame(width: 36, height: 36)
                    if s.state == .running, let p = s.progress {
                        Circle().trim(from: 0, to: p).stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 26, height: 26)
                    } else { Image(systemName: stateSymbol(s.state)).font(.system(size: 14, weight: .bold)).foregroundStyle(.white) }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Ink.text).lineLimit(1)
                    Text(s.state == .running ? s.eta : s.caption).font(.system(size: 11.5)).foregroundStyle(Ink.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                if s.state == .running { RoundGlyph(symbol: "xmark", size: 26, fill: Color(white: 0.88), ink: Ink.muted) }
                else {
                    if !s.secondary.isEmpty { RoundGlyph(symbol: "eye", size: 30, fill: .white, ink: Ink.muted) }
                    Pill(text: s.state == .failed ? "Copy" : "Replace", fill: AnyShapeStyle(s.state == .failed ? Color(white: 0.4) : sage), ink: .white, height: 32, size: 13, shadow: sage.opacity(0.3))
                }
            }.padding(.horizontal, 18)
        }
        .frame(width: 430, height: 66)
        .overlay(alignment: .topTrailing) { if s.state != .running { RoundGlyph(symbol: "xmark", size: 22, fill: Color(white: 0.6), rim: .white).offset(x: 2, y: -6) } }
    }
}

/// B2 — capsule graphite sur cartes empilées, icônes seules.
private struct StyleB2: View {
    let s: LabSample
    var body: some View {
        ZStack(alignment: .top) {
            if s.state == .done {
                Capsule().fill(Color.white).frame(width: 300, height: 56).offset(y: 14).shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                Capsule().fill(Color.white).frame(width: 340, height: 56).offset(y: 7).shadow(color: .black.opacity(0.07), radius: 4, y: 2)
            }
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Ink.text).frame(width: 36, height: 36)
                    .overlay(Image(systemName: stateSymbol(s.state)).font(.system(size: 14, weight: .bold)).foregroundStyle(s.state == .failed ? Color(red: 1, green: 0.55, blue: 0.5) : .white))
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.title).font(.system(size: 14.5, weight: .bold)).foregroundStyle(Ink.text).lineLimit(1)
                    Text(s.state == .running ? s.eta : s.caption).font(.system(size: 11.5)).foregroundStyle(Ink.muted).lineLimit(1)
                }
                Spacer(minLength: 6)
                if s.state == .done {
                    RoundGlyph(symbol: "eye", size: 28, fill: Color(white: 0.92), ink: Ink.text.opacity(0.7))
                    RoundGlyph(symbol: "arrow.triangle.2.circlepath", size: 28, fill: Ink.text, ink: .white)
                } else { RoundGlyph(symbol: s.state == .failed ? "doc.on.doc" : "stop.fill", size: 28, fill: Color(white: 0.92), ink: Ink.text.opacity(0.7)) }
            }
            .padding(.horizontal, 14).frame(width: 380, height: 60)
            .background(Capsule().fill(Color.white).shadow(color: .black.opacity(0.12), radius: 10, y: 3))
            .overlay(alignment: .bottom) {
                if s.state == .running, let p = s.progress { GeometryReader { g in Capsule().fill(Ink.text).frame(width: (g.size.width - 60) * p, height: 3).offset(x: 30, y: g.size.height - 6) } }
            }
            .overlay(alignment: .topTrailing) { RoundGlyph(symbol: "xmark", size: 22, fill: Color(white: 0.6), rim: .white).offset(x: 2, y: -7) }
        }
        .frame(width: 390, height: s.state == .done ? 78 : 66, alignment: .top)
    }
}

/// B3 — la capsule se remplit comme une barre de progression (sable + orange discret) ; devient verte une fois finie.
private struct StyleB3: View {
    let s: LabSample
    private let sand = Color(red: 0.96, green: 0.90, blue: 0.82)
    private let tang = Color(red: 0.93, green: 0.50, blue: 0.24)
    var body: some View {
        ZStack {
            Capsule().fill(Color.white)
            if s.state == .running {
                GeometryReader { g in Capsule().fill(LinearGradient(colors: [sand, Color(red: 0.97, green: 0.82, blue: 0.66)], startPoint: .leading, endPoint: .trailing)).frame(width: g.size.width * (s.progress ?? 0)) }
            } else if s.state == .done { Capsule().fill(Color(red: 0.90, green: 0.95, blue: 0.91)) }
            else { Capsule().fill(Color(red: 0.97, green: 0.90, blue: 0.89)) }
            HStack(spacing: 11) {
                Image(systemName: stateSymbol(s.state)).font(.system(size: 14, weight: .bold)).foregroundStyle(s.state == .done ? Color(red: 0.25, green: 0.55, blue: 0.38) : (s.state == .failed ? Color(red: 0.74, green: 0.28, blue: 0.26) : tang)).frame(width: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.title).font(.system(size: 14.5, weight: .bold)).foregroundStyle(Ink.text).lineLimit(1)
                    Text(s.state == .running ? s.caption + " · " + s.eta : s.caption).font(.system(size: 11.5)).foregroundStyle(Ink.text.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if s.state == .done {
                    Text("Show").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Ink.text.opacity(0.6))
                    Pill(text: "Replace", symbol: "arrow.triangle.2.circlepath", fill: AnyShapeStyle(Color(red: 0.25, green: 0.55, blue: 0.38)), ink: .white, height: 30, size: 12.5, shadow: .clear)
                } else if s.state == .failed { Pill(text: "Copy", fill: AnyShapeStyle(Color(white: 0.4)), ink: .white, height: 30, size: 12.5, shadow: .clear) }
                else { Text("Cancel").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Ink.text.opacity(0.6)) }
            }.padding(.horizontal, 18)
        }
        .clipShape(Capsule())
        .frame(width: 430, height: 58)
        .shadow(color: .black.opacity(0.11), radius: 10, y: 3)
    }
}

/// Planche de comparaison : deux styles côte à côte, chacun avec un travail en cours, un résultat avec « Replace original » et une erreur.
struct ToastLab: View {
    let page: Int
    private var pair: [(String, String)] {
        switch page {
        case 4: return [("A1", "Slim card · sage"), ("A2", "One-line card · graphite"), ("A3", "Card with state chip · slate")]
        case 5: return [("B1", "Capsule with thick rim · green button"), ("B2", "Stacked capsule · graphite icons"), ("B3", "Capsule that fills up · sand & tangerine")]
        case 1: return [("A", "Stacked card · big title · green action"), ("B", "Compact capsule · icon buttons")]
        case 2: return [("C", "Dark & dense · text buttons"), ("D", "File tile · full-width buttons")]
        default: return [("E", "Warm paper · buttons on the right"), ("F", "Left stripe · underlined links")]
        }
    }
    private func card(_ id: String, _ s: LabSample) -> AnyView {
        switch id {
        case "A": return AnyView(StyleA(s: s, stacked: s.state == .done))
        case "A1": return AnyView(StyleA1(s: s))
        case "A2": return AnyView(StyleA2(s: s))
        case "A3": return AnyView(StyleA3(s: s))
        case "B1": return AnyView(StyleB1(s: s))
        case "B2": return AnyView(StyleB2(s: s))
        case "B3": return AnyView(StyleB3(s: s))
        case "B": return AnyView(StyleB(s: s))
        case "C": return AnyView(StyleC(s: s))
        case "D": return AnyView(StyleD(s: s))
        case "E": return AnyView(StyleE(s: s))
        default: return AnyView(StyleF(s: s))
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 30) {
            ForEach(pair, id: \.0) { id, name in
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Text(id).font(.system(size: 13, weight: .heavy)).foregroundStyle(.white).frame(width: 24, height: 24).background(Circle().fill(Ink.text))
                        Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Ink.text)
                    }
                    ForEach(LabSample.all, id: \.title) { s in card(id, s) }
                }
            }
        }
        .padding(34).background(Ink.page).environment(\.colorScheme, .light)
    }
}
