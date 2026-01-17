// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

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
        .target(
            name: "SyniSwift",
            dependencies: [],
            path: "Sources/SyniSwift"
        ),
        .testTarget(
            name: "SyniSwiftTests",
            dependencies: ["SyniSwift"],
            path: "Tests/SyniSwiftTests"
        ),
    ]
)
