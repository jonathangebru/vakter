import Foundation
import AppIntents
import VakterShared

// MARK: - Intents

/// Arms Vakter using the currently-selected mode. The most basic intent we
/// expose; everything else builds on it. The Shortcut form is:
///
///     Action: Arm Vakter
///
/// Returns `.result()` on success; throws `VakterIntentError.helperUnreachable`
/// if the helper daemon isn't running (so Shortcuts surfaces a real failure
/// instead of silently appearing to succeed).
///
/// **Why we open a fresh `NSXPCConnection` here, rather than reusing the
/// `HelperClient` owned by `AppDelegate`:** App Intents are dispatched by
/// the system through Shortcuts and may run in an isolated process context.
/// The codebase has explicit comments warning that `NSApp.delegate as?
/// AppDelegate` returns nil from SwiftUI-hosted contexts (see VakterApp.swift
/// lines 142 and 185). Rather than fight that, each intent invocation opens
/// its own short-lived connection to the helper's Mach service — the exact
/// pattern used by `VakterHelperPoke` (the dev CLI). The helper is the
/// source of truth for state; the app-side `HelperClient` is just one of
/// potentially several XPC clients.
struct ArmVakterIntent: AppIntent {
    static let title: LocalizedStringResource = "Arm Vakter"
    static let description = IntentDescription(
        "Locks your Mac and arms Vakter using the current mode. Use this from a Shortcut tied to your 'Café' Focus, or any automation that should hand off to Vakter."
    )

    func perform() async throws -> some IntentResult {
        // Route through the helper over XPC and wait for its ack. The
        // helper's `arm` method calls `stateMachine.armFromUser()` which
        // engages SleepGuard + SleepDisabler. On macOS those may surface
        // a privileged-auth prompt; Shortcuts can't render Touch ID UI,
        // but the prompt path uses the daemon (after first approval) so
        // subsequent runs are silent.
        let ok = try await VakterIntentXPC.callArm()
        guard ok else {
            throw VakterIntentError.armRejected
        }
        return .result()
    }
}

/// Switches Vakter's active mode (Normal / Travel / Library / Loaner / Cafe).
///
/// Bridges the AppIntent-specific `VakterModeAppEnum` to the shared
/// `VakterMode` and dispatches over XPC. Same lifecycle caveat as
/// `ArmVakterIntent` — we open a fresh connection per invocation.
struct SetVakterModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Vakter Mode"
    static let description = IntentDescription(
        "Switches Vakter between Normal, Travel, Library, and Loaner modes."
    )

    @Parameter(title: "Mode")
    var mode: VakterModeAppEnum

    func perform() async throws -> some IntentResult {
        let raw = mode.asVakterMode.rawValue
        let ok = try await VakterIntentXPC.callSetMode(raw: raw)
        guard ok else {
            throw VakterIntentError.modeRejected(raw)
        }
        return .result()
    }
}

// MARK: - App-enum bridge for VakterMode

/// AppIntents requires its own enum wrapper (it generates a metadata file
/// per case). We mirror VakterMode here. Conversion is trivial.
enum VakterModeAppEnum: String, AppEnum {
    case normal, travel, library, loaner, cafe

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mode"

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .normal:  "Normal",
        .travel:  "Travel",
        .library: "Library",
        .loaner:  "Loaner",
        .cafe:    "Cafe",
    ]

    /// Bridge into the shared model type.
    var asVakterMode: VakterMode {
        switch self {
        case .normal:  return .normal
        case .travel:  return .travel
        case .library: return .library
        case .loaner:  return .loaner
        case .cafe:    return .cafe
        }
    }
}

// MARK: - Intent-side XPC plumbing

/// Errors surfaced to Shortcuts when an intent can't fulfil its job.
/// Conforming to `LocalizedError` makes Shortcuts show the `errorDescription`
/// string in its red banner; otherwise it'd show "An error occurred."
enum VakterIntentError: LocalizedError {
    /// The helper Mach service replied with `false` to `arm`. Usually means
    /// the state machine refused the transition (already armed, mid-grace,
    /// etc.) rather than an outright failure — but the user asked for an
    /// arm, and we couldn't deliver one, so we surface a clean error.
    case armRejected
    /// `setMode` returned false. Almost always indicates an invalid mode
    /// raw value, which shouldn't happen via the typed enum — but defending
    /// against it costs nothing.
    case modeRejected(String)
    /// We never managed to talk to the helper at all (connection invalid,
    /// proxy cast failed, helper LaunchAgent not approved by the user).
    case helperUnreachable

    var errorDescription: String? {
        switch self {
        case .armRejected:
            return "Vakter couldn't arm right now. Open Vakter from the menu bar and try again."
        case .modeRejected(let raw):
            return "Vakter rejected mode change to '\(raw)'."
        case .helperUnreachable:
            return "Vakter's background helper isn't running. Open Vakter from the menu bar to start it."
        }
    }
}

/// One-shot NSXPCConnection helpers used by the intent `perform()` bodies.
///
/// Each call opens a fresh connection, sends the request, awaits the reply
/// (or a hard timeout), then invalidates the connection. This is deliberately
/// **not** a long-lived singleton: App Intents fire infrequently from
/// Shortcuts and there's no benefit to keeping a connection warm.
///
/// **Why the timeout?** `NSXPCConnection` will silently wait forever if the
/// Mach service can't be resolved (e.g. the helper LaunchAgent hasn't been
/// approved yet, or was just renamed and the code-signing requirement no
/// longer matches). Without a timeout the Shortcut hangs indefinitely; with
/// one, Shortcuts shows a real error.
enum VakterIntentXPC {

    /// Hard upper bound for any single intent → helper round-trip. The
    /// `arm` reply is synchronous on the helper side (just flips state)
    /// so 5s is generous. If we hit this the helper is unreachable or
    /// hung — surface that to the user.
    private static let timeoutSeconds: TimeInterval = 5.0

    /// Call `arm` on the helper; bool reply mapped to a Swift Bool.
    static func callArm() async throws -> Bool {
        try await withTimeout { proxy, settle in
            proxy.arm { ok in settle(ok) }
        }
    }

    /// Call `setMode(_:)` on the helper.
    static func callSetMode(raw: String) async throws -> Bool {
        try await withTimeout { proxy, settle in
            proxy.setMode(raw) { ok in settle(ok) }
        }
    }

    /// Open a connection, hand the proxy + a `settle` closure to the caller
    /// so it can issue its one XPC call. `settle(reply)` is invoked from the
    /// XPC reply handler. If the helper is unreachable, a hard timeout fires
    /// after `timeoutSeconds` and throws `.helperUnreachable`.
    ///
    /// **Concurrency:** an `AckGate` arbitrates between the two racing
    /// callbacks (XPC reply on a background queue, timeout via
    /// `DispatchQueue.main.asyncAfter`). Whichever settles first wins; the
    /// loser observes `claim() == false` and is a no-op. This mirrors the
    /// pattern used by `HelperClient.testAlarm()`.
    ///
    /// **Why not `withThrowingTaskGroup` racing two `Task`s:** under Swift
    /// 6 strict concurrency the NSXPCConnection proxy isn't `Sendable`, so
    /// passing it into an `addTask` closure trips a data-race warning. The
    /// `AckGate` + single-continuation form keeps the proxy on the calling
    /// actor and only the typed `Bool` settles cross-context.
    @MainActor
    private static func withTimeout(
        _ body: (VakterHelperProtocol, @escaping @Sendable (Bool) -> Void) -> Void
    ) async throws -> Bool {
        let conn = NSXPCConnection(machServiceName: VakterConstants.xpcMachServiceName)
        conn.remoteObjectInterface = NSXPCInterface(with: VakterHelperProtocol.self)
        conn.resume()

        // Tear down the connection on every exit path (success, throw).
        defer { conn.invalidate() }

        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ err in
            NSLog("[VakterIntent] proxy error: %@", err.localizedDescription)
        }) as? VakterHelperProtocol else {
            throw VakterIntentError.helperUnreachable
        }

        // The result, whichever path arrives first. `nil` means the timeout
        // won, which we translate into `.helperUnreachable` after the await.
        //
        // `withTimeout` is @MainActor so the AckGate (which is also
        // @MainActor) can be constructed synchronously here. The XPC reply
        // closure still arrives on a background queue, so it hops back via
        // `Task { @MainActor in … }` before claiming the gate.
        let result: Bool? = await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
            let gate = AckGate()

            // Path A — XPC reply.
            body(proxy) { ok in
                Task { @MainActor in
                    guard gate.claim() else { return }
                    continuation.resume(returning: ok)
                }
            }

            // Path B — hard timeout. If the helper isn't running at all
            // (LaunchAgent not approved, just renamed, etc.) the XPC reply
            // will never arrive; this surfaces a real error to Shortcuts
            // instead of hanging the user's Shortcut indefinitely.
            DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds) {
                Task { @MainActor in
                    guard gate.claim() else { return }
                    NSLog("[VakterIntent] helper unreachable — XPC reply timed out after %.1fs", timeoutSeconds)
                    continuation.resume(returning: nil)
                }
            }
        }

        guard let value = result else {
            throw VakterIntentError.helperUnreachable
        }
        return value
    }
}

// MARK: - App Shortcuts provider

/// Surfaces our intents as App Shortcuts (pre-built Shortcut tiles that
/// users can drop into automations). Required for Spotlight + Shortcuts
/// auto-discovery on macOS 14+.
///
/// **Discovery caveat:** AppIntents discovery requires
/// `appintentsmetadataprocessor` to consume `.swiftconstvalues` files —
/// a build step SwiftPM doesn't run. The intents below compile and link
/// (this file builds cleanly), but they may not surface in the Shortcuts
/// app until the project gains an .xcodeproj wrapper or we plumb the
/// const-values emission via custom Swift invocations. See Package.swift
/// note on the VakterApp target. The XPC wiring in `perform()` is correct
/// regardless — once discovery is unblocked, the actions Just Work.
struct VakterShortcutsProvider: AppShortcutsProvider {

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ArmVakterIntent(),
            phrases: [
                "Arm \(.applicationName)",
                "Lock and arm \(.applicationName)",
            ],
            shortTitle: "Arm Vakter",
            systemImageName: "shield.fill"
        )

        AppShortcut(
            intent: SetVakterModeIntent(),
            phrases: [
                "Set \(.applicationName) mode",
            ],
            shortTitle: "Set Vakter Mode",
            systemImageName: "rectangle.stack"
        )
    }
}
