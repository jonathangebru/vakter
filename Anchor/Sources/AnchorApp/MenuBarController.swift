import AppKit
import SwiftUI
import AnchorShared

/// Owns the `NSStatusItem` in the menu bar.
///
/// Renders state via the shield glyph:
///   .unarmed → SF Symbol "shield"
///   .armed   → "shield.fill"
///   .grace   → "shield.fill" with a pulse animation (TODO)
///   .alarm   → "shield.lefthalf.filled.badge.exclamationmark"
@MainActor
final class MenuBarController {

    private let item: NSStatusItem
    private var currentState: AnchorState = .unarmed {
        didSet { stateBox.state = currentState }
    }
    private var currentMode: AnchorMode = .normal
    private let helperManager: HelperManager?
    private let helperClient: HelperClient?

    /// Holds the state value that drives the SwiftUI MenubarShield. Wrapping
    /// in an `ObservableObject` lets us push updates into the hosted view
    /// without recreating the NSHostingView on every state change.
    private let stateBox: ShieldStateBox
    private var hostingView: NSHostingView<AnyView>?

    init(
        helperManager: HelperManager? = nil,
        helperClient: HelperClient? = nil
    ) {
        self.helperManager = helperManager
        self.helperClient = helperClient
        self.stateBox = ShieldStateBox()
        item = NSStatusBar.system.statusItem(withLength: 28)
        installSwiftUIShield()

        item.button?.target = self
        item.button?.action = #selector(handleClick)

        // Hook the XPC client: every snapshot push from the helper refreshes
        // our local state and re-renders the menubar shield.
        helperClient?.onSnapshot = { [weak self] snapshot in
            guard let self = self else { return }
            self.currentState = snapshot.state
            self.currentMode = snapshot.mode
            self.refresh()
        }
    }

    private func installSwiftUIShield() {
        // Host a SwiftUI view inside the menubar button so we can use the
        // animated AnchorGlyph + pulse system instead of a static
        // NSImage. ReactiveMenubarShield reads stateBox.state via
        // @EnvironmentObject, so pushing a new value into stateBox.state
        // re-renders the view automatically.
        let host = NSHostingView(
            rootView: AnyView(
                ReactiveMenubarShield()
                    .environmentObject(stateBox)
            )
        )
        host.translatesAutoresizingMaskIntoConstraints = false
        if let button = item.button {
            button.subviews.forEach { $0.removeFromSuperview() }
            button.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                host.topAnchor.constraint(equalTo: button.topAnchor),
                host.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
            // Hide the default button image — our SwiftUI view is the visual.
            button.image = nil
        }
        hostingView = host
    }

    @objc private func handleClick() {
        let menu = NSMenu()

        let header = NSMenuItem(
            title: "Anchor — \(currentState.rawValue) (mode: \(currentMode.displayName))",
            action: nil, keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)

        if let helperManager = helperManager {
            let helperRow = NSMenuItem(title: "Helper: \(helperManager.statusLabel)", action: nil, keyEquivalent: "")
            helperRow.isEnabled = false
            menu.addItem(helperRow)

            if helperManager.status == .requiresApproval {
                let approve = NSMenuItem(title: "Approve in System Settings…",
                                         action: #selector(openHelperApproval),
                                         keyEquivalent: "")
                approve.target = self
                menu.addItem(approve)
            }
        }

        menu.addItem(.separator())

        let armItem = NSMenuItem(
            title: currentState == .unarmed ? "Arm now" : "Disarm…",
            action: #selector(toggleArm), keyEquivalent: "")
        armItem.target = self
        menu.addItem(armItem)

        menu.addItem(.separator())

        // Mode submenu.
        let modeItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu(title: "Mode")
        for mode in AnchorMode.allCases {
            let m = NSMenuItem(title: mode.displayName, action: #selector(pickMode(_:)), keyEquivalent: "")
            m.target = self
            m.representedObject = mode.rawValue
            modeMenu.addItem(m)
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        menu.addItem(.separator())

        // Show captured photos folder.
        let photosItem = NSMenuItem(title: "Show captured photos…",
                                    action: #selector(showPhotosFolder),
                                    keyEquivalent: "")
        photosItem.target = self
        menu.addItem(photosItem)

        menu.addItem(.separator())

        // Diagnostics submenu — Test alarm + Run arm demo + Simulate trigger.
        let diagItem = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
        let diagMenu = NSMenu(title: "Diagnostics")

        let test = NSMenuItem(title: "Test alarm (3 sec)",
                              action: #selector(testAlarm),
                              keyEquivalent: "")
        test.target = self
        diagMenu.addItem(test)

        let demo = NSMenuItem(title: "Run arm demo (no screen lock)",
                              action: #selector(runArmDemo),
                              keyEquivalent: "")
        demo.target = self
        demo.toolTip = "Arms without locking, then triggers a fake lid close so you can hear chirp → grace → alarm in ~12 seconds. Click 'Disarm…' to stop early."
        diagMenu.addItem(demo)

        let simulate = NSMenuItem(title: "Simulate lid-close trigger",
                                  action: #selector(simulateTrigger),
                                  keyEquivalent: "")
        simulate.target = self
        simulate.toolTip = "Only meaningful when already armed — injects a synthetic lid-close signal."
        diagMenu.addItem(simulate)

        diagItem.submenu = diagMenu
        menu.addItem(diagItem)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit Anchor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil  // detach so single-click works next time
    }

    @objc private func openHelperApproval() {
        helperManager?.openLoginItemsSettings()
    }

    @objc private func testAlarm() {
        NSLog("[MenuBar] → helper.testAlarm(3s)")
        helperClient?.testAlarm(seconds: 3.0)
    }

    @objc private func simulateTrigger() {
        NSLog("[MenuBar] → helper.simulateLidClose()")
        helperClient?.simulateLidClose()
    }

    @objc private func runArmDemo() {
        NSLog("[MenuBar] → helper.runArmDemo()")
        helperClient?.runArmDemo()
    }

    @objc private func showPhotosFolder() {
        let dir = AnchorConstants.eventsDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func toggleArm() {
        guard let client = helperClient else { return }
        if currentState == .unarmed {
            NSLog("[MenuBar] → helper.arm()")
            client.arm()
        } else {
            NSLog("[MenuBar] → helper.disarm()")
            client.disarm()
        }
    }

    @objc private func pickMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = AnchorMode(rawValue: raw) else { return }
        NSLog("[MenuBar] → helper.setMode(%@)", mode.rawValue)
        helperClient?.setMode(mode)
    }

    @objc private func openSettings() {
        if #available(macOS 14, *) {
            NSApp.activate()
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    private func refresh() {
        // The SwiftUI shield reacts to stateBox.state on its own —
        // didSet on currentState pushes the new value into stateBox.
        // Nothing else to do here for the visual.
    }
}

// MARK: - SwiftUI <-> AppKit state bridge

/// Holds the current `AnchorState`. Published so the SwiftUI MenubarShield
/// re-renders when it changes.
final class ShieldStateBox: ObservableObject {
    @Published var state: AnchorState = .unarmed
}

private struct ReactiveMenubarShield: View {
    @EnvironmentObject var box: ShieldStateBox
    var body: some View {
        MenubarShield(state: box.state)
    }
}
