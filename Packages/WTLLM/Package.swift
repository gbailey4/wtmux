// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WTLLM",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WTLLM", targets: ["WTLLM"]),
    ],
    dependencies: [
        .package(path: "../WTTransport"),
    ],
    targets: [
        .target(
            name: "WTLLM",
            dependencies: ["WTTransport"]
        ),
        .testTarget(
            name: "WTLLMTests",
            dependencies: ["WTLLM"]
        ),
    ]
)
