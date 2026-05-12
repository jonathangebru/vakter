import Foundation
import Security
import AnchorPrivilegedExec

/// Globally disables system sleep via `pmset -a disablesleep 1` while armed,
/// then restores normal sleep on disarm.
///
/// Why this exists, beyond `SleepGuard`'s IOPM assertions:
/// On Apple Silicon, `kIOPMAssertPreventSystemSleep` + friends are advisory.
/// The firmware-managed lid-close sleep path on a MacBook without an
/// external display **overrides them every time on battery**. The
/// technique used by every working Mac anti-theft tool that handles
/// closed-lid alarms (MacGuard, Fermata's "lid sensor deactivation") is
/// to run `pmset disablesleep` as root.
///
/// **Touch ID note:** we acquire the admin right via `AuthorizationServices`
/// rather than `osascript do shell script ... with administrator privileges`
/// because the AppleScript path is hard-wired to the legacy password-only
/// auth dialog. `AuthorizationCopyRights` requesting `system.privilege.admin`
/// pops the modern system auth dialog which honours Touch ID on supported
/// Macs.
///
/// `AuthorizationExecuteWithPrivileges` is technically deprecated since
/// 10.7 but still functional through current macOS. The long-term path
/// is to install a privileged helper via `SMAppService.daemon` so the
/// auth is asked once-ever rather than per-arm; that's a separate
/// architectural change for v1.5+.
final class SleepDisabler: @unchecked Sendable {

    private var isEngaged = false
    private let lock = NSLock()

    /// Disable system sleep globally. Pops a Touch ID / password dialog.
    /// Returns true if pmset succeeded.
    @discardableResult
    func engage() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if isEngaged { return true }

        NSLog("[SleepDisabler] requesting admin (Touch ID) to disable system sleep…")
        let ok = runPMSet(disable: true)
        if ok {
            isEngaged = true
            NSLog("[SleepDisabler] engaged — pmset disablesleep 1, lid-close sleep blocked")
        } else {
            NSLog("[SleepDisabler] FAILED — falling back to IOPMAssertions only")
        }
        return ok
    }

    /// Restore normal sleep behaviour.
    func release() {
        lock.lock(); defer { lock.unlock() }
        if !isEngaged { return }

        NSLog("[SleepDisabler] releasing — restoring normal sleep…")
        let ok = runPMSet(disable: false)
        if ok {
            isEngaged = false
            NSLog("[SleepDisabler] released — pmset disablesleep 0")
        } else {
            NSLog("[SleepDisabler] release FAILED — user may need to run `sudo pmset -a disablesleep 0` manually")
        }
    }

    /// Acquire admin via `AuthorizationCopyRights` (Touch ID-capable) and
    /// run `pmset -a disablesleep <1|0>` as root.
    ///
    /// Bridged through `AnchorPrivilegedExec` because the Swift overlay
    /// blocks `AuthorizationExecuteWithPrivileges`.
    private func runPMSet(disable: Bool) -> Bool {
        let rc = anchor_run_pmset_admin(disable ? 1 : 0)
        switch rc {
        case 0:
            return true
        case -1:
            NSLog("[SleepDisabler] AuthorizationCreate failed")
            return false
        case -2:
            NSLog("[SleepDisabler] auth dialog dismissed or denied")
            return false
        case -3:
            NSLog("[SleepDisabler] pmset execution failed under privileged exec")
            return false
        default:
            NSLog("[SleepDisabler] unknown error from anchor_run_pmset_admin: %d", rc)
            return false
        }
    }

    deinit {
        // Defensive: if the helper is being torn down while engaged, try to
        // restore normal sleep. Best effort only.
        if isEngaged {
            _ = runPMSet(disable: false)
        }
    }
}
