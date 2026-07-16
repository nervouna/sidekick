// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Sidekick",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Sidekick", targets: ["SidekickApp"]),
        .library(name: "SidekickCore", targets: ["SidekickCore"])
    ],
    targets: [
        .target(name: "SidekickCore"),
        .executableTarget(
            name: "SidekickApp",
            dependencies: ["SidekickCore"]
        ),
        .testTarget(
            name: "SidekickCoreTests",
            dependencies: ["SidekickCore"]
        )
    ]
)
