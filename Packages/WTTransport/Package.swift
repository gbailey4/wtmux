// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WTTransport",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WTTransport", targets: ["WTTransport"]),
    ],
    targets: [
        .target(name: "WTTransport"),
        .testTarget(name: "WTTransportTests", dependencies: ["WTTransport"]),
    ]
)
