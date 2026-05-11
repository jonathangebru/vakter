import Foundation

/// An external signal observed by the helper daemon while in `.armed`.
///
/// These are the inputs to the state machine's `armed → grace` transition,
/// plus the natural-unlock disarm path.
/// Each concrete observer in the helper (LidObserver, PowerObserver,
/// BluetoothObserver, HotkeyObserver, ScreenLockObserver, optional
/// PowerButtonObserver) emits values of this type onto a shared signal
/// channel.
public enum AnchorSignal: Sendable, Equatable {
    case lidClosed
    case lidOpened
    case powerConnected
    case powerDisconnected
    case bluetoothTrustGained
    case bluetoothTrustLost
    case hotkeyArm
    case powerButtonBrief

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
        case .lidClosed, .powerDisconnected, .bluetoothTrustLost, .powerButtonBrief:
            return true
        case .lidOpened, .powerConnected, .bluetoothTrustGained, .hotkeyArm,
             .screenUnlocked, .systemWake:
            return false
        }
    }

    /// Should this signal disarm an armed/grace/alarm session?
    public var triggersDisarm: Bool {
        self == .screenUnlocked
    }

    /// Map signal to the trigger reason recorded in the event log.
    public var asTrigger: AnchorTrigger? {
        switch self {
        case .lidClosed:           return .lidClose
        case .powerDisconnected:   return .powerDisconnect
        case .bluetoothTrustLost:  return .bluetoothPeerLeft
        case .powerButtonBrief:    return .powerButtonBriefPress
        default: return nil
        }
    }
}
