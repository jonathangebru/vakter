import Foundation

/// The four states of the Anchor alarm system, mirroring the state machine
/// documented in `openspec/changes/bootstrap-anchor/design.md`.
///
/// State transitions are managed by `StateMachine` in the helper daemon.
/// The menubar app receives state updates via XPC and renders accordingly.
public enum AnchorState: String, Codable, Sendable, Equatable {
    /// Default resting state. The Mac is in normal use; Anchor is inert.
    case unarmed

    /// The user has explicitly armed Anchor (via the global hotkey, menubar
    /// click, or a Shortcuts intent). Anchor is now watching for trigger
    /// signals: lid close, power disconnect, trusted Bluetooth peer leaving,
    /// or (if available) a brief power-button press.
    case armed

    /// A trigger signal fired. Anchor is in the grace window during which an
    /// authenticated user can disarm without the alarm firing.
    case grace

    /// The grace window expired without authentication. The full alarm —
    /// siren, voice cue, and photo burst — is firing until the user unlocks
    /// the Mac.
    case alarm
}

/// Reasons we transitioned into `.grace` or `.alarm`. Recorded in the event
/// log so the user can see *why* an alarm fired.
public enum AnchorTrigger: String, Codable, Sendable, Equatable {
    case lidClose
    case powerDisconnect
    case bluetoothPeerLeft
    case powerButtonBriefPress

    /// Used when a state change was initiated by the user (e.g. manual arm).
    /// Not strictly a "trigger" — kept here for log uniformity.
    case userAction
}

/// One row in the persistent event log. Written by the helper, displayed
/// by the menubar app's Event Log pane.
public struct AnchorEvent: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let fromState: AnchorState
    public let toState: AnchorState
    public let trigger: AnchorTrigger?
    public let photoFilenames: [String]
    public let modeAtEvent: AnchorMode

    public init(
        id: UUID = UUID(),
        timestamp: Date = .init(),
        fromState: AnchorState,
        toState: AnchorState,
        trigger: AnchorTrigger?,
        photoFilenames: [String] = [],
        modeAtEvent: AnchorMode
    ) {
        self.id = id
        self.timestamp = timestamp
        self.fromState = fromState
        self.toState = toState
        self.trigger = trigger
        self.photoFilenames = photoFilenames
        self.modeAtEvent = modeAtEvent
    }
}
