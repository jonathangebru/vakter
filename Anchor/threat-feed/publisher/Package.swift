// swift-tools-version: 6.0
//
// Vakter threat-feed publisher.
//
// Separate Package from the Anchor app so it can build and run on a Linux
// or macOS CI runner without dragging in AppKit / XPC / SMAppService
// dependencies. CryptoKit (Ed25519) is the only Apple framework used and
// is available on both platforms via swift-crypto.
//
// See README.md for operator instructions.

import PackageDescription

let package = Package(
    name: "VakterThreatFeedPublisher",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "vakter-threat-feed-publisher",
            targets: ["VakterThreatFeedPublisher"]
        )
    ],
    dependencies: [
        // swift-crypto: Apple's open-source Linux-portable mirror of
        // CryptoKit. On macOS it forwards to CryptoKit, so we get one
        // import path that works on both the local dev box and a GitHub
        // Actions runner.
        .package(
            url: "https://github.com/apple/swift-crypto.git",
            from: "3.0.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "VakterThreatFeedPublisher",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto")
            ],
            path: "Sources/VakterThreatFeedPublisher"
        ),
        .testTarget(
            name: "VakterThreatFeedPublisherTests",
            dependencies: ["VakterThreatFeedPublisher"],
            path: "Tests/VakterThreatFeedPublisherTests"
        )
    ]
)
