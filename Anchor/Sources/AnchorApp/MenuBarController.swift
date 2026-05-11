import AppKit
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
    private var currentState: AnchorState = .unarmed
    private var currentMode: AnchorMode = .normal
    private let helperManager: HelperManager?
    private let helperClient: HelperClient?

    init(
        helperManager: HelperManager? = nil,
        helperClient: HelperClient? = nil
    ) {
        self.helperManager = helperManager
        self.helperClient = helperClient
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refresh()

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

        // Diagnostics submenu — Test alarm + Simulate trigger.
        let diagItem = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
        let diagMenu = NSMenu(title: "Diagnostics")
        let test = NSMenuItem(title: "Test alarm (3 sec)",
                              action: #selector(testAlarm),
                              keyEquivalent: "")
        test.target = self
        diagMenu.addItem(test)
        let simulate = NSMenuItem(title: "Simulate lid-close trigger",
                                  action: #selector(simulateTrigger),
                                  keyEquivalent: "")
        simulate.target = self
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
        let symbol: String
        switch currentState {
        case .unarmed: symbol = "shield"
        case .armed:   symbol = "shield.fill"
        case .grace:   symbol = "shield.fill"
        case .alarm:   symbol = "shield.lefthalf.filled.badge.exclamationmark"
        }
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Anchor")
    }
}
