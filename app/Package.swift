// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kanso",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "KansoCore",
            linkerSettings: [.unsafeFlags(["-weak_framework", "FoundationModels"])]  // Apple Intelligence exists only on macOS 26+
        ),
        // SwiftPM stamps the binary with the deployment target as its SDK version, which makes macOS 26+ run the app
        // in compatibility mode (no Liquid Glass). Stamp the real SDK so AppKit and SwiftUI use the current design.
        .executableTarget(name: "Kanso", dependencies: ["KansoCore"],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "macos", "-Xlinker", "14.0", "-Xlinker", "27.0"])]),
        .executableTarget(name: "kanso-cli", dependencies: ["KansoCore"]),
        .testTarget(name: "KansoCoreTests", dependencies: ["KansoCore"]),
    ],
    swiftLanguageModes: [.v5]
)
