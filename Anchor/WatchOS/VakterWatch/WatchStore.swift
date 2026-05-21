import Foundation
import WatchConnectivity
import Combine

/// Watch-side store. Receives state from the iPhone via
/// WatchConnectivity application context (low-power, delivered even
/// when both apps are background), and proxies arm/disarm commands
/// back to the iPhone via `sendMessage(_:replyHandler:)`.
@MainActor
final class WatchStore: NSObject, ObservableObject {

    @Published var state: String = "unarmed"
    @Published var mode: String = "—"
    @Published var lastUpdate: Date = .distantPast

    private var session: WCSession?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
        session = s

        // Apply any context the iPhone already pushed before we activated.
        if !s.receivedApplicationContext.isEmpty {
            applyContext(s.receivedApplicationContext)
        }
    }

    /// Ask the iPhone to issue an arm or disarm command. Returns when
    /// the iPhone has accepted the request (it then proxies to CloudKit
    /// on its own side).
    func send(action: String) async {
        guard let session = session,
              session.isReachable else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.sendMessage(
                ["action": action],
                replyHandler: { _ in cont.resume() },
                errorHandler: { _ in cont.resume() }
            )
        }
    }

    private func applyContext(_ context: [String: Any]) {
        if let s = context["state"] as? String { state = s }
        if let m = context["mode"]  as? String { mode = m }
        lastUpdate = Date()
    }
}

extension WatchStore: @preconcurrency WCSessionDelegate {

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}

    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor [weak self] in
            self?.applyContext(applicationContext)
        }
    }
}
