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

        // Dev-only CLI poker that exercises the XPC protocol. Not shipped.
        .executable(name: "AnchorHelperPoke", targets: ["AnchorHelperPoke"]),

        // Root-privileged LaunchDaemon. Registered via SMAppService.daemon
        // from the menubar app. Exposes a single XPC method for toggling
        // pmset disablesleep, so we don't prompt for admin per arm.
        .executable(name: "AnchorPrivilegedDaemon", targets: ["AnchorPrivilegedDaemon"]),
    ],
    targets: [
        // Shared protocol + types used by both the app and the helper.
        .target(
            name: "AnchorShared",
            path: "Sources/AnchorShared"
        ),

        // Tiny C target that wraps `AuthorizationExecuteWithPrivileges` —
        // necessary because the Swift overlay marks it `unavailable` even
        // though it works in C. Used by the helper's SleepDisabler.
        .target(
            name: "AnchorPrivilegedExec",
            path: "Sources/AnchorPrivilegedExec",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),

        .executableTarget(
            name: "AnchorApp",
            dependencies: ["AnchorShared"],
            path: "Sources/AnchorApp",
            // SPM doesn't bundle these — Resources are assembled into the
            // .app bundle by `Scripts/build-app.sh`. Exclude so SPM stops
            // warning about "unhandled" files.
            exclude: ["Resources"]
            // NOTE: AppIntents discovery (Shortcuts/Spotlight) requires
            // appintentsmetadataprocessor to consume `.swiftconstvalues`
            // files emitted per Swift source — a build phase that SPM does
            // not perform by default. See spikes/SPIKE_REPORT.md spike 8.
            // The intent code in AnchorIntents.swift compiles and links;
            // it will not surface in Shortcuts until we either (a) migrate
            // to .xcodeproj or (b) plumb the const-values emission via
            // custom Swift invocations.
        ),

        .executableTarget(
            name: "AnchorHelper",
            dependencies: ["AnchorShared", "AnchorPrivilegedExec"],
            path: "Sources/AnchorHelper",
            exclude: ["Resources"]
        ),

        .executableTarget(
            name: "AnchorHelperPoke",
            dependencies: ["AnchorShared"],
            path: "Sources/AnchorHelperPoke"
        ),

        .executableTarget(
            name: "AnchorPrivilegedDaemon",
            dependencies: ["AnchorShared"],
            path: "Sources/AnchorPrivilegedDaemon",
            exclude: ["Resources"]
        ),
    ]
)
