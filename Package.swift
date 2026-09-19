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
            url: "https://github.com/leviouwendijk/Agentic.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/AgenticInference.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/AgenticPrograms.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Primitives.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Schema.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Macros.git",
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
                    name: "Agentic",
                    package: "Agentic"
                ),
                .product(
                    name: "AgenticInference",
                    package: "AgenticInference"
                ),
                .product(
                    name: "AgenticPrograms",
                    package: "AgenticPrograms"
                ),
                .product(
                    name: "Primitives",
                    package: "Primitives"
                ),
                .product(
                    name: "Schema",
                    package: "Schema"
                ),
                .product(
                    name: "Macros",
                    package: "Macros"
                ),
            ]
        ),
        .executableTarget(
            name: "AgenticOptimizerTestFlows",
            dependencies: [
                "AgenticOptimizer",
                .product(
                    name: "Agentic",
                    package: "Agentic"
                ),
                .product(
                    name: "AgenticInference",
                    package: "AgenticInference"
                ),
                .product(
                    name: "AgenticPrograms",
                    package: "AgenticPrograms"
                ),
                .product(
                    name: "Primitives",
                    package: "Primitives"
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