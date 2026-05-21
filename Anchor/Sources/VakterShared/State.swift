import Foundation

/// The four states of the Anchor alarm system, mirroring the state machine
/// documented in `openspec/changes/bootstrap-anchor/design.md`.
///
/// State transitions are managed by `StateMachine` in the helper daemon.
/// The menubar app receives state updates via XPC and renders accordingly.
public enum VakterState: String, Codable, Sendable, Equatable {
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
public enum VakterTrigger: String, Codable, Sendable, Equatable {
    case lidClose
    case powerDisconnect
    case bluetoothPeerLeft
    case powerButtonBriefPress

    /// Vakter's `FindMyTokenWatcher` saw the iCloud token disappear
    /// while armed. Strong evidence the thief is wiping Find My.
    case findMyCleared

    /// Vakter's `AppleIDChangeWatcher` saw the signed-in Apple ID
    /// change while armed.
    case appleIDChanged

    /// Used when a state change was initiated by the user (e.g. manual arm).
    /// Not strictly a "trigger" — kept here for log uniformity.
    case userAction
}

/// One row in the persistent event log. Written by the helper, displayed
/// by the menubar app's Event Log pane.
///
/// v1.3 additions (all optional for back-compat with v1.2 events on disk):
///   - `audioFilenames` — ambient audio clips captured during the alarm
///   - `previousEventHash` / `eventHash` — Merkle chain links so the log
///      is tamper-evident. See `EventChain` in this module.
///   - `locationLat` / `locationLon` — best-known coordinate at event time
public struct VakterEvent: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let fromState: VakterState
    public let toState: VakterState
    public let trigger: VakterTrigger?
    public let photoFilenames: [String]
    public let modeAtEvent: VakterMode

    // v1.3 evidence-grade fields. All optional so JSON written by v1.2 still
    // decodes cleanly.
    public let audioFilenames: [String]?
    public let previousEventHash: String?
    public let eventHash: String?
    public let locationLat: Double?
    public let locationLon: Double?

    public init(
        id: UUID = UUID(),
        timestamp: Date = .init(),
        fromState: VakterState,
        toState: VakterState,
        trigger: VakterTrigger?,
        photoFilenames: [String] = [],
        modeAtEvent: VakterMode,
        audioFilenames: [String]? = nil,
        previousEventHash: String? = nil,
        eventHash: String? = nil,
        locationLat: Double? = nil,
        locationLon: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.fromState = fromState
        self.toState = toState
        self.trigger = trigger
        self.photoFilenames = photoFilenames
        self.modeAtEvent = modeAtEvent
        self.audioFilenames = audioFilenames
        self.previousEventHash = previousEventHash
        self.eventHash = eventHash
        self.locationLat = locationLat
        self.locationLon = locationLon
    }
}
