import AppKit
import SwiftUI
import VakterShared

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
    private var currentState: VakterState = .unarmed {
        didSet { stateBox.state = currentState }
    }
    private var currentMode: VakterMode = .normal
    /// Most-recent event from the helper's snapshot. Powers the "Last
    /// event" preview row at the bottom of the menubar dropdown.
    private var currentLastEvent: VakterEvent?
    private let helperManager: HelperManager?
    private let helperClient: HelperClient?

    /// Closure that opens the Settings window. Injected from AppDelegate
    /// because SwiftUI's `Settings` scene doesn't reliably open from
    /// LSUIElement=true apps — we manage our own NSWindow instead.
    private let onShowSettings: () -> Void

    /// Holds the state value that drives the SwiftUI MenubarShield. Wrapping
    /// in an `ObservableObject` lets us push updates into the hosted view
    /// without recreating the NSHostingView on every state change.
    ///
    /// Exposed so AppDelegate can pass the same instance into the Settings
    /// window's SwiftUI hierarchy — keeps the sidebar brand-mark animation
    /// in lockstep with the menubar shield.
    let stateBox: ShieldStateBox
    private var hostingView: NSHostingView<AnyView>?

    /// Drives the signature "On watch" arming overlay window. Lives on
    /// the controller so it survives across multiple arms.
    private let armingOverlay = ArmingOverlayController()

    /// Controller for the dedicated "About Vakter" window. Reused
    /// across opens so we don't stack windows.
    private let aboutWindow = AboutWindowController()

    /// Optional Pareto-style defenses scheduler; if injected the
    /// dropdown grows a category-grouped submenu set sourced from
    /// its most-recent checklist.
    private weak var defensesScheduler: DefensesScheduler?

    init(
        helperManager: HelperManager? = nil,
        helperClient: HelperClient? = nil,
        defensesScheduler: DefensesScheduler? = nil,
        onShowSettings: @escaping () -> Void = {}
    ) {
        self.helperManager = helperManager
        self.helperClient = helperClient
        self.defensesScheduler = defensesScheduler
        self.onShowSettings = onShowSettings
        self.stateBox = ShieldStateBox()
        item = NSStatusBar.system.statusItem(withLength: 28)
        installSwiftUIShield()

        item.button?.target = self
        item.button?.action = #selector(handleClick)
        // VoiceOver: the SwiftUI shield ignores its children for a11y
        // and exposes its own label, but the NSStatusItem button is
        // the actual focus target. Give it a stable label too —
        // refreshed from `refresh()` whenever state changes.
        item.button?.setAccessibilityLabel("Vakter status menu")
        item.button?.setAccessibilityRole(.menuButton)

        // Apply persisted menubar appearance (lighthouse / fake battery /
        // hidden). Re-applied on each `vakterMenubarAppearanceChanged`
        // notification posted from Settings.
        applyAppearance()
        NotificationCenter.default.addObserver(
            forName: .vakterMenubarAppearanceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The `queue: .main` parameter dispatches on main but
            // doesn't satisfy the @MainActor isolation contract in
            // Swift 6 strict-concurrency mode. Re-enter via Task.
            Task { @MainActor [weak self] in
                self?.applyAppearance()
            }
        }

        // Defenses checklist updates — purely informational here
        // because the dropdown is rebuilt on every click anyway.
        // We listen so future code (badge counts, tray badges) has
        // a hook.
        NotificationCenter.default.addObserver(
            forName: .vakterDefensesChecklistUpdated,
            object: nil,
            queue: .main
        ) { _ in
            // Reserved for future use. The next handleClick() rebuilds
            // the dropdown from scratch and will pick up the latest.
        }

        // Hook the XPC client: every snapshot push from the helper refreshes
        // our local state, re-renders the menubar shield, and (on the
        // unarmed → armed transition) shows the signature arming overlay.
        helperClient?.onSnapshot = { [weak self] snapshot in
            guard let self = self else { return }
            let previous = self.currentState
            self.currentState = snapshot.state
            self.currentMode = snapshot.mode
            self.currentLastEvent = snapshot.lastEvent
            self.refresh()

            // Signature moment: when we cross unarmed → armed, render the
            // brief "On watch" overlay. The helper has scheduled the
            // actual screen lock 0.6 s out so this overlay has room to
            // breathe before the system takes the screen.
            if previous != .armed && snapshot.state == .armed {
                Task { @MainActor in
                    self.armingOverlay.show()
                }
            }
            // If the user disarms mid-overlay (rare race) kill it cleanly.
            if previous == .armed && snapshot.state == .unarmed {
                Task { @MainActor in
                    self.armingOverlay.dismissImmediately()
                }
            }
        }
    }

    private func installSwiftUIShield() {
        // Host a SwiftUI view inside the menubar button so we can use the
        // animated VakterGlyph + pulse system instead of a static
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

        // ── Header ─────────────────────────────────────────────────
        // Two-line attributed title à la Bartender / Things 3: the
        // first line is "Vakter" in semibold, the second is a
        // humanised status sentence in secondary colour with a
        // status-tinted dot. Reads at a glance.
        let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = makeHeaderTitle()
        menu.addItem(header)

        if let helperManager = helperManager {
            // Only show the helper row when it's NOT happy — a green
            // "Helper: Running" row in every dropdown is visual noise.
            // When it's anything else (loading / requires approval /
            // failed) the user needs to see it.
            if helperManager.status != .enabled {
                let helperRow = NSMenuItem(
                    title: "Helper: \(helperManager.statusLabel)",
                    action: nil,
                    keyEquivalent: ""
                )
                helperRow.isEnabled = false
                helperRow.image = NSImage(
                    systemSymbolName: "exclamationmark.triangle.fill",
                    accessibilityDescription: nil
                )?.tinted(with: NSColor.systemOrange)
                menu.addItem(helperRow)
            }

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
        for mode in VakterMode.allCases {
            let m = NSMenuItem(title: mode.displayName, action: #selector(pickMode(_:)), keyEquivalent: "")
            m.target = self
            m.representedObject = mode.rawValue
            modeMenu.addItem(m)
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        menu.addItem(.separator())

        // ── Pareto-style security checklist ──────────────────────────
        // Each category becomes a submenu; each check inside it is a
        // disabled row (informational) with an SF Symbol that turns
        // red/amber/green based on its status. Clicking a check opens
        // the System Settings deep-link if one exists.
        if let scheduler = defensesScheduler {
            appendSecurityChecks(to: menu, scheduler: scheduler)
            menu.addItem(.separator())
        }

        // Show captured photos folder.
        let photosItem = NSMenuItem(title: "Show captured photos…",
                                    action: #selector(showPhotosFolder),
                                    keyEquivalent: "")
        photosItem.target = self
        menu.addItem(photosItem)

        // Police-ready PDF evidence report. Generates a single-page PDF
        // covering the last 30 events with a tamper-evidence summary,
        // suitable to hand to law enforcement or an insurance adjuster.
        let reportItem = NSMenuItem(title: "Export incident report (PDF)\u{2026}",
                                    action: #selector(exportEvidenceReport),
                                    keyEquivalent: "")
        reportItem.target = self
        reportItem.toolTip = "Generates a tamper-evident PDF of the last 30 events, signed with the Vakter event chain. Suitable for law enforcement or insurance."
        menu.addItem(reportItem)

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

        let about = NSMenuItem(title: "About Vakter", action: #selector(openAboutWindow), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit Vakter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        // ── Last event preview row ────────────────────────────────
        // Bottom of the dropdown — at-a-glance "did anything happen
        // while I was away." Renders nothing on first launch when
        // there's no event yet. Lives inside a SwiftUI NSHostingView
        // so we can use VakterDesign tokens directly.
        if let lastEvent = currentLastEvent {
            menu.addItem(.separator())
            let row = NSMenuItem()
            let host = NSHostingView(rootView: LastEventMenuRow(event: lastEvent))
            host.translatesAutoresizingMaskIntoConstraints = true
            // Width 280 matches the natural menu width; AppKit auto-grows
            // if other items are wider. Height grows to fit content.
            let size = host.fittingSize
            host.frame = NSRect(x: 0, y: 0, width: 280, height: size.height)
            row.view = host
            row.isEnabled = false
            menu.addItem(row)
        }

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
        let dir = VakterConstants.eventsDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func exportEvidenceReport() {
        // Read the last 30 events (newest first) and reverse to get
        // chronological order, which is what EventChain.verify expects.
        let events = EventLogStore.shared.recent(limit: 30).reversed().map { $0 }
        let input = EvidenceReport.Input.from(events: events)

        let panel = NSSavePanel()
        panel.title = "Save Incident Report"
        panel.nameFieldStringValue = "vakter-incident-\(timestampForFilename()).pdf"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if let out = EvidenceReport.render(input, to: url) {
                NSWorkspace.shared.activateFileViewerSelecting([out])
            } else {
                let alert = NSAlert()
                alert.messageText = "Couldn't generate the report"
                alert.informativeText = "Please try again, or report this in Settings → About → Send diagnostics."
                alert.runModal()
            }
        }
    }

    /// Filename-safe ISO timestamp.
    private func timestampForFilename() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return f.string(from: Date())
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
              let mode = VakterMode(rawValue: raw) else { return }
        NSLog("[MenuBar] → helper.setMode(%@)", mode.rawValue)
        helperClient?.setMode(mode)
    }

    @objc private func openSettings() {
        onShowSettings()
    }

    @objc private func openAboutWindow() {
        aboutWindow.show()
    }

    // MARK: - Pareto-style security checks
    //
    // Renders the 5-category checklist as nested submenus on the
    // menubar dropdown, mirroring the standard Pareto Security UX.
    // Click-through on a row opens the relevant System Settings pane
    // when the underlying `DefenseItem` has a remediation URL.

    private func appendSecurityChecks(to menu: NSMenu,
                                      scheduler: DefensesScheduler) {
        guard let checklist = scheduler.checklist else {
            // First-launch — scheduler hasn't completed its initial run
            // yet. Show a placeholder row so the dropdown isn't empty.
            let pending = NSMenuItem(title: "Security checks running…",
                                     action: nil, keyEquivalent: "")
            pending.isEnabled = false
            menu.addItem(pending)
            return
        }

        for (category, items) in checklist.byCategory {
            let parent = NSMenuItem(title: category.displayName,
                                    action: nil, keyEquivalent: "")
            parent.image = NSImage(
                systemSymbolName: iconForStatus(checklist.worstStatus(in: category)),
                accessibilityDescription: nil
            )?.tinted(with: tintForStatus(checklist.worstStatus(in: category)))

            let sub = NSMenu(title: category.displayName)
            for item in items {
                let row = NSMenuItem(title: item.title,
                                     action: item.remediationURLString != nil
                                        ? #selector(openRemediation(_:))
                                        : nil,
                                     keyEquivalent: "")
                row.target = self
                row.representedObject = item.remediationURLString
                row.toolTip = item.detail
                row.image = NSImage(
                    systemSymbolName: item.status.icon,
                    accessibilityDescription: nil
                )?.tinted(with: tintForStatus(item.status))
                sub.addItem(row)
            }
            parent.submenu = sub
            menu.addItem(parent)
        }

        // Footer: "Last check 49 min ago" + Run Checks (⌘R).
        let lastRunRow = NSMenuItem(
            title: "Last check \(checklist.relativeRunLabel())",
            action: nil, keyEquivalent: "")
        lastRunRow.isEnabled = false
        menu.addItem(lastRunRow)

        let runNow = NSMenuItem(title: "Run Checks",
                                action: #selector(runChecksNow),
                                keyEquivalent: "r")
        runNow.target = self
        runNow.isEnabled = !scheduler.isRunning
        menu.addItem(runNow)
    }

    @objc private func openRemediation(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func runChecksNow() {
        defensesScheduler?.runNow()
    }

    private func iconForStatus(_ s: DefenseStatus) -> String { s.icon }

    private func tintForStatus(_ s: DefenseStatus) -> NSColor {
        switch s.tone {
        case .healthy:   return NSColor.systemGreen
        case .warning:   return NSColor.systemOrange
        case .attention: return NSColor.systemRed
        case .neutral:   return NSColor.secondaryLabelColor
        }
    }

    private func refresh() {
        // The SwiftUI shield reacts to stateBox.state on its own —
        // didSet on currentState pushes the new value into stateBox.
        // Update the NSStatusItem button's a11y label so VoiceOver
        // announces the current state when the icon is focused.
        item.button?.setAccessibilityLabel(
            "Vakter, \(humanStateLabel().lowercased()), \(currentMode.displayName) mode"
        )
    }

    // MARK: - Header attributed string

    /// Builds the two-line header for the menubar dropdown:
    ///   Line 1 (semibold 13pt, label):     "Vakter"
    ///   Line 2 (regular 11pt, secondary):  "• On watch · Travel mode"
    ///
    /// The dot is tinted by current state so the user can read the
    /// dropdown's status in their peripheral vision.
    private func makeHeaderTitle() -> NSAttributedString {
        let result = NSMutableAttributedString()

        // Line 1: wordmark
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        result.append(NSAttributedString(string: "Vakter\n", attributes: titleAttrs))

        // Line 2: status dot + sentence
        let dotAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: statusDotColor()
        ]
        result.append(NSAttributedString(string: "● ", attributes: dotAttrs))

        let statusAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        result.append(NSAttributedString(
            string: "\(humanStateLabel()) · \(currentMode.displayName) mode",
            attributes: statusAttrs
        ))

        return result
    }

    private func humanStateLabel() -> String {
        switch currentState {
        case .unarmed: return "Off watch"
        case .armed:   return "On watch"
        case .grace:   return "Grace period"
        case .alarm:   return "Alarm engaged"
        }
    }

    private func statusDotColor() -> NSColor {
        switch currentState {
        case .unarmed: return NSColor.tertiaryLabelColor
        case .armed:   return NSColor.systemGreen
        case .grace:   return NSColor.systemOrange
        case .alarm:   return NSColor.systemRed
        }
    }

    /// Re-read `MenubarAppearanceStore` and update the icon + visibility
    /// accordingly. Called both at controller construction and whenever
    /// the user picks a new appearance in Settings (via a notification).
    func applyAppearance() {
        let appearance = MenubarAppearanceStore.load()
        switch appearance {
        case .hidden:
            item.isVisible = false
            NSLog("[MenuBarController] appearance = hidden (icon removed)")

        case .fakeBattery:
            item.isVisible = true
            // Tear down the SwiftUI lighthouse and show a stock battery
            // SF symbol so casual observers read it as the system widget.
            hostingView?.removeFromSuperview()
            hostingView = nil
            if let button = item.button {
                button.image = NSImage(
                    systemSymbolName: "battery.75",
                    accessibilityDescription: nil
                )
                button.image?.isTemplate = true
            }
            NSLog("[MenuBarController] appearance = fakeBattery")

        case .lighthouse:
            item.isVisible = true
            if hostingView == nil {
                installSwiftUIShield()
            }
            NSLog("[MenuBarController] appearance = lighthouse")
        }
    }
}

/// Notification posted when the user changes Vakter's menubar appearance
/// in Settings. `MenuBarController` observes this and re-renders.
public extension Notification.Name {
    static let vakterMenubarAppearanceChanged =
        Notification.Name("app.vakter.menubarAppearanceChanged")
}

// MARK: - SwiftUI <-> AppKit state bridge

/// Holds the current `VakterState`. Published so the SwiftUI MenubarShield
/// re-renders when it changes.
final class ShieldStateBox: ObservableObject {
    @Published var state: VakterState = .unarmed
}

private struct ReactiveMenubarShield: View {
    @EnvironmentObject var box: ShieldStateBox
    var body: some View {
        MenubarShield(state: box.state)
    }
}

// MARK: - Last event menu row (SwiftUI hosted in the dropdown)

/// Renders a two-line "Last event" preview at the bottom of the menubar
/// dropdown. Two columns: transition + meta on the left, timestamp on
/// the right. Matches the spec in `Website/concepts/index.html § 02`.
///
/// All state is captured at construction time — the menu rebuilds on
/// every click, so we don't need this view to be observably reactive.
private struct LastEventMenuRow: View {
    let event: VakterEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Last event")
                    .font(.system(size: 9.5, weight: .semibold).monospaced())
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)

                Text(transitionTitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)

                if !metaLine.isEmpty {
                    Text(metaLine)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(timeStamp)
                    .font(.system(size: 10, weight: .regular).monospaced())
                    .foregroundStyle(.secondary)
                Text(dayStamp)
                    .font(.system(size: 9, weight: .regular).monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: derived strings

    /// "Grace → Alarm", "Armed → Unarmed", etc.
    private var transitionTitle: String {
        "\(humanState(event.fromState)) → \(humanState(event.toState))"
    }

    private func humanState(_ s: VakterState) -> String {
        switch s {
        case .unarmed: return "Off"
        case .armed:   return "Armed"
        case .grace:   return "Grace"
        case .alarm:   return "Alarm"
        }
    }

    /// "3 photos · 10 s audio · lid close" — only the non-empty bits.
    private var metaLine: String {
        var bits: [String] = []
        let photos = event.photoFilenames.count
        let audio = event.audioFilenames?.count ?? 0
        if photos > 0 { bits.append("\(photos) photo\(photos == 1 ? "" : "s")") }
        if audio > 0 { bits.append("\(audio) audio") }
        if let trig = event.trigger {
            bits.append(triggerLabel(trig))
        }
        return bits.joined(separator: " · ")
    }

    private func triggerLabel(_ t: VakterTrigger) -> String {
        switch t {
        case .lidClose: return "lid close"
        case .powerDisconnect: return "unplug"
        case .bluetoothPeerLeft: return "BT left"
        case .powerButtonBriefPress: return "power tap"
        case .findMyCleared: return "Find My cleared"
        case .appleIDChanged: return "Apple ID change"
        case .userAction: return "manual"
        }
    }

    private var timeStamp: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: event.timestamp)
    }

    private var dayStamp: String {
        let cal = Calendar.current
        if cal.isDateInToday(event.timestamp) { return "today" }
        if cal.isDateInYesterday(event.timestamp) { return "yesterday" }
        let f = DateFormatter()
        f.dateFormat = "dd MMM"
        return f.string(from: event.timestamp).lowercased()
    }
}

// MARK: - NSImage tint helper

private extension NSImage {
    /// Returns a copy of the receiver tinted with `color`. Used to give
    /// each security-check row the green/amber/red SF Symbol that
    /// matches its status — AppKit menus don't honour SwiftUI's
    /// `.foregroundStyle()` on `Image(systemName:)`, so we do it the
    /// AppKit way (draw the symbol into a fresh image with the tint
    /// blended via `.sourceIn`).
    func tinted(with color: NSColor) -> NSImage {
        let tinted = NSImage(size: self.size, flipped: false) { rect -> Bool in
            color.set()
            rect.fill()
            self.draw(in: rect,
                      from: .zero,
                      operation: .destinationIn,
                      fraction: 1.0)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }
}
