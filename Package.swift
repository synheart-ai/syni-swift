// swift-tools-version: 5.9
//
// Package: SyniSwift
// License: Apache-2.0
// Description: Synheart on-device agent SDK for iOS/macOS — thin Swift
//              wrapper around the `syni-runtime` native core plus the
//              Synheart cloud agent API.
//
// Native runtime distribution
// ---------------------------
// `syni-runtime` is shipped via the `synheart` CLI, not SwiftPM. The
// consumer installs it once with the `synheart` CLI:
//
//     curl -fsSL https://synheart.sh/install | sh
//     synheart install runtime syni
//
// That writes `SyniRuntime.xcframework` into the consumer's project at
// `<app>/synheart/vendor/syni-runtime/`. Xcode picks it up at link
// time via a "Frameworks, Libraries, and Embedded Content" entry. The
// SwiftPM package here resolves all C symbols at runtime via
// `dlsym(RTLD_DEFAULT)` — there is no `binaryTarget`, so cloning this
// repo is enough to compile against the API even without the binary
// in place. Calls fail at runtime with a clear error if the runtime
// hasn't been installed.

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
            path: "Sources/SyniSwift"
        ),
        .testTarget(
            name: "SyniSwiftTests",
            dependencies: ["SyniSwift"],
            path: "Tests/SyniSwiftTests"
        ),
    ]
)
