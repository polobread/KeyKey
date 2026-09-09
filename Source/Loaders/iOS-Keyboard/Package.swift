// swift-tools-version: 6.0
import PackageDescription

// Exercise the container's actual purchase flow without linking StoreKit into the keyboard engine.
let package = Package(
    name: "SupporterStoreTests",
    platforms: [.iOS(.v17), .macOS(.v14)],
    dependencies: [.package(path: "KeyKeyEngine")],
    targets: [
        .target(
            name: "SupporterStoreFlow",
            dependencies: [.product(name: "KeyKeyEngine", package: "KeyKeyEngine")],
            path: "ContainerApp",
            exclude: [
                "Acknowledgements.txt", "AppDelegate.swift", "Assets.xcassets",
                "HardwareKeyboardEditorViewController.swift", "Info.plist",
                "KeyKey.entitlements", "PrivacyInfo.xcprivacy", "SetupViewController.swift"
            ],
            sources: ["SupporterStore.swift"]
        ),
        .testTarget(
            name: "SupporterStoreFlowTests",
            dependencies: ["SupporterStoreFlow"],
            path: "SupporterStoreTests"
        )
    ]
)
