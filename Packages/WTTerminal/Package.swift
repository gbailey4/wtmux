// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WTTerminal",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WTTerminal", targets: ["WTTerminal"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.10.0"),
        .package(path: "../WTSSH"),
    ],
    targets: [
        .target(
            name: "WTTerminal",
            dependencies: ["SwiftTerm", "WTSSH"]
        ),
        .testTarget(name: "WTTerminalTests", dependencies: ["WTTerminal"]),
    ]
)
