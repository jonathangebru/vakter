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

        menuBarController = MenuBarController(helperManager: helper)

        // TODO(week-5): if first run, present OnboardingView in a window.
    }
}
