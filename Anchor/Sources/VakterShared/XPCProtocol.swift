import Foundation

// MARK: - Helper-exposed interface (app calls these)

/// The XPC protocol the helper daemon exposes to the menubar app.
///
/// All payloads are JSON-encoded for forward compatibility — we can evolve
/// the schema without breaking the @objc protocol shape.
@objc public protocol VakterHelperProtocol {

    // MARK: One-shot queries

    /// Returns the helper's current snapshot (state + mode + last event).
    /// Reply data is a JSON-encoded `VakterSnapshot`.
    func currentSnapshot(reply: @escaping (Data) -> Void)

    /// Runs the full Pareto-style defenses checklist on demand and replies
    /// with a JSON-encoded `DefenseChecklist`. Slow (~2–6 s wall-clock —
    /// many of the 20 probes shell out to `defaults`, `socketfilterfw`,
    /// `launchctl`, `softwareupdate -l`, `bputil -d`, etc.), so the helper
    /// runs the probe off-thread before invoking `reply`. The method name
    /// is the legacy "preflight" identifier from when the audit was scoped
    /// to a small pre-arm sanity check; it's retained to keep the @objc
    /// XPC protocol shape stable across versions.
    func runPreflight(reply: @escaping (Data) -> Void)

    // MARK: Control

    /// Arm the system. The helper performs the action; reply indicates whether
    /// the arming succeeded (e.g. fails if already armed or mid-grace).
    func arm(reply: @escaping (Bool) -> Void)

    /// Request disarm. The helper performs the auth check (Touch ID/password)
    /// internally; if auth fails or no auth was supplied, returns false.
    func disarm(reply: @escaping (Bool) -> Void)

    /// Switch the active mode. `raw` is `VakterMode.rawValue`.
    func setMode(_ raw: String, reply: @escaping (Bool) -> Void)

    /// Enter Loaner mode with the given trust window in seconds.
    func enterLoaner(seconds: Double, reply: @escaping (Bool) -> Void)

    /// Tell the helper that the user changed the hotkey binding in Settings.
    /// The helper re-reads `HotkeyStore` and re-registers via Carbon.
    func reloadHotkey(reply: @escaping (Bool) -> Void)

    // MARK: Diagnostics

    /// Run the full alarm subsystem (siren + voice + audio override) for
    /// `seconds` seconds, then auto-stop and restore prior audio state.
    /// Does not change the state machine — purely an audio test.
    func testAlarm(seconds: Double, reply: @escaping (Bool) -> Void)

    /// Inject a fake `.lidClosed` signal into the state machine — used to
    /// verify the grace → alarm path without physically closing the lid
    /// (which on some Macs triggers system sleep before grace expires).
    func simulateLidClose(reply: @escaping (Bool) -> Void)

    /// One-click "watch the full arm flow from the menubar" demo: arms
    /// WITHOUT locking the screen, then triggers a fake lid close so the
    /// grace+alarm sequence runs end-to-end. Returns false if not in the
    /// `.unarmed` state.
    func runArmDemo(reply: @escaping (Bool) -> Void)

    // MARK: Trusted Bluetooth peers (Settings pairing UI)

    /// Returns the current trusted-peer list as JSON-encoded
    /// `[TrustedPeer]`.
    func listTrustedPeers(reply: @escaping (Data) -> Void)

    /// Begin recording nearby Bluetooth discoveries. The reply fires
    /// with a JSON-encoded `[BluetoothDiscovery]` (initial snapshot
    /// after a brief delay). The Settings UI then polls
    /// `currentDiscoveries` for live updates.
    func startBluetoothDiscovery(reply: @escaping (Data) -> Void)

    /// Latest snapshot of nearby Bluetooth discoveries (for polling).
    func currentBluetoothDiscoveries(reply: @escaping (Data) -> Void)

    /// Stop the discovery recording (background trust scan continues).
    func stopBluetoothDiscovery(reply: @escaping (Bool) -> Void)

    /// Add a trusted peer. `data` is a JSON-encoded `TrustedPeer`.
    func addTrustedPeer(_ data: Data, reply: @escaping (Bool) -> Void)

    /// Remove a trusted peer by UUID.
    func removeTrustedPeer(_ idString: String, reply: @escaping (Bool) -> Void)
}

// MARK: - App-exposed interface (helper calls these back)

/// The XPC protocol the menubar app exposes to the helper, so the helper
/// can push state changes proactively instead of forcing the app to poll.
@objc public protocol VakterAppProtocol {

    /// Helper invokes this whenever the state, mode, or loaner expiry changes.
    /// Payload is a JSON-encoded `VakterSnapshot`.
    func snapshotChanged(_ data: Data)
}

// MARK: - Snapshot payload

/// State of the helper at a point in time. Sent across XPC as JSON.
public struct VakterSnapshot: Codable, Sendable, Equatable {
    public let state: VakterState
    public let mode: VakterMode
    public let lastEvent: VakterEvent?
    /// If we're in Loaner, when does the trust window expire? Nil otherwise.
    public let loanerExpiresAt: Date?

    public init(
        state: VakterState,
        mode: VakterMode,
        lastEvent: VakterEvent?,
        loanerExpiresAt: Date?
    ) {
        self.state = state
        self.mode = mode
        self.lastEvent = lastEvent
        self.loanerExpiresAt = loanerExpiresAt
    }
}

// MARK: - Helpers for JSON-across-XPC

public enum VakterXPC {

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
