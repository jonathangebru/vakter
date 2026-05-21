import Foundation
import LocalAuthentication
import VakterShared

/// The helper-side XPC server.
///
/// Sets up an `NSXPCListener` bound to the Mach service name declared in
/// `Contents/Library/LaunchAgents/app.vakter.mac.helper.plist` and accepts
/// connections from the menubar app. For each connection we:
///
///   1. Export an `VakterHelperProtocol` object that bridges to the
///      StateMachine.
///   2. Configure the connection's `remoteObjectInterface` so the helper
///      can call back into the app via `VakterAppProtocol.snapshotChanged`.
///   3. Register a state-machine observer that broadcasts snapshots to
///      the connection. Observer is torn down when the connection closes.
///
/// Multiple app instances (or future Shortcuts integrations) can subscribe
/// concurrently — each gets its own observer entry.
final class XPCService: NSObject, NSXPCListenerDelegate {

    private let listener: NSXPCListener
    private let stateMachine: StateMachine
    private let hotkey: HotkeyObserver
    private let bluetooth: BluetoothObserver

    init(stateMachine: StateMachine,
         hotkey: HotkeyObserver,
         bluetooth: BluetoothObserver) {
        self.stateMachine = stateMachine
        self.hotkey = hotkey
        self.bluetooth = bluetooth
        self.listener = NSXPCListener(machServiceName: VakterConstants.xpcMachServiceName)
        super.init()
        self.listener.delegate = self
    }

    func start() {
        listener.resume()
        NSLog("[XPCService] listening on Mach service: %@", VakterConstants.xpcMachServiceName)
    }

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        // Pin the peer to our Team ID. macOS evaluates the requirement
        // when the first message is dispatched; if it fails, the
        // connection is torn down with `NSXPCConnectionInvalid` and no
        // exported method is ever called. Dev builds (unsigned) log a
        // loud warning and skip the requirement; signed/notarised
        // builds always have one installed.
        XPCPeerVerification.install(on: conn)

        conn.exportedInterface = NSXPCInterface(with: VakterHelperProtocol.self)
        conn.remoteObjectInterface = NSXPCInterface(with: VakterAppProtocol.self)

        let bridge = ExportedBridge(stateMachine: stateMachine, hotkey: hotkey, bluetooth: bluetooth, connection: conn)
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
/// this bridge forwards it to the remote `VakterAppProtocol` proxy.
///
/// Marked `@unchecked Sendable` — all mutable state is reached either
/// through the state machine's own lock or through the NSXPCConnection
/// (thread-safe per Apple's contract). The `isTornDown` flag is written
/// only from the connection's invalidation handler.
private final class ExportedBridge: NSObject, VakterHelperProtocol, @unchecked Sendable {

    private let stateMachine: StateMachine
    private let hotkey: HotkeyObserver
    private let bluetooth: BluetoothObserver
    private weak var connection: NSXPCConnection?
    private var isTornDown = false

    init(stateMachine: StateMachine, hotkey: HotkeyObserver, bluetooth: BluetoothObserver, connection: NSXPCConnection) {
        self.stateMachine = stateMachine
        self.hotkey = hotkey
        self.bluetooth = bluetooth
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

    private func broadcast(_ snapshot: VakterSnapshot) {
        guard !isTornDown, let conn = connection else { return }
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ err in
            NSLog("[XPCService] remote proxy error: %@", err.localizedDescription)
        }) as? VakterAppProtocol else { return }
        let payload = VakterXPC.encode(snapshot)
        proxy.snapshotChanged(payload)
    }

    // MARK: VakterHelperProtocol

    func currentSnapshot(reply: @escaping (Data) -> Void) {
        let snap = stateMachine.snapshot()
        reply(VakterXPC.encode(snap))
    }

    func runPreflight(reply: @escaping (Data) -> Void) {
        // Run the 20-check Pareto-style audit and reply with the JSON-encoded
        // `DefenseChecklist`. Probes shell out to `defaults`, `socketfilterfw`,
        // `launchctl`, etc. — slow enough (typically 1–3 s) that we run it
        // off-thread and stream the result back when ready. The app side
        // already handles late replies via the XPC `@escaping` reply block.
        //
        // The XPC reply block is plain Swift `(Data) -> Void` — not
        // `@Sendable` — so the closure body that calls it can't be
        // marked Sendable either. Wrap into an unchecked-Sendable holder
        // so the global-queue dispatch crosses the actor boundary.
        let safeReply = ReplyBoxData(reply: reply)
        DispatchQueue.global(qos: .utility).async {
            let checklist = DefensesProbe.runAll()
            safeReply.reply(VakterXPC.encode(checklist))
        }
    }

    func arm(reply: @escaping (Bool) -> Void) {
        stateMachine.armFromUser()
        reply(true)
    }

    func disarm(reply: @escaping (Bool) -> Void) {
        // Gate any XPC-initiated disarm on biometric/password auth. The
        // *natural* disarm path (the user unlocking the Mac at the lock
        // screen) goes through ScreenLockObserver, never through here —
        // so this only fires when something other than the OS unlock is
        // asking, e.g. a menubar click while the screen is already unlocked,
        // a Shortcuts invocation, or a future iOS-companion request.
        let context = LAContext()
        var err: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            NSLog("[XPCService] disarm: canEvaluatePolicy denied (%@)",
                  err?.localizedDescription ?? "?")
            reply(false)
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Disarm Anchor"
        ) { [weak self] success, authErr in
            if let authErr = authErr {
                NSLog("[XPCService] disarm: auth failed (%@)", authErr.localizedDescription)
            }
            if success {
                self?.stateMachine.disarmFromUser()
            }
            reply(success)
        }
    }

    func setMode(_ raw: String, reply: @escaping (Bool) -> Void) {
        guard let mode = VakterMode(rawValue: raw) else { reply(false); return }
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

    func reloadHotkey(reply: @escaping (Bool) -> Void) {
        hotkey.rebind()
        reply(true)
    }

    func testAlarm(seconds: Double, reply: @escaping (Bool) -> Void) {
        stateMachine.runTestAlarm(seconds: seconds)
        reply(true)
    }

    func simulateLidClose(reply: @escaping (Bool) -> Void) {
        stateMachine.simulateLidClose()
        reply(true)
    }

    func runArmDemo(reply: @escaping (Bool) -> Void) {
        stateMachine.runArmDemo()
        reply(true)
    }

    // MARK: Trusted Bluetooth peers

    func listTrustedPeers(reply: @escaping (Data) -> Void) {
        reply(VakterXPC.encode(TrustedPeerStore.load()))
    }

    func startBluetoothDiscovery(reply: @escaping (Data) -> Void) {
        bluetooth.beginDiscoveryRecording { _ in /* live snapshot via polling */ }
        // Give the radio a beat to surface a first batch of advertisements.
        let safeReply = ReplyBoxData(reply: reply)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) { [weak self] in
            let initial = self?.bluetooth.currentDiscoveries() ?? []
            safeReply.reply(VakterXPC.encode(initial))
        }
    }

    func currentBluetoothDiscoveries(reply: @escaping (Data) -> Void) {
        reply(VakterXPC.encode(bluetooth.currentDiscoveries()))
    }

    func stopBluetoothDiscovery(reply: @escaping (Bool) -> Void) {
        bluetooth.stopDiscoveryRecording()
        reply(true)
    }

    func addTrustedPeer(_ data: Data, reply: @escaping (Bool) -> Void) {
        guard let peer = VakterXPC.decode(TrustedPeer.self, from: data) else {
            reply(false); return
        }
        let existing = TrustedPeerStore.load()
        if existing.count >= TrustedPeerStore.maxCount &&
           !existing.contains(where: { $0.id == peer.id }) {
            NSLog("[XPCService] addTrustedPeer rejected — max %d peers", TrustedPeerStore.maxCount)
            reply(false); return
        }
        TrustedPeerStore.add(peer)
        bluetooth.reloadTrustedPeers()
        reply(true)
    }

    func removeTrustedPeer(_ idString: String, reply: @escaping (Bool) -> Void) {
        guard let uuid = UUID(uuidString: idString) else { reply(false); return }
        TrustedPeerStore.remove(id: uuid)
        bluetooth.reloadTrustedPeers()
        reply(true)
    }
}

// MARK: - Sendable reply boxes

/// Wrapper that lets us safely cross actor boundaries with an XPC reply
/// block. The reply closure is plain `(Data) -> Void` and not `Sendable`
/// (NSXPCConnection is older than Swift concurrency). Boxing it lets us
/// hand the box to a `@Sendable` closure without losing the reply.
///
/// Marked `@unchecked Sendable` because we vouch that the reply block
/// is single-use, owned by the XPC machinery, and won't be called
/// concurrently from multiple threads.
private final class ReplyBoxData: @unchecked Sendable {
    let reply: (Data) -> Void
    init(reply: @escaping (Data) -> Void) {
        self.reply = reply
    }
}
