// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Mandarine",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Mandarine", path: "Sources/Mandarine")
    ],
    swiftLanguageModes: [.v5]
)
