import SwiftUI
import AppKit

struct RedactVideoTool: View {
    let urls: [URL]
    let close: () -> Void
    @StateObject private var player = PlayerController()
    @State private var regions: [Region] = []
    @State private var selected: UUID?
    @State private var style = RedactStyle.solid
    @State private var color = Color.black
    @State private var dragRegion: (id: UUID, mode: Int, start: Double, end: Double, origin: CGFloat)?

    var body: some View {
        ToolShell(title: "Redact Video", close: close) {
            VStack(spacing: 10) {
                RegionEditor(contentSize: player.size == .zero ? CGSize(width: 16, height: 9) : player.size, regions: $regions, selected: $selected, allowsDraw: true,
                             fillStyle: { _ in style == .solid ? AnyView(Rectangle().fill(color)) : AnyView(Rectangle().fill(.ultraThinMaterial)) }) {
                    VideoSurface(player: player.player)
                }
                .frame(width: 420, height: 300)
                .onChange(of: regions.count) { n in
                    if let last = regions.last, last.end == .infinity, let i = regions.indices.last { regions[i].start = 0; regions[i].end = player.duration; _ = n }
                }
                .onDeleteCommand { regions.removeAll { $0.id == selected } }
                HStack { Text("Style").sectionLabel(); Spacer(); PillPicker(options: [(RedactStyle.solid, "Solid"), (.blur, "Blur")], selection: $style) }
                if style == .solid { HStack { Text("Color").sectionLabel(); Spacer(); ColorPicker("", selection: $color).labelsHidden() } }
                Text("Redactions").font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                timeline.frame(height: CGFloat(max(regions.count, 1)) * 24 + 56).coordinateSpace(name: "redactLanes")
                FrameStepRow(player: player)
                Text("Draw boxes on the video, then drag their bars to set when each one is visible.").sectionLabel()
            }.frame(width: 420)
        } footer: {
            Button("Save Redacted Copy") { save() }.buttonStyle(PillButtonStyle()).disabled(regions.isEmpty)
        }
        .task { await player.load(urls[0]) }
    }

    private var timeline: some View {
        GeometryReader { geo in
            let W = geo.size.width - 28, D = max(player.duration, 0.01)
            VStack(spacing: 4) {
                ForEach(Array(regions.enumerated()), id: \.element.id) { i, r in
                    HStack(spacing: 6) {
                        Text("\(i + 1)").font(.system(size: 10)).foregroundStyle(Theme.muted).frame(width: 14)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.05))
                            let x0 = W * CGFloat(r.start / D), x1 = W * CGFloat(min(r.end, D) / D)
                            RoundedRectangle(cornerRadius: 5).fill(Theme.orange.opacity(selected == r.id ? 0.85 : 0.55))
                                .overlay(Text("Box \(i + 1)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white))
                                .frame(width: max(14, x1 - x0)).offset(x: x0)
                                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("redactLanes")).onChanged { v in move(r, v, W, D, edge: nil) }.onEnded { _ in dragRegion = nil })
                            handle().offset(x: x0).gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("redactLanes")).onChanged { v in move(r, v, W, D, edge: 0) }.onEnded { _ in dragRegion = nil })
                            handle().offset(x: x1 - 6).gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("redactLanes")).onChanged { v in move(r, v, W, D, edge: 1) }.onEnded { _ in dragRegion = nil })
                        }.frame(width: W, height: 20).onTapGesture { selected = r.id }
                    }
                }
                if regions.isEmpty { Text("Drag on the video to add").sectionLabel().frame(height: 20) }
                ZStack {
                    FilmStrip(url: urls[0], duration: player.duration, count: 12).clipShape(RoundedRectangle(cornerRadius: 6))
                    Rectangle().fill(Color.white).frame(width: 2).shadow(radius: 1)
                        .frame(maxWidth: .infinity, alignment: .leading).offset(x: W * CGFloat(player.time / D))
                }.frame(width: W, height: 36).padding(.leading, 20)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in player.pause(); player.seek(Double(v.location.x / W) * D) })
            }
        }
    }

    private func handle() -> some View {
        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.9)).frame(width: 4, height: 12).padding(.horizontal, 4)
    }

    private func move(_ r: Region, _ v: DragGesture.Value, _ W: CGFloat, _ D: Double, edge: Int?) {
        if dragRegion?.id != r.id { dragRegion = (r.id, edge ?? 2, r.start, min(r.end, D), v.startLocation.x) }
        guard let d = dragRegion, let i = regions.firstIndex(where: { $0.id == r.id }) else { return }
        let dt = Double(v.translation.width / W) * D
        selected = r.id
        switch edge {
        case 0: regions[i].start = min(max(0, d.start + dt), regions[i].end - 0.1)
        case 1: regions[i].end = max(min(D, d.end + dt), regions[i].start + 0.1)
        default:
            let len = d.end - d.start
            let s = min(max(0, d.start + dt), D - len)
            regions[i].start = s; regions[i].end = s + len
        }
    }

    private func save() {
        let file = urls[0], rs = regions, st = style, col = NSColor(color).usingColorSpace(.sRGB) ?? .black
        close()
        Dispatcher.job("Redacting video…") { progress in
            let info = await FFmpeg.probe(file)
            let W = Double(info.width), H = Double(info.height)
            let hex = String(format: "0x%02X%02X%02X", Int(col.redComponent * 255), Int(col.greenComponent * 255), Int(col.blueComponent * 255))
            var chain = "", label = "0:v"
            for (i, r) in rs.enumerated() {
                let x = Int(r.rect.minX * W), y = Int(r.rect.minY * H), w = max(2, Int(r.rect.width * W)), h = max(2, Int(r.rect.height * H))
                let en = "between(t,\(r.start),\(min(r.end, info.duration)))"
                let out = "v\(i)"
                switch st {
                case .solid:
                    chain += "[\(label)]drawbox=x=\(x):y=\(y):w=\(w):h=\(h):color=\(hex):t=fill:enable='\(en)'[\(out)];"
                case .blur:
                    chain += "[\(label)]split[a\(i)][b\(i)];[b\(i)]crop=\(w):\(h):\(x):\(y),boxblur=luma_radius=\(max(4, min(w, h) / 6)):luma_power=3[c\(i)];[a\(i)][c\(i)]overlay=\(x):\(y):enable='\(en)'[\(out)];"
                }
                label = out
            }
            chain.removeLast()
            let ext = VideoExport.ext(for: file)
            let dest = OutputNaming.sibling(of: file, suffix: " redacted", ext: ext)
            var args = ["-i", file.path, "-filter_complex", chain, "-map", "[\(label)]"] + (info.hasAudio ? ["-map", "0:a"] : [])
            args += VideoExport.codecArgs(for: file)
            if let i = args.firstIndex(of: "-c:a"), args.indices.contains(i + 1) { args[i + 1] = "copy"; if args.indices.contains(i + 3), args[i + 2] == "-b:a" { args.removeSubrange((i + 2)...(i + 3)) } }
            try await FFmpeg.run(args + [dest.path], duration: info.duration, progress: progress)
            return [dest]
        }
    }
}
