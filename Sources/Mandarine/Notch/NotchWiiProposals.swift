import SwiftUI

// Propositions de design (Wii) pour de nouvelles choses sous l'encoche : calendrier / rappels, musique en cours, et des idées avec les Mii.
// Données fictives, rien n'est branché : `--snapshot wiinotch:calendar|music|mii sortie.png /tmp`.

private let blue = Color(red: 0.17, green: 0.63, blue: 0.88)
private let blueLight = Color(red: 0.49, green: 0.78, blue: 0.93)
private let ink = Color(red: 0.56, green: 0.58, blue: 0.60)
private let deep = Color(white: 0.30)

/// L'écran à tube de l'étagère « Wii », en taille libre.
struct WiiProposalScreen<Content: View>: View {
    var w: CGFloat
    var h: CGFloat
    var radius: CGFloat = 34
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(radius: radius).fill(LinearGradient(colors: [Color(white: 0.99), Color(red: 0.90, green: 0.91, blue: 0.93)], startPoint: .top, endPoint: .bottom))
            content()
            WiiCRT().clipShape(NotchShape(radius: radius)).allowsHitTesting(false)
            RadialGradient(colors: [.clear, Color.black.opacity(0.16)], center: .center, startRadius: 100, endRadius: 280).clipShape(NotchShape(radius: radius)).allowsHitTesting(false)
            NotchShape(radius: radius).stroke(Color.white.opacity(0.7), lineWidth: 2)
            NotchShape(radius: radius).stroke(Color.black.opacity(0.25), lineWidth: 1)
            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black).frame(width: 130, height: 24).offset(y: -2)
        }
        .frame(width: w, height: h)
        .clipShape(NotchShape(radius: radius))
        .environment(\.colorScheme, .light)
    }
}

struct WiiRoundButton: View {
    let symbol: String
    var size: CGFloat = 44
    var badge: Int? = nil
    var accent = false
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(accent ? Theme.orange : blue.opacity(0.9), lineWidth: size > 40 ? 3 : 2.5)
            Image(systemName: symbol).font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(accent ? Theme.orange : Color(white: 0.55))
            if let b = badge {
                Text("\(b)").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(.white).frame(width: 17, height: 17)
                    .background(Circle().fill(Theme.orange)).overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5)).offset(x: size * 0.34, y: size * 0.3)
            }
        }
        .frame(width: size, height: size).shadow(color: .black.opacity(0.18), radius: 3, y: 2)
    }
}

/// La barre du bas du menu Wii (heure à segments, date, deux boutons ronds).
struct WiiProposalBar: View {
    var w: CGFloat = 380
    let left: String
    let right: String
    var badge: Int? = nil
    let footer: String
    var onLeft: (() -> Void)? = nil
    var onRight: (() -> Void)? = nil
    var body: some View {
        ZStack(alignment: .topLeading) {
            WiiBar().fill(LinearGradient(colors: [.white, Color(white: 0.89)], startPoint: .top, endPoint: .bottom)).shadow(color: .black.opacity(0.10), radius: 5, y: -2)
            WiiBarLine().stroke(blue, lineWidth: 2.5)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in SevenSegmentClock(date: ctx.date).scaleEffect(0.8).position(x: w / 2, y: 9) }
            Text(footer).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(ink).position(x: w / 2, y: 57)
            WiiRoundButton(symbol: left).position(x: 34, y: 46).onTapGesture { onLeft?() }
            WiiRoundButton(symbol: right, badge: badge).position(x: w - 34, y: 46).onTapGesture { onRight?() }
        }
        .frame(width: w, height: 78)
    }
}

/// Une case à la Wii : dégradé, liseré argenté, reflet.
private struct WiiTile<Content: View>: View {
    var top: Color, bottom: Color
    var w: CGFloat, h: CGFloat
    var radius: CGFloat = 14
    var selected = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
            content()
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(LinearGradient(colors: [Color.white.opacity(0.42), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.5)))
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(selected ? AnyShapeStyle(Theme.orange) : AnyShapeStyle(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.62)], startPoint: .top, endPoint: .bottom)), lineWidth: selected ? 3.5 : 2.5)
        }
        .frame(width: w, height: h)
    }
}

private struct Caption: View {
    let title: String, text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Color(white: 0.15))
            Text(text).font(.system(size: 11.5)).foregroundStyle(Color(white: 0.3)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 380, alignment: .leading)
        }
    }
}

// MARK: Calendrier et rappels

/// C1 · « Chaîne Calendrier » : la feuille du jour à gauche, les rendez-vous en lignes à liseré bleu, barre Wii avec le nombre de rappels sur le bouton courrier.
struct WiiCalendarChannel: View {
    var body: some View {
        WiiProposalScreen(w: 380, h: 246) {
            ZStack(alignment: .top) {
                HStack(alignment: .top, spacing: 12) {
                    datePage
                    VStack(spacing: 7) {
                        row("09:30", "Point projet", Color(red: 0.55, green: 0.55, blue: 0.9), past: true)
                        row("14:30", "Réunion équipe", Theme.orange, next: true)
                        row("18:00", "Appeler Camille", Color(red: 0.2, green: 0.7, blue: 0.5))
                    }
                }
                .padding(.horizontal, 18).padding(.top, 36)
                WiiProposalBar(left: "plus", right: "envelope.fill", badge: 3, footer: "lun. 17/11").frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private var datePage: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white)
            VStack(spacing: 0) {
                ZStack {
                    UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16).fill(LinearGradient(colors: [blueLight, blue], startPoint: .top, endPoint: .bottom))
                    Text("NOVEMBRE").font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1.2).foregroundStyle(.white)
                }.frame(height: 26)
                Text("17").font(.system(size: 54, weight: .heavy, design: .rounded)).foregroundStyle(Color(red: 0.42, green: 0.50, blue: 0.58)).padding(.top, 2)
                Text("lundi").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(ink)
            }
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.62)], startPoint: .top, endPoint: .bottom), lineWidth: 2.5)
        }
        .frame(width: 108, height: 122).shadow(color: .black.opacity(0.15), radius: 3, y: 2)
    }

    private func row(_ time: String, _ title: String, _ tint: Color, next: Bool = false, past: Bool = false) -> some View {
        HStack(spacing: 8) {
            Circle().fill(tint.opacity(past ? 0.4 : 1)).frame(width: 10, height: 10)
            Text(title).font(.system(size: 12.5, weight: .bold, design: .rounded)).foregroundStyle(past ? ink.opacity(0.7) : deep).strikethrough(past).lineLimit(1)
            Spacer(minLength: 4)
            if next { Text("12 min").font(.system(size: 9.5, weight: .heavy, design: .rounded)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Theme.orange)) }
            Text(time).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(next ? blue : ink)
        }
        .padding(.horizontal, 12).frame(width: 240, height: 36)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LinearGradient(colors: [.white, Color(white: 0.93)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(next ? blue : Color(white: 0.78), lineWidth: next ? 3 : 2)))
    }
}

/// C2 · « Tableau de messages » : un papier crème rayé comme celui de la Wii, rappels à cocher, étiquette bleue du jour.
struct WiiReminderBoard: View {
    var body: some View {
        WiiProposalScreen(w: 380, h: 214) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(red: 1.0, green: 0.985, blue: 0.90))
                    .overlay(Canvas { ctx, size in for y in stride(from: CGFloat(30), to: size.height, by: 30) { ctx.fill(Path(CGRect(x: 14, y: y, width: size.width - 28, height: 1)), with: .color(Color(red: 0.55, green: 0.75, blue: 0.9).opacity(0.35))) } })
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(red: 0.9, green: 0.84, blue: 0.62), lineWidth: 2))
                    .frame(width: 344, height: 164).offset(x: 18, y: 34)
                Text("Rappels").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(blue).offset(x: 34, y: 42)
                Text("lun. 17").font(.system(size: 10.5, weight: .heavy, design: .rounded)).tracking(0.8).foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(LinearGradient(colors: [blueLight, blue], startPoint: .top, endPoint: .bottom))).offset(x: 286, y: 44)
                VStack(alignment: .leading, spacing: 8) {
                    item("Envoyer la facture", "aujourd'hui", done: true)
                    item("Réserver le train", "aujourd'hui", done: false, hot: true)
                    item("Sauvegarde du disque", "demain", done: false)
                }.offset(x: 34, y: 74)
            }
            .frame(width: 380, height: 214, alignment: .topLeading)
        }
    }
    private func item(_ text: String, _ tag: String, done: Bool, hot: Bool = false) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(done ? AnyShapeStyle(LinearGradient(colors: [blueLight, blue], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.white))
                Circle().strokeBorder(hot ? Theme.orange : blue, lineWidth: 2.5)
                if done { Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white) }
            }.frame(width: 20, height: 20)
            Text(text).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(done ? ink.opacity(0.7) : deep).strikethrough(done)
            Spacer()
            Text(tag).font(.system(size: 9.5, weight: .bold, design: .rounded)).foregroundStyle(hot ? Theme.orange : ink)
        }.frame(width: 312)
    }
}

/// C3 · « Prochain rendez-vous » : une pastille compacte sous l'encoche (aile de verre), avec le compte à rebours ; elle passe à l'orange à l'approche.
struct WiiNextEventPill: View {
    var urgent = false
    var body: some View {
        WiiProposalScreen(w: 330, h: 74, radius: 26) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(LinearGradient(colors: urgent ? [Color(red: 1, green: 0.7, blue: 0.4), Theme.orange] : [blueLight, blue], startPoint: .top, endPoint: .bottom))
                    Circle().strokeBorder(Color.white, lineWidth: 2)
                    Image(systemName: "calendar").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                }.frame(width: 34, height: 34).shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Réunion équipe").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(deep)
                    Text("Salle 2 · 14:30").font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundStyle(ink)
                }
                Spacer()
                Text(urgent ? "1 min" : "12 min").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(urgent ? Theme.orange : blue)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white).overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(urgent ? Theme.orange : blue, lineWidth: 2.5)))
            }
            .padding(.horizontal, 16).padding(.top, 26).padding(.bottom, 8)
            VStack { Spacer(); Capsule().fill(Color.black.opacity(0.08)).frame(height: 4).overlay(alignment: .leading) { Capsule().fill(urgent ? Theme.orange : blue).frame(width: urgent ? 280 : 130, height: 4) }.padding(.horizontal, 22).padding(.bottom, 7) }
        }
    }
}

// MARK: Musique en cours

private let artColors = [Color(red: 0.99, green: 0.62, blue: 0.25), Color(red: 0.86, green: 0.25, blue: 0.45), Color(red: 0.35, green: 0.25, blue: 0.75)]
private struct FakeArt: View {
    var body: some View { LinearGradient(colors: artColors, startPoint: .topLeading, endPoint: .bottomTrailing) }
}

private struct Rail: View {
    var w: CGFloat, fraction: CGFloat
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color(white: 0.82)).frame(width: w, height: 6)
            Capsule().fill(LinearGradient(colors: [blueLight, blue], startPoint: .top, endPoint: .bottom)).frame(width: w * fraction, height: 6)
            Circle().fill(Color.white).overlay(Circle().strokeBorder(blue, lineWidth: 3)).frame(width: 16, height: 16).offset(x: w * fraction - 8).shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
        }.frame(width: w, height: 16)
    }
}

/// M1 · « Disque Wii » : la chaîne Disque — un disque qui brille en bleu et tourne ; pochette au centre, titre, barre de lecture, trois boutons ronds.
struct WiiDiscChannel: View {
    var body: some View {
        WiiProposalScreen(w: 380, h: 240) {
            ZStack(alignment: .topLeading) {
                disc.position(x: 106, y: 134)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Titre de la chanson").font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(deep).lineLimit(1)
                    Text("Artiste · Album").font(.system(size: 11.5, weight: .medium, design: .rounded)).foregroundStyle(ink)
                    Rail(w: 168, fraction: 0.42).padding(.top, 8)
                    HStack { Text("1:24"); Spacer(); Text("-2:08") }.font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(ink).frame(width: 168)
                    HStack(spacing: 12) {
                        WiiRoundButton(symbol: "backward.fill", size: 36)
                        WiiRoundButton(symbol: "pause.fill", size: 46, accent: true)
                        WiiRoundButton(symbol: "forward.fill", size: 36)
                    }.padding(.top, 8)
                }.frame(width: 172, alignment: .leading).position(x: 282, y: 136)
                HStack(spacing: 4) { Image(systemName: "music.note"); Text("Musique") }.font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(LinearGradient(colors: [blueLight, blue], startPoint: .top, endPoint: .bottom))).position(x: 318, y: 46)
            }
        }
    }
    private var disc: some View {
        ZStack {
            Circle().fill(blue.opacity(0.5)).frame(width: 178, height: 178).blur(radius: 14)
            Circle().fill(AngularGradient(colors: [Color(white: 0.98), Color(white: 0.76), Color(white: 0.98), Color(white: 0.70), Color(white: 0.98)], center: .center)).frame(width: 158, height: 158)
            FakeArt().clipShape(Circle()).frame(width: 130, height: 130)
            Circle().strokeBorder(Color.white.opacity(0.65), lineWidth: 2).frame(width: 130, height: 130)
            Circle().fill(Color.white).frame(width: 30, height: 30)
            Circle().strokeBorder(Color(white: 0.72), lineWidth: 2).frame(width: 30, height: 30)
            Circle().trim(from: 0.04, to: 0.2).stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 6, lineCap: .round)).frame(width: 148, height: 148).rotationEffect(.degrees(-35))
        }
    }
}

/// M2 · « Ailes » : tout petit, de part et d'autre de la vraie encoche : la pochette (ou l'icône vidéo) à gauche, l'égaliseur bleu à droite.
struct WiiNowPlayingWings: View {
    enum Kind { case audio, video, paused }
    var kind: Kind = .audio
    var body: some View {
        WiiProposalScreen(w: 360, h: 42, radius: 21) {
            HStack {
                left.padding(.leading, 14)
                Spacer()
                right.padding(.trailing, 16)
            }
            .frame(maxHeight: .infinity)
        }
    }
    @ViewBuilder private var left: some View {
        switch kind {
        case .video:
            ZStack { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(LinearGradient(colors: [Color(red: 0.36, green: 0.80, blue: 1.0), Color(red: 0.10, green: 0.42, blue: 0.96)], startPoint: .top, endPoint: .bottom))
                Image(systemName: "play.fill").font(.system(size: 11)).foregroundStyle(.white) }
                .frame(width: 34, height: 26).overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white, lineWidth: 1.5))
        default:
            FakeArt().clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)).frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white, lineWidth: 1.5)).shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
    }
    private var right: some View {
        HStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(Array([0.5, 0.9, 0.65, 1.0, 0.4].enumerated()), id: \.offset) { _, f in
                    Capsule().fill(LinearGradient(colors: [blueLight, blue], startPoint: .top, endPoint: .bottom)).frame(width: 4, height: kind == .paused ? 4 : 18 * f)
                }
            }.frame(height: 20, alignment: .bottom)
            Text(kind == .video ? "12:41" : "1:24").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(ink)
        }
    }
}

/// M3 · « Chaîne Musique » : la case « en lecture » (avec les autres sons et vidéos qui jouent, chacun dans sa case), la barre de lecture, le volume dans la barre Wii.
struct WiiMusicChannels: View {
    var body: some View {
        WiiProposalScreen(w: 380, h: 246) {
            ZStack(alignment: .top) {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        WiiTile(top: Color(red: 1.0, green: 0.93, blue: 0.80), bottom: Color(red: 0.98, green: 0.73, blue: 0.40), w: 176, h: 58, selected: true) {
                            HStack(spacing: 8) {
                                FakeArt().clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)).frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Titre de la chanson").font(.system(size: 11.5, weight: .heavy, design: .rounded)).lineLimit(1)
                                    Text("Artiste").font(.system(size: 10, weight: .medium, design: .rounded)).opacity(0.75)
                                }
                            }.foregroundStyle(Color(red: 0.62, green: 0.30, blue: 0.05)).padding(.horizontal, 8).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        WiiTile(top: Color(red: 0.36, green: 0.80, blue: 1.0), bottom: Color(red: 0.10, green: 0.42, blue: 0.96), w: 84, h: 58) {
                            VStack(spacing: 2) { Image(systemName: "play.rectangle.fill").font(.system(size: 17)); Text("YouTube").font(.system(size: 10, weight: .bold, design: .rounded)) }.foregroundStyle(.white)
                        }
                        WiiTile(top: Color(red: 0.62, green: 0.93, blue: 0.32), bottom: Color(red: 0.06, green: 0.62, blue: 0.40), w: 84, h: 58) {
                            VStack(spacing: 2) { Image(systemName: "mic.fill").font(.system(size: 17)); Text("Podcast").font(.system(size: 10, weight: .bold, design: .rounded)) }.foregroundStyle(.white)
                        }
                    }
                    HStack(spacing: 10) {
                        WiiRoundButton(symbol: "backward.fill", size: 34)
                        WiiRoundButton(symbol: "pause.fill", size: 40, accent: true)
                        WiiRoundButton(symbol: "forward.fill", size: 34)
                        VStack(spacing: 3) { Rail(w: 150, fraction: 0.42); HStack { Text("1:24"); Spacer(); Text("3:32") }.font(.system(size: 9.5, weight: .semibold, design: .monospaced)).foregroundStyle(ink).frame(width: 150) }
                    }.padding(.horizontal, 12).frame(width: 346, height: 54)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.04)).overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.black.opacity(0.07), lineWidth: 2)))
                }.padding(.top, 36)
                WiiProposalBar(left: "speaker.wave.2.fill", right: "airplayaudio", footer: "Musique · 3 sources").frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

// MARK: Mii

/// Un Mii très simple, dessiné en SwiftUI, juste pour illustrer les idées (la vraie bibliothèque sera celle de l'utilisateur).
struct MiiFace: View {
    enum Mood { case happy, sleepy, worried, party }
    var skin = Color(red: 1.0, green: 0.84, blue: 0.70)
    var hair = Color(red: 0.35, green: 0.22, blue: 0.12)
    var shirt = blue
    var mood: Mood = .happy
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).fill(shirt).frame(width: size * 0.74, height: size * 0.36).offset(y: size * 0.42)
            Ellipse().fill(hair).frame(width: size * 0.80, height: size * 0.74).offset(y: -size * 0.12)
            Ellipse().fill(skin).frame(width: size * 0.66, height: size * 0.72).offset(y: size * 0.02)
            Ellipse().fill(hair).frame(width: size * 0.7, height: size * 0.28).offset(y: -size * 0.28)
            HStack(spacing: size * 0.17) {
                ForEach(0..<2, id: \.self) { _ in
                    if mood == .sleepy { Capsule().fill(Color(white: 0.2)).frame(width: size * 0.12, height: size * 0.025) }
                    else { Ellipse().fill(Color(white: 0.15)).frame(width: size * 0.065, height: size * 0.12) }
                }
            }.offset(y: -size * 0.01)
            mouth.offset(y: size * 0.17)
            if mood == .party { Image(systemName: "party.popper.fill").font(.system(size: size * 0.3)).foregroundStyle(Theme.orange).offset(x: size * 0.36, y: -size * 0.36) }
            if mood == .sleepy { Text("z").font(.system(size: size * 0.3, weight: .heavy, design: .rounded)).foregroundStyle(blue).offset(x: size * 0.36, y: -size * 0.34) }
        }.frame(width: size, height: size * 1.05)
    }
    @ViewBuilder private var mouth: some View {
        switch mood {
        case .worried: Capsule().fill(Color(white: 0.3)).frame(width: size * 0.12, height: size * 0.04)
        case .sleepy: Circle().fill(Color(white: 0.3)).frame(width: size * 0.07, height: size * 0.07)
        default: Path { p in p.addArc(center: CGPoint(x: size * 0.1, y: 0), radius: size * 0.1, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false) }
            .stroke(Color(red: 0.7, green: 0.25, blue: 0.2), style: StrokeStyle(lineWidth: size * 0.03, lineCap: .round)).frame(width: size * 0.2, height: size * 0.1)
        }
    }
}

/// I1 · « Mii compagnon » : un Mii dans l'aile gauche de l'encoche, qui réagit (travail fini, rien à faire, erreur) avec une bulle.
struct WiiMiiCompanion: View {
    let mood: MiiFace.Mood
    let text: String
    var body: some View {
        WiiProposalScreen(w: 360, h: 58, radius: 24) {
            HStack(spacing: 8) {
                MiiFace(mood: mood, size: 34).padding(.leading, 12)
                Spacer()
                Text(text).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(deep)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white).overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(blue, lineWidth: 2.5)))
                    .padding(.trailing, 12)
            }.padding(.top, 14)
        }
    }
}

/// I2 · « Place des Mii » : les personnes enregistrées dans Mandarine (Réglages → Personnes) se tiennent sur l'étagère ; un clic sur l'un d'eux montre ses photos.
struct WiiMiiPlaza: View {
    var body: some View {
        WiiProposalScreen(w: 380, h: 150) {
            VStack(spacing: 0) {
                Spacer().frame(height: 34)
                HStack(alignment: .bottom, spacing: 12) {
                    mii("Léa", Color(red: 1.0, green: 0.84, blue: 0.70), Color(red: 0.2, green: 0.12, blue: 0.08), Color(red: 0.2, green: 0.7, blue: 0.5), .party)
                    mii("Sam", Color(red: 0.85, green: 0.65, blue: 0.5), Color(red: 0.1, green: 0.1, blue: 0.1), Theme.orange, .happy)
                    mii("Maman", Color(red: 1.0, green: 0.86, blue: 0.74), Color(red: 0.65, green: 0.65, blue: 0.7), Color(red: 0.55, green: 0.45, blue: 0.85), .happy)
                    mii("Noa", Color(red: 0.95, green: 0.75, blue: 0.6), Color(red: 0.8, green: 0.55, blue: 0.2), blue, .sleepy)
                    mii("Inès", Color(red: 0.6, green: 0.42, blue: 0.3), Color(red: 0.1, green: 0.07, blue: 0.05), Color(red: 0.9, green: 0.3, blue: 0.45), .happy)
                }
                Capsule().fill(Color.black.opacity(0.08)).frame(width: 330, height: 7).padding(.top, 2)
                Spacer()
            }
        }
    }
    private func mii(_ name: String, _ skin: Color, _ hair: Color, _ shirt: Color, _ mood: MiiFace.Mood) -> some View {
        VStack(spacing: 2) {
            MiiFace(skin: skin, hair: hair, shirt: shirt, mood: mood, size: 50)
            Text(name).font(.system(size: 9.5, weight: .bold, design: .rounded)).foregroundStyle(ink)
        }
    }
}

/// I3 · Un Mii comme avatar dans le calendrier : l'anniversaire d'une personne enregistrée, ou la personne d'un rappel.
struct WiiMiiEvents: View {
    var body: some View {
        WiiProposalScreen(w: 380, h: 156) {
            VStack(spacing: 7) {
                line(MiiFace(skin: Color(red: 1.0, green: 0.84, blue: 0.70), hair: Color(red: 0.2, green: 0.12, blue: 0.08), shirt: Color(red: 0.2, green: 0.7, blue: 0.5), mood: .party, size: 30), "Anniversaire de Léa", "demain", hot: true)
                line(MiiFace(skin: Color(red: 0.85, green: 0.65, blue: 0.5), hair: Color(red: 0.1, green: 0.1, blue: 0.1), shirt: Theme.orange, size: 30), "Appeler Sam", "18:00", hot: false)
            }.padding(.top, 40)
        }
    }
    private func line(_ mii: MiiFace, _ title: String, _ when: String, hot: Bool) -> some View {
        HStack(spacing: 8) {
            mii.frame(width: 38, height: 34)
            Text(title).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(deep)
            Spacer()
            Text(when).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(hot ? Theme.orange : blue)
        }
        .padding(.horizontal, 12).frame(width: 340, height: 44)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LinearGradient(colors: [.white, Color(white: 0.93)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(hot ? Theme.orange : Color(white: 0.78), lineWidth: hot ? 3 : 2)))
    }
}

// MARK: Planches

struct WiiProposalSheet: View {
    let kind: String
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            switch kind {
            case "calendar":
                block("C1 · Chaîne Calendrier", "La feuille du jour, les rendez-vous en lignes à liseré bleu (le prochain entouré, avec « 12 min »), le nombre de rappels sur le bouton courrier de la barre Wii.") { WiiCalendarChannel() }
                block("C2 · Tableau de messages", "Un papier crème rayé comme le Tableau de messages de la Wii : rappels à cocher en pastilles bleues, orange pour celui qui presse.") { WiiReminderBoard() }
                block("C3 · Prochain rendez-vous", "Une pastille discrète sous l'encoche, avec une barre de temps ; elle passe à l'orange à l'approche.") { VStack(alignment: .leading, spacing: 10) { WiiNextEventPill(); WiiNextEventPill(urgent: true) } }
            case "music":
                block("M1 · Disque Wii", "La chaîne Disque : un disque qui brille en bleu et tourne (la pochette au centre), titre, barre de lecture à curseur rond, trois boutons.") { WiiDiscChannel() }
                block("M2 · Ailes (très discret)", "De part et d'autre de la vraie encoche : la pochette à gauche, l'égaliseur bleu à droite. Trois états : musique, vidéo, pause (égaliseur à plat).") { VStack(alignment: .leading, spacing: 10) { WiiNowPlayingWings(kind: .audio); WiiNowPlayingWings(kind: .video); WiiNowPlayingWings(kind: .paused) } }
                block("M3 · Chaîne Musique", "Les cases à la Wii : celle qui joue (liseré orange), et une case par autre son ou vidéo en cours ; commandes et barre de lecture dessous.") { WiiMusicChannels() }
            default:
                block("I1 · Mii compagnon", "Un Mii dans l'aile gauche de l'encoche qui réagit : content quand un travail est fini, endormi quand rien ne se passe, inquiet en cas d'erreur.") { VStack(alignment: .leading, spacing: 10) { WiiMiiCompanion(mood: .party, text: "Terminé !"); WiiMiiCompanion(mood: .sleepy, text: "Rien à faire…"); WiiMiiCompanion(mood: .worried, text: "Oups, une erreur") } }
                block("I2 · Place des Mii", "Les personnes enregistrées (Réglages → Personnes) se tiennent sur l'étagère comme sur la Place Mii ; un clic montre leurs photos ou lance Face Select.") { WiiMiiPlaza() }
                block("I3 · Mii dans le calendrier", "Chaque rendez-vous ou anniversaire prend le Mii de la personne concernée.") { WiiMiiEvents() }
            }
        }
        .padding(28).frame(width: 460, alignment: .leading)
        .background(Color(red: 0.81, green: 0.85, blue: 0.89))
    }
    private func block<V: View>(_ title: String, _ text: String, @ViewBuilder _ v: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 8) { Caption(title: title, text: text); v().shadow(color: .black.opacity(0.18), radius: 8, y: 4) }
    }
}
