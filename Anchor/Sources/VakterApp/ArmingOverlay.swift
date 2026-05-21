import SwiftUI
import AppKit
import VakterShared

/// The signature "On watch" arming moment.
///
/// When the user presses their arming hotkey (or clicks Arm from the
/// menubar), the helper transitions to `.armed` and schedules the
/// system screen-lock to engage 0.6 s later (`ScreenLocker.lockScreen(after:)`).
/// During that 0.6 s window the menubar app renders this full-screen
/// overlay: a calm anchor-gradient background, the hero anchor glyph
/// with rings rippling outward, and a brief "On watch" caption with
/// the etymology tagline.
///
/// The overlay fades in fast (0.18 s), holds, and fades out as the
/// screen lock takes over. Visually it's the *handoff* — the moment
/// Vakter assumes the watch.
///
/// Implementation notes:
///   - We use a borderless transparent NSWindow at .floating level
///     covering the full screen. It doesn't intercept clicks
///     (`ignoresMouseEvents = true`) so even mid-fade the user can't
///     get stuck.
///   - Released when fade-out completes; recreated on next arm.
///   - Lives entirely in the menubar app — no XPC roundtrip needed.
@MainActor
final class ArmingOverlayController {

    private var window: NSWindow?

    /// Show the overlay. Fades in over `fadeIn` seconds, holds for
    /// `hold` seconds, fades out over `fadeOut` seconds, then closes.
    /// Total duration ≈ fadeIn + hold + fadeOut (≈ 0.6 s by default).
    func show(
        fadeIn: TimeInterval = 0.18,
        hold: TimeInterval = 0.24,
        fadeOut: TimeInterval = 0.18
    ) {
        // If a previous overlay is still in-flight, dismiss it
        // immediately and replace.
        window?.orderOut(nil)
        window = nil

        guard let screen = NSScreen.main else { return }

        // Borderless transparent window, full-screen.
        let w = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = .floating
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        // The borderless + ignoresMouseEvents combination already
        // prevents this from stealing focus or accepting clicks.

        let host = NSHostingView(rootView: ArmingOverlayView())
        host.frame = screen.frame
        w.contentView = host
        w.alphaValue = 0
        w.orderFrontRegardless()

        self.window = w

        // Fade in → hold → fade out → close.
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fadeIn
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            w.animator().alphaValue = 1.0
        }, completionHandler: {
            DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
                guard let self = self, let w = self.window else { return }
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = fadeOut
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    w.animator().alphaValue = 0.0
                }, completionHandler: { [weak self] in
                    self?.window?.orderOut(nil)
                    self?.window = nil
                })
            }
        })
    }

    /// Force-dismiss any in-flight overlay. Called when the helper
    /// publishes an .unarmed snapshot mid-flight (rare but possible
    /// if the user disarms during the 0.6 s window).
    func dismissImmediately() {
        window?.orderOut(nil)
        window = nil
    }
}

// MARK: - SwiftUI content

private struct ArmingOverlayView: View {

    /// Local animation phase — drives a subtle scale-in on the hero
    /// glyph from 0.92 → 1.0 to give the moment a tactile arrival
    /// instead of a flat fade.
    @State private var arrivePhase: CGFloat = 0.92
    @State private var captionVisible: Bool = false

    var body: some View {
        ZStack {
            // Calm anchor-gradient background, very subtle.
            VakterDesign.anchorGradient
                .opacity(0.92)
                .ignoresSafeArea()

            // Soft vignette so the centre is brighter.
            RadialGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.35)
                ],
                center: .center,
                startRadius: 80,
                endRadius: 900
            )
            .ignoresSafeArea()

            // Hero brand mark + caption. Lighthouse with white silhouette
            // and a warm amber lantern.
            VStack(spacing: VakterDesign.spacingL) {
                LighthouseHeroMark(
                    cycleSeconds: 2.4,
                    size: 240,
                    silhouetteColor: .white,
                    beamColor: VakterDesign.lantern
                )
                .scaleEffect(arrivePhase)

                VStack(spacing: VakterDesign.spacingS) {
                    Text("On watch")
                        // Pre-v1.2 used serif italic — read as
                        // "wedding invitation" rather than security
                        // app. SF Pro Display semibold is the macOS
                        // Sequoia hero type style and matches the
                        // wordmark elsewhere in the app.
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(.white)
                        .tracking(-0.5)
                        .opacity(captionVisible ? 1.0 : 0.0)
                        .offset(y: captionVisible ? 0 : 8)

                    Text("Vakter has the deck.")
                        .font(VakterDesign.bodyFont)
                        .foregroundStyle(.white.opacity(0.72))
                        .opacity(captionVisible ? 1.0 : 0.0)
                }
                .animation(VakterDesign.easeStandard.delay(0.08), value: captionVisible)
            }
        }
        .onAppear {
            withAnimation(VakterDesign.springTactile) {
                arrivePhase = 1.0
            }
            // Slight delay on the caption so the glyph arrives first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                captionVisible = true
            }
        }
        // VoiceOver: announce the moment as a single phrase so users
        // hear "Vakter is on watch" rather than the glyph + two text
        // labels read independently. The overlay only lives ~0.6 s
        // before the screen lock takes over, so we want the spoken
        // confirmation to land cleanly.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vakter is on watch")
        .accessibilityAddTraits(.isStaticText)
    }
}
