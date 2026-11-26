// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IslandMenu",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "IslandMenu",
            path: "Sources/IslandMenu",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
