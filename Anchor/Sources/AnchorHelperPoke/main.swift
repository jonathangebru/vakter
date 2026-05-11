import Foundation
import AnchorShared

// One-shot CLI verifier:
//   - Opens an NSXPCConnection to the running helper
//   - Calls arm(), waits, calls disarm()
//   - Prints what the helper replies
//   - Logs any snapshot pushes received during the window
//
// Lives under `Sources/AnchorHelperPoke` so SPM builds it as a third
// executable. Not shipped in the .app bundle — purely a dev tool.
//
// NOTE: Swift 6 will print "data race detected" warnings when running
// this tool. That's the runtime calling out the deliberately sloppy
// semaphore-based control flow here, NOT a bug in the real app/helper
// code. This is a throwaway debug script; don't bother fixing.

final class PokeClient: NSObject, AnchorAppProtocol {
    func snapshotChanged(_ data: Data) {
        if let snap = AnchorXPC.decode(AnchorSnapshot.self, from: data) {
            print("← snapshot: state=\(snap.state.rawValue) mode=\(snap.mode.rawValue)")
        } else {
            print("← snapshot: <decode failure, \(data.count) bytes>")
        }
    }
}

print("== HelperPoke ==\n")

let conn = NSXPCConnection(machServiceName: AnchorConstants.xpcMachServiceName)
conn.remoteObjectInterface = NSXPCInterface(with: AnchorHelperProtocol.self)
conn.exportedInterface = NSXPCInterface(with: AnchorAppProtocol.self)

let client = PokeClient()
conn.exportedObject = client

conn.invalidationHandler = { print("connection invalidated") }
conn.interruptionHandler = { print("connection interrupted") }
conn.resume()

guard let proxy = conn.remoteObjectProxyWithErrorHandler({ err in
    print("proxy error: \(err.localizedDescription)")
}) as? AnchorHelperProtocol else {
    print("FAIL: could not cast remote proxy to AnchorHelperProtocol")
    exit(1)
}

// 1. Query current snapshot.
let semaphoreA = DispatchSemaphore(value: 0)
proxy.currentSnapshot { data in
    if let snap = AnchorXPC.decode(AnchorSnapshot.self, from: data) {
        print("→ currentSnapshot: state=\(snap.state.rawValue) mode=\(snap.mode.rawValue)")
    } else {
        print("→ currentSnapshot: <decode failure>")
    }
    semaphoreA.signal()
}
semaphoreA.wait()

// 2. Arm.
print("\n→ arm()")
let semaphoreB = DispatchSemaphore(value: 0)
proxy.arm { ok in
    print("← arm replied: \(ok)")
    semaphoreB.signal()
}
semaphoreB.wait()

// Brief window to receive snapshotChanged pushes.
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))

// 3. Disarm.
print("\n→ disarm()")
let semaphoreC = DispatchSemaphore(value: 0)
proxy.disarm { ok in
    print("← disarm replied: \(ok)")
    semaphoreC.signal()
}
semaphoreC.wait()

RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))

print("\nDone.")
