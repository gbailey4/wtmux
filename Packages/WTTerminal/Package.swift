// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WTTerminal",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WTTerminal", targets: ["WTTerminal"]),
    ],
    targets: [
        .target(
            name: "WTTerminal",
            resources: [.copy("Resources")]
        ),
        .testTarget(name: "WTTerminalTests", dependencies: ["WTTerminal"]),
    ]
)
