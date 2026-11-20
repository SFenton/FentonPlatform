// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FentonPlatform",
    platforms: [
        .iOS(.v17),
        // macOS exists only so `swift test` runs the pure-logic tests on the Mac host; there is no macOS product or UI.
        .macOS(.v14)
    ],
    products: [
        .library(name: "FentonAppleCore", targets: ["FentonAppleCore"]),
        .library(name: "FentonAppleTelemetry", targets: ["FentonAppleTelemetry"]),
        .library(name: "FentonUIKit", targets: ["FentonUIKit"]),
        .library(name: "FentonUIKitTestHostSupport", targets: ["FentonUIKitTestHostSupport"]),
        .library(name: "FentonXCUITestSupport", targets: ["FentonXCUITestSupport"])
    ],
    targets: [
        .target(
            name: "FentonAppleCore",
            path: "platforms/apple/Sources/FentonAppleCore"
        ),
        .target(
            name: "FentonAppleTelemetry",
            dependencies: ["FentonAppleCore"],
            path: "platforms/apple/Sources/FentonAppleTelemetry"
        ),
        .target(
            name: "FentonUIKit",
            dependencies: ["FentonAppleCore", "FentonAppleTelemetry"],
            path: "platforms/apple/Sources/FentonUIKit"
        ),
        .target(
            name: "FentonUIKitTestHostSupport",
            dependencies: ["FentonUIKit"],
            path: "platforms/apple/TestSupport/FentonUIKitTestHostSupport"
        ),
        .target(
            name: "FentonXCUITestSupport",
            path: "platforms/apple/TestSupport/FentonXCUITestSupport"
        ),
        .testTarget(
            name: "FentonAppleCoreTests",
            dependencies: ["FentonAppleCore"],
            path: "platforms/apple/Tests/Core"
        ),
        .testTarget(
            name: "FentonAppleTelemetryTests",
            dependencies: ["FentonAppleTelemetry"],
            path: "platforms/apple/Tests/Telemetry"
        ),
        .testTarget(
            name: "FentonUIKitHostedTests",
            dependencies: ["FentonUIKit"],
            path: "platforms/apple/Tests/UIKitHosted"
        )
    ]
)
