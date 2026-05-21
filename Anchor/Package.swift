// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vakter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // The user-facing menubar app entry point. Wrapped into an .app bundle
        // by `Scripts/build-app.sh`.
        .executable(name: "VakterApp", targets: ["VakterApp"]),

        // The background daemon. Wrapped into the helper LaunchAgent.
        .executable(name: "VakterHelper", targets: ["VakterHelper"]),

        // Dev-only CLI poker that exercises the XPC protocol. Not shipped.
        .executable(name: "VakterHelperPoke", targets: ["VakterHelperPoke"]),

        // Root-privileged LaunchDaemon. Registered via SMAppService.daemon
        // from the menubar app. Exposes a single XPC method for toggling
        // pmset disablesleep, so we don't prompt for admin per arm.
        .executable(name: "VakterPrivilegedDaemon", targets: ["VakterPrivilegedDaemon"]),
    ],
    targets: [
        // Shared protocol + types used by both the app and the helper.
        .target(
            name: "VakterShared",
            path: "Sources/VakterShared"
        ),

        // Tiny C target that wraps `AuthorizationExecuteWithPrivileges` —
        // necessary because the Swift overlay marks it `unavailable` even
        // though it works in C. Used by the helper's SleepDisabler.
        .target(
            name: "VakterPrivilegedExec",
            path: "Sources/VakterPrivilegedExec",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),

        .executableTarget(
            name: "VakterApp",
            dependencies: ["VakterShared"],
            path: "Sources/VakterApp",
            // SPM doesn't bundle these — Resources are assembled into the
            // .app bundle by `Scripts/build-app.sh`. Exclude so SPM stops
            // warning about "unhandled" files.
            exclude: ["Resources"]
            // NOTE: AppIntents discovery (Shortcuts/Spotlight) requires
            // appintentsmetadataprocessor to consume `.swiftconstvalues`
            // files emitted per Swift source — a build phase that SPM does
            // not perform by default. See spikes/SPIKE_REPORT.md spike 8.
            // The intent code in VakterIntents.swift compiles and links;
            // it will not surface in Shortcuts until we either (a) migrate
            // to .xcodeproj or (b) plumb the const-values emission via
            // custom Swift invocations.
        ),

        .executableTarget(
            name: "VakterHelper",
            dependencies: ["VakterShared", "VakterPrivilegedExec"],
            path: "Sources/VakterHelper",
            exclude: ["Resources"],
            linkerSettings: [
                // Embed the helper's Info.plist into the Mach-O so macOS
                // can read CFBundleName when it shows the privileged-auth
                // dialog ("Vakter wants to make changes" rather than the
                // binary filename). Same trick as the daemon below.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/VakterHelper/Resources/Info.plist"
                ])
            ]
        ),

        .executableTarget(
            name: "VakterHelperPoke",
            dependencies: ["VakterShared"],
            path: "Sources/VakterHelperPoke"
        ),

        .executableTarget(
            name: "VakterPrivilegedDaemon",
            dependencies: ["VakterShared"],
            path: "Sources/VakterPrivilegedDaemon",
            exclude: ["Resources"],
            linkerSettings: [
                // SMAppService.daemon refuses to spawn a binary whose
                // Info.plist isn't bound into the Mach-O. For .app-style
                // bundles Xcode handles this automatically; with SwiftPM
                // we ask the linker to create the __TEXT,__info_plist
                // section ourselves.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/VakterPrivilegedDaemon/Resources/Info.plist"
                ])
            ]
        ),

        // --- Tests ---------------------------------------------------

        // Pure unit tests on the shared types. Includes the AckGate
        // concurrency primitive used by the test-alarm race fix.
        .testTarget(
            name: "VakterSharedTests",
            dependencies: ["VakterShared"],
            path: "Tests/VakterSharedTests"
        ),

        // State-machine tests. Use @testable import to reach the
        // internal types and inject SleepGuarding / SleepDisabling
        // / AudioControlling / PhotoCapturing mocks.
        .testTarget(
            name: "VakterHelperTests",
            dependencies: ["VakterHelper", "VakterShared"],
            path: "Tests/VakterHelperTests"
        ),
    ]
)
