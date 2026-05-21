import Foundation
import VakterShared

// One-shot CLI verifier:
//   - Opens an NSXPCConnection to the running helper
//   - Calls arm(), waits, calls disarm()
//   - Prints what the helper replies
//   - Logs any snapshot pushes received during the window
//
// Lives under `Sources/VakterHelperPoke` so SPM builds it as a third
// executable. Not shipped in the .app bundle — purely a dev tool.
//
// NOTE: Swift 6 will print "data race detected" warnings when running
// this tool. That's the runtime calling out the deliberately sloppy
// semaphore-based control flow here, NOT a bug in the real app/helper
// code. This is a throwaway debug script; don't bother fixing.

final class PokeClient: NSObject, VakterAppProtocol {
    func snapshotChanged(_ data: Data) {
        if let snap = VakterXPC.decode(VakterSnapshot.self, from: data) {
            print("← snapshot: state=\(snap.state.rawValue) mode=\(snap.mode.rawValue)")
        } else {
            print("← snapshot: <decode failure, \(data.count) bytes>")
        }
    }
}

print("== HelperPoke ==\n")

let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "armdisarm"

let conn = NSXPCConnection(machServiceName: VakterConstants.xpcMachServiceName)
conn.remoteObjectInterface = NSXPCInterface(with: VakterHelperProtocol.self)
conn.exportedInterface = NSXPCInterface(with: VakterAppProtocol.self)

let client = PokeClient()
conn.exportedObject = client

conn.invalidationHandler = { print("connection invalidated") }
conn.interruptionHandler = { print("connection interrupted") }
conn.resume()

guard let proxy = conn.remoteObjectProxyWithErrorHandler({ err in
    print("proxy error: \(err.localizedDescription)")
}) as? VakterHelperProtocol else {
    print("FAIL: could not cast remote proxy to VakterHelperProtocol")
    exit(1)
}

// Hotkey-only smoke test: write a non-default binding, call reloadHotkey,
// then restore the default. The helper log should show two `[HotkeyObserver]
// registered ...` lines proving the rebind path works.
if mode == "testalarm" {
    print("→ Calling testAlarm(3.0). Expect to hear siren + voice for ~3s.")
    let sem = DispatchSemaphore(value: 0)
    proxy.testAlarm(seconds: 3.0) { ok in
        print("← testAlarm reply: \(ok)")
        sem.signal()
    }
    sem.wait()
    // Block while alarm plays so we don't exit before it completes.
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 4.0))
    print("\nDone.")
    exit(0)
}

if mode == "demo" {
    // Full arm-demo cycle: arm + synthetic lid-close + grace + alarm.
    // Exercises the entire alarm pipeline (state machine, photo
    // burst, audio capture, evidence bundle delivery, cloud upload).
    // The helper schedules it without screen-locking so we can watch
    // the logs.
    print("→ Calling runArmDemo(). Watch the helper log for ~15s.")
    let sem = DispatchSemaphore(value: 0)
    proxy.runArmDemo { ok in
        print("← runArmDemo reply: \(ok)")
        sem.signal()
    }
    sem.wait()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 16.0))
    print("\nDone.")
    exit(0)
}

if mode == "hotkey" {
    let custom = HotkeyBinding(keyCode: 0 /* A */,
                               modifiers: UInt32(0x100 /* cmdKey */ |
                                                 0x200 /* shiftKey */ |
                                                 0x800 /* optionKey */))
    print("→ Writing custom binding \(custom.displayLabel) to HotkeyStore")
    HotkeyStore.save(custom)

    let sem = DispatchSemaphore(value: 0)
    proxy.reloadHotkey { ok in
        print("← reloadHotkey: \(ok)")
        sem.signal()
    }
    sem.wait()

    sleep(1)

    print("→ Restoring default \(HotkeyBinding.default.displayLabel)")
    HotkeyStore.save(.default)

    let sem2 = DispatchSemaphore(value: 0)
    proxy.reloadHotkey { ok in
        print("← reloadHotkey: \(ok)")
        sem2.signal()
    }
    sem2.wait()

    print("\nDone — check the helper log for two register entries.")
    exit(0)
}

// 1. Query current snapshot.
let semaphoreA = DispatchSemaphore(value: 0)
proxy.currentSnapshot { data in
    if let snap = VakterXPC.decode(VakterSnapshot.self, from: data) {
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
