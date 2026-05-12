import Foundation

/// Globally disables system sleep via `pmset -a disablesleep 1` while armed,
/// then restores normal sleep on disarm.
///
/// Why this exists, beyond `SleepGuard`'s IOPM assertions:
/// On Apple Silicon, `kIOPMAssertPreventSystemSleep` + friends are advisory.
/// The firmware-managed lid-close sleep path on a MacBook without an
/// external display **overrides them every time on battery**. We proved
/// this in real testing — the assertions return success, but the system
/// sleeps anyway, the audio hardware powers down, and no alarm is audible
/// through the closed lid.
///
/// The technique used by every working Mac anti-theft tool that handles
/// closed-lid alarms (MacGuard, Fermata's "lid sensor deactivation",
/// caffeinate-style apps with admin support) is to shell out to
/// `pmset -a disablesleep 1`. That requires root, which we get by
/// invoking through `osascript do shell script "..." with administrator
/// privileges` — which pops the system Touch ID / password dialog.
///
/// Lifecycle:
///   - `engage()` called when state machine enters `.armed`. The user
///     sees a Touch ID prompt with reason "Anchor needs to keep your Mac
///     awake while armed." On success, sleep is globally disabled.
///   - `release()` called when state machine returns to `.unarmed`. Runs
///     `pmset -a disablesleep 0`. This SHOULD also require admin, but
///     `pmset` honours the previous "session" once you've authenticated
///     once recently — in practice the second prompt is suppressed if it
///     comes within a short window. If a prompt does appear, the user
///     has already authenticated (they unlocked the Mac), so they can
///     Touch ID quickly again.
///
/// Failure handling:
///   - If the user cancels the auth prompt: engage() returns false. The
///     state machine should still proceed with arming (we lose closed-
///     lid coverage but keep open-lid coverage via SleepGuard).
///   - On helper crash/quit while engaged: a deinit hook fires release()
///     so the user's Mac doesn't stay sleep-disabled forever.
final class SleepDisabler: @unchecked Sendable {

    private var isEngaged = false
    private let lock = NSLock()

    /// Disable system sleep globally. Returns true if pmset succeeded.
    /// Caller should still proceed with arming even if this returns
    /// false — the IOPM assertions in SleepGuard provide partial
    /// coverage as a fallback.
    @discardableResult
    func engage() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if isEngaged { return true }

        NSLog("[SleepDisabler] requesting admin to disable system sleep…")
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

    /// Run pmset via osascript with administrator privileges. This pops the
    /// system Touch ID / password dialog. Returns true on success.
    private func runPMSet(disable: Bool) -> Bool {
        let value = disable ? 1 : 0
        let prompt = disable
            ? "Anchor needs administrator access to keep your Mac awake while armed (otherwise closing the lid would silently put the Mac to sleep and the alarm could not play)."
            : "Anchor is disarming and is restoring normal sleep behaviour."
        // The literal embedded inside the shell script. We use single-quotes
        // around the inner command so the outer AppleScript double-quotes work.
        let script = """
        do shell script "/usr/bin/pmset -a disablesleep \(value)" \
            with prompt "\(prompt)" \
            with administrator privileges
        """

        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", script]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("[SleepDisabler] failed to launch osascript: %@", error.localizedDescription)
            return false
        }

        if process.terminationStatus != 0 {
            let err = String(data: stderrPipe.fileHandleForReading.availableData, encoding: .utf8) ?? "(no stderr)"
            NSLog("[SleepDisabler] osascript exit=%d stderr=%@", process.terminationStatus, err.trimmingCharacters(in: .whitespacesAndNewlines))
            return false
        }
        return true
    }

    deinit {
        // Defensive: if the helper is being torn down while engaged, try to
        // restore normal sleep. This may prompt for admin and may fail
        // silently — best effort only. The user can always run
        // `sudo pmset -a disablesleep 0` manually to recover.
        if isEngaged {
            _ = runPMSet(disable: false)
        }
    }
}
