// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Mandarine",
    platforms: [.macOS("13.3")],
    targets: [
        // Moteur de reconnaissance vocale Whisper (whisper.cpp, MIT) : bibliothèque officielle précompilée (Metal + Accelerate, arm64 et Intel).
        // Elle ne sert que si l'utilisateur télécharge le modèle optionnel (Réglages → Engines).
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-b5454-xcframework.zip",
            checksum: "e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b"
        ),
        .executableTarget(name: "Mandarine", dependencies: ["whisper"], path: "Sources/Mandarine")
    ],
    swiftLanguageModes: [.v5]
)
