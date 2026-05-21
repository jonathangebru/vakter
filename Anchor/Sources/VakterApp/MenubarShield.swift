import SwiftUI
import VakterShared

/// The SwiftUI view we host inside the menubar's `NSStatusItem`.
///
/// Visual states (post-revamp):
///   - `.unarmed`  : monochrome lighthouse glyph, very slow 6 s breath
///                   (1 % scale) — reads as "alive but resting".
///                   Lantern dot dark.
///   - `.armed`    : navy lighthouse + tighter 3 s breath (4 % scale),
///                   warm amber lantern dot lit at the dome.
///   - `.grace`    : slate-blue lighthouse + concentric pulse ring
///                   (1.4 s cycle, watching faster). Lantern still amber.
///   - `.alarm`    : coral lighthouse + aggressive bounce (0.6 s loop)
///                   + 3 ripple rings expanding outward. Lantern dot
///                   blazes coral and pulses with the bounce.
///
/// All animations are driven by a single continuously-ticking `phase`
/// value, so transitions between states blend smoothly without snapping.
///
/// The lighthouse here uses the simplified `.menubar` variant (no
/// gallery, no separate lantern room) so the silhouette stays crisp
/// at 18pt; the full lighthouse with all the architectural detail is
/// rendered at icon / onboarding / arming-overlay scale instead.
struct MenubarShield: View {

    let state: VakterState

    @State private var phase: CGFloat = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            // Pulse ring(s) behind the glyph — only visible in grace/alarm.
            ForEach(0..<pulseRingCount, id: \.self) { i in
                pulseRing(index: i)
            }
            // The lighthouse silhouette.
            LighthouseGlyph.menubar
                .fill(
                    glyphColor,
                    style: FillStyle(eoFill: true, antialiased: true)
                )
                .scaleEffect(glyphScale)
                .opacity(glyphOpacity)
                .animation(VakterDesign.easeGentle, value: state)

            // The lantern dot at the dome — same scale modulation as the
            // tower so they breathe together, then state-tinted.
            if let lantern = lanternDotColor {
                Circle()
                    .fill(lantern)
                    .frame(width: 2.6, height: 2.6)
                    .shadow(color: lantern.opacity(0.55), radius: 1.4, x: 0, y: 0)
                    .opacity(lanternOpacity)
                    .scaleEffect(glyphScale)
                    .position(
                        x: 18 * LighthouseGlyph.menubarLanternUnit().x,
                        y: 18 * LighthouseGlyph.menubarLanternUnit().y
                    )
                    .animation(VakterDesign.easeStandard, value: state)
            }
        }
        .frame(width: 18, height: 18)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vakter, \(accessibilityStateLabel)")
        .accessibilityHint("Open the Vakter menu")
        .onAppear { startTicking() }
        .onDisappear { timer?.invalidate() }
    }

    /// Plain-English label spoken by VoiceOver instead of raw rawValues.
    private var accessibilityStateLabel: String {
        switch state {
        case .unarmed: return "off watch"
        case .armed:   return "on watch"
        case .grace:   return "grace period"
        case .alarm:   return "alarm engaged"
        }
    }

    // MARK: Lantern dot

    /// Colour of the tiny "light" at the dome. Nil = no dot drawn
    /// (the resting state — Vakter is alive but the lamp is dark).
    private var lanternDotColor: Color? {
        switch state {
        case .unarmed: return nil
        case .armed:   return VakterDesign.lantern
        case .grace:   return VakterDesign.lantern
        case .alarm:   return VakterDesign.alarm
        }
    }

    /// Phase-modulated dot opacity. The dot pulses brighter in alarm
    /// and slowly breathes when armed, matching the tower's rhythm.
    private var lanternOpacity: Double {
        switch state {
        case .unarmed: return 0.0
        case .armed:   return 0.85 + 0.15 * Double(sin(phase * 2 * .pi / 3.0))
        case .grace:   return 0.80 + 0.20 * Double(sin(phase * 2 * .pi))
        case .alarm:   return 0.70 + 0.30 * Double(sin(phase * 4 * .pi))
        }
    }

    // MARK: Per-state visual parameters

    private var glyphColor: Color {
        // All four states use appearance-adapting colours so the
        // lighthouse stays visible on both light and dark menubars.
        // Pre-v1.0 used the fixed `VakterDesign.anchor` navy for armed,
        // which was ~10% contrast on the dark-mode menubar background
        // (effectively invisible). The adaptive variants flip to a
        // soft moonlight blue-white in dark mode, keeping the visual
        // language (cool, calm) while restoring contrast.
        switch state {
        case .unarmed: return Color.primary.opacity(0.65)
        case .armed:   return VakterDesign.anchorAdaptive
        case .grace:   return VakterDesign.watchAdaptive
        case .alarm:   return VakterDesign.alarm    // coral stays vivid on both
        }
    }

    /// Scale modulation per state. The unarmed state now has a very subtle
    /// breath (1 % amplitude, 6 s cycle) so the menubar reads as "watching
    /// but resting" rather than "dead". Distinguishes us from competitors
    /// whose menubar icons sit completely static.
    private var glyphScale: CGFloat {
        switch state {
        case .unarmed:
            // Very slow, very gentle breath — barely perceptible but
            // visible at the edge of attention.
            return 1.0 + 0.01 * sin(phase * 2 * .pi / 6.0)
        case .armed:
            // 3 s breath, 4 % amplitude — confident, watching.
            return 1.0 + 0.04 * sin(phase * 2 * .pi / 3.0)
        case .grace:
            return 1.0 + 0.06 * sin(phase * 2 * .pi)
        case .alarm:
            return 1.0 + 0.12 * sin(phase * 4 * .pi)
        }
    }

    private var glyphOpacity: Double {
        switch state {
        case .unarmed: return 1.0
        case .armed:   return 1.0
        case .grace:   return 0.92 + 0.08 * Double(sin(phase * 2 * .pi))
        case .alarm:   return 0.85 + 0.15 * Double(sin(phase * 4 * .pi))
        }
    }

    private var pulseRingCount: Int {
        switch state {
        case .unarmed, .armed: return 0
        case .grace:           return 2
        case .alarm:           return 3
        }
    }

    private func pulseRing(index: Int) -> some View {
        // Each ring is offset in phase so they ripple outward in sequence.
        let stagger = CGFloat(index) * 0.25
        let cycle: CGFloat = state == .alarm ? 0.6 : 1.4
        let p = ((phase / cycle) + stagger).truncatingRemainder(dividingBy: 1)
        return Circle()
            .strokeBorder(
                state == .alarm ? VakterDesign.alarm : VakterDesign.watch,
                lineWidth: 1.2
            )
            .scaleEffect(0.55 + p * 0.9)
            .opacity(Double(1.0 - p))
    }

    // MARK: Animation engine

    /// We drive phase via Timer rather than SwiftUI's `.timeline` because
    /// we want a stable, smooth pulse independent of view recomputation
    /// (the menubar gets aggressively redrawn by AppKit).
    private func startTicking() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            DispatchQueue.main.async {
                phase += 1.0 / 30.0
                if phase > 1000 { phase = 0 } // never overflow
            }
        }
    }
}
