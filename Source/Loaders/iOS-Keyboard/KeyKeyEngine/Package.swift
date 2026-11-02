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
        // Declarations come from the shared ABI; Rust is built by Xcode or the
        // explicit host-test helper, never while evaluating this manifest.
        .target(
            name: "CGuanyinma",
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("guanyinma"), .linkedLibrary("iconv")]
        ),
        .target(
            name: "KeyKeyEngine",
            dependencies: ["CGuanyinma"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "KeyKeyEngineTests", dependencies: ["KeyKeyEngine"])
    ]
)
