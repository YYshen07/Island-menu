// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IslandMenu",
    platforms: [.macOS("27.0")],
    targets: [
        .target(
            name: "IslandShared",
            path: "Sources/IslandShared",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "IslandMenu",
            dependencies: ["IslandShared"],
            path: "Sources/IslandMenu",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "IslandMenuHelper",
            dependencies: ["IslandShared"],
            path: "Sources/IslandMenuHelper",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
