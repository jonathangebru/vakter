import SwiftUI
import AppKit
import VakterShared

/// Thin SwiftUI wrapper around `NSVisualEffectView` so we get the
/// real macOS sidebar vibrancy material that System Settings uses.
/// `Color(nsColor: .underPageBackgroundColor)` reads as a flat fill —
/// this gives us the actual blur + translucency.
struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .followsWindowActiveState
        v.isEmphasized = true
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Root of the Settings window — calm-protector design.
///
/// Layout: a sidebar with sections + a content area. Different from
/// macOS's default tab style, more in keeping with the brand: it should
/// feel composed and quiet, not panel-y.
struct SettingsRoot: View {

    enum Section: String, CaseIterable, Identifiable {
        case general       = "General"
        case shortcut      = "Shortcut"
        case modes         = "Modes"
        case sound         = "Sound"
        case bluetooth     = "Trusted Devices"
        case defenses      = "Defenses"
        case autoArm       = "Auto-arm & Cloud"
        case notifications = "Notifications"
        case privacy       = "Privacy"
        case eventLog      = "Event Log"
        case about         = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general:       return "gearshape.fill"
            case .shortcut:      return "command.circle.fill"
            case .modes:         return "square.stack.3d.up.fill"
            case .sound:         return "speaker.wave.3.fill"
            case .bluetooth:     return "antenna.radiowaves.left.and.right"
            case .defenses:      return "checkmark.shield.fill"
            case .autoArm:       return "location.fill.viewfinder"
            case .notifications: return "bell.badge.fill"
            case .privacy:       return "eye.slash.fill"
            case .eventLog:      return "clock.fill"
            case .about:         return "info.circle.fill"
            }
        }

        /// Tile tint — each tab gets its own colour, the way System
        /// Settings does (Network blue, Privacy red, General grey…).
        /// Pulled from the standard macOS sidebar palette.
        var iconTint: Color {
            switch self {
            case .general:       return Color(nsColor: .systemGray)
            case .shortcut:      return Color(nsColor: .systemPurple)
            case .modes:         return Color(nsColor: .systemTeal)
            case .sound:         return Color(nsColor: .systemPink)
            case .bluetooth:     return Color(nsColor: .systemBlue)
            case .defenses:      return Color(nsColor: .systemGreen)
            case .autoArm:       return Color(nsColor: .systemYellow)
            case .notifications: return Color(nsColor: .systemOrange)
            case .privacy:       return Color(nsColor: .systemIndigo)
            case .eventLog:      return Color(nsColor: .systemBrown)
            case .about:         return Color(nsColor: .systemBlue)
            }
        }

        /// Foreground colour for the icon glyph when the row ISN'T
        /// selected (selection state uses `.white` on a solid tile).
        /// In unselected state the icon sits on a 16 %-tint fill, so
        /// the glyph itself stays the full tint colour for legibility.
        var iconForeground: Color { iconTint }
    }

    @State private var selected: Section = .general

    /// Same observable that drives the menubar shield. AppDelegate
    /// injects it via `.environmentObject(menuBarController.stateBox)`
    /// so the Settings sidebar's brand mark animates in lockstep with
    /// the menubar shield.
    @EnvironmentObject var shieldBox: ShieldStateBox

    /// XPC client injected by AppDelegate when the Settings window opens.
    /// Replaces the old `NSApp.delegate as? AppDelegate` cast which
    /// silently returned nil when SettingsRoot was hosted inside an
    /// `NSHostingController`, breaking every Settings → helper call
    /// (test-alarm preview, mode picker, hotkey rebind, Bluetooth pair).
    @EnvironmentObject var helperClient: HelperClient

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            contentArea
        }
        .frame(minWidth: 760, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // Pull a fresh snapshot from the helper the moment the
            // window opens — otherwise the sidebar shield can briefly
            // show stale state if Settings is launched while the XPC
            // connection is still spinning up.
            helperClient.requestSnapshotNow()
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand header — live menubar shield + wordmark + state pill.
            // Tight padding, single-line, no decorative grace beyond that.
            // Matches the System Settings header pattern: identity at
            // the top of the sidebar, with state info on the right.
            HStack(spacing: VakterDesign.spacingS) {
                MenubarShield(state: shieldBox.state)
                    .frame(width: 22, height: 22)
                Text("Vakter")
                    .font(.system(size: 16, weight: .semibold))
                Spacer(minLength: 4)
                stateBadge
            }
            .padding(.horizontal, VakterDesign.spacingM)
            .padding(.top, VakterDesign.spacingM)
            .padding(.bottom, VakterDesign.spacingS)

            Divider().padding(.horizontal, VakterDesign.spacingS).padding(.bottom, VakterDesign.spacingS)

            // Sidebar rows — single flat list, native System-Settings look.
            // No nested headers, no status card (it lived here pre-v1.2 and
            // read as overcrowded against Apple's "one purpose per surface"
            // pattern; the same data now lives in the Defenses tab).
            VStack(spacing: 1) {
                ForEach(Section.allCases) { section in
                    sidebarRow(section)
                }
            }
            .padding(.horizontal, VakterDesign.spacingS)

            Spacer()

            // Footer — etymology tagline, kept as a small brand signature
            // in the spirit of "Designed by Apple in California" on the
            // About screen.
            VStack(alignment: .leading, spacing: 2) {
                Text("Vakter")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Norwegian \u{2014} \u{201C}the night-watchmen\u{201D}")
                    .font(VakterDesign.captionFont)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, VakterDesign.spacingM)
            .padding(.bottom, VakterDesign.spacingM)
        }
        .frame(width: 204)
        .background(
            // Real vibrant sidebar material — same blur Apple uses in
            // every System Settings pane. Falls back to a solid fill
            // when the window is inactive (vibrancyEnabled = false).
            VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
        )
    }

    /// A tiny tinted pill that reads the current state — calm when
    /// unarmed, watching when armed, urgent when grace/alarm.
    private var stateBadge: some View {
        let (label, tone): (String, VakterStatusPill.Tone) = {
            switch shieldBox.state {
            case .unarmed: return ("idle",    .neutral)
            case .armed:   return ("on watch", .watching)
            case .grace:   return ("grace",   .attention)
            case .alarm:   return ("ALARM",   .attention)
            }
        }()
        return VakterStatusPill(label, tone: tone)
            .font(.system(size: 9))
            .scaleEffect(0.8, anchor: .trailing)
    }

    private func sidebarRow(_ section: Section) -> some View {
        let isSelected = selected == section
        return Button(action: { selected = section }) {
            HStack(spacing: 10) {
                // Each icon sits in a soft rounded-square "tile" — the
                // System Settings sidebar pattern (App Store, Music,
                // etc.). When selected, the tile becomes solid system-
                // accent; when not, it's a subtle fill of the same hue.
                Image(systemName: section.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : section.iconForeground)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isSelected
                                  ? section.iconTint
                                  : section.iconTint.opacity(0.16))
                    )

                Text(section.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected
                          ? Color.primary.opacity(0.08)
                          : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(section.rawValue) settings")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Content

    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VakterDesign.spacingL) {
                switch selected {
                case .general:       GeneralTab()
                case .shortcut:      ShortcutTab()
                case .modes:         ModesTab()
                case .sound:         SoundTab()
                case .bluetooth:     BluetoothTab()
                case .defenses:      DefensesTab()
                case .autoArm:       AutoArmAndCloudTab()
                case .notifications: NotificationsTab()
                case .privacy:       PrivacyTab()
                case .eventLog:      EventLogView()
                case .about:         AboutTab()
                }
            }
            .padding(VakterDesign.spacingXL)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Sidebar Today status card

/// Compact status block in the sidebar. Shows a live snapshot of the
/// user's posture without sending them deeper into Settings — sparkline
/// of recent Defenses scores, count of this-week's events, time-ago of
/// the last arm. Tappable rows jump to the matching Settings tab.
private struct SidebarStatusCard: View {

    let onTapScore: () -> Void
    let onTapEvents: () -> Void

    @State private var history: [DefensesScoreSample] = []
    @State private var thisWeekEvents: Int = 0
    @State private var lastArmAgo: String = "\u{2014}"

    var body: some View {
        VStack(alignment: .leading, spacing: VakterDesign.spacingS) {
            VakterEyebrow("Today")
                .padding(.horizontal, VakterDesign.spacingS)
                .padding(.top, VakterDesign.spacingXS)

            VStack(spacing: 1) {
                Button(action: onTapScore) {
                    scoreRow
                }
                .buttonStyle(.plain)

                Button(action: onTapEvents) {
                    eventsRow
                }
                .buttonStyle(.plain)

                lastArmRow
            }
        }
        .padding(VakterDesign.spacingS)
        .background(
            RoundedRectangle(cornerRadius: VakterDesign.radiusM, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: VakterDesign.radiusM, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .onAppear { refresh() }
    }

    // MARK: Rows

    private var scoreRow: some View {
        HStack(spacing: VakterDesign.spacingS) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Defenses")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(history.last?.score ?? 0)")
                        .font(VakterDesign.tabularLarge)
                        .foregroundStyle(VakterDesign.anchor)
                    Text("/100")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if history.count >= 2 {
                MiniSparkline(samples: history)
                    .frame(width: 52, height: 22)
            }
        }
        .padding(.horizontal, VakterDesign.spacingS)
        .padding(.vertical, VakterDesign.spacingS)
        .background(
            RoundedRectangle(cornerRadius: VakterDesign.radiusS, style: .continuous)
                .fill(Color.clear)
        )
        .contentShape(Rectangle())
    }

    private var eventsRow: some View {
        HStack(spacing: VakterDesign.spacingS) {
            VStack(alignment: .leading, spacing: 2) {
                Text("This week")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(thisWeekEvents)")
                        .font(VakterDesign.tabularLarge)
                        .foregroundStyle(.primary)
                    Text("events")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "clock")
                .foregroundStyle(.tertiary)
                .font(.system(size: 14))
        }
        .padding(.horizontal, VakterDesign.spacingS)
        .padding(.vertical, VakterDesign.spacingS)
        .contentShape(Rectangle())
    }

    private var lastArmRow: some View {
        HStack {
            Text("Last arm")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(lastArmAgo)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, VakterDesign.spacingS)
        .padding(.vertical, VakterDesign.spacingS)
    }

    // MARK: Data refresh

    private func refresh() {
        history = DefensesScoreHistory.load()
        let events = EventLogStore.shared.recent(limit: 200)
        let oneWeekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        thisWeekEvents = events.filter { $0.timestamp >= oneWeekAgo }.count

        if let last = events.first(where: { $0.toState == .armed }) {
            lastArmAgo = relativeAgo(last.timestamp)
        } else {
            lastArmAgo = "\u{2014}"
        }
    }

    private func relativeAgo(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

/// A small inline sparkline tuned for the sidebar status card —
/// renders the line + a single highlighted dot at the latest sample.
/// Stripped-down sibling of the bigger `Sparkline` used in DefensesTab.
private struct MiniSparkline: View {

    let samples: [DefensesScoreSample]

    var body: some View {
        GeometryReader { geo in
            let scores = samples.map { Double($0.score) }
            let maxVal = max(scores.max() ?? 100, 100.0)
            let minVal = min(scores.min() ?? 0,   0.0)
            let range  = max(maxVal - minVal, 1.0)

            let points: [CGPoint] = scores.enumerated().map { idx, val in
                let x = scores.count == 1 ? geo.size.width / 2 :
                    geo.size.width * CGFloat(idx) / CGFloat(scores.count - 1)
                let y = geo.size.height * (1.0 - CGFloat((val - minVal) / range))
                return CGPoint(x: x, y: y)
            }

            ZStack {
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: first)
                    for pt in points.dropFirst() {
                        p.addLine(to: pt)
                    }
                }
                .stroke(VakterDesign.anchor.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                if let last = points.last {
                    Circle()
                        .fill(VakterDesign.anchor)
                        .frame(width: 4, height: 4)
                        .position(last)
                }
            }
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @State private var graceSeconds: Double = GraceSettingsStore.load().seconds

    var body: some View {
        Text("General")
            .font(VakterDesign.titleFont)

        VakterCard(
            title: "Grace window",
            subtitle: "How long Vakter waits after a trigger before the alarm fires. Short for fast deterrence, longer if you sometimes need a moment to come back and disarm."
        ) {
            VStack(alignment: .leading, spacing: VakterDesign.spacingM) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(graceSeconds.rounded()))")
                        .font(VakterDesign.titleFont.monospaced())
                        .foregroundStyle(VakterDesign.anchor)
                    Text("seconds")
                        .font(VakterDesign.bodyFont)
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: $graceSeconds,
                    in: GraceSettings.minSeconds...GraceSettings.maxSeconds,
                    step: 1
                ) {
                    Text("Grace seconds")
                } minimumValueLabel: {
                    Text("\(Int(GraceSettings.minSeconds))s")
                        .font(VakterDesign.captionFont)
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("\(Int(GraceSettings.maxSeconds))s")
                        .font(VakterDesign.captionFont)
                        .foregroundStyle(.secondary)
                }
                .tint(VakterDesign.anchor)
                .onChange(of: graceSeconds) { _, new in
                    GraceSettingsStore.save(GraceSettings(seconds: new.rounded()))
                }

                // Preset quick-pick
                HStack(spacing: VakterDesign.spacingS) {
                    ForEach([3, 5, 8, 12, 20], id: \.self) { preset in
                        Button(action: {
                            graceSeconds = Double(preset)
                            GraceSettingsStore.save(GraceSettings(seconds: Double(preset)))
                        }) {
                            Text("\(preset)s")
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(
                                    Capsule().fill(
                                        Int(graceSeconds.rounded()) == preset ?
                                            VakterDesign.anchor.opacity(0.15) :
                                            Color.primary.opacity(0.06)
                                    )
                                )
                                .foregroundStyle(
                                    Int(graceSeconds.rounded()) == preset ?
                                        VakterDesign.anchor : .primary
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        VakterCard(
            title: "Launch at login",
            subtitle: "Vakter's background helper and privileged daemon are managed via macOS Login Items. Open the system pane to review them."
        ) {
            HStack {
                Button("Open Login Items…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                Spacer()
            }
        }
    }
}

// MARK: - Shortcut

private struct ShortcutTab: View {
    @EnvironmentObject var helperClient: HelperClient
    @State private var binding: HotkeyBinding = HotkeyStore.load()

    var body: some View {
        Text("Arming Shortcut")
            .font(VakterDesign.titleFont)

        VakterCard(
            title: "Press this combo anywhere",
            subtitle: "When you press the shortcut, Vakter locks your Mac and arms the alarm in one motion. Pick something with at least one modifier (⌘, ⌃, ⌥, ⇧) so it doesn't fire while typing."
        ) {
            KeyRecorder(binding: $binding, onChange: { newBinding in
                HotkeyStore.save(newBinding)
                helperClient.reloadHotkey()
            })

            HStack {
                Button {
                    binding = .default
                    HotkeyStore.save(.default)
                    helperClient.reloadHotkey()
                } label: {
                    Label("Restore default", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                Spacer()
                VakterStatusPill("Default: \(HotkeyBinding.default.displayLabel)",
                                 tone: .neutral, icon: "info.circle")
            }
        }
    }
}

// MARK: - Modes

private struct ModesTab: View {

    @EnvironmentObject var helperClient: HelperClient
    @State private var activeMode: VakterMode = ActiveModeStore.load()

    /// Modes laid out from calm to fierce — this is the order on the
    /// concepts-page spectrum, NOT the persistence rawValue order.
    private let spectrum: [VakterMode] = [.loaner, .library, .normal, .cafe, .travel]

    /// 1 = most calm, 5 = most fierce. Drives the intensity pip bar
    /// on each card.
    private func intensity(_ mode: VakterMode) -> Int {
        switch mode {
        case .loaner:  return 2
        case .library: return 2
        case .normal:  return 3
        case .cafe:    return 4
        case .travel:  return 5
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Modes")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.6)
                Text("Five tempers, one watch. Each mode adjusts grace, audibility, and what counts as a trigger. Tap a card to switch — the helper picks it up immediately.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .frame(maxWidth: 640, alignment: .leading)
            }

            // Spectrum label row
            HStack(spacing: 14) {
                Text("CALM")
                    .font(.system(size: 10, weight: .semibold).monospaced())
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.primary.opacity(0.1), VakterDesign.lantern],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                Text("FIERCE")
                    .font(.system(size: 10, weight: .semibold).monospaced())
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 4)

            // Spectrum of mode cards
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(spectrum, id: \.self) { mode in
                    modeCard(mode)
                }
            }
        }
    }

    private func modeCard(_ mode: VakterMode) -> some View {
        let p = ModeParameters.parameters(for: mode)
        let selected = activeMode == mode
        let intens = intensity(mode)

        return Button(action: { pick(mode) }) {
            VStack(alignment: .leading, spacing: 10) {
                // Intensity pip bar (5 cells, lit per mode)
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { i in
                        Rectangle()
                            .fill(i < intens ? VakterDesign.lantern : Color.primary.opacity(0.1))
                            .frame(height: 3)
                            .cornerRadius(2)
                            .shadow(color: i < intens ? VakterDesign.lantern.opacity(0.5) : .clear,
                                    radius: 3)
                    }
                }

                // Mode label
                Text(mode.displayName.uppercased())
                    .font(.system(size: 9.5, weight: .semibold).monospaced())
                    .tracking(1.2)
                    .foregroundStyle(VakterDesign.lantern)

                // Display name (the "human" word for the mode)
                Text(temperWord(mode))
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(.primary)

                Text(mode.blurb)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                // Specs row
                Text(specsLine(mode, params: p))
                    .font(.system(size: 9.5).monospaced())
                    .tracking(0.4)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)

                // Selection indicator
                HStack {
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(VakterDesign.lantern)
                    } else {
                        Image(systemName: "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.primary.opacity(0.18))
                    }
                }
            }
            .padding(14)
            .frame(minHeight: 200, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected
                          ? VakterDesign.lantern.opacity(0.06)
                          : Color.primary.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        selected ? VakterDesign.lantern.opacity(0.4) : Color.primary.opacity(0.08),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mode.displayName) mode. \(mode.blurb)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func pick(_ mode: VakterMode) {
        guard mode != activeMode else { return }
        activeMode = mode
        ActiveModeStore.save(mode)
        helperClient.setMode(mode)
        NSLog("[Settings] active mode -> %@", mode.rawValue)
    }

    /// The brand-voice noun for each mode's *character* — used as the
    /// big card title, separate from the rawValue / displayName which
    /// is what the user picks in the menu.
    private func temperWord(_ mode: VakterMode) -> String {
        switch mode {
        case .loaner:  return "Forgiving"
        case .library: return "Silent"
        case .normal:  return "Everyday"
        case .cafe:    return "Considerate"
        case .travel:  return "Paranoid"
        }
    }

    private func specsLine(_ mode: VakterMode, params p: ModeParameters) -> String {
        let grace = "grace \(Int(p.graceSeconds))s"
        let audible = p.audible ? "loud" : "silent"
        let cap: String
        if let c = p.alarmCapSeconds {
            cap = "cap \(Int(c))s"
        } else {
            cap = "cap —"
        }
        return "\(grace) · \(audible) · \(cap)"
    }
}

// MARK: - Sound — v1.2 Apple-style redesign
//
// Two sections (Recorded / Synthesized), single-select inline rows
// with system-tinted icons, Preview button next to each row so the
// user can audition without leaving the row. Mirrors System Settings →
// Sound → Sound Effects layout almost exactly.

private struct SoundTab: View {

    @EnvironmentObject var helperClient: HelperClient
    @State private var selected: AlarmSound = AlarmSoundStore.load()
    @State private var previewing: AlarmSound? = nil

    /// Two sections — sample-backed first (recommended), synth second.
    private var sampleBackedSounds: [AlarmSound] {
        AlarmSound.allCases.filter { $0.isSampleBacked }
    }
    private var synthSounds: [AlarmSound] {
        AlarmSound.allCases.filter { !$0.isSampleBacked }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VakterDesign.spacingXL) {

            // Page title — System Settings style: title at top of content
            // area, no decorative card around it.
            VStack(alignment: .leading, spacing: 4) {
                Text("Sound")
                    .font(VakterDesign.titleFont)
                Text("Pick the sound Vakter plays when the alarm fires. All options run at maximum volume on the built-in speakers — only the character changes.")
                    .font(VakterDesign.bodyFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Recorded — sample-backed Sonniss alarms.
            VakterCard(
                title: "Recorded alarms",
                subtitle: "Professionally-recorded patterns. Recommended."
            ) {
                VStack(spacing: 1) {
                    ForEach(sampleBackedSounds, id: \.self) { sound in
                        soundRow(sound, isLast: sound == sampleBackedSounds.last)
                    }
                }
            }

            // Synth — locale cadences + classic synth.
            VakterCard(
                title: "Synthesised tones",
                subtitle: "Frequency-accurate emergency-vehicle cadences. Useful for locale-recognisable alarms (Japanese / European)."
            ) {
                VStack(spacing: 1) {
                    ForEach(synthSounds, id: \.self) { sound in
                        soundRow(sound, isLast: sound == synthSounds.last)
                    }
                }
            }

            // Voice cue card — informational only. The actual voice
            // plays as part of every alarm; this just shows the user
            // what they'll hear (in their locale).
            VakterCard(
                title: "Voice cue",
                subtitle: "Between siren tones Vakter speaks a phrase in your system language. Harder to ignore than a tone alone."
            ) {
                VStack(alignment: .leading, spacing: VakterDesign.spacingS) {
                    HStack(spacing: VakterDesign.spacingS) {
                        Image(systemName: "waveform.and.person.filled")
                            .foregroundStyle(VakterDesign.accent)
                            .font(.system(size: 16, weight: .semibold))
                        Text(quotedVoicePhrase)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                    }
                    .padding(VakterDesign.spacingS + 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: VakterDesign.radiusS, style: .continuous)
                            .fill(VakterDesign.accent.opacity(0.06))
                    )
                    Text("Bundled audio for 10 languages. Falls back to your installed system voice if your locale isn't included.")
                        .font(VakterDesign.captionFont)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// One alarm-sound row. Looks like a `Form` row in System Settings:
    /// tinted SF Symbol on the left, title + blurb, checkmark, preview
    /// button. Tap anywhere on the row to select; tap the preview
    /// button to audition without switching.
    private func soundRow(_ sound: AlarmSound, isLast: Bool?) -> some View {
        let isSelected = selected == sound
        let isPlaying  = previewing == sound
        return VStack(spacing: 0) {
            HStack(spacing: VakterDesign.spacingM) {
                // Tinted icon tile.
                Image(systemName: sound.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(VakterDesign.accent)
                    )
                    .opacity(isSelected ? 1.0 : 0.55)

                // Title + blurb.
                VStack(alignment: .leading, spacing: 1) {
                    Text(sound.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(sound.blurb)
                        .font(VakterDesign.captionFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: VakterDesign.spacingS)

                // Preview button — Apple sidebar-row "info" pattern.
                Button {
                    auditionPreview(sound)
                } label: {
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(isPlaying ? VakterDesign.accent : .secondary)
                }
                .buttonStyle(.plain)
                .help(isPlaying ? "Playing\u{2026}" : "Preview")
                .accessibilityLabel("Preview \(sound.displayName)")

                // Selection indicator.
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? VakterDesign.accent : Color.primary.opacity(0.18))
            }
            .contentShape(Rectangle())
            .padding(.vertical, 7)
            .padding(.horizontal, 2)
            .onTapGesture { pick(sound) }
            // VoiceOver: expose the whole row as a single button so
            // users can navigate sound options without VoiceOver
            // reading the title + blurb + checkmark as separate items.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(sound.displayName). \(sound.blurb)")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint("Selects this alarm sound")

            if isLast == false {
                Divider().padding(.leading, 38)
            }
        }
    }

    private func pick(_ sound: AlarmSound) {
        guard sound != selected else { return }
        selected = sound
        AlarmSoundStore.save(sound)
        NSLog("[Settings] alarm sound -> %@", sound.rawValue)
    }

    /// Play a 3-second preview of a specific sound regardless of which
    /// one is currently selected. The "selected" state is untouched.
    /// Uses LocalAlarmPreview which knows both the synth + sample-backed
    /// paths (the v1.1.1 bug fix).
    private func auditionPreview(_ sound: AlarmSound) {
        // Save the user's selection, temporarily switch, preview, then
        // restore. LocalAlarmPreview reads AlarmSoundStore at the moment
        // of play() — there's no way to pass an override today without
        // re-plumbing it. This temp-swap is the least-invasive shim.
        let savedSelection = AlarmSoundStore.load()
        AlarmSoundStore.save(sound)
        previewing = sound
        LocalAlarmPreview.shared.play(seconds: 3.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            AlarmSoundStore.save(savedSelection)
            if previewing == sound { previewing = nil }
        }
    }

    private var quotedVoicePhrase: String {
        // Show the phrase in the user's actual system locale so they
        // see what they'd hear during an alarm.
        let text = LocalePhrases.text(.alarmVoiceCue)
        return "\u{201C}\(text)\u{201D}"
    }
}

// MARK: - Bluetooth

private struct BluetoothTab: View {
    @EnvironmentObject var helperClient: HelperClient
    @State private var peers: [TrustedPeer] = []
    @State private var showingPairing = false

    var body: some View {
        Text("Trusted Devices")
            .font(VakterDesign.titleFont)
        Text("Pair the things you keep with you — phone, AirPods, Apple Watch. Vakter tracks whether they're in Bluetooth range so it can tell when you're near the Mac. **Pairing does not trigger the alarm.** Lid close and cable disconnect remain the real triggers; walking to the coffee counter with your phone won't wake the siren.")
            .font(VakterDesign.bodyFont)
            .foregroundStyle(.secondary)

        VakterCard(
            title: peers.isEmpty ? "No devices paired yet" : "Paired devices",
            subtitle: peers.isEmpty
                ? "Optional — pairing a phone or watch lets Vakter sense whether you're nearby, useful for future presence-aware features. You can pair up to \(TrustedPeerStore.maxCount)."
                : "Vakter senses these via Bluetooth. Presence is informational only — used for the event log and future presence-aware grace tuning, never as a direct alarm trigger."
        ) {
            VStack(spacing: VakterDesign.spacingS) {
                ForEach(peers) { peer in
                    peerRow(peer)
                }

                if peers.count < TrustedPeerStore.maxCount {
                    Button {
                        showingPairing = true
                    } label: {
                        Label("Add a device", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VakterDesign.anchor)
                    .controlSize(.large)
                }
            }
        }
        .onAppear { refreshPeers() }
        .sheet(isPresented: $showingPairing, onDismiss: { refreshPeers() }) {
            PairingSheet(onClose: { showingPairing = false })
                .frame(width: 540, height: 480)
        }
    }

    private func refreshPeers() {
        helperClient.listTrustedPeers { list in
            peers = list.sorted(by: { $0.dateAdded > $1.dateAdded })
        }
    }

    private func peerRow(_ peer: TrustedPeer) -> some View {
        HStack(spacing: VakterDesign.spacingM) {
            Image(systemName: iconFor(name: peer.displayName))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(VakterDesign.anchor)
                .frame(width: 32, height: 32)
                .background(Circle().fill(VakterDesign.anchor.opacity(0.10)))
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.displayName)
                    .font(.system(size: 14, weight: .semibold))
                Text(peer.id.uuidString.prefix(8))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                removePeer(peer)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove this device from the trusted set")
        }
        .padding(VakterDesign.spacingS)
        .background(
            RoundedRectangle(cornerRadius: VakterDesign.radiusS, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func removePeer(_ peer: TrustedPeer) {
        helperClient.removeTrustedPeer(id: peer.id) { _ in
            refreshPeers()
        }
    }

    private func iconFor(name: String) -> String {
        let n = name.lowercased()
        if n.contains("iphone")    { return "iphone" }
        if n.contains("airpods")   { return "airpods" }
        if n.contains("ipad")      { return "ipad" }
        if n.contains("watch")     { return "applewatch" }
        if n.contains("mac")       { return "macbook" }
        return "antenna.radiowaves.left.and.right"
    }
}

/// Modal that shows nearby BT devices and lets the user pick one to trust.
private struct PairingSheet: View {
    @EnvironmentObject var helperClient: HelperClient
    let onClose: () -> Void

    @State private var discoveries: [BluetoothDiscovery] = []
    @State private var pollTimer: Timer?
    @State private var pickedID: UUID?
    @State private var scanStartedAt: Date = Date()
    @State private var showingTimeoutHint: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add a trusted device")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Scanning for nearby Bluetooth devices. Pair the device with your Mac first (System Settings → Bluetooth) for the most reliable matching.")
                        .font(VakterDesign.captionFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Done", action: onClose)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
            .padding(VakterDesign.spacingL)

            Divider()

            if discoveries.isEmpty {
                VStack(spacing: VakterDesign.spacingM) {
                    ProgressView()
                        .controlSize(.large)
                    if showingTimeoutHint {
                        VStack(spacing: 4) {
                            Text("Still scanning…")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Make sure your device is powered on and discoverable in System Settings → Bluetooth. Some headphones only advertise during pairing mode.")
                                .font(VakterDesign.captionFont)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 360)
                        }
                    } else {
                        Text("Scanning…")
                            .foregroundStyle(.secondary)
                            .font(VakterDesign.bodyFont)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(discoveries) { d in
                            discoveryRow(d)
                        }
                    }
                    .padding(VakterDesign.spacingM)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            startDiscovery()
            startPolling()
        }
        .onDisappear {
            pollTimer?.invalidate()
            helperClient.stopBluetoothDiscovery()
        }
    }

    private func discoveryRow(_ d: BluetoothDiscovery) -> some View {
        HStack(spacing: VakterDesign.spacingM) {
            // Signal-strength visual: 4 bars filled proportional to RSSI.
            // -30 dBm or stronger = full bars, -90 dBm or weaker = no bars.
            let strength = max(0, min(4, (d.rssi + 90) / 15))
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < strength ? VakterDesign.anchor : Color.primary.opacity(0.12))
                        .frame(width: 4, height: 4 + CGFloat(i) * 3)
                }
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(d.displayName)
                    .font(.system(size: 14, weight: .medium))
                Text("\(d.rssi) dBm · \(d.id.uuidString.prefix(8))")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                addPeer(d)
            } label: {
                Text("Add")
                    .frame(minWidth: 60)
            }
            .buttonStyle(.borderedProminent)
            .tint(VakterDesign.anchor)
            .controlSize(.small)
        }
        .padding(.vertical, VakterDesign.spacingS)
        .padding(.horizontal, VakterDesign.spacingM)
        .background(
            RoundedRectangle(cornerRadius: VakterDesign.radiusS, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func startDiscovery() {
        helperClient.startBluetoothDiscovery { initial in
            discoveries = initial
        }
    }

    private func startPolling() {
        scanStartedAt = Date()
        showingTimeoutHint = false
        // Capture the injected client now so the timer closure has a
        // stable reference (Timer's closure isn't @MainActor and can't
        // re-fetch the environment object).
        let client = helperClient
        let started = scanStartedAt
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            Task { @MainActor in
                client.currentBluetoothDiscoveries { list in
                    discoveries = list
                    // After ten quiet seconds, surface a hint so the
                    // user knows the scan isn't stuck.
                    if list.isEmpty,
                       Date().timeIntervalSince(started) > 10 {
                        showingTimeoutHint = true
                    }
                }
            }
        }
    }

    private func addPeer(_ d: BluetoothDiscovery) {
        let peer = TrustedPeer(id: d.id, displayName: d.displayName)
        helperClient.addTrustedPeer(peer) { ok in
            if ok { onClose() }
        }
    }
}

// MARK: - Defenses

private struct DefensesTab: View {
    @State private var checks: [DefenseCheck] = []
    @State private var history: [DefensesScoreSample] = []
    @State private var expandedCategory: DefenseCategory? = .identity

    /// Pareto-style grouping. Each existing check is mapped to one
    /// category via `categorize(_:)`. The categories themselves match
    /// the concepts-page § 04 spec and stay stable across releases.
    enum DefenseCategory: String, CaseIterable, Identifiable {
        case identity, filesystem, network, sleepLock, appIntegrity
        var id: String { rawValue }

        var label: String {
            switch self {
            case .identity:     return "Identity & sign-in"
            case .filesystem:   return "Filesystem"
            case .network:      return "Network"
            case .sleepLock:    return "Sleep & lock"
            case .appIntegrity: return "App integrity"
            }
        }

        var icon: String {
            switch self {
            case .identity:     return "person.crop.circle.fill"
            case .filesystem:   return "internaldrive.fill"
            case .network:      return "network"
            case .sleepLock:    return "lock.fill"
            case .appIntegrity: return "checkmark.shield.fill"
            }
        }
    }

    private func categorize(_ check: DefenseCheck) -> DefenseCategory {
        switch check.id {
        case "filevault":                            return .filesystem
        case "findmymac", "touchid", "autologin":    return .identity
        case "firewall", "stealthmode":              return .network
        case "screenlock", "loginwindow-msg":        return .sleepLock
        case "gatekeeper", "sip", "softwareupdates",
             "vakter-login-items":                   return .appIntegrity
        default:                                     return .appIntegrity
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Defenses")
                        .font(.system(size: 28, weight: .semibold))
                        .tracking(-0.6)
                    Spacer()
                    Button {
                        runChecks()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Re-check")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(Color.primary.opacity(0.08))
                        )
                        .overlay(
                            Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
                Text("Pareto-style checklist. The boring security stuff macOS lets you turn on, but most people forget. We check it every 4 hours. We never change settings silently — every fix opens System Settings.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 700, alignment: .leading)
            }

            // Score card
            scoreCard

            // Trend sparkline (only when we have >= 2 days of data)
            if history.count >= 2 {
                DefensesSparklineCard(samples: history)
            }

            // Categorized checklist
            VStack(spacing: 8) {
                ForEach(DefenseCategory.allCases) { cat in
                    categoryCard(cat)
                }
            }
        }
        .onAppear { runChecks() }
    }

    // MARK: Category card (expandable)

    private func categoryCard(_ cat: DefenseCategory) -> some View {
        let checksInCat = checks.filter { categorize($0) == cat }
        let passing = checksInCat.filter { $0.status == .healthy }.count
        let total = checksInCat.count
        let isExpanded = expandedCategory == cat

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    expandedCategory = isExpanded ? nil : cat
                }
            } label: {
                HStack(spacing: 12) {
                    // Icon tile
                    Image(systemName: cat.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(categoryColor(passing: passing, total: total))
                        )

                    Text(cat.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 12)

                    // Count
                    Text("\(passing) / \(total) passing")
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(.tertiary)

                    // Status pip
                    categoryStatusPip(passing: passing, total: total)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    Divider().opacity(0.5)
                    VStack(spacing: 0) {
                        ForEach(Array(checksInCat.enumerated()), id: \.element.id) { idx, check in
                            checkRow(check, isLast: idx == checksInCat.count - 1)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isExpanded ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06),
                    lineWidth: 1
                )
        )
    }

    private func categoryColor(passing: Int, total: Int) -> Color {
        guard total > 0 else { return Color.secondary }
        if passing == total { return VakterDesign.healthy }
        if passing >= total - 1 { return Color(red: 0.85, green: 0.60, blue: 0.20) }
        return VakterDesign.alarm
    }

    private func categoryStatusPip(passing: Int, total: Int) -> some View {
        let label: String
        let bg: Color
        let fg: Color
        if total == 0 {
            label = "—"; bg = Color.secondary.opacity(0.15); fg = .secondary
        } else if passing == total {
            label = "all good"; bg = VakterDesign.healthy.opacity(0.15); fg = VakterDesign.healthy
        } else if passing >= total - 1 {
            label = "1 to fix"; bg = Color(red: 0.85, green: 0.60, blue: 0.20).opacity(0.18); fg = Color(red: 0.85, green: 0.60, blue: 0.20)
        } else {
            label = "\(total - passing) to fix"; bg = VakterDesign.alarm.opacity(0.18); fg = VakterDesign.alarm
        }
        return Text(label)
            .font(.system(size: 10).monospaced())
            .tracking(0.4)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(bg))
            .foregroundStyle(fg)
    }

    /// Single source of truth for re-running the audit. Records a sample
    /// in `DefensesScoreHistory` so the sparkline trend builds up over
    /// time. Idempotent within a day — the store overwrites within-day
    /// samples, so re-checking 4 times today still produces one bar.
    private func runChecks() {
        let fresh = DefensesAudit.run()
        let score = DefensesAudit.score(fresh)
        DefensesScoreHistory.record(score: score)
        checks = fresh
        history = DefensesScoreHistory.load()
    }

    private var scoreCard: some View {
        let score = DefensesAudit.score(checks)
        // Explicit thresholds with clear action implication:
        //   100         → nothing to fix
        //   80–99       → well secured (low priority tweaks)
        //   60–79       → review (one or two real issues)
        //   < 60        → real exposure
        let (label, tint): (String, Color) = {
            switch score {
            case 100:    return ("Locked down",     VakterDesign.healthy)
            case 80...99: return ("Well secured",    VakterDesign.watch)
            case 60...79: return ("Review",          Color(red: 0.85, green: 0.60, blue: 0.20))
            default:     return ("Needs attention", VakterDesign.alarm)
            }
        }()
        return HStack(spacing: VakterDesign.spacingL) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.10), lineWidth: 8)
                    .frame(width: 88, height: 88)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100.0)
                    .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 88, height: 88)
                Text("\(score)")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 18, weight: .semibold))
                Text("\(checks.filter { $0.status == .healthy }.count) of \(checks.count) checks healthy")
                    .font(VakterDesign.bodyFont)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(VakterDesign.spacingL)
        .background(
            RoundedRectangle(cornerRadius: VakterDesign.radiusM, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: VakterDesign.radiusM, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
    }

    private func checkRow(_ check: DefenseCheck, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Status icon
                Image(systemName: check.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(check.tint)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle().fill(check.tint.opacity(0.16))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(check.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(check.detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if check.status == .healthy {
                    Text("passing")
                        .font(.system(size: 10).monospaced())
                        .foregroundStyle(VakterDesign.healthy)
                } else if let url = check.systemSettingsURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Text("Fix in Settings →")
                            .font(.system(size: 11).monospaced())
                            .foregroundStyle(VakterDesign.lantern)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 9)

            if !isLast {
                Divider()
                    .opacity(0.4)
                    .padding(.leading, 30)
            }
        }
    }
}

// MARK: - Defenses sparkline

/// Tiny inline trend card: a sparkline of the last N days of Defenses
/// scores plus a delta-vs-start label. Only rendered when we have at
/// least two distinct daily samples.
private struct DefensesSparklineCard: View {

    let samples: [DefensesScoreSample]

    var body: some View {
        let first = samples.first?.score ?? 0
        let last  = samples.last?.score ?? 0
        let delta = last - first

        return VakterCard(
            title: "Trend",
            subtitle: "Your Defenses score over the last \(samples.count) day\(samples.count == 1 ? "" : "s")."
        ) {
            HStack(spacing: VakterDesign.spacingL) {
                Sparkline(samples: samples)
                    .frame(height: 56)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(last)")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(VakterDesign.anchor)
                    deltaPill(delta)
                }
                .frame(width: 80)
            }
        }
    }

    @ViewBuilder
    private func deltaPill(_ delta: Int) -> some View {
        if delta == 0 {
            VakterStatusPill("steady", tone: .neutral)
        } else if delta > 0 {
            VakterStatusPill("\u{2B06}\u{FE0E} +\(delta)", tone: .healthy)
        } else {
            VakterStatusPill("\u{2B07}\u{FE0E} \(delta)", tone: .attention)
        }
    }
}

/// Minimal sparkline — connects samples with a single rounded path and
/// dots the latest sample. Designed for the Defenses tab; not generic.
private struct Sparkline: View {

    let samples: [DefensesScoreSample]

    var body: some View {
        GeometryReader { geo in
            let scores = samples.map { Double($0.score) }
            let maxVal = max(scores.max() ?? 100, 100.0)
            let minVal = min(scores.min() ?? 0,   0.0)
            let range  = max(maxVal - minVal, 1.0)

            let points: [CGPoint] = scores.enumerated().map { idx, val in
                let x = scores.count == 1 ? geo.size.width / 2 :
                    geo.size.width * CGFloat(idx) / CGFloat(scores.count - 1)
                let y = geo.size.height * (1.0 - CGFloat((val - minVal) / range))
                return CGPoint(x: x, y: y)
            }

            ZStack {
                // Filled area under the curve (soft fill).
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: CGPoint(x: first.x, y: geo.size.height))
                    p.addLine(to: first)
                    for pt in points.dropFirst() {
                        p.addLine(to: pt)
                    }
                    if let last = points.last {
                        p.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                    }
                    p.closeSubpath()
                }
                .fill(VakterDesign.anchor.opacity(0.10))

                // The line itself.
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: first)
                    for pt in points.dropFirst() {
                        p.addLine(to: pt)
                    }
                }
                .stroke(VakterDesign.anchor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // Latest dot.
                if let last = points.last {
                    Circle()
                        .fill(VakterDesign.anchor)
                        .frame(width: 7, height: 7)
                        .position(last)
                }
            }
        }
    }
}

// MARK: - About

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: VakterDesign.spacingL) {
            // Hero lighthouse mark — same emblem as the app icon and
            // onboarding welcome. Ties the About page to the brand.
            LighthouseHeroMark(cycleSeconds: 5.0, size: 160)
                .padding(.top, VakterDesign.spacingS)

            VStack(spacing: VakterDesign.spacingXS) {
                Text("Vakter")
                    .font(VakterDesign.wordmark)
                Text("Your laptop's night-watchman.")
                    .font(VakterDesign.bodyFont)
                    .foregroundStyle(.secondary)
            }

            Text("Norwegian: \u{201C}the night-watchmen on a sailing ship.\u{201D} The crew who stay awake at anchor so the rest of the ship can sleep. That's what Vakter does for your Mac.")
                .font(VakterDesign.captionFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 380)

            HStack(spacing: VakterDesign.spacingM) {
                VakterStatusPill("v0.1.0", tone: .neutral)
                VakterStatusPill("Apple Silicon", tone: .neutral, icon: "cpu")
                VakterStatusPill("Notarised", tone: .healthy, icon: "checkmark.seal.fill")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, VakterDesign.spacingL)
    }
}
