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
    private let helperManager: HelperManager?

    init(helperManager: HelperManager? = nil) {
        self.helperManager = helperManager
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refresh()

        item.button?.target = self
        item.button?.action = #selector(handleClick)

        // TODO(week-3): subscribe to helper-daemon snapshots via XPC and
        // update `currentState` + refresh on changes.
    }

    @objc private func handleClick() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Anchor — \(currentState.rawValue)", action: nil, keyEquivalent: "")
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

    @objc private func toggleArm() {
        // TODO(week-3): wire to helper XPC.
        NSLog("[MenuBar] arm/disarm clicked (XPC not yet wired)")
    }

    @objc private func pickMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = AnchorMode(rawValue: raw) else { return }
        NSLog("[MenuBar] mode picked: %@", mode.rawValue)
        // TODO(week-3): tell helper.
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
