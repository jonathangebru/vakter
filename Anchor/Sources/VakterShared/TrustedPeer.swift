import Foundation

/// One Bluetooth peer the user has paired as "trusted." Anchor uses the
/// presence of any trusted peer to dampen false alarms; ALL of them
/// being out of range for ≥3 seconds is the bluetooth-trust-lost signal.
public struct TrustedPeer: Codable, Sendable, Identifiable, Equatable, Hashable {

    /// The peripheral's `CBPeripheral.identifier` (UUID). This is stable
    /// across sessions for devices that have been paired with the Mac at
    /// the system level (e.g. via System Settings → Bluetooth). For
    /// unpaired devices, macOS sometimes rotates this for privacy —
    /// document to users that they should pair the device with the Mac
    /// before adding it to Anchor.
    public let id: UUID

    /// Human-readable name (e.g. "Jonathan's iPhone"). May be missing
    /// for some advertising devices; we fall back to "Unknown device".
    public let displayName: String

    /// When the user added it. Sorted-by-recency in the UI.
    public let dateAdded: Date

    public init(id: UUID, displayName: String, dateAdded: Date = Date()) {
        self.id = id
        self.displayName = displayName
        self.dateAdded = dateAdded
    }
}

/// JSON-backed store for the user's trusted-peers list. Same pattern as
/// HotkeyStore and GraceSettingsStore — file at
/// ~/Library/Application Support/Anchor/trusted-peers.json.
public enum TrustedPeerStore {

    private static var url: URL {
        VakterConstants.supportDirectoryURL.appendingPathComponent("trusted-peers.json")
    }

    public static func load() -> [TrustedPeer] {
        guard let data = try? Data(contentsOf: url),
              let peers = try? JSONDecoder().decode([TrustedPeer].self, from: data) else {
            return []
        }
        return peers
    }

    public static func save(_ peers: [TrustedPeer]) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(peers)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("[TrustedPeerStore] save failed: %@", error.localizedDescription)
        }
    }

    public static func add(_ peer: TrustedPeer) {
        var peers = load()
        peers.removeAll { $0.id == peer.id }   // dedupe
        peers.append(peer)
        save(peers)
    }

    public static func remove(id: UUID) {
        let peers = load().filter { $0.id != id }
        save(peers)
    }

    /// Maximum peers we allow. Designed for v1 to be more than enough
    /// (phone + AirPods + Watch + Tile + spouse's phone is 5).
    public static let maxCount = 10
}

/// Result of a Bluetooth scan — what the user sees when they tap
/// "Add a device" in Settings. Shipped over XPC.
public struct BluetoothDiscovery: Codable, Sendable, Identifiable, Equatable, Hashable {
    public let id: UUID            // CBPeripheral.identifier
    public let displayName: String
    public let rssi: Int           // signal strength; closer to 0 = stronger

    public init(id: UUID, displayName: String, rssi: Int) {
        self.id = id
        self.displayName = displayName
        self.rssi = rssi
    }
}
