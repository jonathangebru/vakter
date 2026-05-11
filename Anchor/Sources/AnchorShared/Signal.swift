import Foundation

/// An external signal observed by the helper daemon while in `.armed`.
///
/// These are the inputs to the state machine's `armed → grace` transition.
/// Each concrete observer in the helper (LidObserver, PowerObserver,
/// BluetoothObserver, HotkeyObserver, optional PowerButtonObserver) emits
/// values of this type onto a shared signal channel.
public enum AnchorSignal: Sendable, Equatable {
    case lidClosed
    case lidOpened
    case powerConnected
    case powerDisconnected
    case bluetoothTrustGained
    case bluetoothTrustLost
    case hotkeyArm
    case powerButtonBrief

    /// Should this signal transition us from `.armed` to `.grace`?
    public var triggersGrace: Bool {
        switch self {
        case .lidClosed, .powerDisconnected, .bluetoothTrustLost, .powerButtonBrief:
            return true
        case .lidOpened, .powerConnected, .bluetoothTrustGained, .hotkeyArm:
            return false
        }
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
