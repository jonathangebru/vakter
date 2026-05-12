import Foundation
@preconcurrency import CoreBluetooth
import AnchorShared

/// Watches for the user's trusted Bluetooth peers via CoreBluetooth.
///
/// Behaviour:
///   - Maintains a continuous scan for nearby BLE advertisements.
///   - For each advertisement matching a trusted-peer UUID, updates
///     `lastSeen[peerID]` to now.
///   - Every 1 second, evaluates trust:
///       * If at least one trusted peer was seen in the last 3 s →
///         trust HELD (no signal emitted; status stays "any peer in range")
///       * If ALL trusted peers have been stale for ≥3 consecutive seconds →
///         emits `.bluetoothTrustLost` once
///       * If a peer comes back after being lost → emits
///         `.bluetoothTrustGained` once
///   - If there are zero trusted peers, the observer is dormant — it
///     doesn't emit signals, since there's nothing to lose.
///
/// **Exposes a scan-for-discovery mode** used by the Settings UI to let
/// the user pick a peer to add. While this mode is active, every
/// discovery is recorded in `latestDiscoveries`; `currentDiscoveries`
/// returns the snapshot for the XPC reply.
///
/// Discovery vs. trust scanning are the same underlying scan — we just
/// keep both pipelines and switch between which one is recording.
final class BluetoothObserver: NSObject, AnchorSignalObserver, CBCentralManagerDelegate, @unchecked Sendable {

    private var central: CBCentralManager!
    private var emit: ((AnchorSignal) -> Void)?

    /// All UUIDs of trusted peers — refreshed when XPC modifies the store.
    private var trustedIDs: Set<UUID> = []

    /// When we last saw each trusted peer.
    private var lastSeen: [UUID: Date] = [:]

    /// Tracks whether we last emitted .lost or .gained, so we don't
    /// re-emit the same signal on every evaluation tick.
    private var lastEmittedLost: Bool = false

    /// Pending discoveries during a "pairing scan" (recorded for the
    /// Settings UI). Keyed by UUID; we always keep the latest RSSI.
    private var discoveries: [UUID: BluetoothDiscovery] = [:]
    private var discoveryUpdateHandler: (([BluetoothDiscovery]) -> Void)?

    private var evalTimer: DispatchSourceTimer?

    /// Threshold for "stale": this many seconds without a sighting
    /// counts as out of range. Matches the design.md grace pattern.
    private let staleThreshold: TimeInterval = 3.0

    override init() {
        super.init()
    }

    func start(_ emit: @escaping (AnchorSignal) -> Void) {
        self.emit = emit
        // Run the central on its own utility queue — keeps the BT
        // dispatch off the main run loop.
        let queue = DispatchQueue(label: "app.anchor.mac.bluetooth", qos: .utility)
        self.central = CBCentralManager(delegate: self, queue: queue, options: [
            CBCentralManagerOptionShowPowerAlertKey: false
        ])
        reloadTrustedPeers()

        // Periodic trust evaluation — every 1 second, check if every
        // trusted peer is stale. Cheap.
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1.0, repeating: 1.0)
        t.setEventHandler { [weak self] in self?.evaluateTrust() }
        t.resume()
        self.evalTimer = t

        NSLog("[BluetoothObserver] started (Watching %d trusted peer(s))",
              trustedIDs.count)
    }

    // MARK: - Public API (for XPC)

    /// Reload trusted-peer list from the store. Called when the Settings
    /// UI adds/removes a peer.
    func reloadTrustedPeers() {
        let peers = TrustedPeerStore.load()
        let ids = Set(peers.map { $0.id })
        trustedIDs = ids
        // Drop lastSeen for any peer that's no longer trusted.
        lastSeen = lastSeen.filter { ids.contains($0.key) }
        NSLog("[BluetoothObserver] reloaded — now watching %d peer(s)", ids.count)
    }

    /// Begin recording every discovery into `discoveries` until `stop`
    /// is called. The Settings UI uses this for the "Add a device"
    /// modal.
    func beginDiscoveryRecording(onUpdate: @escaping ([BluetoothDiscovery]) -> Void) {
        discoveries.removeAll()
        discoveryUpdateHandler = onUpdate
        // CBCentralManager: while we're already scanning for trust, we
        // also pass all results to discoveries. Force a re-scan if not
        // already running so we pick up the latest snapshot quickly.
        kickScan()
    }

    /// Snapshot of currently-visible nearby BT peripherals (newest update first).
    func currentDiscoveries() -> [BluetoothDiscovery] {
        Array(discoveries.values)
            .sorted { $0.rssi > $1.rssi }  // strongest signal first
    }

    func stopDiscoveryRecording() {
        discoveryUpdateHandler = nil
        // Keep scanning — we still need it for trust evaluation.
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        NSLog("[BluetoothObserver] CBCentralManager state: %ld", central.state.rawValue)
        if central.state == .poweredOn {
            kickScan()
        } else {
            // Stop scanning if BT goes off; we can't track anything.
            if central.isScanning { central.stopScan() }
        }
    }

    private func kickScan() {
        guard central.state == .poweredOn else { return }
        if central.isScanning { return }
        // Scan with duplicates allowed so we keep getting RSSI samples
        // for the same peer. Without this we only get one event per
        // peripheral and can't tell when something goes out of range.
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
        NSLog("[BluetoothObserver] scanning…")
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        let now = Date()
        let pid = peripheral.identifier
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Unknown device"

        // 1. If this peer is in the trusted set, update lastSeen.
        if trustedIDs.contains(pid) {
            lastSeen[pid] = now
        }

        // 2. If we're recording discoveries (for the Settings pairing UI),
        // update the discovery snapshot.
        if discoveryUpdateHandler != nil {
            discoveries[pid] = BluetoothDiscovery(
                id: pid, displayName: name, rssi: RSSI.intValue
            )
            // Throttle UI updates — only push at most every 0.5 s.
            // We track the throttle via the timer, but for simplicity
            // just push now (the UI can debounce).
            discoveryUpdateHandler?(currentDiscoveries())
        }
    }

    // MARK: - Trust evaluation

    private func evaluateTrust() {
        // Zero trusted peers → dormant.
        if trustedIDs.isEmpty {
            return
        }

        let now = Date()
        // "In range" = seen within the last `staleThreshold` seconds.
        let anyInRange = trustedIDs.contains { id in
            guard let seen = lastSeen[id] else { return false }
            return now.timeIntervalSince(seen) < staleThreshold
        }

        if anyInRange {
            // Trust is held. If we previously emitted .lost, fire .gained.
            if lastEmittedLost {
                NSLog("[BluetoothObserver] trust regained — at least one trusted peer back in range")
                emit?(.bluetoothTrustGained)
                lastEmittedLost = false
            }
        } else {
            // Trust is lost. Only emit on the transition (not every tick).
            if !lastEmittedLost {
                NSLog("[BluetoothObserver] trust LOST — all %d trusted peer(s) out of range", trustedIDs.count)
                emit?(.bluetoothTrustLost)
                lastEmittedLost = true
            }
        }
    }

    deinit {
        evalTimer?.cancel()
        if central?.isScanning == true { central?.stopScan() }
    }
}
