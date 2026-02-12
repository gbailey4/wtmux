// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WTDiff",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WTDiff", targets: ["WTDiff"]),
    ],
    dependencies: [
        .package(url: "https://github.com/appstefan/HighlightSwift.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "WTDiff", dependencies: ["HighlightSwift"]),
        .testTarget(name: "WTDiffTests", dependencies: ["WTDiff"]),
    ]
)
