import Foundation
import ServiceManagement
import VakterShared

/// Lifecycle manager for the embedded `VakterPrivilegedDaemon` LaunchDaemon.
///
/// The daemon runs as root and exposes a single XPC method
/// (`VakterPrivilegedProtocol.setSleepDisabled`) so the user-level helper
/// can toggle `pmset disablesleep` without prompting for admin each time.
///
/// Registration:
///   - On first launch, `register()` adds the daemon to the system's
///     Login Items. macOS shows the user a notification: "Anchor added a
///     Login Item." The user can view/control it in System Settings →
///     General → Login Items & Extensions → Allow in Background.
///   - The user must approve it ONCE. Subsequent launches use the
///     already-approved daemon silently.
///   - Like `HelperManager`, we proactively unregister+register on every
///     launch so the recorded code requirement (LWCR) refreshes when
///     the app binary is re-signed (e.g. via Sparkle update).
@MainActor
final class PrivilegedDaemonManager {

    private static let daemonPlistName = "app.vakter.mac.privileged-helper.plist"

    private let service: SMAppService

    init() {
        self.service = SMAppService.daemon(plistName: PrivilegedDaemonManager.daemonPlistName)
    }

    var status: SMAppService.Status { service.status }

    var statusLabel: String {
        switch service.status {
        case .notRegistered:    return "not registered"
        case .enabled:          return "enabled (root daemon ready)"
        case .requiresApproval: return "needs approval in System Settings"
        case .notFound:         return "plist missing from bundle"
        @unknown default:       return "unknown"
        }
    }

    /// Register the daemon. Pops a one-time system Login Items prompt the
    /// first time. After approval, the daemon is launchable on-demand via
    /// its Mach service.
    ///
    /// **Important:** unlike HelperManager, we DO NOT unconditionally
    /// unregister-before-register. For a system-domain daemon, unregister
    /// revokes the user's Login Items approval. If we unregister on every
    /// app launch, the user has to re-approve every time we relaunch the
    /// app (or rebuild the bundle) — and during the time between
    /// unregister and re-approval, the daemon is gone and our XPC calls
    /// silently fall back to the per-arm Touch ID path. Bug.
    @discardableResult
    func ensureRegistered() -> SMAppService.Status {
        switch service.status {
        case .enabled:
            // Apple thinks the daemon is enabled. But launchd may secretly
            // be bound to a STALE binary from a previous install (e.g. the
            // pre-rebrand `VakterPrivilegedDaemon` instead of the current
            // `VakterPrivilegedDaemon`). The helper's XPC connection to
            // that stale binary fails with "Couldn't communicate" and we
            // fall back to the per-arm password prompt — the exact bug
            // we built the daemon to avoid.
            //
            // Probe launchctl directly. If the bound executable path
            // doesn't match the current bundle's daemon binary, force a
            // refresh — unregister so Apple drops the stale binding, then
            // re-register. The user has to re-approve in Login Items, but
            // it's a one-time cost vs. a password prompt on every arm.
            if !isDaemonBindingFresh() {
                NSLog("[PrivilegedDaemonManager] launchctl is bound to a STALE daemon binary — auto force-refresh")
                forceRefreshRegistration()
                return service.status
            }
            NSLog("[PrivilegedDaemonManager] already enabled — leaving registration alone")
            return .enabled

        case .requiresApproval:
            // The daemon is registered but the user hasn't enabled the
            // Login Items toggle yet. Bounce them to the right pane.
            NSLog("[PrivilegedDaemonManager] needs one-time approval in System Settings → Login Items")
            SMAppService.openSystemSettingsLoginItems()
            return .requiresApproval

        case .notRegistered, .notFound:
            // Fresh — try to register. If macOS still wants approval after
            // we register (the common first-run case), open Login Items.
            do {
                try service.register()
                NSLog("[PrivilegedDaemonManager] register() succeeded — status: %@", statusLabel)
            } catch {
                let nsError = error as NSError
                if service.status == .requiresApproval {
                    NSLog("[PrivilegedDaemonManager] needs one-time approval in System Settings → Login Items")
                } else {
                    NSLog("[PrivilegedDaemonManager] register() FAILED: %@ (domain=%@ code=%ld) — final status: %@",
                          error.localizedDescription, nsError.domain, nsError.code, statusLabel)
                }
            }
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
            return service.status

        @unknown default:
            return service.status
        }
    }

    func unregister() {
        do { try service.unregister() } catch {
            NSLog("[PrivilegedDaemonManager] unregister failed: %@", error.localizedDescription)
        }
    }

    /// Force a full unregister → register cycle. The user has to
    /// re-approve in Login Items afterwards (one tap), but this clears
    /// every stale launchctl + LWCR binding from previous installs.
    /// Auto-fired by `ensureRegistered()` when the bound binary is
    /// detected as stale; also surfaceable from a Settings "Repair"
    /// button if we want it user-visible later.
    func forceRefreshRegistration() {
        NSLog("[PrivilegedDaemonManager] forcing refresh of LaunchDaemon registration")
        do { try service.unregister() } catch {
            NSLog("[PrivilegedDaemonManager] refresh: unregister() failed: %@",
                  error.localizedDescription)
        }
        do {
            try service.register()
            NSLog("[PrivilegedDaemonManager] refresh: re-registered — status now: %@", statusLabel)
        } catch {
            NSLog("[PrivilegedDaemonManager] refresh: register() FAILED: %@",
                  error.localizedDescription)
        }
        // Always open Login Items — the daemon needs explicit user
        // approval after re-registration.
        SMAppService.openSystemSettingsLoginItems()
    }

    /// True if launchctl's bound daemon binary points inside the
    /// currently-running app bundle. False when it's bound to an
    /// orphan path (a previous install at a different bundle ID,
    /// the pre-rebrand `VakterPrivilegedDaemon`, etc.).
    ///
    /// We parse `launchctl print system/<label>` and look for the
    /// `program = <path>` line, then check that the path is under
    /// `/Applications/Vakter.app/`.
    private func isDaemonBindingFresh() -> Bool {
        let (text, status) = Shell.runDetailed(
            "/bin/launchctl",
            ["print", "system/app.vakter.mac.privileged-helper"])
        if status != 0 {
            // launchctl couldn't find it — not registered. Let the
            // normal .notRegistered path handle it.
            return false
        }
        // Conservative health check: the daemon is fresh if it has a
        // running PID OR the last exit was clean (0) AND it's NOT
        // returning EX_CONFIG (78, LWCR mismatch).
        //
        // The pre-v0.10.2 check looked for `/Vakter.app/` in the
        // `program` line — but SMAppService daemons are reported as
        // a RELATIVE path (`Contents/MacOS/VakterPrivilegedDaemon`),
        // so the check ALWAYS returned false, ALWAYS called
        // forceRefreshRegistration, ALWAYS unregistered the daemon,
        // ALWAYS dropped the user's Login-Items approval. The
        // password-prompt-on-every-arm bug was the auto-recovery code
        // tearing down a perfectly good registration on every launch.
        //
        // A genuinely-stale binding looks like:
        //   - `last exit code = 78` (EX_CONFIG, LWCR predicate fails)
        //   - or `last exit code` is non-zero with no PID
        // Anything else — including "just rebuilt" — is fine; launchd
        // already handles binary swaps at the bundled path correctly.
        if text.contains("last exit code = 78")          { return false }
        if text.contains("EX_CONFIG")                    { return false }
        if text.range(of: #"pid = [0-9]+"#,
                      options: .regularExpression) != nil { return true }
        if text.contains("last exit code = 0")           { return true }
        return true   // assume healthy; we don't have evidence otherwise
    }
}
