import SwiftUI
import AnchorShared

/// The SwiftUI view we host inside the menubar's `NSStatusItem`.
///
/// Visual states:
///   - `.unarmed`  : monochrome anchor glyph, secondary colour, no animation
///   - `.armed`    : navy anchor + subtle ambient breath (3 s loop)
///   - `.grace`    : navy anchor + concentric pulse ring (faster, watching)
///   - `.alarm`    : coral anchor + aggressive bounce (0.6 s loop)
///
/// All animations are SwiftUI implicit so transitions blend smoothly when
/// the state machine pushes a new snapshot mid-animation.
struct MenubarShield: View {

    let state: AnchorState

    // Drive the pulse animations from a single phase value that ticks
    // continuously while the view is alive.
    @State private var phase: CGFloat = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            // Pulse ring(s) behind the glyph — only visible in grace/alarm.
            ForEach(0..<pulseRingCount, id: \.self) { i in
                pulseRing(index: i)
            }
            // The anchor itself.
            AnchorGlyph()
                .fill(
                    glyphColor,
                    style: FillStyle(eoFill: true, antialiased: true)
                )
                .scaleEffect(glyphScale)
                .opacity(glyphOpacity)
                .animation(.spring(response: 0.45, dampingFraction: 0.6),
                           value: state)
        }
        .frame(width: 18, height: 18)
        .padding(.horizontal, 2)
        .onAppear { startTicking() }
        .onDisappear { timer?.invalidate() }
    }

    // MARK: Per-state visual parameters

    private var glyphColor: Color {
        switch state {
        case .unarmed: return Color.primary.opacity(0.65)
        case .armed:   return AnchorDesign.anchor
        case .grace:   return AnchorDesign.watch
        case .alarm:   return AnchorDesign.alarm
        }
    }

    private var glyphScale: CGFloat {
        switch state {
        case .unarmed: return 1.0
        case .armed:   return 1.0 + 0.04 * sin(phase * .pi)     // gentle breath
        case .grace:   return 1.0 + 0.06 * sin(phase * 2 * .pi)
        case .alarm:   return 1.0 + 0.12 * sin(phase * 4 * .pi) // aggressive
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
                state == .alarm ? AnchorDesign.alarm : AnchorDesign.watch,
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
