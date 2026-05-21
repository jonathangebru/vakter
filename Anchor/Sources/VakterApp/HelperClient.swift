import Foundation
import VakterShared

/// The app-side XPC client.
///
/// Owns the `NSXPCConnection` to the helper daemon and surfaces a Swifty
/// API for the rest of the app (`arm()`, `setMode(_)`, …). Receives
/// snapshot updates back from the helper and republishes them via a
/// MainActor-isolated callback for the menubar to render.
///
/// Connection lifecycle:
///   - Created at app launch (after `SMAppService.register()` succeeds)
///   - Survives helper restarts: NSXPCConnection auto-reconnects on next
///     call. Snapshot subscriptions need to be re-established after a
///     reconnect; we do that opportunistically.
@MainActor
final class HelperClient: NSObject, VakterAppProtocol, ObservableObject {

    /// Called every time the helper pushes a new snapshot.
    /// Always invoked on the main actor.
    var onSnapshot: ((VakterSnapshot) -> Void)?

    private var connection: NSXPCConnection?

    /// Cached most-recent snapshot. Useful for synchronous UI reads
    /// (the menubar renders immediately from this).
    private(set) var lastSnapshot: VakterSnapshot?

    override init() {
        super.init()
    }

    func connect() {
        let conn = NSXPCConnection(machServiceName: VakterConstants.xpcMachServiceName)
        conn.remoteObjectInterface = NSXPCInterface(with: VakterHelperProtocol.self)
        conn.exportedInterface = NSXPCInterface(with: VakterAppProtocol.self)
        conn.exportedObject = self
        conn.invalidationHandler = { [weak self] in
            NSLog("[HelperClient] connection invalidated")
            self?.handleDisconnect()
        }
        conn.interruptionHandler = { [weak self] in
            NSLog("[HelperClient] connection interrupted")
            self?.handleDisconnect()
        }
        conn.resume()
        self.connection = conn

        // Kick a no-op call to force the connection to actually establish
        // and trigger the helper's first snapshotChanged() push.
        requestSnapshotNow()
    }

    private func handleDisconnect() {
        connection = nil
        // Try to reconnect after a short backoff. NSXPCConnection itself
        // doesn't auto-reconnect after invalidation, so we recreate.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.connection == nil else { return }
            NSLog("[HelperClient] reconnecting…")
            self.connect()
        }
    }

    private func helperProxy() -> VakterHelperProtocol? {
        guard let conn = connection else { return nil }
        return conn.remoteObjectProxyWithErrorHandler { err in
            NSLog("[HelperClient] proxy error: %@", err.localizedDescription)
        } as? VakterHelperProtocol
    }

    // MARK: - Commands

    func arm() {
        helperProxy()?.arm { ok in
            NSLog("[HelperClient] arm reply: %@", ok ? "ok" : "rejected")
        }
    }

    func disarm() {
        helperProxy()?.disarm { ok in
            NSLog("[HelperClient] disarm reply: %@", ok ? "ok" : "rejected")
        }
    }

    func setMode(_ mode: VakterMode) {
        helperProxy()?.setMode(mode.rawValue) { ok in
            NSLog("[HelperClient] setMode reply: %@", ok ? "ok" : "rejected")
        }
    }

    func enterLoaner(window: LoanerTrustWindow) {
        helperProxy()?.enterLoaner(seconds: window.rawValue) { ok in
            NSLog("[HelperClient] enterLoaner reply: %@", ok ? "ok" : "rejected")
        }
    }

    /// Ask the helper to re-read HotkeyStore and re-register its Carbon
    /// hotkey. Called after the user picks a new combo in Settings.
    func reloadHotkey() {
        helperProxy()?.reloadHotkey { ok in
            NSLog("[HelperClient] reloadHotkey reply: %@", ok ? "ok" : "rejected")
        }
    }

    // MARK: - Diagnostics

    /// Fire the real alarm subsystem (siren + voice + audio override) for
    /// `seconds` via the helper, then auto-restore. Doesn't change state.
    ///
    /// **Reliability fallback:** if the XPC call doesn't ack within 1.0 s
    /// (helper not running, LWCR mismatch after rebuild, daemon not
    /// approved, etc.) we play a *local* AVAudioPlayer-driven preview
    /// inside the app process. The user still hears something so they
    /// can audition the alarm sound; the helper just won't be the one
    /// playing it. Bundle-internal, no system-audio override — quieter,
    /// but works offline and pre-approval.
    ///
    /// **Concurrency:** the XPC reply closure runs on the connection's
    /// background queue, while the 1.0 s fallback runs on the main queue.
    /// We funnel both through an `AckGate` that hops to @MainActor before
    /// claiming — whichever arrives first wins, the other is a no-op.
    /// This avoids the obvious data race on a plain `var didAck = false`
    /// and prevents the double-siren bug where both paths fire.
    func testAlarm(seconds: Double = 3.0) {
        let gate = AckGate()
        helperProxy()?.testAlarm(seconds: seconds) { ok in
            Task { @MainActor in
                guard gate.claim() else { return }
                NSLog("[HelperClient] testAlarm reply: %@", ok ? "ok" : "rejected")
            }
        }
        // Race: if the helper doesn't ack within a second, run a local
        // fallback preview so the button isn't silently broken.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard gate.claim() else { return }
            NSLog("[HelperClient] testAlarm: helper unreachable — playing local fallback preview")
            self?.playLocalFallbackPreview(seconds: seconds)
        }
    }

    /// Last-resort siren preview that doesn't depend on the helper. Plays
    /// a synthesised 880 Hz sine for ~`seconds` seconds at the current
    /// system volume on the system default output. Used when the helper
    /// LaunchAgent is unreachable (just-renamed-binary LWCR mismatch,
    /// pre-approval, etc.) so the user can still audition the alarm.
    private func playLocalFallbackPreview(seconds: Double) {
        LocalAlarmPreview.shared.play(seconds: seconds)
    }

    /// Inject a synthetic lid-close signal — drives ARMED → GRACE → ALARM
    /// without physically closing the lid.
    func simulateLidClose() {
        helperProxy()?.simulateLidClose { ok in
            NSLog("[HelperClient] simulateLidClose reply: %@", ok ? "ok" : "rejected")
        }
    }

    /// One-click "watch the arming flow from the menubar" demo — arms
    /// without locking the screen, then triggers a fake lid close so
    /// chirp → grace chirps → alarm play through audibly.
    func runArmDemo() {
        helperProxy()?.runArmDemo { ok in
            NSLog("[HelperClient] runArmDemo reply: %@", ok ? "ok" : "rejected")
        }
    }

    // MARK: Trusted Bluetooth peers

    /// Fetch the current trusted-peer list from the helper.
    func listTrustedPeers(completion: @escaping ([TrustedPeer]) -> Void) {
        helperProxy()?.listTrustedPeers { data in
            let peers = VakterXPC.decode([TrustedPeer].self, from: data) ?? []
            Task { @MainActor in completion(peers) }
        }
    }

    /// Start a discovery scan. Initial reply arrives ~0.8 s later with
    /// any peripherals already in advertisement range.
    func startBluetoothDiscovery(completion: @escaping ([BluetoothDiscovery]) -> Void) {
        helperProxy()?.startBluetoothDiscovery { data in
            let list = VakterXPC.decode([BluetoothDiscovery].self, from: data) ?? []
            Task { @MainActor in completion(list) }
        }
    }

    /// Latest snapshot for live polling during the pairing modal.
    func currentBluetoothDiscoveries(completion: @escaping ([BluetoothDiscovery]) -> Void) {
        helperProxy()?.currentBluetoothDiscoveries { data in
            let list = VakterXPC.decode([BluetoothDiscovery].self, from: data) ?? []
            Task { @MainActor in completion(list) }
        }
    }

    func stopBluetoothDiscovery() {
        helperProxy()?.stopBluetoothDiscovery { _ in }
    }

    func addTrustedPeer(_ peer: TrustedPeer, completion: @escaping (Bool) -> Void) {
        helperProxy()?.addTrustedPeer(VakterXPC.encode(peer)) { ok in
            Task { @MainActor in completion(ok) }
        }
    }

    func removeTrustedPeer(id: UUID, completion: @escaping (Bool) -> Void) {
        helperProxy()?.removeTrustedPeer(id.uuidString) { ok in
            Task { @MainActor in completion(ok) }
        }
    }

    func requestSnapshotNow() {
        helperProxy()?.currentSnapshot { [weak self] data in
            guard let snap = VakterXPC.decode(VakterSnapshot.self, from: data) else { return }
            Task { @MainActor [weak self] in
                self?.deliverSnapshot(snap)
            }
        }
    }

    // MARK: - Defenses checklist

    /// Ask the helper to run the full Pareto-style defenses checklist
    /// (`DefensesProbe.runAll()`) and call `completion` on the main actor
    /// with the decoded `DefenseChecklist`.
    ///
    /// The probe shells out to ~10 binaries and typically takes 2–6 s.
    /// The helper runs it off its main queue and replies via the
    /// XPC `@escaping` callback when it's done — so this method
    /// returns immediately and the completion fires later.
    ///
    /// **Fallback path:** if XPC is unreachable (helper not approved,
    /// LWCR mismatch, daemon crashed, dev build with no helper running)
    /// the reply block never fires. Callers should layer a timeout +
    /// in-process `DefensesProbe.runAll()` fallback on top — see
    /// `DefensesScheduler.runNow()` for the canonical pattern. Without
    /// a timeout, a missing helper would leave the menubar's Defenses
    /// submenu stuck on stale data forever, which is exactly the
    /// trust-eroding glitch this XPC route is meant to prevent.
    ///
    /// `completion` is `nil`-tolerant of decode failure: a malformed
    /// payload (empty `Data`, encoder/decoder schema drift, etc.) is
    /// surfaced as `nil` so the caller can decide whether to fall
    /// back rather than silently render an empty checklist.
    func runPreflight(completion: @escaping (DefenseChecklist?) -> Void) {
        guard let proxy = helperProxy() else {
            // Helper not connected — propagate nil so the caller can
            // fall back to a local probe rather than hang on a reply
            // that will never arrive.
            Task { @MainActor in completion(nil) }
            return
        }
        proxy.runPreflight { data in
            let checklist = VakterXPC.decode(DefenseChecklist.self, from: data)
            Task { @MainActor in completion(checklist) }
        }
    }

    // MARK: - VakterAppProtocol (called by the helper)

    nonisolated func snapshotChanged(_ data: Data) {
        guard let snap = VakterXPC.decode(VakterSnapshot.self, from: data) else {
            NSLog("[HelperClient] snapshotChanged: decode failed")
            return
        }
        Task { @MainActor [weak self] in
            self?.deliverSnapshot(snap)
        }
    }

    private func deliverSnapshot(_ snapshot: VakterSnapshot) {
        lastSnapshot = snapshot
        onSnapshot?(snapshot)
    }
}

// `AckGate` lives in VakterShared so the helper-side equivalents can
// reuse it and so it's directly unit-testable.
