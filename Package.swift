// swift-tools-version: 6.0

import PackageDescription

// A headless build of the same core sources used by the macOS application.
// This package does not produce a command-line application.
let package = Package(
    name: "RACKET",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RacketCore", targets: ["RacketCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "RacketCore",
            path: "RACKET/Core",
            resources: [.process("Rules/Rules")]
        ),
        .testTarget(
            name: "RacketCoreTests",
            dependencies: ["RacketCore"],
            path: "Tests",
            exclude: ["Fixtures"]
        )
    ],
    swiftLanguageModes: [.v6]
)
