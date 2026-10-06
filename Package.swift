// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Hestia",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        .library(name: "ATContracts", targets: ["ATContracts"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.10.0"),
    ],
    targets: [
        .target(name: "ATContracts"),
        .testTarget(
            name: "ATContractsTests",
            dependencies: [
                "ATContracts",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
