import SwiftUI
import AppKit
import AVFoundation
import VakterShared

@main
struct VakterApp: App {

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
    private var cloudKitPublisher: CloudKitPublisher?
    private var helperManager: HelperManager?
    private var privilegedDaemonManager: PrivilegedDaemonManager?
    // Internal so Settings tabs can fire client.reloadHotkey() etc.
    private(set) var helperClient: HelperClient?
    /// Pareto-style 80/20 security checklist. Runs every 30 minutes;
    /// menubar dropdown reads the published checklist to render the
    /// "Access Security › Firewall & Sharing › …" submenus.
    private(set) var defensesScheduler: DefensesScheduler?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[Vakter] launched")

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

        // Pareto-style defenses checklist. Created BEFORE the menubar
        // controller so the menu can read its `checklist` property the
        // very first time the user clicks the menubar icon.
        let defenses = DefensesScheduler()
        defensesScheduler = defenses

        menuBarController = MenuBarController(
            helperManager: helper,
            helperClient: client,
            defensesScheduler: defenses,
            onShowSettings: { [weak self] in self?.showSettingsWindow() }
        )

        // v1.4: CloudKit publisher pushes every snapshot + event to the
        // user's private iCloud database. The iPhone + Watch companion
        // apps read from there.
        //
        // Safe-by-construction: `CloudKitPublisher.init?` checks the
        // app's signed entitlements via `EntitlementProbe` before it
        // touches `CKContainer(identifier:)` — so if iCloud isn't
        // provisioned (dev builds, ad-hoc signing, or just before
        // iOS/SETUP.md is run), the publisher returns nil and the
        // app keeps running. No UserDefault flag, no crash.
        if let publisher = CloudKitPublisher() {
            cloudKitPublisher = publisher
            // Tee the snapshot callback so both the MenuBarController and
            // the CloudKitPublisher receive every push.
            let existingOnSnapshot = client.onSnapshot
            client.onSnapshot = { [weak self] snapshot in
                existingOnSnapshot?(snapshot)
                Task { @MainActor in
                    self?.cloudKitPublisher?.publish(snapshot: snapshot)
                }
            }
            NSLog("[AppDelegate] CloudKitPublisher enabled.")
        }

        defenses.start()

        // Camera permission — request it now, in a calm context, rather
        // than mid-alarm when the user can't actually grant it. macOS
        // attributes the grant to the .app bundle, which means the
        // embedded helper inherits access for AVCaptureSession.
        requestCameraAccessIfNeeded()

        // First-launch onboarding sheet. Quietly skipped for users who
        // have already been through it.
        if !OnboardingState.hasCompleted {
            // Show after a beat so the menubar shield has rendered.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.presentOnboarding()
            }
        }
    }

    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?

    /// Called by MenuBarController when the user picks "Settings…".
    /// SwiftUI's `Settings` scene doesn't reliably open from
    /// LSUIElement=true apps (the activation policy keeps the window
    /// hidden), so we present our own NSWindow that hosts SettingsRoot
    /// directly. Tracks a single shared window so repeated clicks just
    /// bring the existing one forward.
    @MainActor
    func showSettingsWindow() {
        if let win = settingsWindow {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            return
        }

        // Inject the menubar's shield-state observable so the Settings
        // sidebar's brand mark animates in sync with the menubar shield.
        let stateBox = menuBarController?.stateBox ?? ShieldStateBox()
        // ALSO inject `helperClient` so Settings tabs can call testAlarm,
        // setMode, reloadHotkey, etc. without the fragile
        // `NSApp.delegate as? AppDelegate` cast (which silently returned
        // nil when the Settings window was hosted via NSHostingController,
        // breaking every Settings → helper call).
        let client = helperClient ?? HelperClient()
        let host = NSHostingController(
            rootView: SettingsRoot()
                .environmentObject(stateBox)
                .environmentObject(client)
        )
        let window = NSWindow(contentViewController: host)
        window.title = "Vakter Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 760, height: 560)
        window.center()
        window.isReleasedWhenClosed = false

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Only drop back to accessory if no other windows are open.
                if self?.onboardingWindow == nil {
                    NSApp.setActivationPolicy(.accessory)
                }
                self?.settingsWindow = nil
            }
        }
    }

    @MainActor
    private func presentOnboarding() {
        // Plain NSWindow rather than a Settings panel because Settings is
        // already a reserved Scene for our preferences. We want a discrete,
        // sheet-style window centred on screen.
        //
        // Inject the helperClient directly because @NSApplicationDelegate-
        // Adaptor's SwiftUI wrapping breaks `NSApp.delegate as? AppDelegate`
        // when the cast happens from inside the hosted SwiftUI sheet.
        let host = NSHostingController(
            rootView: OnboardingSheet(helperClient: helperClient)
        )
        let window = NSWindow(contentViewController: host)
        window.title = "Welcome to Vakter"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        // Bring the app forward enough for the window to show.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        onboardingWindow = window
        // Listen for the window closing so we can drop activation policy
        // back to .accessory (menubar-only).
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                NSApp.setActivationPolicy(.accessory)
                self?.onboardingWindow = nil
            }
        }
    }

    private func requestCameraAccessIfNeeded() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            NSLog("[Vakter] camera permission: authorized")
        case .denied, .restricted:
            NSLog("[Vakter] camera permission: %@ — alarm photos disabled until user fixes in System Settings",
                  status == .denied ? "denied" : "restricted")
        case .notDetermined:
            NSLog("[Vakter] camera permission: requesting now")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                NSLog("[Vakter] camera permission %@", granted ? "GRANTED" : "DENIED by user")
            }
        @unknown default:
            break
        }
    }
}
