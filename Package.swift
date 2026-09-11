// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "AgenticOptimizer",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "AgenticOptimizer",
            targets: [
                "AgenticOptimizer",
            ]
        ),
        .executable(
            name: "aopttest",
            targets: [
                "AgenticOptimizerTestFlows",
            ]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/leviouwendijk/AgenticInference.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/TestFlows.git",
            branch: "master"
        ),
    ],
    targets: [
        .target(
            name: "AgenticOptimizer",
            dependencies: [
                .product(
                    name: "AgenticInference",
                    package: "AgenticInference"
                ),
            ]
        ),
        .executableTarget(
            name: "AgenticOptimizerTestFlows",
            dependencies: [
                "AgenticOptimizer",
                .product(
                    name: "AgenticInference",
                    package: "AgenticInference"
                ),
                .product(
                    name: "TestFlows",
                    package: "TestFlows"
                ),
            ]
        ),
    ],
    swiftLanguageModes: [
        .v6,
    ]
)
