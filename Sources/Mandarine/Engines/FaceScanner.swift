import Foundation
import Vision
import AVFoundation
import AppKit

/// Un visage trouvé : fichier d'origine, empreinte (128 nombres), vignette et score de netteté/taille.
struct FaceHit {
    let file: URL
    let vector: [Float]
    let thumb: CGImage
    let score: Float
}

/// Un groupe de visages jugés identiques.
struct FaceCluster: Identifiable {
    let id: Int
    var members: [Int]
    var centroid: [Float]
    var files: [URL] = []
    var thumb: CGImage
}

enum FaceScanner {
    /// Position des 5 repères (yeux, nez, coins de la bouche) dans une image de visage 112×112 (gabarit ArcFace / SFace).
    private static let template: [(x: Double, y: Double)] = [(38.2946, 51.6963), (73.5318, 51.5014), (56.0252, 71.7366), (41.5493, 92.3655), (70.7299, 92.2041)]

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        var s: Float = 0
        for i in 0..<min(a.count, b.count) { s += a[i] * b[i] }
        return s
    }

    // MARK: Détection + alignement + empreinte

    /// `minRelativeWidth` : largeur minimale du visage par rapport à l'image (ignore les passants du fond).
    static func faces(in image: CGImage, file: URL, minRelativeWidth: Double = 0.04) throws -> [FaceHit] {
        let W = Double(image.width), H = Double(image.height)
        let req = VNDetectFaceLandmarksRequest()
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([req])
        let embedder = try FaceEmbedder.get()
        var out: [FaceHit] = []
        for obs in req.results ?? [] {
            let box = obs.boundingBox
            guard box.width >= minRelativeWidth, box.width * W >= 40, let lm = obs.landmarks else { continue }
            func pts(_ r: VNFaceLandmarkRegion2D?) -> [CGPoint] {
                (r?.pointsInImage(imageSize: CGSize(width: W, height: H)) ?? []).map { CGPoint(x: $0.x, y: H - $0.y) }      // origine en haut à gauche
            }
            func mean(_ p: [CGPoint]) -> CGPoint? { p.isEmpty ? nil : CGPoint(x: p.map(\.x).reduce(0, +) / Double(p.count), y: p.map(\.y).reduce(0, +) / Double(p.count)) }
            guard let e1 = mean(pts(lm.leftEye)), let e2 = mean(pts(lm.rightEye)), let nose = mean(pts(lm.nose)) else { continue }
            let lips = pts(lm.outerLips)
            guard let mL = lips.min(by: { $0.x < $1.x }), let mR = lips.max(by: { $0.x < $1.x }) else { continue }
            let (eL, eR) = e1.x < e2.x ? (e1, e2) : (e2, e1)
            let src = [eL, eR, nose, mL, mR]
            guard let aligned = align(image, from: src), let vec = try? embedder.embed(aligned) else { continue }
            guard let thumb = crop(image, box: box, size: 80) else { continue }
            out.append(FaceHit(file: file, vector: vec, thumb: thumb, score: Float(box.width) * obs.confidence))
        }
        return out
    }

    /// Image 112×112 du visage redressé (similitude déduite des 5 repères), en CHW RGB 0…255.
    private static func align(_ image: CGImage, from src: [CGPoint]) -> [Float]? {
        let n = Double(src.count)
        let ms = (x: src.map(\.x).reduce(0, +) / n, y: src.map(\.y).reduce(0, +) / n)
        let md = (x: template.map(\.x).reduce(0, +) / n, y: template.map(\.y).reduce(0, +) / n)
        var num1 = 0.0, num2 = 0.0, den = 0.0
        for (s, d) in zip(src, template) {
            let sx = s.x - ms.x, sy = s.y - ms.y, dx = d.x - md.x, dy = d.y - md.y
            num1 += sx * dx + sy * dy; num2 += sx * dy - sy * dx; den += sx * sx + sy * sy
        }
        guard den > 1e-6 else { return nil }
        let a = num1 / den, b = num2 / den
        let tx = md.x - (a * ms.x - b * ms.y), ty = md.y - (b * ms.x + a * ms.y)
        guard let ctx = CGContext(data: nil, width: 112, height: 112, bitsPerComponent: 8, bytesPerRow: 112 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 112, height: 112))
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: 112); ctx.scaleBy(x: 1, y: -1)                       // repère dest. : origine en haut
        ctx.concatenate(CGAffineTransform(a: a, b: b, c: -b, d: a, tx: tx, ty: ty))     // image (origine en haut) → gabarit
        ctx.translateBy(x: 0, y: Double(image.height)); ctx.scaleBy(x: 1, y: -1)        // CGImage se dessine origine en bas
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let raw = ctx.data else { return nil }
        let px = raw.bindMemory(to: UInt8.self, capacity: 112 * 112 * 4)
        var chw = [Float](repeating: 0, count: 3 * 112 * 112)
        for i in 0..<(112 * 112) { for c in 0..<3 { chw[c * 112 * 112 + i] = Float(px[i * 4 + c]) } }
        return chw
    }

    private static func crop(_ image: CGImage, box: CGRect, size: Int) -> CGImage? {
        let W = Double(image.width), H = Double(image.height)
        var r = CGRect(x: box.minX * W, y: (1 - box.maxY) * H, width: box.width * W, height: box.height * H)
        r = r.insetBy(dx: -r.width * 0.3, dy: -r.height * 0.3).intersection(CGRect(x: 0, y: 0, width: W, height: H))
        guard !r.isEmpty, let c = image.cropping(to: r.integral) else { return nil }
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        let s = max(Double(size) / Double(c.width), Double(size) / Double(c.height))      // remplit le carré, centré
        let w = Double(c.width) * s, h = Double(c.height) * s
        ctx.draw(c, in: CGRect(x: (Double(size) - w) / 2, y: (Double(size) - h) / 2, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: Fichiers (photos et vidéos)

    /// Cherche les visages de tous les fichiers. `progress(fichiers lus, total, visages trouvés)`.
    static func scan(_ urls: [URL], minRelativeWidth: Double = 0.04, progress: @escaping (Int, Int, Int) -> Void) async throws -> [FaceHit] {
        _ = try FaceEmbedder.get()          // échoue tout de suite si le modèle manque
        var hits: [FaceHit] = []
        for (i, u) in urls.enumerated() {
            try Task.checkCancellation()
            let found = try await Task.detached { () throws -> [FaceHit] in
                switch FileKind.detect(u) {
                case .image:
                    guard let (img, _) = try? ImageEngine.load(u, maxSide: 2000) else { return [] }
                    return try faces(in: img, file: u, minRelativeWidth: minRelativeWidth)
                case .video:
                    return try await videoFaces(u, minRelativeWidth: minRelativeWidth)
                default: return []
                }
            }.value
            hits += found
            progress(i + 1, urls.count, hits.count)
        }
        return hits
    }

    /// Une image toutes les ~2 s (40 au plus). Un même visage revu dans la vidéo n'est gardé qu'une fois.
    private static func videoFaces(_ url: URL, minRelativeWidth: Double) async throws -> [FaceHit] {
        let duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
        let count = duration > 0 ? min(40, max(1, Int(duration / 2))) : 1
        var kept: [FaceHit] = []
        for k in 0..<count {
            try Task.checkCancellation()
            let t = duration > 0 ? duration * (Double(k) + 0.5) / Double(count) : 0
            guard let frame = await VideoFrames.native(url, at: t) else { continue }
            for h in try faces(in: frame, file: url, minRelativeWidth: minRelativeWidth) where !kept.contains(where: { cosine($0.vector, h.vector) > 0.8 }) {
                kept.append(h)
            }
        }
        return kept
    }

    // MARK: Regroupement

    /// Regroupe les visages par ressemblance d'empreinte. `threshold` : similarité cosinus minimale (mesuré sur 504 photos de 42 personnes : à 0,50 aucun visage mal rangé, 44 groupes pour 42 personnes).
    static func cluster(_ hits: [FaceHit], threshold: Float = 0.50) -> [FaceCluster] {
        // 1) Affectation au groupe le plus proche, en commençant par les visages les plus nets
        var clusters: [FaceCluster] = []
        for i in hits.indices.sorted(by: { hits[$0].score > hits[$1].score }) {
            var best = -1, bestSim: Float = threshold
            for (c, cl) in clusters.enumerated() { let s = cosine(cl.centroid, hits[i].vector); if s >= bestSim { best = c; bestSim = s } }
            if best >= 0 {
                clusters[best].members.append(i)
                clusters[best].centroid = centroid(clusters[best].members.map { hits[$0].vector })
            } else {
                clusters.append(FaceCluster(id: clusters.count, members: [i], centroid: hits[i].vector, thumb: hits[i].thumb))
            }
        }
        // 2) Fusion des groupes dont les centres sont assez proches
        var merged = true
        while merged {
            merged = false
            outer: for a in clusters.indices { for b in clusters.indices where b > a && cosine(clusters[a].centroid, clusters[b].centroid) >= threshold {
                clusters[a].members += clusters[b].members
                clusters[a].centroid = centroid(clusters[a].members.map { hits[$0].vector })
                clusters.remove(at: b); merged = true; break outer
            } }
        }
        // Fichiers, vignette représentative (visage le plus net), tri par nombre de fichiers
        let order = Dictionary(uniqueKeysWithValues: Set(hits.map(\.file)).enumerated().map { ($1, $0) })
        for c in clusters.indices {
            let best = clusters[c].members.max { hits[$0].score < hits[$1].score }!
            clusters[c].thumb = hits[best].thumb
            var seen = Set<URL>()
            clusters[c].files = clusters[c].members.map { hits[$0].file }.filter { seen.insert($0).inserted }.sorted { (order[$0] ?? 0) < (order[$1] ?? 0) }
        }
        return clusters.sorted { $0.files.count > $1.files.count }.enumerated().map { var c = $1; c = FaceCluster(id: $0, members: c.members, centroid: c.centroid, files: c.files, thumb: c.thumb); return c }
    }

    private static func centroid(_ v: [[Float]]) -> [Float] {
        var s = [Float](repeating: 0, count: v[0].count)
        for x in v { for i in s.indices { s[i] += x[i] } }
        let n = max(s.reduce(0) { $0 + $1 * $1 }.squareRoot(), 1e-9)
        return s.map { $0 / n }
    }
}
