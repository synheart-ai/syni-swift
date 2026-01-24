// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// MARK: - Configuration

/// Set to true when using the local XCFramework for development.
/// Set to false (and uncomment the URL-based binary target) for distribution.
let useLocalFramework = true

/// Path to the local XCFramework (relative to package root).
/// Build with: ./Scripts/build-xcframework.sh
let localFrameworkPath = "Frameworks/SyniRuntime.xcframework"

// MARK: - Package Definition

let package = Package(
    name: "SyniSwift",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SyniSwift",
            targets: ["SyniSwift"]
        ),
    ],
    dependencies: [],
    targets: [
        // Binary target for syni-runtime XCFramework
        // This is the App Store compliant way to distribute native libraries
        .binaryTarget(
            name: "SyniRuntime",
            // Option 1: Local framework (for development)
            path: localFrameworkPath

            // Option 2: Remote URL (for distribution via SPM)
            // Uncomment and update URL/checksum for releases:
            // url: "https://github.com/synheart/syni-runtime/releases/download/v1.0.0/SyniRuntime.xcframework.zip",
            // checksum: "sha256-checksum-here"
        ),

        // Swift wrapper that uses the XCFramework
        .target(
            name: "SyniSwift",
            dependencies: ["SyniRuntime"],
            path: "Sources/SyniSwift"
        ),

        .testTarget(
            name: "SyniSwiftTests",
            dependencies: ["SyniSwift"],
            path: "Tests/SyniSwiftTests"
        ),
    ]
)
