// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CypraeaCLI",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/sollahiro/cypraea-core.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "CypraeaCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "CypraeaCore", package: "cypraea-core"),
            ],
            path: "Sources/CypraeaCLI"
        ),
        .testTarget(
            name: "CypraeaCLITests",
            dependencies: ["CypraeaCLI"],
            path: "Tests/CypraeaCLITests"
        ),
    ]
)
