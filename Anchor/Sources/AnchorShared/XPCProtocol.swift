import Foundation

// MARK: - Helper-exposed interface (app calls these)

/// The XPC protocol the helper daemon exposes to the menubar app.
///
/// All payloads are JSON-encoded for forward compatibility — we can evolve
/// the schema without breaking the @objc protocol shape.
@objc public protocol AnchorHelperProtocol {

    // MARK: One-shot queries

    /// Returns the helper's current snapshot (state + mode + last event).
    /// Reply data is a JSON-encoded `AnchorSnapshot`.
    func currentSnapshot(reply: @escaping (Data) -> Void)

    /// Runs the pre-flight security checklist on demand.
    /// Reply data is a JSON-encoded `PreflightResult` (defined later).
    func runPreflight(reply: @escaping (Data) -> Void)

    // MARK: Control

    /// Arm the system. The helper performs the action; reply indicates whether
    /// the arming succeeded (e.g. fails if already armed or mid-grace).
    func arm(reply: @escaping (Bool) -> Void)

    /// Request disarm. The helper performs the auth check (Touch ID/password)
    /// internally; if auth fails or no auth was supplied, returns false.
    func disarm(reply: @escaping (Bool) -> Void)

    /// Switch the active mode. `raw` is `AnchorMode.rawValue`.
    func setMode(_ raw: String, reply: @escaping (Bool) -> Void)

    /// Enter Loaner mode with the given trust window in seconds.
    func enterLoaner(seconds: Double, reply: @escaping (Bool) -> Void)
}

// MARK: - App-exposed interface (helper calls these back)

/// The XPC protocol the menubar app exposes to the helper, so the helper
/// can push state changes proactively instead of forcing the app to poll.
@objc public protocol AnchorAppProtocol {

    /// Helper invokes this whenever the state, mode, or loaner expiry changes.
    /// Payload is a JSON-encoded `AnchorSnapshot`.
    func snapshotChanged(_ data: Data)
}

// MARK: - Snapshot payload

/// State of the helper at a point in time. Sent across XPC as JSON.
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

// MARK: - Helpers for JSON-across-XPC

public enum AnchorXPC {

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Encode any Codable into the `Data` payload form the XPC methods use.
    public static func encode<T: Encodable>(_ value: T) -> Data {
        (try? encoder.encode(value)) ?? Data()
    }

    /// Decode a payload from XPC into a typed value, or nil on failure.
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        guard !data.isEmpty else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
