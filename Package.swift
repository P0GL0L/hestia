// swift-tools-version: 6.0

import Foundation
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
        .library(name: "ATAgent", targets: ["ATAgent"]),
        .library(name: "ATCatalog", targets: ["ATCatalog"]),
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
        .target(
            name: "ATAgent",
            dependencies: ["ATContracts"]
        ),
        .target(
            name: "ATCatalog",
            dependencies: ["ATContracts"]
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
        .testTarget(
            name: "ATAgentTests",
            dependencies: [
                "ATAgent",
                "ATContracts",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
        .testTarget(
            name: "ATCatalogTests",
            dependencies: [
                "ATCatalog",
                "ATContracts",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)

// HESTIA_PACKAGE_ONLY=1 leaves the app out, so `swift test` builds and runs only the library modules
// and their tests. The macOS CI runner sets it because its Xcode differs from the one the app ships with.
#if os(macOS)
if ProcessInfo.processInfo.environment["HESTIA_PACKAGE_ONLY"] == nil {
    package.targets.append(
        .executableTarget(
            name: "HestiaApp",
            dependencies: ["ATContracts", "ATGeometry", "ATExchange", "ATDrawings"],
            path: "Apps/Hestia/Sources/HestiaApp"
        )
    )
}
#endif
