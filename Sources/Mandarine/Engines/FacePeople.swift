import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Un visage de référence d'une personne : son empreinte (128 nombres, voir `FaceEmbedder`) et une petite vignette. La photo d'origine n'est pas gardée.
struct PersonSample: Codable, Identifiable {
    var id = UUID()
    var vector: Data
    var thumb: Data
    var floats: [Float] { vector.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) } }
    var image: CGImage? { CGImageSourceCreateWithData(thumb as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) } }
}

/// Une personne connue : un nom et quelques visages de référence.
struct KnownPerson: Identifiable, Codable {
    var id = UUID()
    var name: String
    var samples: [PersonSample] = []
}

/// Les personnes que l'utilisateur a enregistrées (Réglages → Personnes). Face Select les retrouve parmi les photos et les place en tête de liste.
/// Rien n'est « entraîné » : on compare l'empreinte de chaque visage à celles des visages de référence (ressemblance cosinus).
/// Tout reste dans ~/Library/Application Support/Mandarine/people.json, sur ce Mac.
@MainActor
final class FacePeople: ObservableObject {
    static let shared = FacePeople()
    static let maxSamples = 30
    static let defaultThreshold = 0.50          // mesuré sur 504 photos de 42 personnes : à 0,50 aucun visage mal rangé

    @Published private(set) var people: [KnownPerson] = []

    nonisolated static var file: URL { FaceModel.folder.deletingLastPathComponent().appendingPathComponent("people.json") }

    private init() { load() }

    private func load() {
        guard let data = try? Data(contentsOf: Self.file), let p = try? JSONDecoder().decode([KnownPerson].self, from: data) else { return }
        people = p
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(people) { try? data.write(to: Self.file, options: .atomic) }
    }

    // MARK: Modifications

    @discardableResult
    func addPerson(name: String, samples: [FaceHit] = []) -> UUID {
        var p = KnownPerson(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L("New person") : name)
        p.samples = samples.prefix(5).compactMap(Self.sample)
        people.append(p); save()
        return p.id
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = people.firstIndex(where: { $0.id == id }) else { return }
        people[i].name = name; save()
    }

    func remove(_ id: UUID) { people.removeAll { $0.id == id }; save() }

    func removeSample(_ sample: UUID, of id: UUID) {
        guard let i = people.firstIndex(where: { $0.id == id }) else { return }
        people[i].samples.removeAll { $0.id == sample }; save()
    }

    /// Ajoute un visage de référence ; ignoré s'il est quasi identique à un visage déjà gardé, ou si la personne en a déjà `maxSamples`.
    @discardableResult
    func add(_ hit: FaceHit, to id: UUID) -> Bool {
        guard let i = people.firstIndex(where: { $0.id == id }), people[i].samples.count < Self.maxSamples, let s = Self.sample(hit) else { return false }
        if people[i].samples.contains(where: { FaceScanner.cosine($0.floats, hit.vector) > 0.98 }) { return false }
        people[i].samples.append(s); save()
        return true
    }

    private static func sample(_ hit: FaceHit) -> PersonSample? {
        let jpeg = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, hit.thumb, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return PersonSample(vector: hit.vector.withUnsafeBufferPointer { Data(buffer: $0) }, thumb: jpeg as Data)
    }

    // MARK: Détection dans une photo

    /// Les visages d'une photo (image, HEIC…), du plus grand au plus petit. Lance une erreur si le modèle de visages manque.
    nonisolated static func detect(in url: URL) async throws -> [FaceHit] {
        try await Task.detached { () throws -> [FaceHit] in
            guard let (img, _) = try? ImageEngine.load(url, maxSide: 2000) else { return [] }
            return try FaceScanner.faces(in: img, file: url, minRelativeWidth: 0.03).sorted { $0.score > $1.score }
        }.value
    }

    // MARK: Reconnaissance

    /// Range chaque visage chez la personne qui lui ressemble le plus (au moins `threshold`) ; les autres restent « inconnus ».
    nonisolated static func assign(_ hits: [FaceHit], people: [KnownPerson], threshold: Float) -> (byPerson: [UUID: [Int]], rest: [Int]) {
        let refs = people.map { ($0.id, $0.samples.map(\.floats)) }
        var byPerson: [UUID: [Int]] = [:], rest: [Int] = []
        for (i, h) in hits.enumerated() {
            var best: UUID?, bestSim = threshold
            for (id, vs) in refs { for v in vs { let s = FaceScanner.cosine(v, h.vector); if s >= bestSim { best = id; bestSim = s } } }
            if let b = best { byPerson[b, default: []].append(i) } else { rest.append(i) }
        }
        return (byPerson, rest)
    }
}
