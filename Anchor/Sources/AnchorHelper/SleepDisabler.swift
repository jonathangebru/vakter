import Foundation
import AnchorShared
import AnchorPrivilegedExec

/// Globally disables system sleep via `pmset -a disablesleep 1` while
/// armed, then restores normal sleep on disarm.
///
/// **Primary path (no per-arm prompt):**
/// Connect to the privileged daemon (`AnchorPrivilegedDaemon`, registered
/// via `SMAppService.daemon` from the menubar app) over XPC and call
/// `setSleepDisabled(_:)`. The daemon runs as root and executes pmset
/// silently. The user authorised the daemon ONCE in System Settings →
/// Login Items; no further prompts.
///
/// **Fallback path (when daemon isn't registered/approved yet):**
/// Use the in-process `AuthorizationServices` path via the C bridge.
/// Pops a Touch ID prompt for admin and runs pmset directly. Used the
/// very first time the user arms before approving the daemon, or if
/// the user later disables it in Login Items.
final class SleepDisabler: @unchecked Sendable {

    private var isEngaged = false
    private let lock = NSLock()

    @discardableResult
    func engage() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if isEngaged { return true }

        let ok = setSleep(disabled: true)
        if ok {
            isEngaged = true
            NSLog("[SleepDisabler] engaged — lid-close sleep blocked")
        } else {
            NSLog("[SleepDisabler] FAILED to disable sleep — IOPMAssertions are only fallback")
        }
        return ok
    }

    func release() {
        lock.lock(); defer { lock.unlock() }
        if !isEngaged { return }

        let ok = setSleep(disabled: false)
        if ok {
            isEngaged = false
            NSLog("[SleepDisabler] released — Mac may sleep normally")
        } else {
            NSLog("[SleepDisabler] release FAILED — user may need to run `sudo pmset -a disablesleep 0` manually")
        }
    }

    // MARK: - Implementation

    private func setSleep(disabled: Bool) -> Bool {
        // Primary path: privileged daemon via XPC.
        if setSleepViaDaemon(disabled: disabled) {
            return true
        }
        // Fallback: in-process Touch ID prompt + AuthorizationServices.
        NSLog("[SleepDisabler] daemon path unavailable — falling back to local Touch ID prompt")
        return setSleepViaLocalAuth(disabled: disabled)
    }

    /// Try to reach the privileged daemon and ask it to set
    /// disablesleep. Returns true on success.
    /// Returns false if the daemon isn't running / not yet approved /
    /// XPC handshake fails.
    private func setSleepViaDaemon(disabled: Bool) -> Bool {
        let conn = NSXPCConnection(
            machServiceName: AnchorConstants.privilegedDaemonMachServiceName,
            options: .privileged
        )
        conn.remoteObjectInterface = NSXPCInterface(with: AnchorPrivilegedProtocol.self)
        conn.resume()
        defer { conn.invalidate() }

        // The connection lazily resolves the Mach service. If launchd
        // can't find a registered service with that name, the proxy
        // call will fail with NSXPCConnectionInvalid.
        var didReply = false
        var success = false
        let sem = DispatchSemaphore(value: 0)

        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ err in
            NSLog("[SleepDisabler] daemon XPC error: %@", err.localizedDescription)
            sem.signal()
        }) as? AnchorPrivilegedProtocol else {
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
            NSLog("[SleepDisabler] daemon call timed out")
            return false
        }
        return didReply && success
    }

    /// Last-resort fallback: in-process Touch ID prompt + run pmset.
    /// Used when the privileged daemon hasn't been registered/approved
    /// yet (e.g. first launch before user has clicked through Login Items).
    private func setSleepViaLocalAuth(disabled: Bool) -> Bool {
        let rc = anchor_run_pmset_admin(disabled ? 1 : 0)
        return rc == 0
    }

    deinit {
        if isEngaged {
            _ = setSleep(disabled: false)
        }
    }
}
