import SwiftUI

/// The Vakter brand mark — a stylised lighthouse silhouette.
///
/// Visually a clean two-tone lighthouse: tapered base, slender shaft,
/// capital walkway, lantern room with the light, and dome on top.
/// Designed to read at every render size from the 1024pt master icon
/// down to the 60pt onboarding hero. (The menubar still uses the
/// `VakterGlyph` — smaller-scale rendering of a lighthouse gets muddy
/// at 18pt menubar size, where the anchor's strong horizontal cross-bar
/// reads cleaner.)
///
/// The light source itself is left empty in this shape — render it as
/// a separate filled element (typically `VakterDesign.lantern`) on top,
/// so the colour stack can be navy silhouette + amber light.
struct LighthouseGlyph: Shape {

    enum Variant {
        /// Default — tuned for 60pt+ render contexts.
        case standard
        /// Stronger weight + slightly taller tower for 256pt+ icon use.
        case hero
        /// Simplified silhouette for 18pt menubar rendering — drops
        /// the gallery walkway and separate lantern room so the shape
        /// stays crisp instead of muddy. Just chunky base + tapered
        /// tower + dome + tiny finial.
        case menubar
    }

    var variant: Variant = .standard

    func path(in rect: CGRect) -> Path {
        if variant == .menubar {
            return menubarPath(in: rect)
        }

        // Normalise so the lighthouse breathes inside the rect.
        let inset = rect.width * 0.08
        let inner = rect.insetBy(dx: inset, dy: inset)

        let cx = inner.midX
        let topY = inner.minY
        let bottomY = inner.maxY
        let h = inner.height
        let w = inner.width

        // Variant tunes.
        let baseWidthRatio: CGFloat   = variant == .hero ? 0.62 : 0.60
        let towerWidthRatio: CGFloat  = variant == .hero ? 0.36 : 0.38
        let capWidthRatio: CGFloat    = variant == .hero ? 0.50 : 0.50
        let lanternWidthRatio: CGFloat = variant == .hero ? 0.30 : 0.32

        var p = Path()

        // 1) Base / foundation — short trapezoid at the bottom.
        let baseHeight = h * 0.10
        let baseTopY = bottomY - baseHeight
        let baseHalfBottom = w * baseWidthRatio / 2
        let baseHalfTop = w * (baseWidthRatio - 0.06) / 2
        p.move(to: CGPoint(x: cx - baseHalfBottom, y: bottomY))
        p.addLine(to: CGPoint(x: cx + baseHalfBottom, y: bottomY))
        p.addLine(to: CGPoint(x: cx + baseHalfTop, y: baseTopY))
        p.addLine(to: CGPoint(x: cx - baseHalfTop, y: baseTopY))
        p.closeSubpath()

        // 2) Tower — tapered (slightly wider at bottom than top).
        let towerBottomY = baseTopY
        let towerTopY    = topY + h * 0.34
        let towerHalfBottom = w * towerWidthRatio / 2
        let towerHalfTop    = w * (towerWidthRatio - 0.06) / 2
        p.move(to: CGPoint(x: cx - towerHalfBottom, y: towerBottomY))
        p.addLine(to: CGPoint(x: cx + towerHalfBottom, y: towerBottomY))
        p.addLine(to: CGPoint(x: cx + towerHalfTop, y: towerTopY))
        p.addLine(to: CGPoint(x: cx - towerHalfTop, y: towerTopY))
        p.closeSubpath()

        // 3) Capital walkway — slightly wider than tower top, short.
        let capHeight = h * 0.045
        let capTopY = towerTopY - capHeight
        let capHalfWidth = w * capWidthRatio / 2
        let capRect = CGRect(
            x: cx - capHalfWidth,
            y: capTopY,
            width: capHalfWidth * 2,
            height: capHeight
        )
        p.addRoundedRect(in: capRect, cornerSize: CGSize(width: 1.5, height: 1.5))

        // 4) Lantern room — square with a small pillar feel.
        let lanternHeight = h * 0.10
        let lanternBottomY = capTopY
        let lanternTopY = lanternBottomY - lanternHeight
        let lanternHalfWidth = w * lanternWidthRatio / 2
        let lanternRect = CGRect(
            x: cx - lanternHalfWidth,
            y: lanternTopY,
            width: lanternHalfWidth * 2,
            height: lanternHeight
        )
        p.addRoundedRect(in: lanternRect, cornerSize: CGSize(width: 2, height: 2))

        // 5) Dome / roof on top — a half-circle.
        let domeHeight = h * 0.08
        let domeRect = CGRect(
            x: cx - lanternHalfWidth,
            y: lanternTopY - domeHeight,
            width: lanternHalfWidth * 2,
            height: domeHeight * 2
        )
        p.move(to: CGPoint(x: cx - lanternHalfWidth, y: lanternTopY))
        p.addArc(
            center: CGPoint(x: cx, y: lanternTopY),
            radius: lanternHalfWidth,
            startAngle: .degrees(180),
            endAngle: .degrees(360),
            clockwise: false
        )
        p.closeSubpath()
        _ = domeRect // (kept for layout reasoning; not directly drawn)

        // 6) Finial / lightning rod — thin vertical line above the dome.
        let finialHeight = h * 0.05
        let finialThick  = w * 0.012
        let finialRect = CGRect(
            x: cx - finialThick / 2,
            y: lanternTopY - domeHeight - finialHeight,
            width: finialThick,
            height: finialHeight
        )
        p.addRect(finialRect)

        return p
    }
}

extension LighthouseGlyph {
    static var hero: LighthouseGlyph { LighthouseGlyph(variant: .hero) }
    static var menubar: LighthouseGlyph { LighthouseGlyph(variant: .menubar) }

    /// Where the lantern dot should sit in a menubar-variant frame.
    /// Centred horizontally, at the dome base (top of tower) — that's
    /// the visual "lamp" position on a real lighthouse.
    static func menubarLanternUnit() -> UnitPoint {
        // Mirrors the menubar layout: 6 % inset, finial 6 % of inner h,
        // dome 16 % of inner h — dot sits at the dome's flat base.
        // unit_y = inset_unit + (1 - 2*inset_unit) * (finial + dome)
        //        = 0.06 + 0.88 * 0.22 ≈ 0.254
        return UnitPoint(x: 0.5, y: 0.254)
    }

    /// Simplified silhouette for 18pt menubar rendering.
    /// Just: chunky base + tapered tower + dome + tiny finial.
    /// No gallery walkway, no separate lantern room — those features
    /// blur into a smudge at menubar size.
    private func menubarPath(in rect: CGRect) -> Path {
        let inset = rect.width * 0.06
        let inner = rect.insetBy(dx: inset, dy: inset)

        let cx = inner.midX
        let topY = inner.minY
        let bottomY = inner.maxY
        let h = inner.height
        let w = inner.width

        // Vertical layout (top → bottom):
        //   finial : 6 % of h
        //   dome   : 16 % of h
        //   tower  : 56 % of h
        //   base   : 16 % of h
        //   slack  :  6 % (already absorbed by inset)
        let finialHeight = h * 0.06
        let domeHeight   = h * 0.16
        let towerHeight  = h * 0.56
        let baseHeight   = h * 0.16

        let finialBottomY = topY + finialHeight
        let domeBottomY   = finialBottomY + domeHeight
        let towerBottomY  = domeBottomY + towerHeight
        let baseBottomY   = towerBottomY + baseHeight

        // Tower geometry — tapered, half-widths.
        let towerHalfTop    = w * 0.16
        let towerHalfBottom = w * 0.22

        // Dome radius matches the tower top so they meet cleanly.
        let domeRadius = towerHalfTop + w * 0.04

        // Base — chunky trapezoid wider than the tower bottom.
        let baseHalfTop    = w * 0.28
        let baseHalfBottom = w * 0.35

        // Finial thickness.
        let finialThick = max(w * 0.04, 1.0)

        var p = Path()

        // 1) Finial (tiny rod on top).
        let finialRect = CGRect(
            x: cx - finialThick / 2,
            y: topY,
            width: finialThick,
            height: finialHeight
        )
        p.addRect(finialRect)

        // 2) Dome (half-circle sitting on tower top).
        p.move(to: CGPoint(x: cx - domeRadius, y: domeBottomY))
        p.addArc(
            center: CGPoint(x: cx, y: domeBottomY),
            radius: domeRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(360),
            clockwise: false
        )
        p.closeSubpath()

        // 3) Tower (tapered trapezoid).
        p.move(to: CGPoint(x: cx - towerHalfTop, y: domeBottomY))
        p.addLine(to: CGPoint(x: cx + towerHalfTop, y: domeBottomY))
        p.addLine(to: CGPoint(x: cx + towerHalfBottom, y: towerBottomY))
        p.addLine(to: CGPoint(x: cx - towerHalfBottom, y: towerBottomY))
        p.closeSubpath()

        // 4) Base (chunkier trapezoid).
        p.move(to: CGPoint(x: cx - baseHalfTop, y: towerBottomY))
        p.addLine(to: CGPoint(x: cx + baseHalfTop, y: towerBottomY))
        p.addLine(to: CGPoint(x: cx + baseHalfBottom, y: min(baseBottomY, bottomY)))
        p.addLine(to: CGPoint(x: cx - baseHalfBottom, y: min(baseBottomY, bottomY)))
        p.closeSubpath()

        return p
    }
}

/// A hero-quality animated brand mark using the lighthouse + a warm
/// amber lantern beam radiating from the lamp room. Used in onboarding
/// welcome, About tab, and (white-tinted) the arming overlay.
struct LighthouseHeroMark: View {

    /// Pulse cycle for the beam shimmer. Lower = faster.
    var cycleSeconds: Double = 4.0
    var size: CGFloat = 180
    /// Silhouette colour for the lighthouse shape.
    var silhouetteColor: Color = VakterDesign.anchor
    /// Lantern beam + halo colour. Warm amber by default.
    var beamColor: Color = VakterDesign.lantern

    @State private var phase: CGFloat = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            // 1. Warm radial halo behind the lighthouse — the "glow"
            //    every lighthouse casts at dusk. Phase-modulated so it
            //    breathes gently.
            let haloPulse = 0.85 + 0.15 * sin(Double(phase) * 2 * Double.pi / cycleSeconds)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            beamColor.opacity(0.55 * haloPulse),
                            beamColor.opacity(0.0)
                        ],
                        center: UnitPoint(x: 0.5, y: 0.32),
                        startRadius: size * 0.04,
                        endRadius: size * 0.55
                    )
                )
                .frame(width: size, height: size)

            // 2. Three subtle concentric rings rippling outward, like a
            //    foghorn pulse from the lamp room. Phase-staggered.
            ForEach(0..<3, id: \.self) { i in
                ring(index: i)
            }

            // 3. The lighthouse silhouette itself.
            LighthouseGlyph.hero
                .fill(silhouetteColor)
                .frame(width: size * 0.46, height: size * 0.68)

            // 4. A tiny amber dot at the lamp room — the literal light.
            Circle()
                .fill(beamColor)
                .frame(width: size * 0.045, height: size * 0.045)
                .offset(y: -size * 0.20)
                .shadow(color: beamColor.opacity(0.6), radius: 6, x: 0, y: 0)
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
            .strokeBorder(beamColor, lineWidth: 0.8)
            .scaleEffect(0.45 + p * 0.55)
            .opacity(Double(0.35 * (1.0 - p)))
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
