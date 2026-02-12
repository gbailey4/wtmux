// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WTCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WTCore", targets: ["WTCore"]),
    ],
    targets: [
        .target(name: "WTCore"),
        .testTarget(name: "WTCoreTests", dependencies: ["WTCore"]),
    ]
)
