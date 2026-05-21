#!/usr/bin/env swift

// Renders the Vakter app icon at all required iconset sizes via direct
// Core Graphics / NSBitmapImageRep — no SwiftUI ImageRenderer (which
// hangs in plain `swift` CLI without a full AppKit runloop).
//
// Brand: a stylised lighthouse silhouette on a deep-navy squircle,
// with a warm amber lantern at the lamp room. Mirrors the
// `LighthouseGlyph` SwiftUI Shape used in the in-app hero contexts.
//
// Usage:  cd Vakter && swift Scripts/generate-icon.swift
// Output: Sources/VakterApp/Resources/AppIcon.icns

import AppKit
import CoreGraphics

// MARK: - Draw the icon at a given pixel size

func drawIcon(size pixels: Int) -> NSBitmapImageRep? {
    let s = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 32
    ) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }

    // Flip the Y axis so the rest of this function can use the same
    // "Y increases downward" convention as SwiftUI / UIKit. Without
    // this, paths read upside-down because NSBitmapImageRep contexts
    // are natively bottom-up.
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)

    // 1. Squircle background with diagonal navy gradient.
    let cornerRadius = s * 0.22
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let bgPath = CGPath(roundedRect: bgRect,
                        cornerWidth: cornerRadius,
                        cornerHeight: cornerRadius,
                        transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.14, green: 0.24, blue: 0.42, alpha: 1.0),
            CGColor(red: 0.05, green: 0.12, blue: 0.26, alpha: 1.0)
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: s),
        end:   CGPoint(x: s, y: 0),
        options: []
    )
    ctx.restoreGState()

    // 2. Subtle top highlight (soft inner stroke).
    let highlightRect = bgRect.insetBy(dx: s * 0.012, dy: s * 0.012)
    let highlightPath = CGPath(roundedRect: highlightRect,
                                cornerWidth: cornerRadius - s * 0.012,
                                cornerHeight: cornerRadius - s * 0.012,
                                transform: nil)
    ctx.saveGState()
    ctx.addPath(highlightPath)
    ctx.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 0.16)
    ctx.setLineWidth(s * 0.003)
    ctx.strokePath()
    ctx.restoreGState()

    // Layout — the lighthouse glyph occupies ~70% of the canvas, centred.
    let glyphHeight = s * 0.78
    let glyphWidth  = s * 0.58
    let glyphRect = CGRect(
        x: (s - glyphWidth) / 2,
        y: (s - glyphHeight) / 2,
        width: glyphWidth, height: glyphHeight
    )

    // The lantern centre is ~16% from the TOP of the glyph rect (matches
    // the lantern room's vertical centre at frac 0.16 inside the glyph).
    // In NSGraphicsContext (flipped coordinates, Y=0 at top), this is
    // simply glyphRect.minY + glyphHeight * 0.16.
    let lampCenter = CGPoint(
        x: s / 2,
        y: glyphRect.minY + glyphHeight * 0.16
    )

    // 3. Warm amber lantern halo. Soft radial glow centred at the
    // lantern room. Painted BEFORE the silhouette so the lighthouse
    // cuts a clean shape out of the glow.
    let haloGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.98, green: 0.78, blue: 0.40, alpha: 0.75),
            CGColor(red: 0.95, green: 0.62, blue: 0.20, alpha: 0.0)
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()  // confine the halo to the squircle
    ctx.drawRadialGradient(
        haloGradient,
        startCenter: lampCenter, startRadius: s * 0.03,
        endCenter:   lampCenter, endRadius:   s * 0.62,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()

    // 4. Two soft amber beams stretching horizontally from the lantern.
    //    Stylised, not realistic — adds energy and pulls the eye to
    //    the light source.
    if pixels >= 64 {
        ctx.saveGState()
        ctx.addPath(bgPath)
        ctx.clip()
        let beamHeight = s * 0.07
        let beamLength = s * 0.42
        // Left beam
        let leftBeam = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 1.0, green: 0.88, blue: 0.55, alpha: 0.0),
                CGColor(red: 1.0, green: 0.85, blue: 0.50, alpha: 0.55)
            ] as CFArray,
            locations: [0, 1]
        )!
        let leftRect = CGRect(
            x: lampCenter.x - beamLength, y: lampCenter.y - beamHeight / 2,
            width: beamLength, height: beamHeight
        )
        ctx.saveGState()
        ctx.addRect(leftRect)
        ctx.clip()
        ctx.drawLinearGradient(
            leftBeam,
            start: CGPoint(x: leftRect.minX, y: leftRect.midY),
            end:   CGPoint(x: leftRect.maxX, y: leftRect.midY),
            options: []
        )
        ctx.restoreGState()
        // Right beam (mirror)
        let rightRect = CGRect(
            x: lampCenter.x, y: lampCenter.y - beamHeight / 2,
            width: beamLength, height: beamHeight
        )
        let rightBeam = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 1.0, green: 0.85, blue: 0.50, alpha: 0.55),
                CGColor(red: 1.0, green: 0.88, blue: 0.55, alpha: 0.0)
            ] as CFArray,
            locations: [0, 1]
        )!
        ctx.saveGState()
        ctx.addRect(rightRect)
        ctx.clip()
        ctx.drawLinearGradient(
            rightBeam,
            start: CGPoint(x: rightRect.minX, y: rightRect.midY),
            end:   CGPoint(x: rightRect.maxX, y: rightRect.midY),
            options: []
        )
        ctx.restoreGState()
        ctx.restoreGState()
    }

    // 5. Lighthouse silhouette in ivory.
    let glyphPath = lighthouseGlyphPath(in: glyphRect)
    ctx.saveGState()
    ctx.setFillColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1.0)
    ctx.addPath(glyphPath)
    ctx.fillPath(using: .winding)
    ctx.restoreGState()

    // 6. The lantern light itself — a bright amber dot inside the
    //    lantern room with a soft local bloom.
    let lightSize = s * 0.055
    let lightRect = CGRect(
        x: lampCenter.x - lightSize / 2,
        y: lampCenter.y - lightSize / 2,
        width: lightSize, height: lightSize
    )
    ctx.saveGState()
    let bloomGrad = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 1.0, green: 0.95, blue: 0.65, alpha: 1.0),
            CGColor(red: 0.95, green: 0.70, blue: 0.25, alpha: 0.0)
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        bloomGrad,
        startCenter: lampCenter, startRadius: 0,
        endCenter:   lampCenter, endRadius:   lightSize * 1.9,
        options: []
    )
    ctx.setFillColor(red: 1.0, green: 0.92, blue: 0.55, alpha: 1.0)
    ctx.addEllipse(in: lightRect)
    ctx.fillPath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Lighthouse glyph path
//
// Stronger silhouette than the original draft. Classic profile:
// chunky stepped base, gently tapered tower, distinctly wider gallery
// walkway, clear lantern room, full rounded dome, slender finial.
// Read at 16pt and at 1024pt without losing identity.
//
// Y convention: this function uses the SwiftUI-style "Y increases
// downward" convention (minY = top of rect, maxY = bottom). The
// caller flips the rect / context for Core Graphics rendering.

func lighthouseGlyphPath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let inset = rect.width * 0.04
    let inner = rect.insetBy(dx: inset, dy: inset)
    let cx = inner.midX
    let topY = inner.minY
    let bottomY = inner.maxY
    let h = inner.height
    let w = inner.width

    // Vertical layout (% of height, from top down):
    //   0..6    finial
    //   6..10   dome (half-circle on top of lantern room)
    //   10..22  lantern room (with cross-glass implied)
    //   22..27  gallery walkway (overhang)
    //   27..82  tower (tapered, slight cigar)
    //   82..95  base step
    //   95..100 ground line

    // 1) BASE STEP — chunky horizontal block at the very bottom.
    let baseTopFrac: CGFloat = 0.82
    let baseBottomFrac: CGFloat = 0.95
    let baseTopY = topY + h * baseTopFrac
    let baseBottomY = topY + h * baseBottomFrac
    let baseHalf = w * 0.42
    path.addRect(CGRect(
        x: cx - baseHalf, y: baseTopY,
        width: baseHalf * 2, height: baseBottomY - baseTopY
    ))

    // Ground line — a wider, very thin "soil" line under the base.
    let groundY = topY + h * 0.95
    let groundHalf = w * 0.48
    path.addRect(CGRect(
        x: cx - groundHalf, y: groundY,
        width: groundHalf * 2, height: h * 0.04
    ))

    // 2) TOWER — long tapered trapezoid from base to gallery.
    //    Slight cigar curve via two small intermediate widths so the
    //    silhouette doesn't look like a column.
    let towerTopFrac: CGFloat = 0.27
    let towerTopY = topY + h * towerTopFrac
    let towerBottomY = baseTopY
    let towerHalfBottom = w * 0.30
    let towerHalfMid    = w * 0.26   // narrowest waist
    let towerHalfTop    = w * 0.28
    let midY = (towerTopY + towerBottomY) / 2

    path.move(to: CGPoint(x: cx - towerHalfBottom, y: towerBottomY))
    // Up the left side with a soft curve through the mid-waist.
    path.addQuadCurve(
        to: CGPoint(x: cx - towerHalfTop, y: towerTopY),
        control: CGPoint(x: cx - towerHalfMid, y: midY)
    )
    // Across the top of the tower.
    path.addLine(to: CGPoint(x: cx + towerHalfTop, y: towerTopY))
    // Down the right side, mirrored curve.
    path.addQuadCurve(
        to: CGPoint(x: cx + towerHalfBottom, y: towerBottomY),
        control: CGPoint(x: cx + towerHalfMid, y: midY)
    )
    path.closeSubpath()

    // 3) GALLERY WALKWAY — overhanging horizontal block above the tower,
    //    clearly wider than the tower top.
    let galleryTopFrac: CGFloat = 0.22
    let galleryBottomFrac: CGFloat = 0.27
    let galleryTopY = topY + h * galleryTopFrac
    let galleryBottomY = topY + h * galleryBottomFrac
    let galleryHalf = w * 0.36
    path.addRect(CGRect(
        x: cx - galleryHalf, y: galleryTopY,
        width: galleryHalf * 2, height: galleryBottomY - galleryTopY
    ))

    // 4) LANTERN ROOM — taller than wide, with a small horizontal
    //    cap-rail at the bottom edge (implies the glass-room walls).
    let lanternTopFrac: CGFloat = 0.10
    let lanternBottomFrac: CGFloat = 0.22
    let lanternTopY = topY + h * lanternTopFrac
    let lanternBottomY = topY + h * lanternBottomFrac
    let lanternHalf = w * 0.22
    let lanternRect = CGRect(
        x: cx - lanternHalf, y: lanternTopY,
        width: lanternHalf * 2,
        height: lanternBottomY - lanternTopY
    )
    let lanternCorner = min(lanternRect.width, lanternRect.height) * 0.12
    path.addRoundedRect(
        in: lanternRect,
        cornerWidth: lanternCorner, cornerHeight: lanternCorner
    )

    // 5) DOME — proper half-circle sitting on top of the lantern.
    //    Radius equals the lantern's half-width so the dome fits the
    //    lantern exactly with no overhang. We've flipped the rendering
    //    context (see drawIcon) so Y increases downward; sweeping the
    //    arc from 180° → 360° clockwise produces the visual TOP half.
    let domeRadius = lanternHalf
    let domeCenterY = lanternTopY
    path.move(to: CGPoint(x: cx - domeRadius, y: domeCenterY))
    path.addArc(
        center: CGPoint(x: cx, y: domeCenterY),
        radius: domeRadius,
        startAngle: .pi,
        endAngle: 2 * .pi,
        clockwise: false
    )
    path.closeSubpath()

    // 6) FINIAL — slim vertical needle above the dome.
    let finialHeight = h * 0.05
    let finialThick  = w * 0.018
    let finialTopY = topY + h * 0.01
    let finialBottomY = finialTopY + finialHeight
    path.addRect(CGRect(
        x: cx - finialThick / 2, y: finialTopY,
        width: finialThick, height: finialBottomY - finialTopY
    ))

    return path
}

// MARK: - Pipeline

let here = FileManager.default.currentDirectoryPath
let iconsetDir = "\(here)/build/AppIcon.iconset"
let outIcns    = "\(here)/Sources/VakterApp/Resources/AppIcon.icns"

try? FileManager.default.removeItem(atPath: iconsetDir)
try? FileManager.default.createDirectory(
    atPath: iconsetDir, withIntermediateDirectories: true
)

let sizes: [(String, Int)] = [
    ("icon_16x16.png",       16),
    ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),
    ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",     128),
    ("icon_128x128@2x.png",  256),
    ("icon_256x256.png",     256),
    ("icon_256x256@2x.png",  512),
    ("icon_512x512.png",     512),
    ("icon_512x512@2x.png",  1024),
]

for (name, pixels) in sizes {
    guard let rep = drawIcon(size: pixels) else {
        print("FAIL: render \(name)")
        exit(1)
    }
    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("FAIL: png \(name)")
        exit(1)
    }
    let url = URL(fileURLWithPath: "\(iconsetDir)/\(name)")
    try data.write(to: url)
    print("rendered \(name)")
}

// Run iconutil to assemble the .icns.
let p = Process()
p.launchPath = "/usr/bin/iconutil"
p.arguments = ["--convert", "icns", iconsetDir, "--output", outIcns]
try p.run()
p.waitUntilExit()
if p.terminationStatus != 0 {
    print("FAIL: iconutil exit \(p.terminationStatus)")
    exit(1)
}

print("✅ wrote \(outIcns)")
