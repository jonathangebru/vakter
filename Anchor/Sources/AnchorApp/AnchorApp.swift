import SwiftUI
import AppKit
import AnchorShared

@main
struct AnchorApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var delegate

    var body: some Scene {
        // Settings window — opened via menubar "Settings…".
        Settings {
            SettingsRoot()
                .frame(minWidth: 580, minHeight: 420)
        }
    }
}

/// Owns the menubar status item and the onboarding window.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBarController: MenuBarController?
    private var helperManager: HelperManager?
    private var helperClient: HelperClient?

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
    }
}
