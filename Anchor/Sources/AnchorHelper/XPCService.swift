import Foundation
import AnchorShared

/// The helper-side XPC server.
///
/// Sets up an `NSXPCListener` bound to the Mach service name declared in
/// `Contents/Library/LaunchAgents/app.anchor.mac.helper.plist` and accepts
/// connections from the menubar app. For each connection we:
///
///   1. Export an `AnchorHelperProtocol` object that bridges to the
///      StateMachine.
///   2. Configure the connection's `remoteObjectInterface` so the helper
///      can call back into the app via `AnchorAppProtocol.snapshotChanged`.
///   3. Register a state-machine observer that broadcasts snapshots to
///      the connection. Observer is torn down when the connection closes.
///
/// Multiple app instances (or future Shortcuts integrations) can subscribe
/// concurrently — each gets its own observer entry.
final class XPCService: NSObject, NSXPCListenerDelegate {

    private let listener: NSXPCListener
    private let stateMachine: StateMachine

    init(stateMachine: StateMachine) {
        self.stateMachine = stateMachine
        self.listener = NSXPCListener(machServiceName: AnchorConstants.xpcMachServiceName)
        super.init()
        self.listener.delegate = self
    }

    func start() {
        listener.resume()
        NSLog("[XPCService] listening on Mach service: %@", AnchorConstants.xpcMachServiceName)
    }

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {

        // TODO(week-3.5): verify the peer's code signature matches our Team ID
        // via SecCodeCopyGuestWithAttributes / SecRequirement so only our own
        // app can call privileged operations. For dev/v1, we trust same-user
        // peers (LaunchAgents are user-scoped already, so cross-user calls
        // aren't possible).

        conn.exportedInterface = NSXPCInterface(with: AnchorHelperProtocol.self)
        conn.remoteObjectInterface = NSXPCInterface(with: AnchorAppProtocol.self)

        let bridge = ExportedBridge(stateMachine: stateMachine, connection: conn)
        conn.exportedObject = bridge

        conn.invalidationHandler = { [weak bridge] in
            bridge?.tearDown()
            NSLog("[XPCService] connection invalidated")
        }
        conn.interruptionHandler = { [weak bridge] in
            bridge?.tearDown()
            NSLog("[XPCService] connection interrupted")
        }

        conn.resume()
        NSLog("[XPCService] accepted new connection")
        return true
    }
}

// MARK: - The exported object — one per connection

/// Per-connection bridge: holds a weak reference to the state machine and
/// the active NSXPCConnection. When the state machine publishes a snapshot,
/// this bridge forwards it to the remote `AnchorAppProtocol` proxy.
///
/// Marked `@unchecked Sendable` — all mutable state is reached either
/// through the state machine's own lock or through the NSXPCConnection
/// (thread-safe per Apple's contract). The `isTornDown` flag is written
/// only from the connection's invalidation handler.
private final class ExportedBridge: NSObject, AnchorHelperProtocol, @unchecked Sendable {

    private let stateMachine: StateMachine
    private weak var connection: NSXPCConnection?
    private var isTornDown = false

    init(stateMachine: StateMachine, connection: NSXPCConnection) {
        self.stateMachine = stateMachine
        self.connection = connection
        super.init()

        // Subscribe to snapshot changes; forward over XPC.
        stateMachine.addObserver { [weak self] snapshot in
            self?.broadcast(snapshot)
        }
    }

    func tearDown() {
        isTornDown = true
        connection = nil
    }

    private func broadcast(_ snapshot: AnchorSnapshot) {
        guard !isTornDown, let conn = connection else { return }
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ err in
            NSLog("[XPCService] remote proxy error: %@", err.localizedDescription)
        }) as? AnchorAppProtocol else { return }
        let payload = AnchorXPC.encode(snapshot)
        proxy.snapshotChanged(payload)
    }

    // MARK: AnchorHelperProtocol

    func currentSnapshot(reply: @escaping (Data) -> Void) {
        let snap = stateMachine.snapshot()
        reply(AnchorXPC.encode(snap))
    }

    func runPreflight(reply: @escaping (Data) -> Void) {
        // TODO(week-6.5): implement the actual checklist read. Return empty
        // payload for now so the protocol shape is exercised.
        reply(Data())
    }

    func arm(reply: @escaping (Bool) -> Void) {
        stateMachine.armFromUser()
        reply(true)
    }

    func disarm(reply: @escaping (Bool) -> Void) {
        // TODO(week-4): gate via LAContext biometric auth before applying.
        stateMachine.disarmFromUser()
        reply(true)
    }

    func setMode(_ raw: String, reply: @escaping (Bool) -> Void) {
        guard let mode = AnchorMode(rawValue: raw) else { reply(false); return }
        stateMachine.setMode(mode)
        reply(true)
    }

    func enterLoaner(seconds: Double, reply: @escaping (Bool) -> Void) {
        let window: LoanerTrustWindow
        switch seconds {
        case ..<5400:  window = .oneHour
        case ..<10800: window = .twoHours
        default:       window = .fourHours
        }
        stateMachine.enterLoaner(window: window)
        reply(true)
    }
}
