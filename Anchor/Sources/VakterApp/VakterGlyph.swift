import SwiftUI

/// The Vakter brand mark — a stylised maritime anchor silhouette.
///
/// Drawn as a SwiftUI Shape so it scales crisply at every render size
/// (menubar, settings sidebar, onboarding hero, arming overlay) and
/// respects light/dark mode without baked PNG assets. The proportions
/// are deliberate: generous negative space at the top (the ring),
/// strong vertical shaft, and curved arms that read at 16-22pt menubar
/// size and remain elegant at 200pt+ hero size.
///
/// Use the `.hero` variant for large renders (onboarding welcome,
/// About hero, arming overlay) — it has stronger weight + slightly
/// more graceful arm curves than the menubar default.
struct VakterGlyph: Shape {

    enum Variant {
        /// Default — tuned for 16-22pt menubar/sidebar/inline use.
        case standard
        /// Stronger weight + graceful arms — tuned for 60pt+ hero contexts.
        case hero
    }

    var variant: Variant = .standard

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let _ = rect.height
        // Normalise so the glyph fits inside the rect with breathing room.
        let inset = w * 0.08
        let inner = rect.insetBy(dx: inset, dy: inset)

        // Variant-specific weight tweaks. Hero gets slightly thicker
        // strokes and a slightly tighter ring, which read better at
        // large sizes without making the menubar version look heavy.
        let shaftThickRatio: CGFloat = (variant == .hero) ? 0.085 : 0.07
        let armThickRatio:   CGFloat = (variant == .hero) ? 0.065 : 0.05
        let ringDiameterRatio: CGFloat = (variant == .hero) ? 0.24 : 0.22
        let crossWidthRatio:  CGFloat = (variant == .hero) ? 0.50 : 0.45
        let crossThickRatio:  CGFloat = (variant == .hero) ? 0.075 : 0.06

        var p = Path()

        let centerX = inner.midX
        let topY    = inner.minY
        let bottomY = inner.maxY

        // 1) Top ring — a small circle that sits at the top.
        let ringDiameter = inner.width * ringDiameterRatio
        let ringCenterY  = topY + ringDiameter * 0.55
        let ringRect = CGRect(
            x: centerX - ringDiameter / 2,
            y: ringCenterY - ringDiameter / 2,
            width: ringDiameter,
            height: ringDiameter
        )
        p.addEllipse(in: ringRect)

        // 2) Vertical shaft from below the ring down to the cross-bar.
        let shaftTop    = ringCenterY + ringDiameter * 0.45
        let shaftBottom = bottomY - inner.height * 0.05

        // Cross-bar (horizontal) — narrow but present so the silhouette
        // reads as an anchor and not just a hook.
        let crossY      = shaftTop + inner.height * 0.10
        let crossWidth  = inner.width * crossWidthRatio
        let crossThick  = inner.height * crossThickRatio
        let crossRect = CGRect(
            x: centerX - crossWidth / 2,
            y: crossY - crossThick / 2,
            width: crossWidth,
            height: crossThick
        )
        p.addRoundedRect(in: crossRect, cornerSize: CGSize(width: crossThick / 2,
                                                            height: crossThick / 2))

        // 3) Shaft as a thin pill.
        let shaftThick = inner.width * shaftThickRatio
        let shaftRect = CGRect(
            x: centerX - shaftThick / 2,
            y: shaftTop,
            width: shaftThick,
            height: shaftBottom - shaftTop
        )
        p.addRoundedRect(in: shaftRect, cornerSize: CGSize(width: shaftThick / 2,
                                                            height: shaftThick / 2))

        // 4) Curved arms — two symmetrical hooks reaching out from the
        // shaft's bottom. Built as bezier arcs that flare outwards
        // then sweep upwards into a point.
        let armSpan   = inner.width * (variant == .hero ? 0.82 : 0.78)
        let armDip    = inner.height * 0.08
        let armRise   = inner.height * 0.18
        let leftBase  = CGPoint(x: centerX - inner.width * 0.05, y: shaftBottom)
        let rightBase = CGPoint(x: centerX + inner.width * 0.05, y: shaftBottom)

        // Left arm
        let leftTip = CGPoint(x: centerX - armSpan / 2, y: shaftBottom - armRise)
        let leftDip = CGPoint(x: centerX - armSpan / 4, y: shaftBottom + armDip)
        let leftThick = inner.width * armThickRatio
        p.move(to: CGPoint(x: leftBase.x, y: leftBase.y - leftThick))
        p.addQuadCurve(
            to: CGPoint(x: leftTip.x, y: leftTip.y),
            control: CGPoint(x: leftDip.x, y: leftDip.y - armDip * 0.4)
        )
        p.addLine(to: CGPoint(x: leftTip.x + leftThick * 0.6,
                               y: leftTip.y + leftThick * 0.6))
        p.addQuadCurve(
            to: CGPoint(x: leftBase.x, y: leftBase.y + leftThick),
            control: CGPoint(x: leftDip.x, y: leftDip.y + leftThick * 0.4)
        )
        p.closeSubpath()

        // Right arm (mirror)
        let rightTip = CGPoint(x: centerX + armSpan / 2, y: shaftBottom - armRise)
        let rightDip = CGPoint(x: centerX + armSpan / 4, y: shaftBottom + armDip)
        let rightThick = inner.width * armThickRatio
        p.move(to: CGPoint(x: rightBase.x, y: rightBase.y - rightThick))
        p.addQuadCurve(
            to: CGPoint(x: rightTip.x, y: rightTip.y),
            control: CGPoint(x: rightDip.x, y: rightDip.y - armDip * 0.4)
        )
        p.addLine(to: CGPoint(x: rightTip.x - rightThick * 0.6,
                               y: rightTip.y + rightThick * 0.6))
        p.addQuadCurve(
            to: CGPoint(x: rightBase.x, y: rightBase.y + rightThick),
            control: CGPoint(x: rightDip.x, y: rightDip.y + rightThick * 0.4)
        )
        p.closeSubpath()

        // 5) Subtract the ring's inner hole so the top reads as a ring,
        // not a solid disc. We do this by overlaying a smaller ellipse;
        // SwiftUI's even-odd fill rule handles it.
        let holeInset = ringDiameter * 0.32
        let holeRect = ringRect.insetBy(dx: holeInset, dy: holeInset)
        p.addEllipse(in: holeRect)

        return p
    }
}

extension VakterGlyph {
    /// Convenience: rendered as a single-colour silhouette with the
    /// even-odd fill rule (so the ring reads as a hole).
    func tinted(_ color: Color) -> some View {
        self
            .fill(color, style: FillStyle(eoFill: true, antialiased: true))
    }

    /// Convenience: hero-weight variant.
    static var hero: VakterGlyph {
        VakterGlyph(variant: .hero)
    }
}

/// A hero-quality animated brand mark for onboarding welcome,
/// About tab, and the arming overlay. Concentric pulse rings breathe
/// outward at a calm 4 s cycle, with a soft anchor-coloured glow ring
/// behind the glyph itself.
struct VakterHeroMark: View {

    /// Optional override to make the rings pulse a hair faster/slower —
    /// used by the arming overlay (faster) vs the welcome step (calmer).
    var cycleSeconds: Double = 4.0
    var size: CGFloat = 140
    var color: Color = VakterDesign.anchor

    @State private var phase: CGFloat = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            // Three concentric rings rippling outward.
            ForEach(0..<3, id: \.self) { i in
                ring(index: i)
            }

            // Soft halo behind the glyph.
            Circle()
                .fill(color.opacity(0.10))
                .frame(width: size * 0.70, height: size * 0.70)

            // The anchor itself — hero variant.
            VakterGlyph.hero
                .fill(color, style: FillStyle(eoFill: true, antialiased: true))
                .frame(width: size * 0.50, height: size * 0.50)
        }
        .frame(width: size, height: size)
        .onAppear { startTicking() }
        .onDisappear { timer?.invalidate() }
    }

    private func ring(index: Int) -> some View {
        let stagger = CGFloat(index) * 0.33
        let cycle = CGFloat(cycleSeconds)
        let p = ((phase / cycle) + stagger).truncatingRemainder(dividingBy: 1)
        return Circle()
            .strokeBorder(color, lineWidth: 1.0)
            .scaleEffect(0.55 + p * 0.55)
            .opacity(Double(0.4 * (1.0 - p)))
            .frame(width: size, height: size)
    }

    private func startTicking() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            DispatchQueue.main.async {
                phase += 1.0 / 30.0
                if phase > 10_000 { phase = 0 }
            }
        }
    }
}
