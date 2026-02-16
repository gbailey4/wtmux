// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WTSSH",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WTSSH", targets: ["WTSSH"]),
    ],
    dependencies: [
        .package(path: "../WTTransport"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.8.0"),
    ],
    targets: [
        .target(
            name: "WTSSH",
            dependencies: [
                "WTTransport",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
            ]
        ),
        .testTarget(
            name: "WTSSHTests",
            dependencies: ["WTSSH"]
        ),
    ]
)
