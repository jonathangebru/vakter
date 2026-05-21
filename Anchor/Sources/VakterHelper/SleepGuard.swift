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
///   - `kIOPMAssertPreventUserIdleSystemSleep` — prevents the idle-timer
///     sleep path. Honoured on battery and AC. Cheap.
///   - `kIOPMAssertPreventSystemSleep` — the textually-strongest assertion.
///     On Apple Silicon this is *gated to AC power* on many models, which
///     is why our first attempt at SleepGuard failed for lid-close-on-
///     battery. Worth holding because when it does work, it's broader.
///   - `kIOPMAssertPreventUserIdleDisplaySleep` — this is the assertion
///     `caffeinate -d` uses and it IS honoured on battery. It prevents
///     lid-close sleep because closing the lid normally drives display
///     sleep → system sleep, and this assertion blocks the first step.
///     This is what actually makes the lid-close trigger work in real
///     life on a MacBook on battery.
///
/// Lifecycle:
///   - `engage()` called when the state machine enters `armed`
///   - `release()` called when the state machine returns to `unarmed`
///   - Idempotent — calling engage() twice is a no-op; calling release()
///     when not engaged is a no-op.
/// Protocol the state machine talks to so we can inject a test double
/// in unit tests. `SleepGuard` is the production conformer.
protocol SleepGuarding {
    @discardableResult
    func engage() -> Bool
    func release()
}

final class SleepGuard: SleepGuarding {

    private var idAssertionPreventSystem: IOPMAssertionID = 0
    private var idAssertionPreventUserIdle: IOPMAssertionID = 0
    private var idAssertionPreventDisplay: IOPMAssertionID = 0
    private var isEngaged = false

    /// Acquire all three assertions so the Mac cannot sleep until we
    /// let it. Returns true if at least the display-sleep assertion
    /// was acquired (that's the one that actually prevents lid-close
    /// sleep on Apple Silicon).
    @discardableResult
    func engage() -> Bool {
        guard !isEngaged else { return true }

        let displayReason = "Anchor is armed — keeping the Mac awake so a theft trigger can fire" as CFString
        let systemReason  = "Anchor is armed — preventing system sleep" as CFString
        let idleReason    = "Anchor is armed — preventing idle sleep" as CFString

        var rcDisplay: IOReturn = kIOReturnError
        var rcSystem:  IOReturn = kIOReturnError
        var rcIdle:    IOReturn = kIOReturnError

        // 1. The critical one for lid-close-on-battery.
        rcDisplay = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            displayReason,
            &idAssertionPreventDisplay
        )

        // 2. Belt-and-braces — only honoured on AC on some Macs, harmless elsewhere.
        rcSystem = IOPMAssertionCreateWithName(
            "PreventSystemSleep" as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            systemReason,
            &idAssertionPreventSystem
        )

        // 3. Belt-and-braces — prevents the idle-timer code path.
        rcIdle = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            idleReason,
            &idAssertionPreventUserIdle
        )

        let displayOK = (rcDisplay == kIOReturnSuccess)
        if displayOK {
            isEngaged = true
            NSLog("[SleepGuard] engaged — display=%d preventSystem=%d userIdle=%d (display ok=%@ system ok=%@ idle ok=%@)",
                  Int(idAssertionPreventDisplay),
                  Int(idAssertionPreventSystem),
                  Int(idAssertionPreventUserIdle),
                  displayOK ? "yes" : "no",
                  rcSystem == kIOReturnSuccess ? "yes" : "no",
                  rcIdle == kIOReturnSuccess ? "yes" : "no")
        } else {
            NSLog("[SleepGuard] FAILED engage — display rc=0x%X system rc=0x%X idle rc=0x%X",
                  UInt32(rcDisplay), UInt32(rcSystem), UInt32(rcIdle))
            release()
        }
        return displayOK
    }

    /// Release all assertions and let the Mac sleep normally again.
    func release() {
        if idAssertionPreventDisplay != 0 {
            _ = IOPMAssertionRelease(idAssertionPreventDisplay)
            idAssertionPreventDisplay = 0
        }
        if idAssertionPreventSystem != 0 {
            _ = IOPMAssertionRelease(idAssertionPreventSystem)
            idAssertionPreventSystem = 0
        }
        if idAssertionPreventUserIdle != 0 {
            _ = IOPMAssertionRelease(idAssertionPreventUserIdle)
            idAssertionPreventUserIdle = 0
        }
        if isEngaged {
            isEngaged = false
            NSLog("[SleepGuard] released — Mac may sleep normally")
        }
    }

    deinit {
        release()
    }
}
