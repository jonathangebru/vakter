import SwiftUI
import AppKit
import AVFoundation
import AnchorShared

@main
struct AnchorApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var delegate

    var body: some Scene {
        // Settings window — opened via menubar "Settings…".
        Settings {
            SettingsRoot()
                .frame(minWidth: 760, minHeight: 560)
        }
    }
}

/// Owns the menubar status item and the onboarding window.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBarController: MenuBarController?
    private var helperManager: HelperManager?
    private var privilegedDaemonManager: PrivilegedDaemonManager?
    // Internal so Settings tabs can fire client.reloadHotkey() etc.
    private(set) var helperClient: HelperClient?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[Anchor] launched")

        // Hide Dock icon — menubar-only.
        NSApp.setActivationPolicy(.accessory)

        // Register the bundled helper LaunchAgent. macOS will either auto-
        // enable it (if previously approved) or mark it as requiresApproval
        // and bounce the user to System Settings → Login Items & Extensions.
        let helper = HelperManager()
        helper.ensureRegistered()
        helperManager = helper

        // Register the privileged daemon (runs as root). Same approval
        // model. After the user approves once in Login Items, arming the
        // alarm no longer prompts for admin — the daemon handles pmset
        // disablesleep silently over XPC.
        let daemon = PrivilegedDaemonManager()
        daemon.ensureRegistered()
        privilegedDaemonManager = daemon

        // Open an XPC connection to the running helper. NSXPCConnection lazy-
        // resolves the Mach service name, so this is safe to call even if the
        // helper hasn't quite finished spawning yet — first request will
        // block until the listener is up.
        let client = HelperClient()
        client.connect()
        helperClient = client

        menuBarController = MenuBarController(
            helperManager: helper,
            helperClient: client
        )

        // Camera permission — request it now, in a calm context, rather
        // than mid-alarm when the user can't actually grant it. macOS
        // attributes the grant to the .app bundle, which means the
        // embedded helper inherits access for AVCaptureSession.
        requestCameraAccessIfNeeded()
    }

    private func requestCameraAccessIfNeeded() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            NSLog("[Anchor] camera permission: authorized")
        case .denied, .restricted:
            NSLog("[Anchor] camera permission: %@ — alarm photos disabled until user fixes in System Settings",
                  status == .denied ? "denied" : "restricted")
        case .notDetermined:
            NSLog("[Anchor] camera permission: requesting now")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                NSLog("[Anchor] camera permission %@", granted ? "GRANTED" : "DENIED by user")
            }
        @unknown default:
            break
        }
    }
}
