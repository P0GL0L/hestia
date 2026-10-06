// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Hestia",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        .library(name: "ATContracts", targets: ["ATContracts"]),
        .library(name: "ATGeometry", targets: ["ATGeometry"]),
        .library(name: "ATExchange", targets: ["ATExchange"]),
        .library(name: "ATDrawings", targets: ["ATDrawings"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.10.0"),
    ],
    targets: [
        .target(name: "ATContracts"),
        .target(
            name: "ATGeometry",
            dependencies: ["ATContracts"]
        ),
        .target(
            name: "ATExchange",
            dependencies: ["ATContracts", "ATGeometry"]
        ),
        .target(
            name: "ATDrawings",
            dependencies: ["ATContracts", "ATGeometry"]
        ),
        .testTarget(
            name: "ATContractsTests",
            dependencies: [
                "ATContracts",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
        .testTarget(
            name: "ATGeometryTests",
            dependencies: [
                "ATGeometry",
                "ATContracts",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
        .testTarget(
            name: "ATExchangeTests",
            dependencies: [
                "ATExchange",
                "ATGeometry",
                "ATContracts",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
        .testTarget(
            name: "ATDrawingsTests",
            dependencies: [
                "ATDrawings",
                "ATGeometry",
                "ATContracts",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)

#if os(macOS)
package.targets.append(
    .executableTarget(
        name: "HestiaApp",
        dependencies: ["ATContracts", "ATGeometry", "ATExchange", "ATDrawings"],
        path: "Apps/Hestia/Sources/HestiaApp"
    )
)
#endif
