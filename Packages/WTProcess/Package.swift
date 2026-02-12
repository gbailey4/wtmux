// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WTProcess",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WTProcess", targets: ["WTProcess"]),
    ],
    dependencies: [
        .package(path: "../WTTransport"),
    ],
    targets: [
        .target(name: "WTProcess", dependencies: ["WTTransport"]),
        .testTarget(name: "WTProcessTests", dependencies: ["WTProcess"]),
    ]
)
