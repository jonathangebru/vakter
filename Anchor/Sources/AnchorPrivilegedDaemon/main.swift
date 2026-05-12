import Foundation
import AnchorShared

// AnchorPrivilegedDaemon — runs as root via launchd, controlled by
// SMAppService.daemon registration from the menubar app.
//
// Lifecycle:
//   1. AnchorApp calls SMAppService.daemon(...).register() on first run
//   2. macOS adds it to Login Items; user approves once in System Settings
//   3. launchd starts this binary as root (UID 0)
//   4. We listen on the privileged Mach service
//   5. AnchorHelper (user-level LaunchAgent) connects to us via XPC and
//      asks us to toggle `pmset disablesleep`
//   6. We validate the peer's code signature and execute the call
//
// Security: every incoming connection is validated against our app's
// own code requirement (team ID + bundle ID) before honouring any call.
// Otherwise any process could connect to this Mach service.

NSLog("[Anchor.privileged] starting (uid=%d gid=%d)", getuid(), getgid())

let listener = NSXPCListener(machServiceName: AnchorConstants.privilegedDaemonMachServiceName)
let delegate = ListenerDelegate()
listener.delegate = delegate
listener.resume()

NSLog("[Anchor.privileged] listening on Mach service: %@",
      AnchorConstants.privilegedDaemonMachServiceName)

RunLoop.main.run()
