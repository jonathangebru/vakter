import SwiftUI
import AppKit
import AVFoundation
import VakterShared

/// First-launch walkthrough. Presented as a sheet at the centre of the
/// screen. Five steps:
///   1. Welcome           — brand intro
///   2. Permissions       — camera + bluetooth + login-items grant
///   3. Hotkey reveal     — the single most important thing
///   4. Hear the alarm    — preview, build trust before relying on it
///   5. Done              — close
///
/// Designed to feel calm, not transactional. Big glyph, generous
/// whitespace, single primary action per step.
struct OnboardingSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .welcome
    @State private var hotkey: HotkeyBinding = HotkeyStore.load()

    // Dependency-injected so we don't have to fish through NSApp.delegate
    // (which fails when the cast happens from inside a SwiftUI sheet —
    // the @NSApplicationDelegateAdaptor wrapping breaks the runtime cast).
    let helperClient: HelperClient?

    init(helperClient: HelperClient? = nil) {
        self.helperClient = helperClient
    }

    enum Step: Int, CaseIterable {
        case welcome, permissions, hotkey, hearAlarm, done
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top progress dots
            progressDots
                .padding(.top, VakterDesign.spacingL)
                .padding(.bottom, VakterDesign.spacingM)

            // Step content
            ScrollView {
                Group {
                    switch step {
                    case .welcome:     welcomeStep
                    case .permissions: permissionsStep
                    case .hotkey:      hotkeyStep
                    case .hearAlarm:   hearAlarmStep
                    case .done:        doneStep
                    }
                }
                .padding(.horizontal, VakterDesign.spacingXL)
                .padding(.vertical, VakterDesign.spacingM)
                .frame(maxWidth: .infinity)
            }

            // Bottom nav
            navBar
                .padding(VakterDesign.spacingL)
                .background(
                    Color(nsColor: .underPageBackgroundColor)
                        .overlay(
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 1),
                            alignment: .top
                        )
                )
        }
        .frame(width: 540, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Top progress

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases.dropLast(), id: \.self) { s in
                Capsule()
                    // System accent (Sequoia blue by default) instead
                    // of brand navy — matches macOS pagination dots
                    // in StoreKit prompts, About boxes, etc.
                    .fill(s.rawValue <= step.rawValue ?
                          VakterDesign.accent : Color.primary.opacity(0.15))
                    .frame(width: s == step ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: step)
            }
        }
    }

    // MARK: Welcome

    private var welcomeStep: some View {
        VStack(spacing: VakterDesign.spacingL) {
            // Hero brand mark — a lighthouse silhouette with a warm
            // amber lantern at the lamp room. The lighthouse is the
            // emblem of the night-watchman: it stands awake while the
            // rest of the ship sleeps.
            LighthouseHeroMark(cycleSeconds: 4.0, size: 168)
                .padding(.top, VakterDesign.spacingS)

            VStack(spacing: VakterDesign.spacingS) {
                Text("Vakter")
                    .font(VakterDesign.wordmark)
                VakterEyebrow("Norwegian \u{2014} the night-watchmen")
                    .padding(.top, 2)
                Text("The night-watch for your Mac \u{2014} calm when you're nearby, fierce the moment someone tries to walk off with it.")
                    .font(VakterDesign.bodyFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, VakterDesign.spacingL)
                    .padding(.top, 2)
            }

            // Three hero feature cards. Replaces the previous bullet list.
            HStack(alignment: .top, spacing: VakterDesign.spacingS) {
                heroFeatureCard(
                    icon: "lock.fill",
                    title: "One shortcut",
                    text: "Press \(hotkey.displayLabel) anywhere \u{2014} lock & arm in one motion."
                )
                heroFeatureCard(
                    icon: "shield.lefthalf.filled",
                    title: "Smart triggers",
                    text: "Lid close, unplug, Bluetooth peers leaving. Even through a closed lid."
                )
                heroFeatureCard(
                    icon: "person.fill.checkmark",
                    title: "Calm disarm",
                    text: "Touch ID at the lock screen. macOS verified you \u{2014} that's enough."
                )
            }
            .padding(.top, VakterDesign.spacingS)
        }
    }

    /// Compact hero card used in the Welcome step. Three of these sit in
    /// a row, each a self-contained quick-look at one of Vakter's pillars.
    private func heroFeatureCard(icon: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: VakterDesign.spacingS) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(VakterDesign.anchor)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(VakterDesign.anchor.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(VakterDesign.captionFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1)
            }
            Spacer(minLength: 0)
        }
        .padding(VakterDesign.spacingM)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: VakterDesign.radiusM, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: VakterDesign.radiusM, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: Permissions

    @State private var cameraStatus: String = "checking…"
    @State private var loginItemsHint: Bool = false

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: VakterDesign.spacingL) {
            Text("Permissions")
                .font(.system(size: 26, weight: .semibold))
            Text("Vakter only asks for what it actually uses.")
                .font(VakterDesign.bodyFont)
                .foregroundStyle(.secondary)

            permissionCard(
                icon: "camera.fill",
                title: "Camera",
                why: "If the alarm fires, Vakter captures photos so you can see who tried to take your Mac.",
                status: cameraStatus,
                action: "Open Privacy & Security\u{2026}",
                onAction: openCameraPrivacy
            )

            permissionCard(
                icon: "antenna.radiowaves.left.and.right",
                title: "Bluetooth",
                why: "Vakter senses when your trusted devices (phone, AirPods, watch) are nearby and dampens false alarms.",
                status: "Granted on first use",
                action: nil,
                onAction: nil
            )

            permissionCard(
                icon: "shield.lefthalf.filled.badge.checkmark",
                title: "Login Items & Extensions",
                why: "Vakter needs to install a background helper and a privileged daemon. Both let it work silently after you arm — no Touch ID prompts per arm.",
                status: "Approve once in System Settings",
                action: "Open Login Items\u{2026}",
                onAction: openLoginItems
            )
        }
        .onAppear { refreshCameraStatus() }
    }

    private func permissionCard(
        icon: String, title: String, why: String,
        status: String, action: String?, onAction: (() -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: VakterDesign.spacingM) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(VakterDesign.anchor)
                .frame(width: 36, height: 36)
                .background(Circle().fill(VakterDesign.anchor.opacity(0.10)))

            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(why)
                    .font(VakterDesign.bodyFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    VakterStatusPill(status, tone: status.lowercased().contains("granted") ? .healthy : .neutral)
                    if let action = action, let onAction = onAction {
                        Spacer()
                        Button(action, action: onAction)
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(VakterDesign.spacingM)
        .background(
            RoundedRectangle(cornerRadius: VakterDesign.radiusM, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: VakterDesign.radiusM, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func refreshCameraStatus() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:   cameraStatus = "Granted"
        case .denied:       cameraStatus = "Denied — needs fixing"
        case .restricted:   cameraStatus = "Restricted by system policy"
        case .notDetermined: cameraStatus = "Will be asked on first alarm"
        @unknown default:   cameraStatus = "Unknown"
        }
    }

    private func openCameraPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openLoginItems() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Hotkey

    private var hotkeyStep: some View {
        VStack(spacing: VakterDesign.spacingL) {
            Text("Your arming shortcut")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.6)
            Text("Press this combo anywhere on your Mac. Vakter locks the screen and goes on watch in one motion. Pick your own if you'd rather.")
                .font(VakterDesign.bodyFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            // The combo, rendered as physical-feeling keycap blocks —
            // matches the concepts § 03 spec. Each cap has a slight
            // gradient + bottom shadow that reads as 3D.
            HStack(spacing: 10) {
                ForEach(Array(hotkey.displayLabel.enumerated()), id: \.offset) { _, ch in
                    keycapBlock(symbol: String(ch))
                }
            }
            .padding(.vertical, VakterDesign.spacingL)

            // Micro-affordance: tells the user this is interactive
            Text("tap any key to test · click to remap")
                .font(.system(size: 10.5, weight: .regular).monospaced())
                .tracking(0.6)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)

            KeyRecorder(binding: $hotkey) { newBinding in
                HotkeyStore.save(newBinding)
                helperClient?.reloadHotkey()
            }
        }
    }

    /// Physical-feeling keycap. Slight top-light gradient + bottom shadow
    /// + amber symbol color = "press me" without saying it.
    private func keycapBlock(symbol: String) -> some View {
        Text(symbol)
            .font(.system(size: 32, weight: .semibold).monospaced())
            .foregroundStyle(VakterDesign.lantern)
            .frame(width: 56, height: 66)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.primary.opacity(0.07),
                                    Color.primary.opacity(0.03)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                }
            )
            .overlay(
                // Top-light highlight: a thin amber inner stroke at top
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(VakterDesign.lantern.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 1, x: 0, y: 1)
            .shadow(color: VakterDesign.lantern.opacity(0.12), radius: 6, x: 0, y: 2)
    }

    // MARK: Hear the alarm

    @State private var hasHeardAlarm = false
    @State private var isPlaying = false
    /// Anchor for the waveform's "live" amplitude window. When non-nil
    /// and within the play duration, the waveform pulses at full
    /// amplitude. Otherwise it rests at a low idle amplitude.
    @State private var playStartedAt: Date?
    private let playDuration: TimeInterval = 3.0

    private var hearAlarmStep: some View {
        VStack(spacing: VakterDesign.spacingL) {
            Text("Hear the alarm")
                .font(.system(size: 26, weight: .semibold))
            Text("This is the sound a thief hears. Try it now so you know what to expect — and so you trust it'll fire when you walk away.")
                .font(VakterDesign.bodyFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, VakterDesign.spacingM)

            // Big speaker visual + live waveform underneath.
            VStack(spacing: VakterDesign.spacingM) {
                ZStack {
                    Circle()
                        .fill(isPlaying ? VakterDesign.alarm.opacity(0.16)
                              : (hasHeardAlarm ? VakterDesign.healthy.opacity(0.10)
                                                : VakterDesign.alarm.opacity(0.08)))
                        .frame(width: 140, height: 140)
                        .animation(.easeInOut(duration: 0.4), value: isPlaying)

                    // Subtle ring pulse while playing.
                    if isPlaying {
                        Circle()
                            .stroke(VakterDesign.alarm.opacity(0.5), lineWidth: 2)
                            .frame(width: 140, height: 140)
                            .scaleEffect(1.18)
                            .opacity(0.0)
                            .animation(
                                .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                                value: isPlaying
                            )
                    }

                    Image(systemName: hasHeardAlarm && !isPlaying
                          ? "checkmark.circle.fill" : "speaker.wave.3.fill")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(
                            hasHeardAlarm && !isPlaying
                                ? VakterDesign.healthy
                                : VakterDesign.alarm
                        )
                }

                AlarmWaveformView(
                    isPlaying: isPlaying,
                    playStartedAt: playStartedAt
                )
                .frame(height: 56)
                .frame(maxWidth: 360)
            }

            Button {
                triggerPreview()
            } label: {
                Label(
                    isPlaying ? "Playing…"
                              : (hasHeardAlarm ? "Play again" : "Play the alarm"),
                    systemImage: isPlaying ? "waveform" :
                                  (hasHeardAlarm ? "arrow.clockwise" : "play.fill")
                )
                .frame(minWidth: 160)
            }
            .disabled(isPlaying)
            .buttonStyle(.borderedProminent)
            .tint(VakterDesign.alarm)
            .controlSize(.large)

            Text("Volume will be temporarily forced to max on internal speakers, then restored.")
                .font(VakterDesign.captionFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, VakterDesign.spacingS)
        }
    }

    /// Starts a real testAlarm, drives the visual playing-state, and
    /// flips back to idle after `playDuration`.
    private func triggerPreview() {
        guard !isPlaying else { return }
        hasHeardAlarm = true
        isPlaying = true
        playStartedAt = Date()
        if let client = helperClient {
            NSLog("[Onboarding] sending testAlarm via injected HelperClient")
            client.testAlarm(seconds: playDuration)
        } else {
            NSLog("[Onboarding] helperClient not injected — visual-only preview")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + playDuration + 0.2) {
            self.isPlaying = false
        }
    }

    // MARK: Done

    private var doneStep: some View {
        VStack(spacing: VakterDesign.spacingL) {
            ZStack {
                Circle()
                    .fill(VakterDesign.healthy.opacity(0.10))
                    .frame(width: 140, height: 140)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 70, weight: .light))
                    .foregroundStyle(VakterDesign.healthy)
            }

            VStack(spacing: VakterDesign.spacingS) {
                Text("You're set.")
                    .font(.system(size: 28, weight: .semibold))
                Text("Vakter is on watch in your menu bar. Press \(hotkey.displayLabel) whenever you walk away.")
                    .font(VakterDesign.bodyFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: VakterDesign.spacingS) {
                VakterStatusPill("Hotkey: \(hotkey.displayLabel)", tone: .neutral, icon: "command")
                // Pre-v1.2 this said "On watch" which was a lie — the
                // user hasn't armed yet, they've just finished setup.
                // "Ready to arm" is honest and primes the action.
                VakterStatusPill("Ready to arm", tone: .healthy, icon: "shield.lefthalf.filled")
            }
            .padding(.top, VakterDesign.spacingM)
        }
    }

    // MARK: Nav bar

    private var navBar: some View {
        HStack {
            if step != .welcome {
                Button {
                    advance(by: -1)
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            Button(action: nextAction) {
                Text(primaryButtonLabel).frame(minWidth: 100)
            }
            .buttonStyle(.borderedProminent)
            .tint(VakterDesign.anchor)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var primaryButtonLabel: String {
        switch step {
        case .welcome:     return "Get started"
        case .permissions: return "Continue"
        case .hotkey:      return "Continue"
        case .hearAlarm:   return "Continue"
        case .done:        return "Finish"
        }
    }

    private func nextAction() {
        if step == .done {
            OnboardingState.markComplete()
            dismiss()
        } else {
            advance(by: 1)
        }
    }

    private func advance(by delta: Int) {
        let new = Step(rawValue: step.rawValue + delta) ?? step
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
            step = new
        }
    }
}

// MARK: - Live waveform

/// A sine-driven waveform that idles low when off-air and swells to
/// full amplitude during a preview. Uses TimelineView(.animation) so
/// the rendering is GPU-driven; no Timer / no allocations per frame.
private struct AlarmWaveformView: View {

    let isPlaying: Bool
    let playStartedAt: Date?

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                draw(ctx: ctx, size: size, now: context.date)
            }
        }
    }

    private func draw(ctx: GraphicsContext, size: CGSize, now: Date) {
        let midY = size.height / 2
        let width = size.width
        let baseFreq: Double = 2.0   // wave-cycles-per-screen
        let timeBase = now.timeIntervalSinceReferenceDate

        let idleAmplitude: Double = 0.08
        let activeAmplitude: Double = 0.85

        // Compute the current amplitude. Fade in/out smoothly when
        // playing toggles.
        let amplitude: Double
        if isPlaying, let start = playStartedAt {
            let elapsed = now.timeIntervalSince(start)
            let attack = min(1.0, elapsed / 0.2)
            amplitude = idleAmplitude + (activeAmplitude - idleAmplitude) * attack
        } else {
            amplitude = idleAmplitude
        }

        // Build the path.
        var path = Path()
        let steps = 120
        for i in 0...steps {
            let x = CGFloat(i) / CGFloat(steps) * width
            // Two wave components for a richer look: base sine + tiny
            // higher-frequency overlay, modulated by amplitude.
            let phase = (Double(i) / Double(steps)) * 2 * .pi * baseFreq
                + timeBase * (isPlaying ? 6.0 : 1.2)
            let overlay = isPlaying ? 0.20 * sin(phase * 3.5) : 0
            let y = midY + CGFloat((sin(phase) + overlay) * amplitude) * (size.height / 2 - 4)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        // Stroke colour shifts: calm when idle, alarm tint when playing.
        let strokeColor: Color = isPlaying ? VakterDesign.alarm : VakterDesign.anchorSecondary
        ctx.stroke(
            path,
            with: .color(strokeColor),
            style: StrokeStyle(lineWidth: isPlaying ? 2.2 : 1.4, lineCap: .round, lineJoin: .round)
        )

        // Centre baseline (very faint).
        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: midY))
        baseline.addLine(to: CGPoint(x: width, y: midY))
        ctx.stroke(
            baseline,
            with: .color(Color.primary.opacity(0.08)),
            style: StrokeStyle(lineWidth: 0.5, dash: [3, 4])
        )
    }
}

// MARK: - Persistence

enum OnboardingState {
    /// Bumped from `anchor.onboarding.completed` to `vakter.onboarding.completed`
    /// in the Anchor → Vakter rebrand. This intentionally re-triggers
    /// the onboarding flow for users upgrading from the Anchor-era
    /// install, so they see the (new) Login Items approval step for
    /// the renamed daemon — otherwise every arm would prompt for a
    /// password because the old daemon's approval doesn't transfer to
    /// the new bundle ID.
    private static let key = "vakter.onboarding.completed"

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markComplete() {
        UserDefaults.standard.set(true, forKey: key)
    }
}
