import Foundation

/// The XPC protocol the helper daemon exposes to the menubar app.
///
/// All methods are async. The helper is the source of truth for state;
/// the app is a thin observer + control surface.
@objc public protocol AnchorHelperProtocol {

    // MARK: Observation

    /// Returns the helper's current state, mode, and last event.
    func currentSnapshot(reply: @escaping (Data) -> Void)

    /// Subscribe to state changes. The helper invokes `reply` every time
    /// the state changes, including immediately on subscription.
    /// Cancellation = the connection going away.
    func subscribe(reply: @escaping (Data) -> Void)

    // MARK: Control

    /// Arm the system. Same effect as the hotkey or menubar click.
    func arm(reply: @escaping (Bool) -> Void)

    /// Request disarm. Will fail if the user has not authenticated.
    /// The helper performs the auth check internally.
    func disarm(reply: @escaping (Bool) -> Void)

    /// Switch the active mode.
    func setMode(_ raw: String, reply: @escaping (Bool) -> Void)

    /// Enter Loaner mode with the given trust window (seconds).
    func enterLoaner(seconds: Double, reply: @escaping (Bool) -> Void)

    /// Run the pre-flight security checklist and return a JSON-encoded result.
    func runPreflight(reply: @escaping (Data) -> Void)
}

/// Snapshot payload (JSON-encoded across XPC).
public struct AnchorSnapshot: Codable, Sendable, Equatable {
    public let state: AnchorState
    public let mode: AnchorMode
    public let lastEvent: AnchorEvent?
    /// If we're in Loaner, when does the trust window expire? Nil otherwise.
    public let loanerExpiresAt: Date?

    public init(
        state: AnchorState,
        mode: AnchorMode,
        lastEvent: AnchorEvent?,
        loanerExpiresAt: Date?
    ) {
        self.state = state
        self.mode = mode
        self.lastEvent = lastEvent
        self.loanerExpiresAt = loanerExpiresAt
    }
}
