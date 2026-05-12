import SwiftUI

/// The Anchor brand mark — a stylised maritime anchor silhouette.
///
/// Drawn as a SwiftUI Shape so it scales crisply at every menubar size
/// (compact / standard / dock-extra-large) and respects light/dark mode
/// without needing baked PNG assets. The proportions are deliberate:
/// generous negative space at the top (the ring), strong vertical
/// shaft, and curved arms that read at 16-22pt menubar size.
struct AnchorGlyph: Shape {

    /// Thickness of the strokes relative to the bounding box.
    /// Default works well at menubar size; raise for larger renders.
    var strokeRatio: CGFloat = 0.13

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        // Normalise so the glyph fits inside the rect with breathing room.
        let inset = w * 0.08
        let inner = rect.insetBy(dx: inset, dy: inset)

        var p = Path()

        let centerX = inner.midX
        let topY    = inner.minY
        let bottomY = inner.maxY

        // 1) Top ring — a small circle that sits at the top.
        let ringDiameter = inner.width * 0.22
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
        let crossWidth  = inner.width * 0.45
        let crossThick  = inner.height * 0.06
        let crossRect = CGRect(
            x: centerX - crossWidth / 2,
            y: crossY - crossThick / 2,
            width: crossWidth,
            height: crossThick
        )
        p.addRoundedRect(in: crossRect, cornerSize: CGSize(width: crossThick / 2,
                                                            height: crossThick / 2))

        // 3) Shaft as a thin pill.
        let shaftThick = inner.width * 0.07
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
        let armSpan   = inner.width * 0.78
        let armDip    = inner.height * 0.08   // how far below the shaft bottom the curve dips
        let armRise   = inner.height * 0.18   // how high the tips rise back up
        let leftBase  = CGPoint(x: centerX - inner.width * 0.05, y: shaftBottom)
        let rightBase = CGPoint(x: centerX + inner.width * 0.05, y: shaftBottom)

        // Left arm
        let leftTip = CGPoint(x: centerX - armSpan / 2, y: shaftBottom - armRise)
        let leftDip = CGPoint(x: centerX - armSpan / 4, y: shaftBottom + armDip)
        let leftThick = inner.width * 0.05
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
        let rightThick = inner.width * 0.05
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

extension AnchorGlyph {
    /// Convenience: rendered as a single-colour silhouette with the
    /// even-odd fill rule (so the ring reads as a hole).
    func tinted(_ color: Color) -> some View {
        self
            .fill(color, style: FillStyle(eoFill: true, antialiased: true))
    }
}
