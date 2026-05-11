import Foundation
import CoreBluetooth
import AnchorShared

/// Observes the presence of the user's trusted Bluetooth peer set.
///
/// Stub for now — wired in during week 3 of v1 build. See
/// `openspec/changes/bootstrap-anchor/design.md` § Signals — Bluetooth peer.
///
/// Behaviour (when implemented):
///   - User pairs 1–10 trusted devices during onboarding
///   - We maintain a CBCentralManager scanning for known peripheral UUIDs
///   - If ANY trusted peer is in range (RSSI above threshold) → trust held
///   - If ALL trusted peers are out of range for ≥3 consecutive seconds → emit .bluetoothTrustLost
final class BluetoothObserver: NSObject, AnchorSignalObserver, CBCentralManagerDelegate {

    private var central: CBCentralManager?
    private var emit: ((AnchorSignal) -> Void)?

    func start(_ emit: @escaping (AnchorSignal) -> Void) {
        self.emit = emit
        // TODO(week-3): build real implementation.
        // For now, we initialise but do not actually scan — placeholder.
        central = CBCentralManager(delegate: self, queue: nil)
        NSLog("[BluetoothObserver] stub initialised (no trusted peers configured)")
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        NSLog("[BluetoothObserver] CBCentralManager state: %ld", central.state.rawValue)
    }
}
