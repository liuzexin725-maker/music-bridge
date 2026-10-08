// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MusicBridgeApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MusicBridgeApp", targets: ["MusicBridgeApp"])
    ],
    targets: [
        .executableTarget(
            name: "MusicBridgeApp",
            path: "Sources/MusicBridgeApp"
        )
    ],
    swiftLanguageModes: [.v5]
)
