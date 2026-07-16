// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Sidekick",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Sidekick", targets: ["SidekickApp"]),
        .library(name: "SidekickCore", targets: ["SidekickCore"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/gonzalezreal/swift-markdown-ui.git",
            exact: "2.4.1"
        )
    ],
    targets: [
        .target(name: "SidekickCore"),
        .executableTarget(
            name: "SidekickApp",
            dependencies: [
                "SidekickCore",
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ]
        ),
        .testTarget(
            name: "SidekickCoreTests",
            dependencies: ["SidekickCore"]
        ),
        .testTarget(
            name: "SidekickAppTests",
            dependencies: ["SidekickApp", "SidekickCore"]
        )
    ]
)
