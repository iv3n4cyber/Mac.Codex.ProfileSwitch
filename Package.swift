// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Mac.Codex.ProfileSwitch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Mac.Codex.ProfileSwitch",
            targets: ["MacCodexProfileSwitch"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MacCodexProfileSwitch"
        )
    ]
)
