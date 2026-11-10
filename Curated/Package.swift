// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Curated",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Curated",
            path: "Sources/Curated",
            // SwiftPM stamps the binary as built with the macOS 14 SDK, so AppKit and AVKit fall back to their
            // pre-Liquid Glass look (e.g. AVKit's floating controls). Stamp the real SDK instead.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "macos",
                                           "-Xlinker", "14.0", "-Xlinker", "27.0"])]
        )
    ],
    swiftLanguageModes: [.v5]
)
