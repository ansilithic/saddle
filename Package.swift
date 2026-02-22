// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "saddle",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(path: "../swift-cli-core"),
    ],
    targets: [
        .executableTarget(
            name: "saddle",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "CLICore", package: "swift-cli-core"),
            ]
        ),
        .testTarget(name: "SaddleTests", dependencies: ["saddle"])
    ]
)
