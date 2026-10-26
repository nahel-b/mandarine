// Outil de signature des mises à jour de Mandarine (Ed25519, CryptoKit).
//   swift Scripts/update_tool.swift keygen          # crée la paire de clés (une seule fois)
//   swift Scripts/update_tool.swift sign fichier    # écrit la signature (base64) de ce fichier sur la sortie standard
// La clé privée vient de la variable UPDATE_PRIVATE_KEY, sinon du fichier ~/.mandarine/update_private_key. Ne la publiez jamais.
import Foundation
import CryptoKit

let fm = FileManager.default
let keyFile = fm.homeDirectoryForCurrentUser.appendingPathComponent(".mandarine/update_private_key")

func fail(_ m: String) -> Never { FileHandle.standardError.write(Data((m + "\n").utf8)); exit(1) }

func privateKey() -> Curve25519.Signing.PrivateKey {
    let b64 = ProcessInfo.processInfo.environment["UPDATE_PRIVATE_KEY"] ?? (try? String(contentsOf: keyFile, encoding: .utf8)) ?? ""
    guard let d = Data(base64Encoded: b64.trimmingCharacters(in: .whitespacesAndNewlines)), let k = try? Curve25519.Signing.PrivateKey(rawRepresentation: d)
    else { fail("Clé privée introuvable : définissez UPDATE_PRIVATE_KEY ou lancez « swift Scripts/update_tool.swift keygen ».") }
    return k
}

let args = CommandLine.arguments
guard args.count >= 2 else { fail("Usage : keygen | sign <fichier>") }
switch args[1] {
case "keygen":
    if fm.fileExists(atPath: keyFile.path) { fail("Une clé existe déjà : \(keyFile.path). Supprimez-la seulement si vous voulez en changer (les anciennes versions de l'app ne pourront plus se mettre à jour).") }
    let k = Curve25519.Signing.PrivateKey()
    try fm.createDirectory(at: keyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try k.rawRepresentation.base64EncodedString().write(to: keyFile, atomically: true, encoding: .utf8)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile.path)
    let pub = k.publicKey.rawRepresentation.base64EncodedString()
    try (pub + "\n").write(toFile: "Scripts/update_public_key.txt", atomically: true, encoding: .utf8)
    print("Clé privée : \(keyFile.path)  (à copier dans le secret GitHub UPDATE_PRIVATE_KEY, sans jamais la publier)")
    print("Clé publique : \(pub)  (écrite dans Scripts/update_public_key.txt, intégrée à l'app)")
case "sign":
    guard args.count >= 3, let data = fm.contents(atPath: args[2]) else { fail("Fichier introuvable.") }
    print(try privateKey().signature(for: data).base64EncodedString())
default:
    fail("Usage : keygen | sign <fichier>")
}
