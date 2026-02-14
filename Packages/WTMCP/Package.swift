// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WTMCP",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../WTCore"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "wtmux-mcp",
            dependencies: [
                "WTCore",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/WTMCP"
        ),
    ]
)
