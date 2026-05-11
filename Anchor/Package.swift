// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Anchor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // The user-facing menubar app entry point. Wrapped into an .app bundle
        // by `Scripts/build-app.sh`.
        .executable(name: "AnchorApp", targets: ["AnchorApp"]),

        // The background daemon. Wrapped into the helper LaunchAgent.
        .executable(name: "AnchorHelper", targets: ["AnchorHelper"]),
    ],
    targets: [
        // Shared protocol + types used by both the app and the helper.
        .target(
            name: "AnchorShared",
            path: "Sources/AnchorShared"
        ),

        .executableTarget(
            name: "AnchorApp",
            dependencies: ["AnchorShared"],
            path: "Sources/AnchorApp",
            // SPM doesn't bundle these — Resources are assembled into the
            // .app bundle by `Scripts/build-app.sh`. Exclude so SPM stops
            // warning about "unhandled" files.
            exclude: ["Resources"]
        ),

        .executableTarget(
            name: "AnchorHelper",
            dependencies: ["AnchorShared"],
            path: "Sources/AnchorHelper",
            exclude: ["Resources"]
        ),
    ]
)
