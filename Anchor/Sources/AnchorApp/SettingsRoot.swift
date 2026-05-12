import SwiftUI
import AppKit
import AnchorShared

/// Root of the Settings window — calm-protector design.
///
/// Layout: a sidebar with sections + a content area. Different from
/// macOS's default tab style, more in keeping with the brand: it should
/// feel composed and quiet, not panel-y.
struct SettingsRoot: View {

    enum Section: String, CaseIterable, Identifiable {
        case general    = "General"
        case shortcut   = "Shortcut"
        case modes      = "Modes"
        case sound      = "Sound"
        case bluetooth  = "Trusted Devices"
        case defenses   = "Defenses"
        case eventLog   = "Event Log"
        case about      = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general:   return "gearshape"
            case .shortcut:  return "command"
            case .modes:     return "rectangle.stack"
            case .sound:     return "speaker.wave.3"
            case .bluetooth: return "antenna.radiowaves.left.and.right"
            case .defenses:  return "checkmark.shield"
            case .eventLog:  return "clock"
            case .about:     return "info.circle"
            }
        }
    }

    @State private var selected: Section = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            contentArea
        }
        .frame(minWidth: 720, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand mark
            HStack(spacing: AnchorDesign.spacingS) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AnchorDesign.anchor)
                Text("Anchor")
                    .font(.system(size: 19, weight: .semibold, design: .default))
            }
            .padding(.horizontal, AnchorDesign.spacingL)
            .padding(.top, AnchorDesign.spacingL)
            .padding(.bottom, AnchorDesign.spacingM)

            // Sections
            VStack(spacing: 2) {
                ForEach(Section.allCases) { section in
                    sidebarRow(section)
                }
            }
            .padding(.horizontal, AnchorDesign.spacingS)

            Spacer()

            // Footer
            Text("Watch over your Mac.\nWalk away in peace.")
                .font(AnchorDesign.captionFont)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .padding(.horizontal, AnchorDesign.spacingL)
                .padding(.bottom, AnchorDesign.spacingL)
        }
        .frame(width: 220)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func sidebarRow(_ section: Section) -> some View {
        Button(action: { selected = section }) {
            HStack(spacing: AnchorDesign.spacingS) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected == section ? .white : AnchorDesign.anchorSecondary)
                    .frame(width: 18)
                Text(section.rawValue)
                    .font(.system(size: 13, weight: selected == section ? .semibold : .medium))
                    .foregroundStyle(selected == section ? .white : .primary)
                Spacer()
            }
            .padding(.horizontal, AnchorDesign.spacingS)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: AnchorDesign.radiusS, style: .continuous)
                    .fill(selected == section ?
                          AnchorDesign.anchor :
                          Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Content

    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AnchorDesign.spacingL) {
                switch selected {
                case .general:   GeneralTab()
                case .shortcut:  ShortcutTab()
                case .modes:     ModesTab()
                case .sound:     SoundTab()
                case .bluetooth: BluetoothTab()
                case .defenses:  DefensesTab()
                case .eventLog:  EventLogView()
                case .about:     AboutTab()
                }
            }
            .padding(AnchorDesign.spacingXL)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @State private var graceSeconds: Double = GraceSettingsStore.load().seconds

    var body: some View {
        Text("General")
            .font(AnchorDesign.titleFont)

        AnchorCard(
            title: "Grace window",
            subtitle: "How long Anchor waits after a trigger before the alarm fires. Short for fast deterrence, longer if you sometimes need a moment to come back and disarm."
        ) {
            VStack(alignment: .leading, spacing: AnchorDesign.spacingM) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(graceSeconds.rounded()))")
                        .font(AnchorDesign.titleFont.monospaced())
                        .foregroundStyle(AnchorDesign.anchor)
                    Text("seconds")
                        .font(AnchorDesign.bodyFont)
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
                        .font(AnchorDesign.captionFont)
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("\(Int(GraceSettings.maxSeconds))s")
                        .font(AnchorDesign.captionFont)
                        .foregroundStyle(.secondary)
                }
                .tint(AnchorDesign.anchor)
                .onChange(of: graceSeconds) { _, new in
                    GraceSettingsStore.save(GraceSettings(seconds: new.rounded()))
                }

                // Preset quick-pick
                HStack(spacing: AnchorDesign.spacingS) {
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
                                            AnchorDesign.anchor.opacity(0.15) :
                                            Color.primary.opacity(0.06)
                                    )
                                )
                                .foregroundStyle(
                                    Int(graceSeconds.rounded()) == preset ?
                                        AnchorDesign.anchor : .primary
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        AnchorCard(
            title: "Launch at login",
            subtitle: "Anchor's background helper and privileged daemon are managed via macOS Login Items. Open the system pane to review them."
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
    @State private var binding: HotkeyBinding = HotkeyStore.load()

    var body: some View {
        Text("Arming Shortcut")
            .font(AnchorDesign.titleFont)

        AnchorCard(
            title: "Press this combo anywhere",
            subtitle: "When you press the shortcut, Anchor locks your Mac and arms the alarm in one motion. Pick something with at least one modifier (⌘, ⌃, ⌥, ⇧) so it doesn't fire while typing."
        ) {
            KeyRecorder(binding: $binding, onChange: { newBinding in
                HotkeyStore.save(newBinding)
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.helperClient?.reloadHotkey()
                }
            })

            HStack {
                Button {
                    binding = .default
                    HotkeyStore.save(.default)
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.helperClient?.reloadHotkey()
                    }
                } label: {
                    Label("Restore default", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                Spacer()
                AnchorStatusPill("Default: \(HotkeyBinding.default.displayLabel)",
                                 tone: .neutral, icon: "info.circle")
            }
        }
    }
}

// MARK: - Modes

private struct ModesTab: View {
    var body: some View {
        Text("Modes")
            .font(AnchorDesign.titleFont)
        Text("Anchor changes posture for different situations. Mode is also pickable from the menubar dropdown.")
            .font(AnchorDesign.bodyFont)
            .foregroundStyle(.secondary)

        VStack(spacing: AnchorDesign.spacingS) {
            ForEach(AnchorMode.allCases, id: \.self) { mode in
                modeCard(mode)
            }
        }
    }

    private func modeCard(_ mode: AnchorMode) -> some View {
        let p = ModeParameters.parameters(for: mode)
        return HStack(alignment: .top, spacing: AnchorDesign.spacingM) {
            ZStack {
                Circle()
                    .fill(AnchorDesign.anchor.opacity(0.10))
                    .frame(width: 44, height: 44)
                Image(systemName: iconFor(mode))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AnchorDesign.anchor)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: AnchorDesign.spacingS) {
                    Text(mode.displayName)
                        .font(.system(size: 16, weight: .semibold))
                    AnchorStatusPill("\(Int(p.graceSeconds))s default grace",
                                     tone: .neutral)
                    if p.audible {
                        AnchorStatusPill("loud", tone: .attention, icon: "speaker.wave.3.fill")
                    } else {
                        AnchorStatusPill("silent", tone: .watching, icon: "speaker.slash")
                    }
                }
                Text(mode.blurb)
                    .font(AnchorDesign.bodyFont)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(AnchorDesign.spacingM)
        .background(
            RoundedRectangle(cornerRadius: AnchorDesign.radiusM, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AnchorDesign.radiusM, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func iconFor(_ mode: AnchorMode) -> String {
        switch mode {
        case .normal:  return "cup.and.saucer.fill"
        case .travel:  return "airplane"
        case .library: return "book.closed.fill"
        case .loaner:  return "person.2.fill"
        }
    }
}

// MARK: - Sound

private struct SoundTab: View {
    var body: some View {
        Text("Sound")
            .font(AnchorDesign.titleFont)

        AnchorCard(
            title: "Alarm preview",
            subtitle: "Hear what a thief would hear. The real alarm runs at maximum volume on the built-in speakers, regardless of your current settings."
        ) {
            HStack {
                Button {
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.helperClient?.testAlarm(seconds: 3.0)
                    }
                } label: {
                    Label("Test alarm (3 sec)", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(AnchorDesign.anchor)
                Spacer()
            }
        }

        AnchorCard(
            title: "Voice cue",
            subtitle: "During the alarm, Anchor speaks a phrase between siren tones — it's harder to ignore than just a tone. You can customise the text in a future update."
        ) {
            Text("\u{201C}This MacBook is being tracked. Please put it down.\u{201D}")
                .font(.system(size: 14, weight: .medium, design: .serif).italic())
                .foregroundStyle(AnchorDesign.anchor)
                .padding(AnchorDesign.spacingM)
                .background(
                    RoundedRectangle(cornerRadius: AnchorDesign.radiusS, style: .continuous)
                        .fill(AnchorDesign.anchor.opacity(0.06))
                )
        }
    }
}

// MARK: - Bluetooth

private struct BluetoothTab: View {
    @State private var peers: [TrustedPeer] = []
    @State private var showingPairing = false

    var body: some View {
        Text("Trusted Devices")
            .font(AnchorDesign.titleFont)
        Text("Pair the things you keep with you — phone, AirPods, Apple Watch. While at least one is nearby, Anchor dampens false alarms. When all of them go out of Bluetooth range, that's a theft signal.")
            .font(AnchorDesign.bodyFont)
            .foregroundStyle(.secondary)

        AnchorCard(
            title: peers.isEmpty ? "No devices paired yet" : "Paired devices",
            subtitle: peers.isEmpty
                ? "Pair at least one to enable Bluetooth-presence triggers. You can pair up to \(TrustedPeerStore.maxCount)."
                : "Anchor watches for all of these. If they're ALL out of range for 3+ seconds, the alarm trigger fires."
        ) {
            VStack(spacing: AnchorDesign.spacingS) {
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
                    .tint(AnchorDesign.anchor)
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
        guard let delegate = NSApp.delegate as? AppDelegate,
              let client = delegate.helperClient else { return }
        client.listTrustedPeers { list in
            peers = list.sorted(by: { $0.dateAdded > $1.dateAdded })
        }
    }

    private func peerRow(_ peer: TrustedPeer) -> some View {
        HStack(spacing: AnchorDesign.spacingM) {
            Image(systemName: iconFor(name: peer.displayName))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AnchorDesign.anchor)
                .frame(width: 32, height: 32)
                .background(Circle().fill(AnchorDesign.anchor.opacity(0.10)))
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
        .padding(AnchorDesign.spacingS)
        .background(
            RoundedRectangle(cornerRadius: AnchorDesign.radiusS, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func removePeer(_ peer: TrustedPeer) {
        guard let delegate = NSApp.delegate as? AppDelegate,
              let client = delegate.helperClient else { return }
        client.removeTrustedPeer(id: peer.id) { _ in
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
    let onClose: () -> Void

    @State private var discoveries: [BluetoothDiscovery] = []
    @State private var pollTimer: Timer?
    @State private var pickedID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add a trusted device")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Scanning for nearby Bluetooth devices. Pair the device with your Mac first (System Settings → Bluetooth) for the most reliable matching.")
                        .font(AnchorDesign.captionFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Done", action: onClose)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
            .padding(AnchorDesign.spacingL)

            Divider()

            if discoveries.isEmpty {
                VStack(spacing: AnchorDesign.spacingM) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Scanning…")
                        .foregroundStyle(.secondary)
                        .font(AnchorDesign.bodyFont)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(discoveries) { d in
                            discoveryRow(d)
                        }
                    }
                    .padding(AnchorDesign.spacingM)
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
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.helperClient?.stopBluetoothDiscovery()
            }
        }
    }

    private func discoveryRow(_ d: BluetoothDiscovery) -> some View {
        HStack(spacing: AnchorDesign.spacingM) {
            // Signal-strength visual: 4 bars filled proportional to RSSI.
            // -30 dBm or stronger = full bars, -90 dBm or weaker = no bars.
            let strength = max(0, min(4, (d.rssi + 90) / 15))
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < strength ? AnchorDesign.anchor : Color.primary.opacity(0.12))
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
            .tint(AnchorDesign.anchor)
            .controlSize(.small)
        }
        .padding(.vertical, AnchorDesign.spacingS)
        .padding(.horizontal, AnchorDesign.spacingM)
        .background(
            RoundedRectangle(cornerRadius: AnchorDesign.radiusS, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func startDiscovery() {
        guard let delegate = NSApp.delegate as? AppDelegate,
              let client = delegate.helperClient else { return }
        client.startBluetoothDiscovery { initial in
            discoveries = initial
        }
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            Task { @MainActor in
                guard let delegate = NSApp.delegate as? AppDelegate,
                      let client = delegate.helperClient else { return }
                client.currentBluetoothDiscoveries { list in
                    discoveries = list
                }
            }
        }
    }

    private func addPeer(_ d: BluetoothDiscovery) {
        guard let delegate = NSApp.delegate as? AppDelegate,
              let client = delegate.helperClient else { return }
        let peer = TrustedPeer(id: d.id, displayName: d.displayName)
        client.addTrustedPeer(peer) { ok in
            if ok { onClose() }
        }
    }
}

// MARK: - Defenses

private struct DefensesTab: View {
    @State private var checks: [DefenseCheck] = []

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Your Mac's Defenses")
                .font(AnchorDesign.titleFont)
            Spacer()
            Button {
                checks = DefensesAudit.run()
            } label: {
                Label("Re-check", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }

        Text("Anchor reads your system's posture and surfaces what could be tightened. We never change settings silently — every fix opens System Settings.")
            .font(AnchorDesign.bodyFont)
            .foregroundStyle(.secondary)

        // Big score card
        scoreCard

        // Per-check rows
        VStack(spacing: AnchorDesign.spacingS) {
            ForEach(checks) { check in
                checkRow(check)
            }
        }
        .onAppear {
            checks = DefensesAudit.run()
        }
    }

    private var scoreCard: some View {
        let score = DefensesAudit.score(checks)
        let (label, tint): (String, Color) = {
            switch score {
            case 100:     return ("Locked down", AnchorDesign.healthy)
            case 70...99: return ("Mostly solid", Color(red: 0.85, green: 0.60, blue: 0.20))
            default:      return ("Needs attention", AnchorDesign.alarm)
            }
        }()
        return HStack(spacing: AnchorDesign.spacingL) {
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
                    .font(AnchorDesign.bodyFont)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(AnchorDesign.spacingL)
        .background(
            RoundedRectangle(cornerRadius: AnchorDesign.radiusM, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AnchorDesign.radiusM, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
    }

    private func checkRow(_ check: DefenseCheck) -> some View {
        HStack(alignment: .top, spacing: AnchorDesign.spacingM) {
            Image(systemName: check.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(check.tint)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(check.detail)
                    .font(AnchorDesign.bodyFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if check.status != .healthy, let url = check.systemSettingsURL {
                Button("Fix in Settings") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(AnchorDesign.spacingM)
        .background(
            RoundedRectangle(cornerRadius: AnchorDesign.radiusS, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

// MARK: - About

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: AnchorDesign.spacingL) {
            ZStack {
                Circle()
                    .fill(AnchorDesign.anchor.opacity(0.10))
                    .frame(width: 100, height: 100)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 50, weight: .light))
                    .foregroundStyle(AnchorDesign.anchor)
            }

            VStack(spacing: AnchorDesign.spacingXS) {
                Text("Anchor")
                    .font(.system(size: 30, weight: .semibold))
                Text("Watch over your Mac. Walk away in peace.")
                    .font(AnchorDesign.bodyFont)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: AnchorDesign.spacingM) {
                AnchorStatusPill("v0.1.0", tone: .neutral)
                AnchorStatusPill("Apple Silicon", tone: .neutral, icon: "cpu")
                AnchorStatusPill("Notarised", tone: .healthy, icon: "checkmark.seal.fill")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AnchorDesign.spacingL)
    }
}
