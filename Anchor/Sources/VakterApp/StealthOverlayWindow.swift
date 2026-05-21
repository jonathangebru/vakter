import AppKit
import SwiftUI
import VakterShared

/// The stealth lock-screen takeover. When Vakter enters the `.alarm`
/// state, every connected display is covered by a fullscreen, opaque,
/// high-contrast "STOLEN MAC" overlay window — rendered *above* the
/// macOS lock screen so a thief picking up the Mac sees an unambiguous
/// dead end and a Good Samaritan sees the owner's return-contact info.
///
/// ### Window layering
///
/// macOS's lock screen window sits at `NSWindow.Level.screenSaver`
/// (kCGScreenSaverWindowLevel, raw value 1000). We use `.screenSaver`
/// for our window too. AppKit gives the more recently ordered-front
/// window precedence at the same level, so by calling
/// `orderFrontRegardless()` *after* the system lock screen has appeared
/// we stay visible on top. (Empirically the system lock screen lets
/// us stay on top because we are a foreground app at the same level;
/// if Apple were to reserve the level we'd need to bump to
/// `NSWindow.Level(rawValue: .screenSaver.rawValue + 1)`.)
///
/// ### Multi-monitor
///
/// We create one window per `NSScreen.screens` entry. Each window is
/// sized to that screen's frame (not `visibleFrame` — we want the
/// overlay to cover the menu bar and Dock too). The collection
/// behaviour `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`
/// keeps the overlay visible across desktop Space switches.
///
/// ### Lifecycle
///
/// `show(...)` is idempotent — calling it twice in a row tears down
/// the previous set and creates fresh windows. `dismiss()` orders all
/// windows out and releases them. The controller is `@MainActor`
/// because AppKit window manipulation must happen on the main thread,
/// and SwiftUI's `NSHostingController` requires it.
///
/// ### Why not borderless transparent + click-through?
///
/// The arming overlay (`ArmingOverlayController`) uses
/// `ignoresMouseEvents = true` so it can sit on top of the user's work
/// without blocking interaction. The stealth overlay does the
/// opposite: it **must** block clicks because the whole point is to
/// be a takeover. Falling back to the work below would let a thief
/// click the Vakter menu icon and quit the app. We set
/// `ignoresMouseEvents = false` and allow taps (used by the tappable
/// `tel:` link on the callback number).
@MainActor
final class StealthOverlayWindowController: NSObject {

    /// One window per attached display. Held strongly so AppKit doesn't
    /// release them when ordered out. Drained on every `dismiss()`.
    private var windows: [NSWindow] = []

    /// Auto-dismiss timer used by the Settings → General preview
    /// button. Cancelled if a real alarm shows the overlay or the
    /// user explicitly dismisses. Nil when no preview is in flight.
    private var autoDismissTimer: Timer?

    /// True while at least one overlay window is currently visible.
    /// The Settings preview button uses this to disable itself
    /// during an in-flight preview so the user can't stack them.
    var isVisible: Bool { !windows.isEmpty }

    // Note: no explicit deinit. The controller is owned by AppDelegate
    // and lives for the duration of the process. Swift 6 strict
    // concurrency would also reject a deinit that touches `Timer`
    // (non-Sendable) from the nonisolated synthesised deinit, so the
    // alternative would be MainActor-isolated deinit ceremony for no
    // real-world cleanup benefit.

    // MARK: - Public API

    /// Show the stealth overlay on every connected display. Idempotent —
    /// if a previous overlay is still visible (e.g. multi-display
    /// arrangement just changed and we re-show on a fresh
    /// configuration), we tear it down first so we never accumulate
    /// duplicate windows.
    ///
    /// - Parameters:
    ///   - config: the user's persisted message + callback. The
    ///     view consults `config.displayMessage` / `displayCallback`
    ///     so empty-field handling lives in one place (the model).
    ///   - autoDismissAfter: if non-nil, dismiss automatically after
    ///     this many seconds. Used by the Settings preview button
    ///     (8 s default). For the real alarm path, pass `nil` — the
    ///     overlay stays until the state machine transitions out of
    ///     `.alarm` and the snapshot subscription calls `dismiss()`.
    func show(
        config: StealthOverlayConfig,
        autoDismissAfter: TimeInterval? = nil
    ) {
        // Cancel any prior preview timer; if we're re-showing for a
        // real alarm we don't want a leftover 8 s preview timer to
        // dismiss the real alarm overlay mid-event.
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil

        // Tear down any prior windows. Cheap and bulletproof — we'd
        // rather rebuild than try to reconcile against an existing
        // set when the screen configuration may have changed.
        for w in windows { w.orderOut(nil) }
        windows.removeAll(keepingCapacity: true)

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            NSLog("[StealthOverlay] NSScreen.screens is empty — no overlay shown")
            return
        }

        // The view is the same on every screen — same headline, same
        // user message, same callback. Sharing one config instance
        // across screens keeps tap affordances identical (Good
        // Samaritan can tap the call link on whichever screen they
        // see first).
        for (index, screen) in screens.enumerated() {
            let view = StealthOverlayView(config: config)
            let host = NSHostingView(rootView: view)
            // Older NSWindow init with explicit content rect / style /
            // backing — same form the ArmingOverlay uses. The
            // `init(contentViewController:)` form returns a window
            // whose type inference under Swift 6 strict concurrency
            // confuses the subsequent style/level/collectionBehavior
            // setters (each becomes "can't resolve without contextual
            // type"). Explicit init dodges that.
            let win = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            host.frame = NSRect(origin: .zero, size: screen.frame.size)
            win.contentView = host

            // .screenSaver maps to kCGScreenSaverWindowLevel == 1000,
            // the same level the macOS lock screen uses. We rely on
            // "later ordered-front wins" at equal levels — see file
            // header docs for why we don't bump above this.
            win.level = .screenSaver

            // Opaque dark surface — not see-through. Different from
            // the arming overlay which uses a translucent gradient.
            // The thief should NOT see what the user was doing.
            win.backgroundColor = NSColor(red: 0.04, green: 0.08, blue: 0.14, alpha: 1.0)
            win.isOpaque = true
            win.hasShadow = false

            // Cross Spaces + survive fullscreen Space switches.
            win.collectionBehavior = [
                .canJoinAllSpaces,
                .stationary,
                .fullScreenAuxiliary
            ]

            // Block clicks. The thief must NOT be able to click
            // through to the Vakter menubar item to quit the app.
            // The tappable callback link inside the view still
            // works because clicks land on the SwiftUI hit-test
            // first; we only ignore the "fall through to other apps"
            // behaviour.
            win.ignoresMouseEvents = false

            // Don't let AppKit retain this window after we drop it
            // from `windows` — we own the lifecycle explicitly.
            win.isReleasedWhenClosed = false

            // Cover the *entire* screen including menu bar and Dock.
            // `frame` (not `visibleFrame`) is what we want.
            win.setFrame(screen.frame, display: true)

            // makeKey only on the primary screen so VoiceOver focus
            // lands on the most prominent overlay. orderFrontRegardless
            // is the magic call — without it AppKit can decide our
            // borderless window isn't "important enough" to surface
            // above the lock screen.
            if index == 0 {
                win.makeKeyAndOrderFront(nil)
            }
            win.orderFrontRegardless()

            // Defensive: if Apple ever changes the screenSaver level
            // semantics, surface it loudly in Console rather than
            // silently slipping behind the lock screen.
            assert(
                win.level.rawValue >= NSWindow.Level.screenSaver.rawValue,
                "stealth overlay window level slipped below screenSaver"
            )

            windows.append(win)
        }

        NSLog(
            "[StealthOverlay] shown on %d screen(s); autoDismiss=%@",
            screens.count,
            autoDismissAfter.map { "\($0)s" } ?? "off"
        )

        if let interval = autoDismissAfter {
            scheduleAutoDismiss(after: interval)
        }
    }

    /// Dismiss every overlay window. Safe to call when nothing is
    /// visible — orders are no-ops. Cancels any pending auto-dismiss
    /// timer so a stale preview doesn't fire after a real alarm
    /// has already been disarmed.
    func dismiss() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil

        for w in windows {
            w.orderOut(nil)
        }
        windows.removeAll(keepingCapacity: false)
    }

    // MARK: - Auto-dismiss (preview)

    private func scheduleAutoDismiss(after seconds: TimeInterval) {
        autoDismissTimer?.invalidate()
        // Plain Timer (not DispatchSourceTimer) — we want it bound to
        // the main run loop. We re-enter @MainActor inside the closure
        // because Timer.scheduledTimer's closure isn't @Sendable in a
        // way the compiler can prove for an instance method capture.
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismiss()
            }
        }
        autoDismissTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}

// MARK: - SwiftUI content

/// The visual surface of the stealth overlay. Dark background, huge
/// alarm-red "STOLEN MAC" headline with a subtle pulse, user message,
/// callback line (tappable when phone-shaped), and a small Vakter
/// wordmark at the bottom so the device is identifiable as a
/// Vakter-protected Mac (deterrence by familiarity).
///
/// The hierarchy is deliberately simple: one VStack, no nested cards.
/// On a stranger picking up the Mac, the visual must read in <1
/// second from across a room.
private struct StealthOverlayView: View {

    let config: StealthOverlayConfig

    /// Pulse phase for the "STOLEN MAC" headline scale animation.
    /// Animated from 1.0 → 1.06 → 1.0 with a 2 s cycle. Drives a
    /// subtle attention beacon similar to the menubar lighthouse
    /// pulse — present but not seizure-inducing.
    @State private var pulse: CGFloat = 1.0

    /// Respect the system "Reduce motion" accessibility setting.
    /// If the user has it on, we skip the pulse entirely (a static
    /// hero text is still bold and unmistakable).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Full-bleed dark fill. Solid (not gradient) for maximum
            // legibility from a distance and to avoid any chance the
            // background reads as "still part of the user's work."
            Color(red: 0.04, green: 0.08, blue: 0.14)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // ───── Hero headline ─────
                Text("STOLEN MAC")
                    // 120 pt @ heavy: legible from across a coffee
                    // shop. Slightly tighter tracking gives it the
                    // weight of a stamped warning.
                    .font(.system(size: 120, weight: .heavy, design: .default))
                    .tracking(-2)
                    .foregroundStyle(Color(red: 0.95, green: 0.31, blue: 0.30))
                    .shadow(
                        color: Color(red: 0.95, green: 0.31, blue: 0.30).opacity(0.45),
                        radius: 24, x: 0, y: 0
                    )
                    .scaleEffect(pulse)
                    .accessibilityAddTraits(.isStaticText)

                Spacer(minLength: 32).fixedSize()

                // ───── Owner message ─────
                // displayMessage falls back to the baked-in default
                // when the user has not configured anything, so this
                // line is ALWAYS present. We never render a void below
                // the headline.
                Text(config.displayMessage)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 80)
                    .frame(maxWidth: 900)

                Spacer(minLength: 28).fixedSize()

                // ───── Callback line ─────
                // Only rendered when the user has set one — without
                // a callback there's nothing to dial, and showing an
                // empty "Call:" label would be worse than omitting.
                if let callback = config.displayCallback {
                    callbackView(callback)
                }

                Spacer(minLength: 0)

                // ───── Subtle Vakter signature ─────
                // Bottom-corner wordmark. Two purposes:
                //   1. Brand identification — a Vakter user can spot
                //      one in the wild.
                //   2. Deterrent context — the thief learns the Mac
                //      is running a known anti-theft app, which
                //      raises the cost of attempting to use it.
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("Vakter")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.bottom, 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Single VoiceOver phrase so screen-reader users hear "stolen
        // Mac" and the owner message as one statement, not as five
        // independent labels.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityComposite)
        .onAppear {
            guard !reduceMotion else { return }
            // Continuous gentle pulse. SwiftUI handles the repeating
            // animation; we just toggle pulse to a higher value once
            // and the autoreverses handles the rest.
            withAnimation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
            ) {
                pulse = 1.06
            }
        }
    }

    // MARK: - Callback line

    /// Renders the callback string. If it parses as a phone number
    /// we wrap it as a `Button` that opens the `tel:` URL, so any
    /// passer-by with a nearby iPhone (via Continuity) can call
    /// from the lock screen via Tap-to-Call. If the user wrote
    /// something non-phone-shaped ("Email: jane@example.com",
    /// "Telegram: @owner") we render it as plain text — the
    /// information is still visible, just not tappable.
    @ViewBuilder
    private func callbackView(_ raw: String) -> some View {
        if let telURL = config.telURL {
            Button {
                NSWorkspace.shared.open(telURL)
            } label: {
                callbackLabel(raw, underlined: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Call \(raw)")
            .accessibilityAddTraits(.isButton)
        } else {
            callbackLabel(raw, underlined: false)
        }
    }

    private func callbackLabel(_ raw: String, underlined: Bool) -> some View {
        // Monospace digits so an 8 looks like an 8 from across a room.
        // System weight semibold rather than heavy so the headline
        // wins the eye but this line still draws follow-on attention.
        Text(raw)
            .font(.system(size: 44, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color(red: 0.98, green: 0.82, blue: 0.45))
            .underline(underlined, color: Color(red: 0.98, green: 0.82, blue: 0.45).opacity(0.45))
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        Color(red: 0.98, green: 0.82, blue: 0.45).opacity(0.35),
                        lineWidth: 1.5
                    )
            )
    }

    /// One-shot screen-reader phrase. We intentionally do NOT include
    /// the headline ("Stolen Mac") twice (it's also visually styled);
    /// we read it once at the start, then read the user's message and
    /// callback in plain sequence.
    private var accessibilityComposite: String {
        var parts: [String] = ["This Mac is reported stolen."]
        parts.append(config.displayMessage)
        if let cb = config.displayCallback {
            parts.append("Contact: \(cb)")
        }
        return parts.joined(separator: " ")
    }
}
