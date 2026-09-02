// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Crab",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "CrabCore", targets: ["CrabCore"]),
        .library(name: "CrabArchive", targets: ["CrabArchive"]),
        .library(name: "CrabAppSupport", targets: ["CrabAppSupport"]),
        .executable(name: "crab", targets: ["crab"]),
        .executable(name: "CrabApp", targets: ["CrabApp"]),
        .executable(name: "crab-core-tests", targets: ["CrabCoreTests"]),
    ],
    targets: [
        .target(
            name: "CrabCore",
            path: "Sources/CrabCore"
        ),
        .target(
            name: "CrabArchive",
            path: "Sources/CrabArchive"
        ),
        .target(
            name: "CrabCLI",
            dependencies: ["CrabCore"],
            path: "Sources/CrabCLI"
        ),
        .target(
            name: "CrabAppSupport",
            dependencies: ["CrabArchive", "CrabCore"],
            path: "Sources/CrabAppSupport"
        ),
        .executableTarget(
            name: "CrabApp",
            dependencies: ["CrabAppSupport", "CrabArchive", "CrabCore"],
            path: "Sources/CrabApp",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "crab",
            dependencies: ["CrabCLI", "CrabCore"],
            path: "Sources/crab"
        ),
        .executableTarget(
            name: "CrabCoreTests",
            dependencies: ["CrabAppSupport", "CrabArchive", "CrabCLI", "CrabCore"],
            path: "Sources/CrabCoreTests"
        ),
    ]
)
