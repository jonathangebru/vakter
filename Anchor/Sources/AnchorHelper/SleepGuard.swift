import Foundation
import IOKit
import IOKit.pwr_mgt

/// Holds `IOPMAssertion`s that prevent the Mac from sleeping while Anchor
/// is in any armed state.
///
/// Why this is critical:
/// When a thief closes the lid on a MacBook with no external display,
/// macOS initiates system sleep. The helper process is suspended, the
/// grace-period timer stops, and the alarm never fires — the silent
/// theft path. We close that hole here.
///
/// What we hold:
///   - `kIOPMAssertionTypePreventSystemSleep` — the strongest assertion;
///     prevents lid-close from putting the Mac to sleep. On Apple Silicon
///     this is honoured for our use case (background daemon with a clear
///     reason string).
///   - `kIOPMAssertionTypePreventUserIdleSystemSleep` — belt-and-braces;
///     also prevents idle-timer sleep, in case the user has very short
///     idle sleep configured.
///
/// Lifecycle:
///   - `engage()` called when the state machine enters `armed`
///   - `release()` called when the state machine returns to `unarmed`
///   - Idempotent — calling engage() twice is a no-op; calling release()
///     when not engaged is a no-op.
final class SleepGuard {

    private var idAssertionPreventSystem: IOPMAssertionID = 0
    private var idAssertionPreventUserIdle: IOPMAssertionID = 0
    private var isEngaged = false

    /// Acquire both assertions so the Mac cannot sleep until we let it.
    /// Returns true if both were acquired successfully.
    @discardableResult
    func engage() -> Bool {
        guard !isEngaged else { return true }

        let preventSleepReason = "Anchor is armed — preventing sleep so a theft can be detected" as CFString
        let preventIdleReason  = "Anchor is armed — preventing idle sleep" as CFString

        var rc1: IOReturn = kIOReturnSuccess
        var rc2: IOReturn = kIOReturnSuccess

        rc1 = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            preventIdleReason,
            &idAssertionPreventUserIdle
        )

        rc2 = IOPMAssertionCreateWithName(
            "PreventSystemSleep" as CFString, // a.k.a. kIOPMAssertPreventSystemSleep (NOT in Swift overlay; raw string OK)
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            preventSleepReason,
            &idAssertionPreventSystem
        )

        let ok = (rc1 == kIOReturnSuccess) && (rc2 == kIOReturnSuccess)
        if ok {
            isEngaged = true
            NSLog("[SleepGuard] engaged — userIdle=%d preventSystem=%d",
                  Int(idAssertionPreventUserIdle), Int(idAssertionPreventSystem))
        } else {
            NSLog("[SleepGuard] FAILED engage — userIdle rc=0x%X preventSystem rc=0x%X",
                  UInt32(rc1), UInt32(rc2))
            // Best-effort cleanup if only one succeeded
            if rc1 == kIOReturnSuccess { _ = IOPMAssertionRelease(idAssertionPreventUserIdle) }
            if rc2 == kIOReturnSuccess { _ = IOPMAssertionRelease(idAssertionPreventSystem) }
            idAssertionPreventUserIdle = 0
            idAssertionPreventSystem = 0
        }
        return ok
    }

    /// Release both assertions and let the Mac sleep normally again.
    func release() {
        guard isEngaged else { return }
        if idAssertionPreventUserIdle != 0 {
            _ = IOPMAssertionRelease(idAssertionPreventUserIdle)
            idAssertionPreventUserIdle = 0
        }
        if idAssertionPreventSystem != 0 {
            _ = IOPMAssertionRelease(idAssertionPreventSystem)
            idAssertionPreventSystem = 0
        }
        isEngaged = false
        NSLog("[SleepGuard] released — Mac may sleep normally")
    }

    deinit {
        release()
    }
}
