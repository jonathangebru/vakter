import Foundation

/// An external signal observed by the helper daemon while in `.armed`.
///
/// These are the inputs to the state machine's `armed → grace` transition,
/// plus the natural-unlock disarm path.
/// Each concrete observer in the helper (LidObserver, PowerObserver,
/// BluetoothObserver, HotkeyObserver, ScreenLockObserver, optional
/// PowerButtonObserver) emits values of this type onto a shared signal
/// channel.
public enum VakterSignal: Sendable, Equatable {
    case lidClosed
    case lidOpened
    case powerConnected
    case powerDisconnected
    case bluetoothTrustGained
    case bluetoothTrustLost
    case hotkeyArm
    case powerButtonBrief

    /// `FindMyTokenWatcher` saw the NVRAM `fmm-mobileme-token-FMM` go
    /// from a valid value to empty while armed. High-confidence theft
    /// signal — someone is wiping iCloud from this Mac. Skips grace
    /// and goes straight to alarm.
    case findMyTokenCleared

    /// `AppleIDChangeWatcher` saw the signed-in Apple ID change (hash
    /// of `MobileMeAccounts.Accounts[0].AccountID` flipped) while
    /// armed. High-confidence theft signal — thief re-signed-in with
    /// their own Apple ID. Skips grace, goes straight to alarm.
    case appleIDChanged

    /// The user authenticated their way into the system (Touch ID / password
    /// unlock at the lock screen). macOS has just verified them, so we
    /// trust this as our disarm signal too — no second prompt needed.
    case screenUnlocked

    /// The system has resumed from sleep. Fired by `WakeObserver` whenever
    /// the kernel sends `kIOMessageSystemHasPoweredOn`. If we were in
    /// `.armed` or `.grace` when sleep happened, the grace timer is stale
    /// — the only sane response is to fire the alarm immediately. This is
    /// the belt-and-braces fallback against SleepGuard assertions that
    /// the firmware ignored (Apple Silicon clamshell-close on battery).
    case systemWake

    /// Should this signal transition us from `.armed` to `.grace`?
    public var triggersGrace: Bool {
        switch self {
        case .lidClosed, .powerDisconnected, .powerButtonBrief:
            return true
        case .lidOpened, .powerConnected,
             .bluetoothTrustGained, .bluetoothTrustLost,
             .hotkeyArm,
             .screenUnlocked, .systemWake,
             .findMyTokenCleared, .appleIDChanged:
            // Note: findMyTokenCleared + appleIDChanged DELIBERATELY return
            // false here — the state machine routes them directly to `.alarm`
            // (skipping grace) because they're high-confidence theft signals.
            //
            // bluetoothTrustLost ALSO deliberately returns false: pairing a
            // phone or AirPods as a "trusted peer" and then having the user
            // walk 15 m to a coffee counter would otherwise trigger grace →
            // alarm. The café false-positive isn't worth the narrow detection
            // win. BT trust is kept around as an informational signal — it
            // still flows through `handle(signal:)` and falls through to the
            // default no-op case. Lid-close and cable-disconnect remain the
            // physical-evidence triggers.
            return false
        }
    }

    /// Should this signal disarm an armed/grace/alarm session?
    public var triggersDisarm: Bool {
        self == .screenUnlocked
    }

    /// Map signal to the trigger reason recorded in the event log.
    public var asTrigger: VakterTrigger? {
        switch self {
        case .lidClosed:           return .lidClose
        case .powerDisconnected:   return .powerDisconnect
        case .bluetoothTrustLost:  return .bluetoothPeerLeft
        case .powerButtonBrief:    return .powerButtonBriefPress
        case .findMyTokenCleared:  return .findMyCleared
        case .appleIDChanged:      return .appleIDChanged
        default: return nil
        }
    }
}
