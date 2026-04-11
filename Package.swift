// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScionCLI",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "scion", targets: ["ScionCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/sollahiro/scion-core.git", branch: "main"),
        .package(path: "reown-swift-fork"),
    ],
    targets: [
        .executableTarget(
            name: "ScionCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ScionCore", package: "scion-core"),
                .product(name: "WalletConnect", package: "reown-swift-fork"),
                .product(name: "WalletConnectNetworking", package: "reown-swift-fork"),
                .product(name: "WalletConnectPairing", package: "reown-swift-fork"),
            ],
            path: "Sources/ScionCLI"
        ),
        .testTarget(
            name: "ScionCLITests",
            dependencies: ["ScionCLI"],
            path: "Tests/ScionCLITests"
        ),
    ]
)
