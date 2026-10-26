import Foundation
import MetalPerformanceShadersGraph
import CryptoKit

/// Modèle de reconnaissance faciale SFace (OpenCV Zoo, licence Apache 2.0) : un visage aligné de 112×112 donne une empreinte de 128 nombres ;
/// deux visages de la même personne ont des empreintes proches. Le fichier ONNX est téléchargé à la demande (vérifié par SHA-256),
/// lu par un petit lecteur ONNX intégré, puis exécuté sur le GPU avec MPSGraph : aucune bibliothèque externe.
enum FaceModel {
    static let url = URL(string: "https://github.com/opencv/opencv_zoo/raw/main/models/face_recognition_sface/face_recognition_sface_2021dec.onnx")!
    static let sha256 = "0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79"
    static let sizeText = "37 MB"

    /// ~/Library/Application Support/Mandarine/models (ou le dossier de MANDARINE_MODEL_DIR, pour les tests)
    static var folder: URL {
        if let d = ProcessInfo.processInfo.environment["MANDARINE_MODEL_DIR"] { return URL(fileURLWithPath: d) }
        return FFmpeg.enginesFolder.deletingLastPathComponent().appendingPathComponent("models")
    }
    static var file: URL { folder.appendingPathComponent("face_recognition_sface_2021dec.onnx") }
    static var isInstalled: Bool { FileManager.default.fileExists(atPath: file.path) }

    /// Télécharge, vérifie l'empreinte, puis installe. `progress` reçoit une fraction (0…1).
    static func download(progress: @escaping (Double) -> Void) async throws {
        let (tmp, resp) = try await Downloader.fetch(url, progress: progress)
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw MandarineError("The server answered with an error (\((resp as? HTTPURLResponse)?.statusCode ?? 0)).") }
        guard try Downloader.sha256(of: tmp) == sha256 else { throw MandarineError("The downloaded model doesn't match its expected checksum — nothing was installed.") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: tmp, to: file)
        FaceEmbedder.reset()
    }

    static func remove() { try? FileManager.default.removeItem(at: file); FaceEmbedder.reset() }
}

// MARK: Lecture ONNX minimale (protobuf)

/// Un tenseur lu dans le fichier ONNX.
struct ONNXTensor { let name: String; var dims: [Int]; var floats: [Float] }
struct ONNXNode { let op: String; let inputs: [String]; let outputs: [String]; var ints: [String: [Int]] = [:]; var floats: [String: Float] = [:] }

struct ProtoReader {
    let b: [UInt8]
    var p = 0
    init(_ bytes: [UInt8]) { b = bytes }
    var atEnd: Bool { p >= b.count }

    mutating func varint() -> UInt64 {
        var r: UInt64 = 0, s: UInt64 = 0
        while p < b.count { let x = b[p]; p += 1; r |= UInt64(x & 0x7f) << s; if x & 0x80 == 0 { break }; s += 7 }
        return r
    }
    mutating func field() -> (Int, Int)? { guard !atEnd else { return nil }; let t = Int(varint()); return (t >> 3, t & 7) }
    mutating func bytes() -> ArraySlice<UInt8> { let n = Int(varint()); let s = b[p..<min(p + n, b.count)]; p += n; return s }
    mutating func skip(_ wire: Int) {
        switch wire { case 0: _ = varint(); case 1: p += 8; case 2: _ = bytes(); case 5: p += 4; default: p = b.count }
    }
}

enum ONNX {
    static func packedVarints(_ s: ArraySlice<UInt8>) -> [Int] {
        var r = ProtoReader(Array(s)); var out: [Int] = []
        while !r.atEnd { out.append(Int(Int64(bitPattern: r.varint()))) }
        return out
    }
    static func floatsFrom(_ s: ArraySlice<UInt8>) -> [Float] {
        let n = s.count / 4
        return s.withUnsafeBytes { raw in (0..<n).map { Float(bitPattern: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self)) } }
    }

    static func parse(_ data: Data) throws -> (nodes: [ONNXNode], tensors: [String: ONNXTensor]) {
        var model = ProtoReader([UInt8](data))
        var nodes: [ONNXNode] = [], tensors: [String: ONNXTensor] = [:]
        while let (f, w) = model.field() {
            guard f == 7, w == 2 else { model.skip(w); continue }
            var g = ProtoReader(Array(model.bytes()))
            while let (gf, gw) = g.field() {
                switch (gf, gw) {
                case (1, 2): nodes.append(node(Array(g.bytes())))
                case (5, 2): let t = tensor(Array(g.bytes())); tensors[t.name] = t
                default: g.skip(gw)
                }
            }
        }
        guard !nodes.isEmpty else { throw MandarineError("The face model file is not a valid ONNX model.") }
        return (nodes, tensors)
    }

    private static func node(_ bytes: [UInt8]) -> ONNXNode {
        var r = ProtoReader(bytes)
        var ins: [String] = [], outs: [String] = [], op = ""
        var ints: [String: [Int]] = [:], floats: [String: Float] = [:]
        while let (f, w) = r.field() {
            switch (f, w) {
            case (1, 2): ins.append(String(decoding: r.bytes(), as: UTF8.self))
            case (2, 2): outs.append(String(decoding: r.bytes(), as: UTF8.self))
            case (4, 2): op = String(decoding: r.bytes(), as: UTF8.self)
            case (5, 2):
                var a = ProtoReader(Array(r.bytes())); var name = ""; var iv: [Int] = [], fv: Float?
                while let (af, aw) = a.field() {
                    switch (af, aw) {
                    case (1, 2): name = String(decoding: a.bytes(), as: UTF8.self)
                    case (2, 5): fv = Float(bitPattern: UInt32(truncatingIfNeeded: { let v = Array(a.b[a.p..<a.p + 4]); a.p += 4; return v.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) } }()))
                    case (3, 0): iv = [Int(Int64(bitPattern: a.varint()))]
                    case (8, 2): iv = packedVarints(a.bytes())
                    case (8, 0): iv.append(Int(Int64(bitPattern: a.varint())))
                    default: a.skip(aw)
                    }
                }
                if !iv.isEmpty { ints[name] = iv }
                if let v = fv { floats[name] = v }
            default: r.skip(w)
            }
        }
        return ONNXNode(op: op, inputs: ins, outputs: outs, ints: ints, floats: floats)
    }

    private static func tensor(_ bytes: [UInt8]) -> ONNXTensor {
        var r = ProtoReader(bytes)
        var dims: [Int] = [], name = "", floats: [Float] = []
        while let (f, w) = r.field() {
            switch (f, w) {
            case (1, 2): dims += packedVarints(r.bytes())
            case (1, 0): dims.append(Int(r.varint()))
            case (4, 2): floats = floatsFrom(r.bytes())
            case (8, 2): name = String(decoding: r.bytes(), as: UTF8.self)
            case (9, 2): floats = floatsFrom(r.bytes())
            default: r.skip(w)
            }
        }
        return ONNXTensor(name: name, dims: dims, floats: floats)
    }
}

// MARK: Exécution (MPSGraph)

/// Calcule l'empreinte (128 nombres, normalisée) d'un visage aligné 112×112.
final class FaceEmbedder {
    private static var shared: FaceEmbedder?
    private static let lock = NSLock()
    static func reset() { lock.lock(); shared = nil; lock.unlock() }
    static func get() throws -> FaceEmbedder {
        lock.lock(); defer { lock.unlock() }
        if let s = shared { return s }
        let s = try FaceEmbedder(); shared = s; return s
    }

    private let device: MPSGraphDevice
    private let queue: MTLCommandQueue
    private let graph: MPSGraph
    private let input: MPSGraphTensor
    private let output: MPSGraphTensor

    private init() throws {
        guard FaceModel.isInstalled else { throw MandarineError("The face model isn't installed. Download it in Settings → Engines.") }
        guard let dev = MTLCreateSystemDefaultDevice(), let q = dev.makeCommandQueue() else { throw MandarineError("No GPU available for face recognition.") }
        device = MPSGraphDevice(mtlDevice: dev); queue = q
        let (nodes, tensors) = try ONNX.parse(try Data(contentsOf: FaceModel.file))
        let graph = MPSGraph()

        func f32(_ a: [Float], _ shape: [Int]) -> MPSGraphTensor {
            graph.constant(a.withUnsafeBufferPointer { Data(buffer: $0) }, shape: shape.map(NSNumber.init), dataType: .float32)
        }
        func init_(_ n: String) throws -> ONNXTensor { guard let t = tensors[n] else { throw MandarineError("Unexpected face model (\(n) missing).") }; return t }

        let inp = graph.placeholder(shape: [1, 3, 112, 112], dataType: .float32, name: "data")
        input = inp
        var values: [String: MPSGraphTensor] = ["data": inp]
        var rank: [String: Int] = ["data": 4]
        var last = inp
        for n in nodes {
            let x = n.inputs.first.flatMap { values[$0] }
            var y: MPSGraphTensor
            var r = rank[n.inputs.first ?? ""] ?? 4
            switch n.op {
            case "Sub", "Mul":
                let c = try init_(n.inputs[1])
                let k = f32(c.floats, [1])
                y = n.op == "Sub" ? graph.subtraction(x!, k, name: nil) : graph.multiplication(x!, k, name: nil)
            case "Conv":
                let w = try init_(n.inputs[1])
                let strides = n.ints["strides"] ?? [1, 1], pads = n.ints["pads"] ?? [0, 0, 0, 0], group = n.ints["group"]?.first ?? 1
                let d = MPSGraphConvolution2DOpDescriptor(strideInX: strides[1], strideInY: strides[0], dilationRateInX: 1, dilationRateInY: 1, groups: group,
                                                          paddingLeft: pads[1], paddingRight: pads[3], paddingTop: pads[0], paddingBottom: pads[2],
                                                          paddingStyle: .explicit, dataLayout: .NCHW, weightsLayout: .OIHW)!
                y = graph.convolution2D(x!, weights: f32(w.floats, w.dims), descriptor: d, name: nil)
            case "BatchNormalization":
                let gamma = try init_(n.inputs[1]).floats, beta = try init_(n.inputs[2]).floats, mean = try init_(n.inputs[3]).floats, vr = try init_(n.inputs[4]).floats
                let eps = n.floats["epsilon"] ?? 1e-5
                let scale = (0..<gamma.count).map { gamma[$0] / (vr[$0] + eps).squareRoot() }
                let shift = (0..<gamma.count).map { beta[$0] - mean[$0] * scale[$0] }
                let shape = r == 4 ? [1, gamma.count, 1, 1] : [1, gamma.count]
                y = graph.addition(graph.multiplication(x!, f32(scale, shape), name: nil), f32(shift, shape), name: nil)
            case "PRelu":
                let s = try init_(n.inputs[1]).floats
                let slope = f32(s, r == 4 ? [1, s.count, 1, 1] : [1, s.count])
                let zero = f32([0], [1])
                y = graph.addition(graph.maximum(x!, zero, name: nil), graph.multiplication(slope, graph.minimum(x!, zero, name: nil), name: nil), name: nil)
            case "Dropout":
                y = x!
            case "Flatten":
                y = graph.reshape(x!, shape: [1, -1], name: nil); r = 2
            case "Gemm":
                let w = try init_(n.inputs[1]), b = try init_(n.inputs[2])      // transB = 1 : poids [sortie, entrée]
                let wt = graph.transposeTensor(f32(w.floats, w.dims), dimension: 0, withDimension: 1, name: nil)
                y = graph.addition(graph.matrixMultiplication(primary: x!, secondary: wt, name: nil), f32(b.floats, [1, b.floats.count]), name: nil)
            default:
                throw MandarineError("Unsupported operation in the face model: \(n.op).")
            }
            for o in n.outputs { values[o] = y; rank[o] = r }
            last = y
        }
        output = last
        self.graph = graph
    }

    /// `chw` : 3×112×112 valeurs RGB de 0 à 255.
    func embed(_ chw: [Float]) throws -> [Float] {
        guard chw.count == 3 * 112 * 112 else { throw MandarineError("Bad face image size.") }
        let data = MPSGraphTensorData(device: device, data: chw.withUnsafeBufferPointer { Data(buffer: $0) }, shape: [1, 3, 112, 112], dataType: .float32)
        let result = graph.run(with: queue, feeds: [input: data], targetTensors: [output], targetOperations: nil)
        guard let out = result[output] else { throw MandarineError("The face model produced no result.") }
        var v = [Float](repeating: 0, count: 128)
        out.mpsndarray().readBytes(&v, strideBytes: nil)
        let norm = max(v.reduce(0) { $0 + $1 * $1 }.squareRoot(), 1e-9)
        return v.map { $0 / norm }
    }
}

// MARK: Téléchargement avec progression

enum Downloader {
    final class Progress: NSObject, URLSessionDownloadDelegate {
        let onProgress: (Double) -> Void
        var done: ((URL?, URLResponse?, Error?) -> Void)?
        init(_ p: @escaping (Double) -> Void) { onProgress = p }
        func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData w: Int64, totalBytesWritten tw: Int64, totalBytesExpectedToWrite te: Int64) {
            if te > 0 { onProgress(Double(tw) / Double(te)) }
        }
        func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            // le fichier temporaire disparaît après cette méthode : on le déplace
            let kept = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.moveItem(at: location, to: kept)
            done?(kept, t.response, nil); done = nil
        }
        func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError e: Error?) { if let e = e { done?(nil, nil, e); done = nil } }
    }

    static func fetch(_ url: URL, progress: @escaping (Double) -> Void) async throws -> (URL, URLResponse) {
        let d = Progress(progress)
        let session = URLSession(configuration: .ephemeral, delegate: d, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                d.done = { tmp, resp, err in
                    if let e = err { cont.resume(throwing: e) } else if let t = tmp, let r = resp { cont.resume(returning: (t, r)) }
                    else { cont.resume(throwing: MandarineError("Download failed.")) }
                }
                var req = URLRequest(url: url); req.setValue("Mandarine", forHTTPHeaderField: "User-Agent"); req.timeoutInterval = 60
                session.downloadTask(with: req).resume()
            }
        } onCancel: { session.invalidateAndCancel() }
    }

    /// SHA-256 d'un fichier, lu par blocs (le fichier peut être gros).
    static func sha256(of url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
