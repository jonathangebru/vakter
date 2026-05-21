import SwiftUI
import AppKit
import VakterShared

/// The dedicated "About Vakter" window.
///
/// Lives outside Settings because that's how Mac users expect to find
/// it (every Mac app has one; LSUIElement apps just have to be explicit
/// about how it's invoked — for Vakter the entry point is the menubar
/// dropdown, not the app menu).
///
/// Design follows § 11 of the design-concepts page: small panel,
/// lighthouse glyph, version metadata in monospace, etymology eyebrow,
/// three small action buttons. Intentionally restrained.
@MainActor
final class AboutWindowController {

    private var window: NSWindow?

    /// Open the About window, or bring it to the front if already shown.
    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = NSHostingController(rootView: AboutWindowView())
        let win = NSWindow(contentViewController: host)
        win.styleMask = [.titled, .closable]
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.title = "About Vakter"
        win.setContentSize(NSSize(width: 380, height: 460))
        win.center()
        win.isReleasedWhenClosed = false

        // Track close → release the window so the next show() rebuilds.
        // The notification queue posts on .main but Swift 6 strict-
        // concurrency doesn't believe us; bounce through Task @MainActor.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.window = nil
            }
        }

        self.window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}

// MARK: - View

private struct AboutWindowView: View {

    var body: some View {
        VStack(spacing: 0) {
            // Glyph + name block
            VStack(spacing: 16) {
                LighthouseHeroMark(cycleSeconds: 4.4, size: 96)
                    .padding(.top, 30)

                VStack(spacing: 4) {
                    Text("Vakter")
                        .font(.system(size: 26, weight: .semibold))
                        .tracking(-0.6)

                    Text("Norwegian — the night-watchmen")
                        .font(.system(size: 10, weight: .semibold).monospaced())
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(VakterDesign.lantern)
                }

                Text(versionLine)
                    .font(.system(size: 11.5, weight: .regular).monospaced())
                    .tracking(0.4)
                    .foregroundStyle(.secondary)

                Text("Built by Jonathan Gebru. Solo dev. Email replies within a day.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                    .padding(.top, 4)
            }
            .padding(.bottom, 24)

            Divider().opacity(0.4)

            // Action row
            HStack(spacing: 8) {
                AboutActionButton(
                    title: "Privacy & security",
                    url: URL(string: "https://vakter.app/security")
                )
                AboutActionButton(
                    title: "vakter.app",
                    url: URL(string: "https://vakter.app")
                )
                AboutActionButton(
                    title: "Changelog",
                    url: URL(string: "https://vakter.app/changelog")
                )
            }
            .padding(20)
        }
        .frame(width: 380, height: 460)
        .background(
            // Subtle radial-gradient atmosphere — same vocabulary as the
            // arming overlay, but quiet (this is the About window, not a
            // hero moment).
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                RadialGradient(
                    colors: [
                        VakterDesign.lantern.opacity(0.06),
                        Color.clear
                    ],
                    center: .top,
                    startRadius: 4,
                    endRadius: 220
                )
            }
            .ignoresSafeArea()
        )
    }

    private var versionLine: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        #if arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "unknown"
        #endif
        return "v\(short) · build \(build) · \(arch)"
    }
}

// MARK: - Action button

private struct AboutActionButton: View {
    let title: String
    let url: URL?

    @State private var hovering = false

    var body: some View {
        Button {
            if let url = url { NSWorkspace.shared.open(url) }
        } label: {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? VakterDesign.lantern.opacity(0.16) : Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            hovering ? VakterDesign.lantern.opacity(0.4) : Color.primary.opacity(0.12),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
