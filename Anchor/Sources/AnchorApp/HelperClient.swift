import Foundation
import AnchorShared

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
final class HelperClient: NSObject, AnchorAppProtocol {

    /// Called every time the helper pushes a new snapshot.
    /// Always invoked on the main actor.
    var onSnapshot: ((AnchorSnapshot) -> Void)?

    private var connection: NSXPCConnection?

    /// Cached most-recent snapshot. Useful for synchronous UI reads
    /// (the menubar renders immediately from this).
    private(set) var lastSnapshot: AnchorSnapshot?

    override init() {
        super.init()
    }

    func connect() {
        let conn = NSXPCConnection(machServiceName: AnchorConstants.xpcMachServiceName)
        conn.remoteObjectInterface = NSXPCInterface(with: AnchorHelperProtocol.self)
        conn.exportedInterface = NSXPCInterface(with: AnchorAppProtocol.self)
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

    private func helperProxy() -> AnchorHelperProtocol? {
        guard let conn = connection else { return nil }
        return conn.remoteObjectProxyWithErrorHandler { err in
            NSLog("[HelperClient] proxy error: %@", err.localizedDescription)
        } as? AnchorHelperProtocol
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

    func setMode(_ mode: AnchorMode) {
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

    func requestSnapshotNow() {
        helperProxy()?.currentSnapshot { [weak self] data in
            guard let snap = AnchorXPC.decode(AnchorSnapshot.self, from: data) else { return }
            Task { @MainActor [weak self] in
                self?.deliverSnapshot(snap)
            }
        }
    }

    // MARK: - AnchorAppProtocol (called by the helper)

    nonisolated func snapshotChanged(_ data: Data) {
        guard let snap = AnchorXPC.decode(AnchorSnapshot.self, from: data) else {
            NSLog("[HelperClient] snapshotChanged: decode failed")
            return
        }
        Task { @MainActor [weak self] in
            self?.deliverSnapshot(snap)
        }
    }

    private func deliverSnapshot(_ snapshot: AnchorSnapshot) {
        lastSnapshot = snapshot
        onSnapshot?(snapshot)
    }
}
