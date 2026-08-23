// swift-tools-version: 6.0

import PackageDescription

// The engine is deliberately free of UIKit so it can be exercised with
// `swift test` on the build machine, without an iOS simulator runtime.
let package = Package(
    name: "KeyKeyEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KeyKeyEngine", targets: ["KeyKeyEngine"])
    ],
    targets: [
        .target(
            name: "KeyKeyEngine",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "KeyKeyEngineTests", dependencies: ["KeyKeyEngine"])
    ]
)
