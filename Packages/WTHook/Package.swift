// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WTHook",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "wteasy-hook",
            path: "Sources/WTHook"
        ),
    ]
)
