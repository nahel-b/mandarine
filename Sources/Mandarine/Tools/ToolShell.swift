import UniformTypeIdentifiers
import AppKit
import SwiftUI

/// Cadre commun des fenêtres d'outils : ✕ rond à gauche, titre centré, contenu, pied avec action.
struct ToolShell<Content: View, Footer: View>: View {
    let title: String
    let close: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer
    @ObservedObject private var settings = AppSettings.shared

    private var style: ToolStyle { ToolStyle.current }

    @ViewBuilder var body: some View {
        let st = style
        switch st {
        case .rail: railLayout
        case .islands: islandsLayout
        case .folder: folderLayout
        case .brutal: brutalLayout
        case .retro: retroLayout
        case .capsule: capsuleLayout
        case .sticky: stickyLayout
        case .notepad: notepadLayout
        case .stamp: stampLayout
        case .bubble: bubbleLayout
        case .polaroid: polaroidLayout
        case .ticket: ticketLayout
        default: framedLayout(st)
        }
    }

    private var inner: some View { content().environment(\.toolStyle, .classic) }
    private func actions(_ st: ToolStyle) -> some View { footer().environment(\.toolStyle, st) }

    // MARK: Styles de couleur (même structure : bandeau, contenu, pied)

    private func framedLayout(_ st: ToolStyle) -> some View {
        VStack(spacing: 0) {
            header(st)
            if st == .classic { Divider().opacity(0.6) }
            inner.padding(16)
            if st == .classic { Divider().opacity(0.6) }
            footerBar(st)
        }
        .background(background(st))
        .clipShape(RoundedRectangle(cornerRadius: st.cornerRadius, style: .continuous))
        .overlay(rim(st))
        .environment(\.colorScheme, .light)
    }

    // MARK: Styles de structure

    /// Rail : le titre et les boutons dans une colonne à gauche, le contenu à droite.
    private var railLayout: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                closeCircle(Theme.text.opacity(0.75), Color.black.opacity(0.08))
                Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                VStack(spacing: 8) { actions(.rail) }
            }
            .padding(14).frame(width: 178).frame(maxHeight: .infinity, alignment: .topLeading)
            .background(Color.black.opacity(0.05)).background(DragZone())
            Divider().opacity(0.5)
            inner.padding(16)
        }
        .background(.regularMaterial).background(Color.white.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .light)
    }

    /// Îlots : trois cartes séparées qui flottent (titre, contenu, boutons).
    private var islandsLayout: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                closeCircle(Theme.text.opacity(0.75), Color.black.opacity(0.07))
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 10).frame(height: 46).background(DragZone()).background(card(18))
            inner.padding(16).background(card(24))
            HStack(spacing: 8) { Spacer(); actions(.islands) }.padding(.horizontal, 12).padding(.vertical, 10).background(card(18))
        }
        .padding(.horizontal, 30).padding(.top, 22).padding(.bottom, 42)
        .environment(\.colorScheme, .light)
    }

    private func card(_ r: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: r, style: .continuous).fill(.regularMaterial)
            .background(RoundedRectangle(cornerRadius: r, style: .continuous).fill(Color.white.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).stroke(Color.black.opacity(0.06), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
    }

    /// Dossier : le titre dans l'onglet d'une chemise cartonnée.
    private var folderLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                closeCircle(Color(red: 0.4, green: 0.3, blue: 0.15), Color.black.opacity(0.08))
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(red: 0.3, green: 0.24, blue: 0.14)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 12).padding(.trailing, 28).frame(width: 222, height: 38, alignment: .leading).background(DragZone())
            inner.padding(16).padding(.top, 2)
            Rectangle().fill(Color(red: 0.74, green: 0.62, blue: 0.4).opacity(0.35)).frame(height: 1).padding(.horizontal, 16)
            HStack(spacing: 8) { Spacer(); actions(.folder) }.padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(FolderShape().fill(LinearGradient(colors: [Color(red: 0.99, green: 0.96, blue: 0.88), Color(red: 0.98, green: 0.94, blue: 0.84)], startPoint: .top, endPoint: .bottom)))
        .overlay(FolderShape().stroke(Color(red: 0.74, green: 0.62, blue: 0.4), lineWidth: 1.5))
        .padding(2)
        .environment(\.colorScheme, .light)
    }

    /// Brutaliste : gros traits noirs, ombre dure décalée, angles droits, police à chasse fixe.
    private var brutalLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .black)).foregroundStyle(.black)
                        .frame(width: 28, height: 28).background(Color.white).overlay(Rectangle().stroke(Color.black, lineWidth: 2.5))
                }.buttonStyle(.plain).background(DragZone(blocks: true))
                Text(title.uppercased()).font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundStyle(.black)
                Spacer()
            }
            .padding(.horizontal, 10).frame(height: 48).background(Theme.orange).background(DragZone())
            Rectangle().fill(Color.black).frame(height: 3)
            inner.padding(16).background(Color(red: 1.0, green: 0.98, blue: 0.9))
            Rectangle().fill(Color.black).frame(height: 3)
            HStack(spacing: 10) { Spacer(); actions(.brutal) }.padding(.horizontal, 14).padding(.vertical, 12).background(Color(red: 1.0, green: 0.93, blue: 0.62))
        }
        .overlay(Rectangle().stroke(Color.black, lineWidth: 3.5))
        .background(Rectangle().fill(Color.black).offset(x: 8, y: 8))
        .padding(.leading, 6).padding(.top, 6).padding(.trailing, 14).padding(.bottom, 14)
        .environment(\.colorScheme, .light)
    }

    /// Rétro : fenêtre de Mac des années 90 — bandeau rayé, case de fermeture carrée, panneau creusé.
    private var retroLayout: some View {
        VStack(spacing: 0) {
            ZStack {
                Canvas { ctx, size in
                    for y in stride(from: CGFloat(5), to: size.height - 4, by: 3) { ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Color.black.opacity(0.55))) }
                }
                HStack {
                    Button(action: close) { Rectangle().fill(Color.white).frame(width: 14, height: 14).overlay(Rectangle().stroke(Color.black, lineWidth: 1.5)).padding(10).contentShape(Rectangle()) }
                        .buttonStyle(.plain).background(DragZone(blocks: true))
                    Spacer()
                }
                Text(title).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.black).padding(.horizontal, 12).padding(.vertical, 1).background(Color(white: 0.87))
            }
            .frame(height: 28).background(Color(white: 0.87)).background(DragZone())
            Rectangle().fill(Color.black).frame(height: 1.5)
            inner.padding(14).background(Color.white).overlay(Rectangle().stroke(Color.black, lineWidth: 1.5)).padding(10)
            HStack(spacing: 12) { Spacer(); actions(.retro) }.padding(.horizontal, 14).padding(.bottom, 12)
        }
        .background(Color(white: 0.87))
        .overlay(Rectangle().stroke(Color.black, lineWidth: 1.5))
        .background(Rectangle().fill(Color.black).offset(x: 3, y: 3))
        .clipShape(Rectangle())
        .padding(.leading, 2).padding(.top, 2).padding(.trailing, 6).padding(.bottom, 6)
        .environment(\.colorScheme, .light)
    }

    /// Capsule : pas de bandeau — le titre est une pastille à cheval sur le bord haut, les boutons une barre flottante à cheval sur le bord bas.
    private var capsuleLayout: some View {
        ZStack(alignment: .top) {
            inner.padding(.horizontal, 18).padding(.top, 40).padding(.bottom, 38)
                .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(.regularMaterial)
                    .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.white.opacity(0.7))))
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Color.black.opacity(0.06), lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
                .padding(.top, 20).padding(.bottom, 24)
            HStack(spacing: 8) {
                closeCircle(Theme.text.opacity(0.75), Color.black.opacity(0.07), size: 24)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
            }
            .padding(.leading, 8).padding(.trailing, 16).padding(.vertical, 6).background(DragZone())
            .background(Capsule().fill(.regularMaterial).background(Capsule().fill(Color.white.opacity(0.85))).shadow(color: .black.opacity(0.22), radius: 7, y: 3))
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 8) { actions(.capsule) }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(.regularMaterial).background(Capsule().fill(Color.white.opacity(0.9))).shadow(color: .black.opacity(0.25), radius: 8, y: 4))
        }
        .padding(.horizontal, 30).padding(.top, 18).padding(.bottom, 40)          // marge pour que les ombres ne soient pas rognées par le bord de la fenêtre
        .environment(\.colorScheme, .light)
    }

    /// Pense-bête : papier jaune, bande collante, punaise qui sert de ✕, coin replié, titre à la main.
    private var stickyLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Rectangle().fill(Color.black.opacity(0.07)).frame(height: 30)
                HStack(spacing: 8) {
                    Spacer()
                    Text(title).font(.custom("Marker Felt Wide", size: 18)).foregroundStyle(Color(red: 0.32, green: 0.25, blue: 0.1))
                    Spacer()
                }
                HStack {
                    Button(action: close) {
                        ZStack {
                            Circle().fill(RadialGradient(colors: [Color(red: 1.0, green: 0.45, blue: 0.4), Color(red: 0.78, green: 0.12, blue: 0.14)], center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: 14))
                                .frame(width: 22, height: 22).shadow(color: .black.opacity(0.35), radius: 2, x: 1, y: 2)
                            Image(systemName: "xmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white.opacity(0.9))
                        }.frame(width: 40, height: 40).contentShape(Rectangle())
                    }.buttonStyle(.plain).background(DragZone(blocks: true))
                    Spacer()
                }.padding(.leading, 6)
            }.frame(height: 44).background(DragZone())
            inner.padding(16).padding(.top, 2)
            HStack(spacing: 8) { Spacer(); actions(.sticky) }.padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 34)
        }
        .background(
            ZStack(alignment: .bottomTrailing) {
                FoldedCornerShape().fill(LinearGradient(colors: [Color(red: 1.0, green: 0.96, blue: 0.62), Color(red: 0.99, green: 0.9, blue: 0.45)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.25), radius: 8, x: 2, y: 5)
                Path { p in p.move(to: CGPoint(x: 28, y: 0)); p.addLine(to: CGPoint(x: 28, y: 28)); p.addLine(to: CGPoint(x: 0, y: 28)); p.closeSubpath() }
                    .fill(LinearGradient(colors: [Color(red: 0.86, green: 0.76, blue: 0.3), Color(red: 0.96, green: 0.88, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28).shadow(color: .black.opacity(0.2), radius: 2, x: -1, y: -1)
            }
        )
        .padding(.leading, 8).padding(.top, 6).padding(.trailing, 14).padding(.bottom, 14)
        .environment(\.colorScheme, .light)
    }

    /// Bloc-notes : spirale en haut, titre au feutre.
    private var notepadLayout: some View {
        VStack(spacing: 0) {
            ZStack {
                Canvas { ctx, size in
                    for x in stride(from: CGFloat(22), to: size.width - 14, by: 20) {
                        let ring = Path(roundedRect: CGRect(x: x - 3.5, y: 2, width: 7, height: 22), cornerRadius: 3.5)
                        ctx.fill(ring, with: .linearGradient(Gradient(colors: [Color(white: 0.82), Color(white: 0.42)]), startPoint: CGPoint(x: x - 3, y: 0), endPoint: CGPoint(x: x + 3, y: 0)))
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: 17, width: 6, height: 6)), with: .color(Color(white: 0.2)))
                    }
                }
            }.frame(height: 26).zIndex(2)
            HStack(spacing: 8) {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.text.opacity(0.7))
                        .frame(width: 24, height: 24).background(Circle().fill(Color.black.opacity(0.07))).frame(width: 36, height: 34).contentShape(Rectangle())
                }.buttonStyle(.plain).background(DragZone(blocks: true))
                Text(title).font(.custom("Marker Felt Thin", size: 20)).foregroundStyle(Color(red: 0.12, green: 0.2, blue: 0.5))
                Spacer()
            }.padding(.horizontal, 8).frame(height: 40).background(DragZone())
            Rectangle().fill(Color(red: 0.9, green: 0.35, blue: 0.35).opacity(0.55)).frame(height: 1.5)
            inner.padding(16)
            HStack(spacing: 8) { Spacer(); actions(.notepad) }.padding(.horizontal, 16).padding(.bottom, 14)
        }
        .background(Color(red: 0.995, green: 0.995, blue: 0.97))
        .overlay(alignment: .top) { Rectangle().fill(Color(white: 0.22)).frame(height: 18) }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.black.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 9, y: 5).padding(14)
        .environment(\.colorScheme, .light)
    }

    /// Timbre-poste : bord dentelé, filet intérieur, titre en petites capitales.
    private var stampLayout: some View {
        let ink = Color(red: 0.2, green: 0.25, blue: 0.42)
        return VStack(spacing: 0) {
            ZStack {
                Text(title.uppercased()).font(.system(size: 13, weight: .semibold, design: .serif)).kerning(2.2).foregroundStyle(ink)
                HStack { Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(ink)
                        .frame(width: 22, height: 22).overlay(Circle().stroke(ink, lineWidth: 1.3)).frame(width: 34, height: 34).contentShape(Rectangle())
                }.buttonStyle(.plain).background(DragZone(blocks: true)); Spacer() }
            }.frame(height: 40).background(DragZone())
            Rectangle().fill(ink.opacity(0.5)).frame(height: 1).padding(.horizontal, 10)
            inner.padding(14)
            Rectangle().fill(ink.opacity(0.5)).frame(height: 1).padding(.horizontal, 10)
            HStack(spacing: 8) { Spacer(); actions(.stamp) }.padding(.horizontal, 14).padding(.vertical, 12)
        }
        .padding(14)
        .background(ScallopShape().fill(Color(red: 0.995, green: 0.985, blue: 0.95), style: FillStyle(eoFill: true)).clipShape(Rectangle()).shadow(color: .black.opacity(0.22), radius: 8, y: 4))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(ink.opacity(0.55), lineWidth: 1.4).padding(10))
        .padding(10)
        .environment(\.colorScheme, .light)
    }

    /// Bulle de dialogue avec sa queue.
    private var bubbleLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
                        .frame(width: 24, height: 24).background(Circle().fill(Color.black.opacity(0.06))).frame(width: 36, height: 36).contentShape(Rectangle())
                }.buttonStyle(.plain).background(DragZone(blocks: true))
            }.padding(.leading, 20).padding(.trailing, 8).padding(.top, 8).frame(height: 46).background(DragZone())
            inner.padding(.horizontal, 16).padding(.bottom, 12)
            HStack(spacing: 8) { Spacer(); actions(.bubble) }.padding(.horizontal, 16).padding(.bottom, 16)
            Color.clear.frame(height: 18)
        }
        .background(BubbleShape().fill(.regularMaterial).background(BubbleShape().fill(Color.white.opacity(0.78))).shadow(color: .black.opacity(0.22), radius: 12, y: 5))
        .overlay(BubbleShape().stroke(Color.black.opacity(0.06), lineWidth: 1))
        .padding(14)
        .environment(\.colorScheme, .light)
    }

    /// Polaroid : le contenu dans la « photo », la légende manuscrite sous le cadre.
    private var polaroidLayout: some View {
        VStack(spacing: 0) {
            inner.padding(14).background(Color(white: 0.965))
                .overlay(Rectangle().stroke(Color.black.opacity(0.12), lineWidth: 1))
                .padding(.top, 18).padding(.horizontal, 18)
            HStack(spacing: 10) {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.text.opacity(0.7))
                        .frame(width: 24, height: 24).background(Circle().fill(Color.black.opacity(0.07))).frame(width: 34, height: 40).contentShape(Rectangle())
                }.buttonStyle(.plain).background(DragZone(blocks: true))
                Text(title).font(.custom("Bradley Hand", size: 22).weight(.bold)).foregroundStyle(Color(white: 0.2)).lineLimit(1)
                Spacer(minLength: 8)
                actions(.polaroid)
            }.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 14).background(DragZone())
        }
        .background(Color(red: 0.995, green: 0.99, blue: 0.975).shadow(color: .black.opacity(0.28), radius: 10, y: 6))
        .padding(14)
        .environment(\.colorScheme, .light)
    }

    /// Ticket : le corps, une ligne de déchirure en pointillés avec deux encoches, puis le talon avec les boutons.
    private var ticketLayout: some View {
        let paper = Color(red: 0.995, green: 0.975, blue: 0.9)
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.text.opacity(0.75))
                            .frame(width: 24, height: 24).overlay(Circle().stroke(Theme.text.opacity(0.5), lineWidth: 1.3)).frame(width: 36, height: 38).contentShape(Rectangle())
                    }.buttonStyle(.plain).background(DragZone(blocks: true))
                    Text("ADMIT ONE · " + title.uppercased()).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer()
                }.padding(.horizontal, 10).frame(height: 44).background(DragZone())
                inner.padding(.horizontal, 16).padding(.bottom, 16)
            }
            .background(TicketHalf(top: true).fill(paper, style: FillStyle(eoFill: true)).clipShape(UnevenRoundedRectangleShape(top: 22, bottom: 0)))
            DashedLine().stroke(Theme.text.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).frame(height: 1).padding(.horizontal, 14)
            HStack(spacing: 8) { Spacer(); actions(.ticket) }.padding(.horizontal, 16).padding(.vertical, 14)
                .background(TicketHalf(top: false).fill(paper, style: FillStyle(eoFill: true)).clipShape(UnevenRoundedRectangleShape(top: 0, bottom: 22)))
        }
        .shadow(color: .black.opacity(0.22), radius: 9, y: 5)
        .padding(14)
        .environment(\.colorScheme, .light)
    }

    private func closeCircle(_ fg: Color, _ bg: Color, size: CGFloat = 28) -> some View {
        Button(action: close) {
            Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(fg)
                .frame(width: size, height: size).background(Circle().fill(bg))
        }.buttonStyle(.plain).background(DragZone(blocks: true))
    }

    // MARK: Parties du cadre (styles de couleur)

    private func closeButton(_ st: ToolStyle) -> some View {
        Button(action: close) {
            Group {
                switch st {
                case .tangerine:
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.white)
                        .frame(width: 28, height: 28).background(Circle().fill(Color.white.opacity(0.28)))
                case .graphite:
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.white.opacity(0.9))
                        .frame(width: 28, height: 28).background(Circle().fill(Color.white.opacity(0.14)))
                case .minimal:
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
                        .frame(width: 24, height: 24).background(Circle().fill(Color.black.opacity(0.05)))
                case .wii:
                    Image(systemName: "xmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(ToolPalette.wiiBlue)
                        .frame(width: 28, height: 28).background(Circle().fill(Color.white)).overlay(Circle().stroke(ToolPalette.wiiBlue, lineWidth: 2.2))
                default:
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.text.opacity(0.75))
                        .frame(width: 28, height: 28).background(Circle().fill(Color.black.opacity(0.07)))
                }
            }
            .frame(width: 40, height: 40).contentShape(Rectangle())
        }.buttonStyle(.plain).background(DragZone(blocks: true))
    }

    @ViewBuilder private func header(_ st: ToolStyle) -> some View {
        let bar = ZStack {
            switch st {
            case .minimal:
                HStack { Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text).padding(.leading, 12); Spacer(); closeButton(st) }
            default:
                Text(title).font(.system(size: st == .wii ? 16 : 15, weight: .semibold, design: st == .wii ? .rounded : .default)).foregroundStyle(titleColor(st))
                HStack { closeButton(st); Spacer() }
            }
        }
        .padding(.horizontal, 8).frame(height: 48).background(DragZone()).zIndex(1)
        switch st {
        case .tangerine:
            bar.background(LinearGradient(colors: [ToolPalette.tangerineLight, Theme.orange], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .graphite:
            bar.background(LinearGradient(colors: [Color(white: 0.2), ToolPalette.graphite], startPoint: .top, endPoint: .bottom))
        default:
            bar
        }
    }

    private func titleColor(_ st: ToolStyle) -> Color {
        switch st { case .tangerine, .graphite: return .white; case .wii: return Color(red: 0.36, green: 0.4, blue: 0.46); default: return Theme.text }
    }

    @ViewBuilder private func footerBar(_ st: ToolStyle) -> some View {
        let row = HStack(spacing: 8) { footer() }
            .environment(\.toolStyle, st)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16).padding(.vertical, st == .minimal ? 14 : 12)
        switch st {
        case .graphite:
            row.background(ToolPalette.graphite)
        case .wii:
            VStack(spacing: 0) {
                Rectangle().fill(ToolPalette.wiiBlue).frame(height: 2.5)
                row.background(LinearGradient(colors: [Color.white, Color(red: 0.93, green: 0.95, blue: 0.97)], startPoint: .top, endPoint: .bottom))
            }
        case .tangerine:
            VStack(spacing: 0) { Divider().opacity(0.6); row }
        default:
            row
        }
    }

    @ViewBuilder private func background(_ st: ToolStyle) -> some View {
        switch st {
        case .tangerine: Rectangle().fill(.regularMaterial).background(Color.white.opacity(0.72))
        case .graphite: Rectangle().fill(.regularMaterial).background(Color(white: 0.97))
        case .minimal: Color.white
        case .wii: ToolPalette.wiiBody
        default: Rectangle().fill(.regularMaterial).background(Color.white.opacity(0.6))
        }
    }

    @ViewBuilder private func rim(_ st: ToolStyle) -> some View {
        switch st {
        case .minimal: RoundedRectangle(cornerRadius: st.cornerRadius, style: .continuous).stroke(Color.black.opacity(0.09), lineWidth: 1)
        case .wii: RoundedRectangle(cornerRadius: st.cornerRadius, style: .continuous).strokeBorder(ToolPalette.wiiBlue, lineWidth: 3.5)
        case .graphite: RoundedRectangle(cornerRadius: st.cornerRadius, style: .continuous).stroke(Color.black.opacity(0.35), lineWidth: 1)
        default: EmptyView()
        }
    }
}

/// Sélecteurs de fichiers non modaux : s'affichent au-dessus des fenêtres flottantes et rendent ensuite la main à la fenêtre d'outil.
enum Pickers {
    static func files(_ types: [UTType], _ completion: @escaping ([URL]) -> Void) {
        let back = NSApp.keyWindow
        let p = NSOpenPanel()
        p.allowedContentTypes = types
        p.allowsMultipleSelection = true
        p.level = .modalPanel
        p.begin { r in
            NSApp.activate(ignoringOtherApps: true)
            back?.makeKeyAndOrderFront(nil)
            completion(r == .OK ? p.urls : [])
        }
    }

    static func image(_ completion: @escaping (URL?) -> Void) {
        let back = NSApp.keyWindow
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.level = .modalPanel
        p.begin { r in
            NSApp.activate(ignoringOtherApps: true)
            back?.makeKeyAndOrderFront(nil)
            completion(r == .OK ? p.url : nil)
        }
    }
}

/// Le premier clic sur une fenêtre d'outil est transmis aux boutons (sinon il ne fait qu'activer la fenêtre).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Un glissement dans le contenu (poignées, recadrage, curseurs…) ne doit jamais déplacer la fenêtre.
    override var mouseDownCanMoveWindow: Bool { false }

    /// La fenêtre épouse toujours la taille de son contenu. Elle était dimensionnée une seule fois à l'ouverture : un contenu qui arrive ensuite
    /// (liste chargée, résultat, options qui apparaissent) débordait et se trouvait coupé en haut et en bas.
    private var fitScheduled = false
    override func layout() {
        super.layout()
        guard !fitScheduled else { return }
        fitScheduled = true
        DispatchQueue.main.async { [weak self] in self?.fitWindow() }
    }

    private func fitWindow() {
        fitScheduled = false
        guard let w = window as? ToolWindow else { return }
        let s = fittingSize
        let target = NSSize(width: max(s.width, 380), height: max(s.height, 200))
        if w.hasShadow { w.invalidateShadow() }                         // l'ombre du système doit suivre la forme actuelle du contenu
        guard abs(w.frame.width - target.width) > 1.5 || abs(w.frame.height - target.height) > 1.5 else { return }
        var f = w.frame
        f.origin.y += f.height - target.height                       // le bord haut reste en place
        f.size = target
        if let vis = (w.screen ?? NSScreen.main)?.visibleFrame, f.maxY > vis.maxY { f.origin.y = vis.maxY - f.height }      // jamais sous la barre de menus
        w.setFrame(f, display: true, animate: false)
        if w.hasShadow { w.invalidateShadow() }
    }
}

final class DragZoneView: NSView {
    var blocksDrag = false
    override func viewDidMoveToWindow() { (window as? ToolWindow)?.zones.add(self) }
}

/// Zone de la fenêtre qui la déplace quand on la fait glisser (barre de titre…). `blocks` : zone qui l'empêche (ex. le bouton ✕).
struct DragZone: NSViewRepresentable {
    var blocks = false
    func makeNSView(context: Context) -> DragZoneView { let v = DragZoneView(); v.blocksDrag = blocks; return v }
    func updateNSView(_ v: DragZoneView, context: Context) { v.blocksDrag = blocks }
}

/// Ancienne zone de glissement (conservée pour la tablette flottante).
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView { override var mouseDownCanMoveWindow: Bool { true } }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class ToolWindow: NSWindow {
    /// Échap ferme la fenêtre — mais seulement pour un vrai appui sur Échap (pas pour une autre commande d'annulation venue d'ailleurs).
    override func cancelOperation(_ sender: Any?) {
        guard let e = NSApp.currentEvent, e.type == .keyDown, e.keyCode == 53 else { return }
        close()
    }

    /// Déplacement de la fenêtre : un clic dans la barre de titre (hors bouton ✕) lance le déplacement natif.
    /// Fait ici plutôt que dans une vue SwiftUI, dont la prise en compte des clics n'est pas fiable pour cela.
    /// Zones déclarées par le cadre (DragZone) : un clic dans une zone « déplacement » (et hors zone « bloquante », comme le ✕) déplace la fenêtre.
    let zones = NSHashTable<DragZoneView>.weakObjects()

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            let live = zones.allObjects.filter { $0.window === self && !$0.isHidden }
            func hit(_ z: DragZoneView) -> Bool { z.bounds.contains(z.convert(event.locationInWindow, from: nil)) }
            if !live.contains(where: { $0.blocksDrag && hit($0) }), live.contains(where: { !$0.blocksDrag && hit($0) }) { dragWindow(from: event); return }
        }
        super.sendEvent(event)
    }

    private func dragWindow(from down: NSEvent) {
        let start = convertPoint(toScreen: down.locationInWindow), origin = frame.origin
        while let e = nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if e.type == .leftMouseUp { break }
            let now = convertPoint(toScreen: e.locationInWindow)
            // locationInWindow est relatif à la position actuelle de la fenêtre : on repart de l'origine d'avant le glissement
            let dx = now.x - start.x - (frame.origin.x - origin.x), dy = now.y - start.y - (frame.origin.y - origin.y)
            setFrameOrigin(NSPoint(x: frame.origin.x + dx, y: frame.origin.y + dy))
        }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {   // ⌘W aussi
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" { close(); return true }
        return super.performKeyEquivalent(with: event)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ToolWindowController: NSObject, NSWindowDelegate {
    private static var open: [ToolWindowController] = []
    static var hasOpenWindows: Bool { !open.isEmpty }
    private(set) var window: ToolWindow!

    private static var lastOpened: (key: String, date: Date)?

    static func present(_ id: ToolID, urls: [URL]) {
        // Un même dépôt ne doit pas ouvrir deux fenêtres identiques l'une sur l'autre
        let key = id.rawValue + "|" + urls.map(\.absoluteString).joined(separator: "|")
        if let last = lastOpened, last.key == key, Date().timeIntervalSince(last.date) < 1.5 { return }
        lastOpened = (key, Date())
        present { close in ToolRegistry.view(for: id, urls: urls, close: close) }
    }

    /// Fenêtre d'outil avec un contenu fourni par l'appelant (utilisé quand l'outil a besoin de données déjà lues).
    static func present(_ make: (@escaping () -> Void) -> AnyView) {
        let c = ToolWindowController()
        let close: () -> Void = { [weak c] in c?.close() }
        let root = make(close)
        let host = FirstMouseHostingView(rootView: root.environment(\.colorScheme, .light))
        let size = host.fittingSize
        let w = ToolWindow(contentRect: NSRect(origin: .zero, size: NSSize(width: max(size.width, 380), height: max(size.height, 200))),
                           styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = ToolStyle.current == .classic          // les autres styles dessinent leur propre ombre : celle du système y laissait un liseré gris irrégulier
        w.isMovableByWindowBackground = true
        w.level = .floating
        w.appearance = NSAppearance(named: .aqua)
        w.contentView = host
        w.delegate = c
        w.isReleasedWhenClosed = false
        c.window = w
        w.center()
        open.append(c)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func close() { window.close() }
    func windowWillClose(_ notification: Notification) {
        window.contentView = nil
        ToolWindowController.open.removeAll { $0 === self }
    }
}

/// Quels outils ont une implémentation (les autres sont grisés dans la roue).
enum ToolAvailability {
    static func isImplemented(_ id: ToolID) -> Bool {
        switch id {
        case .removeBackground:
            return BackgroundRemover.isAvailable
        case .resizeImage, .rotateImage, .extractImages, .quickLook, .davinciTree, .videoSnapshots:
            return true
        case .openInCode:
            return VSCode.url != nil
        case .downloadMP3, .downloadMP4, .downloadWAV, .speakText:
            return true
        case .translateText:
            return SnippetEngine.canTranslate
        case .summarizeText:
            return SnippetEngine.canSummarize
        case .extractAudio, .encodeVideo:
            return FFmpeg.isAvailable
        case .compress, .metadata, .editImage, .annotateImage, .frameImage, .cropImage, .redactImage, .createCollage,
             .mergePDF, .organizePDF, .splitPDF, .extractArchive, .ocr, .faceSelect, .scanDocument, .zipFiles, .quickSort, .typeSelect:
            return true
        case .trimVideo, .cropVideo, .changeVideoSpeed, .joinVideos, .splitVideo, .redactVideo, .muteVideo,
             .normalizeAudio, .audioToVideo, .trimAudio, .audioChannels, .redactAudio:
            return FFmpeg.isAvailable
        }
    }
}

struct DashedLine: Shape {
    func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p }
}

/// Rectangle dont seuls le haut ou le bas sont arrondis.
struct UnevenRoundedRectangleShape: Shape {
    var top: CGFloat, bottom: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: top))
        if top > 0 { p.addQuadCurve(to: CGPoint(x: top, y: 0), control: .zero) } else { p.addLine(to: .zero) }
        p.addLine(to: CGPoint(x: r.width - top, y: 0))
        if top > 0 { p.addQuadCurve(to: CGPoint(x: r.width, y: top), control: CGPoint(x: r.width, y: 0)) } else { p.addLine(to: CGPoint(x: r.width, y: 0)) }
        p.addLine(to: CGPoint(x: r.width, y: r.height - bottom))
        if bottom > 0 { p.addQuadCurve(to: CGPoint(x: r.width - bottom, y: r.height), control: CGPoint(x: r.width, y: r.height)) } else { p.addLine(to: CGPoint(x: r.width, y: r.height)) }
        p.addLine(to: CGPoint(x: bottom, y: r.height))
        if bottom > 0 { p.addQuadCurve(to: CGPoint(x: 0, y: r.height - bottom), control: CGPoint(x: 0, y: r.height)) } else { p.addLine(to: CGPoint(x: 0, y: r.height)) }
        p.closeSubpath()
        return p
    }
}
