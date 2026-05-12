import SwiftUI
import AppKit
import AVFoundation
import AnchorShared

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

    enum Step: Int, CaseIterable {
        case welcome, permissions, hotkey, hearAlarm, done
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top progress dots
            progressDots
                .padding(.top, AnchorDesign.spacingL)
                .padding(.bottom, AnchorDesign.spacingM)

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
                .padding(.horizontal, AnchorDesign.spacingXL)
                .padding(.vertical, AnchorDesign.spacingM)
                .frame(maxWidth: .infinity)
            }

            // Bottom nav
            navBar
                .padding(AnchorDesign.spacingL)
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
                    .fill(s.rawValue <= step.rawValue ?
                          AnchorDesign.anchor : Color.primary.opacity(0.15))
                    .frame(width: s == step ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: step)
            }
        }
    }

    // MARK: Welcome

    private var welcomeStep: some View {
        VStack(spacing: AnchorDesign.spacingL) {
            // Big animated brand mark
            ZStack {
                Circle()
                    .fill(AnchorDesign.anchor.opacity(0.08))
                    .frame(width: 140, height: 140)
                AnchorGlyph()
                    .fill(AnchorDesign.anchor,
                          style: FillStyle(eoFill: true, antialiased: true))
                    .frame(width: 75, height: 75)
            }
            .padding(.top, AnchorDesign.spacingM)

            VStack(spacing: AnchorDesign.spacingS) {
                Text("Welcome to Anchor")
                    .font(.system(size: 28, weight: .semibold))
                Text("Watch over your Mac. Walk away in peace.")
                    .font(AnchorDesign.bodyFont)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: AnchorDesign.spacingM) {
                Text("Here's how Anchor protects you:")
                    .font(AnchorDesign.sectionTitle)
                    .padding(.bottom, 2)

                bulletRow(
                    icon: "lock.fill",
                    title: "One shortcut to arm",
                    text: "Press \(hotkey.displayLabel) anywhere on your Mac. The screen locks and the alarm is armed in one motion."
                )

                bulletRow(
                    icon: "shield.lefthalf.filled",
                    title: "Smart triggers",
                    text: "Anchor watches the lid, power adapter, and trusted devices. Any disruption fires the alarm — even through a closed lid."
                )

                bulletRow(
                    icon: "person.fill.checkmark",
                    title: "Calm disarm",
                    text: "Touch ID at the lock screen disarms instantly. macOS verified you — that's enough."
                )
            }
        }
    }

    private func bulletRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: AnchorDesign.spacingM) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AnchorDesign.anchor)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(AnchorDesign.anchor.opacity(0.10))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text).font(AnchorDesign.bodyFont).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    // MARK: Permissions

    @State private var cameraStatus: String = "checking…"
    @State private var loginItemsHint: Bool = false

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: AnchorDesign.spacingL) {
            Text("Permissions")
                .font(.system(size: 26, weight: .semibold))
            Text("Anchor only asks for what it actually uses.")
                .font(AnchorDesign.bodyFont)
                .foregroundStyle(.secondary)

            permissionCard(
                icon: "camera.fill",
                title: "Camera",
                why: "If the alarm fires, Anchor captures photos so you can see who tried to take your Mac.",
                status: cameraStatus,
                action: "Open Privacy & Security…",
                onAction: openCameraPrivacy
            )

            permissionCard(
                icon: "antenna.radiowaves.left.and.right",
                title: "Bluetooth",
                why: "Anchor senses when your trusted devices (phone, AirPods, watch) are nearby and dampens false alarms.",
                status: "Granted on first use",
                action: nil,
                onAction: nil
            )

            permissionCard(
                icon: "shield.lefthalf.filled.badge.checkmark",
                title: "Login Items & Extensions",
                why: "Anchor needs to install a background helper and a privileged daemon. Both let it work silently after you arm — no Touch ID prompts per arm.",
                status: "Approve once in System Settings",
                action: "Open Login Items…",
                onAction: openLoginItems
            )
        }
        .onAppear { refreshCameraStatus() }
    }

    private func permissionCard(
        icon: String, title: String, why: String,
        status: String, action: String?, onAction: (() -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: AnchorDesign.spacingM) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AnchorDesign.anchor)
                .frame(width: 36, height: 36)
                .background(Circle().fill(AnchorDesign.anchor.opacity(0.10)))

            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(why)
                    .font(AnchorDesign.bodyFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    AnchorStatusPill(status, tone: status.lowercased().contains("granted") ? .healthy : .neutral)
                    if let action = action, let onAction = onAction {
                        Spacer()
                        Button(action, action: onAction)
                            .buttonStyle(.bordered)
                    }
                }
            }
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
        VStack(spacing: AnchorDesign.spacingL) {
            Text("Your arming shortcut")
                .font(.system(size: 26, weight: .semibold))
            Text("Press this combo anywhere on your Mac to lock and arm Anchor in one motion. Pick your own if you'd rather.")
                .font(AnchorDesign.bodyFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // The current shortcut, shown big and beautiful.
            HStack(spacing: AnchorDesign.spacingS) {
                ForEach(Array(hotkey.displayLabel), id: \.self) { ch in
                    Text(String(ch))
                        .font(.system(size: 36, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AnchorDesign.anchor)
                        .frame(width: 56, height: 64)
                        .background(
                            RoundedRectangle(cornerRadius: AnchorDesign.radiusM, style: .continuous)
                                .fill(AnchorDesign.anchor.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AnchorDesign.radiusM, style: .continuous)
                                .strokeBorder(AnchorDesign.anchor.opacity(0.25), lineWidth: 1)
                        )
                }
            }
            .padding(.vertical, AnchorDesign.spacingL)

            KeyRecorder(binding: $hotkey) { newBinding in
                HotkeyStore.save(newBinding)
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.helperClient?.reloadHotkey()
                }
            }
        }
    }

    // MARK: Hear the alarm

    @State private var hasHeardAlarm = false

    private var hearAlarmStep: some View {
        VStack(spacing: AnchorDesign.spacingL) {
            Text("Hear the alarm")
                .font(.system(size: 26, weight: .semibold))
            Text("This is the sound a thief hears. Try it now so you know what to expect — and so you trust it'll fire when you walk away.")
                .font(AnchorDesign.bodyFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, AnchorDesign.spacingM)

            // Big speaker visual
            ZStack {
                Circle()
                    .fill(AnchorDesign.alarm.opacity(0.08))
                    .frame(width: 140, height: 140)
                Image(systemName: hasHeardAlarm ? "checkmark.circle.fill" : "speaker.wave.3.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(hasHeardAlarm ? AnchorDesign.healthy : AnchorDesign.alarm)
            }

            Button {
                hasHeardAlarm = true
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.helperClient?.testAlarm(seconds: 3.0)
                }
            } label: {
                Label(
                    hasHeardAlarm ? "Play again" : "Play the alarm",
                    systemImage: hasHeardAlarm ? "arrow.clockwise" : "play.fill"
                )
                .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .tint(AnchorDesign.alarm)
            .controlSize(.large)

            Text("Volume will be temporarily forced to max on internal speakers, then restored.")
                .font(AnchorDesign.captionFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, AnchorDesign.spacingS)
        }
    }

    // MARK: Done

    private var doneStep: some View {
        VStack(spacing: AnchorDesign.spacingL) {
            ZStack {
                Circle()
                    .fill(AnchorDesign.healthy.opacity(0.10))
                    .frame(width: 140, height: 140)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 70, weight: .light))
                    .foregroundStyle(AnchorDesign.healthy)
            }

            VStack(spacing: AnchorDesign.spacingS) {
                Text("You're set.")
                    .font(.system(size: 28, weight: .semibold))
                Text("Anchor is in your menu bar. Press \(hotkey.displayLabel) whenever you walk away.")
                    .font(AnchorDesign.bodyFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: AnchorDesign.spacingS) {
                AnchorStatusPill("Hotkey: \(hotkey.displayLabel)", tone: .neutral, icon: "command")
                AnchorStatusPill("Calm protector", tone: .healthy, icon: "shield.lefthalf.filled")
            }
            .padding(.top, AnchorDesign.spacingM)
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
            .tint(AnchorDesign.anchor)
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

// MARK: - Persistence

enum OnboardingState {
    private static let key = "anchor.onboarding.completed"

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markComplete() {
        UserDefaults.standard.set(true, forKey: key)
    }
}
