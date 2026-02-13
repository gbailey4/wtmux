// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WTGit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WTGit", targets: ["WTGit"]),
    ],
    dependencies: [
        .package(path: "../WTTransport"),
    ],
    targets: [
        .target(name: "WTGit", dependencies: ["WTTransport"]),
        .testTarget(name: "WTGitTests", dependencies: ["WTGit", "WTTransport"]),
    ]
)
