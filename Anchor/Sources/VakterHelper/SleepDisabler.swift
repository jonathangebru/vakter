import Foundation
import VakterShared
import VakterPrivilegedExec

/// Outcome of asking the system to disable lid-close sleep. The state
/// machine reads this to decide whether arming should actually proceed.
public enum SleepDisablerResult: Equatable, Sendable {
    /// Sleep is now disabled. Arming can proceed silently.
    case engaged
    /// The user explicitly cancelled the Touch ID / password prompt.
    /// Arming MUST be aborted — they said no.
    case userCancelled
    /// The privileged daemon is registered but not yet approved in
    /// Login Items. We fell through to the local prompt, but the right
    /// remediation is for the user to approve the daemon. Arming
    /// proceeds with the degraded `SleepGuard`-only fallback, and the
    /// app surfaces an "approve in Login Items" banner.
    case daemonNeedsApproval
    /// Something else broke (XPC error, pmset exit non-zero, etc.).
    /// Arming proceeds with the degraded fallback.
    case failed
}

/// Globally disables system sleep via `pmset -a disablesleep 1` while
/// armed, then restores normal sleep on disarm.
///
/// **Primary path (no per-arm prompt):**
/// Connect to the privileged daemon (`VakterPrivilegedDaemon`, registered
/// via `SMAppService.daemon` from the menubar app) over XPC and call
/// `setSleepDisabled(_:)`. The daemon runs as root and executes pmset
/// silently. The user authorised the daemon ONCE in System Settings →
/// Login Items; no further prompts.
///
/// **Fallback path (when daemon isn't registered/approved yet):**
/// Use the in-process `AuthorizationServices` path via the C bridge.
/// Pops a Touch ID / password prompt for admin and runs pmset directly.
/// Used the very first time the user arms before approving the daemon,
/// or if the user later disables it in Login Items.
/// Protocol the state machine talks to so we can inject a test double
/// in unit tests. `SleepDisabler` is the production conformer.
protocol SleepDisabling {
    @discardableResult
    func engage() -> SleepDisablerResult
    func release()
}

final class SleepDisabler: SleepDisabling, @unchecked Sendable {

    private var isEngaged = false
    private let lock = NSLock()

    /// Attempt to disable system sleep. Returns a structured outcome
    /// so the StateMachine can decide whether arming should proceed.
    @discardableResult
    func engage() -> SleepDisablerResult {
        lock.lock(); defer { lock.unlock() }
        if isEngaged { return .engaged }

        // 1. Try the daemon first.
        if setSleepViaDaemon(disabled: true) {
            isEngaged = true
            NSLog("[Vakter.sleep] engaged via daemon — lid-close sleep blocked")
            return .engaged
        }

        // 2. Daemon path failed. Surface the most likely reason — the
        // daemon isn't approved yet — by attempting the local fallback
        // and inspecting the C bridge's structured return code.
        NSLog("[Vakter.sleep] daemon path unavailable — falling back to local Touch ID prompt")
        let rc = anchor_run_pmset_admin(1)
        switch rc {
        case 0:
            isEngaged = true
            NSLog("[Vakter.sleep] engaged via local auth — lid-close sleep blocked")
            return .engaged
        case -2:
            NSLog("[Vakter.sleep] user cancelled the password prompt — arm aborted")
            return .userCancelled
        default:
            // -1 / -3 / -4 — different concrete failures, but for the
            // state machine the actionable info is the same: the
            // daemon needs approving in Login Items.
            NSLog("[Vakter.sleep] local auth failed rc=%d — degraded fallback", rc)
            return .daemonNeedsApproval
        }
    }

    func release() {
        lock.lock(); defer { lock.unlock() }
        if !isEngaged { return }

        // For release we don't care about user cancel — if the daemon
        // isn't there, we just leave pmset alone (the IOPM assertions
        // are also released, so the system will sleep normally on its
        // own schedule again).
        if setSleepViaDaemon(disabled: false) {
            isEngaged = false
            NSLog("[Vakter.sleep] released — Mac may sleep normally")
            return
        }
        // No prompt on release — silently fall through.
        let rc = anchor_run_pmset_admin(0)
        if rc == 0 {
            isEngaged = false
            NSLog("[Vakter.sleep] released via local auth")
        } else {
            NSLog("[Vakter.sleep] release failed rc=%d — user may need 'sudo pmset -a disablesleep 0'", rc)
        }
    }

    // MARK: - Daemon XPC path

    /// Try to reach the privileged daemon and ask it to set
    /// disablesleep. Returns true on success.
    /// Returns false if the daemon isn't running / not yet approved /
    /// XPC handshake fails.
    private func setSleepViaDaemon(disabled: Bool) -> Bool {
        let conn = NSXPCConnection(
            machServiceName: VakterConstants.privilegedDaemonMachServiceName,
            options: .privileged
        )
        conn.remoteObjectInterface = NSXPCInterface(with: VakterPrivilegedProtocol.self)
        conn.resume()
        defer { conn.invalidate() }

        // The connection lazily resolves the Mach service. If launchd
        // can't find a registered service with that name, the proxy
        // call will fail with NSXPCConnectionInvalid.
        var didReply = false
        var success = false
        let sem = DispatchSemaphore(value: 0)

        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ err in
            NSLog("[Vakter.sleep] daemon XPC error: %@", err.localizedDescription)
            sem.signal()
        }) as? VakterPrivilegedProtocol else {
            return false
        }

        proxy.setSleepDisabled(disabled) { ok in
            didReply = true
            success = ok
            sem.signal()
        }
        // 3-second timeout — if the daemon isn't there we don't want to
        // block the state-machine indefinitely.
        let result = sem.wait(timeout: .now() + 3.0)
        if result == .timedOut {
            NSLog("[Vakter.sleep] daemon call timed out")
            return false
        }
        return didReply && success
    }

    deinit {
        if isEngaged {
            _ = anchor_run_pmset_admin(0)
        }
    }
}
