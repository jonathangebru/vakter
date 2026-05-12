#!/usr/bin/env swift

// Renders the Anchor app icon at all required iconset sizes via direct
// Core Graphics / NSBitmapImageRep — no SwiftUI ImageRenderer (which
// hangs in plain `swift` CLI without a full AppKit runloop).
//
// Usage:  cd Anchor && swift Scripts/generate-icon.swift
// Output: Sources/AnchorApp/Resources/AppIcon.icns

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

    // 1. Squircle background with diagonal gradient.
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
            CGColor(red: 0.07, green: 0.16, blue: 0.32, alpha: 1.0)
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

    // 3. The anchor glyph in ivory. Centered, scaled to ~62% of icon.
    let glyphSize = s * 0.62
    let glyphRect = CGRect(
        x: (s - glyphSize) / 2,
        y: (s - glyphSize) / 2,
        width: glyphSize, height: glyphSize
    )
    let glyphPath = anchorGlyphPath(in: glyphRect)
    ctx.saveGState()
    ctx.setFillColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1.0)
    ctx.addPath(glyphPath)
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Anchor glyph (mirrors AnchorGlyph.swift)

func anchorGlyphPath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let inset = rect.width * 0.08
    let inner = rect.insetBy(dx: inset, dy: inset)

    let centerX = inner.midX
    let topY = inner.minY
    let bottomY = inner.maxY

    let ringDiameter = inner.width * 0.22
    let ringCenterY = topY + ringDiameter * 0.55
    let ringRect = CGRect(
        x: centerX - ringDiameter / 2, y: ringCenterY - ringDiameter / 2,
        width: ringDiameter, height: ringDiameter
    )
    path.addEllipse(in: ringRect)

    let shaftTop = ringCenterY + ringDiameter * 0.45
    let shaftBottom = bottomY - inner.height * 0.05

    let crossY = shaftTop + inner.height * 0.10
    let crossWidth = inner.width * 0.45
    let crossThick = inner.height * 0.06
    let crossRect = CGRect(
        x: centerX - crossWidth / 2, y: crossY - crossThick / 2,
        width: crossWidth, height: crossThick
    )
    path.addRoundedRect(in: crossRect, cornerWidth: crossThick / 2, cornerHeight: crossThick / 2)

    let shaftThick = inner.width * 0.07
    let shaftRect = CGRect(
        x: centerX - shaftThick / 2, y: shaftTop,
        width: shaftThick, height: shaftBottom - shaftTop
    )
    path.addRoundedRect(in: shaftRect, cornerWidth: shaftThick / 2, cornerHeight: shaftThick / 2)

    let armSpan = inner.width * 0.78
    let armDip = inner.height * 0.08
    let armRise = inner.height * 0.18
    let leftBase = CGPoint(x: centerX - inner.width * 0.05, y: shaftBottom)
    let rightBase = CGPoint(x: centerX + inner.width * 0.05, y: shaftBottom)

    let leftTip = CGPoint(x: centerX - armSpan / 2, y: shaftBottom - armRise)
    let leftDip = CGPoint(x: centerX - armSpan / 4, y: shaftBottom + armDip)
    let leftThick = inner.width * 0.05
    path.move(to: CGPoint(x: leftBase.x, y: leftBase.y - leftThick))
    path.addQuadCurve(
        to: CGPoint(x: leftTip.x, y: leftTip.y),
        control: CGPoint(x: leftDip.x, y: leftDip.y - armDip * 0.4)
    )
    path.addLine(to: CGPoint(x: leftTip.x + leftThick * 0.6, y: leftTip.y + leftThick * 0.6))
    path.addQuadCurve(
        to: CGPoint(x: leftBase.x, y: leftBase.y + leftThick),
        control: CGPoint(x: leftDip.x, y: leftDip.y + leftThick * 0.4)
    )
    path.closeSubpath()

    let rightTip = CGPoint(x: centerX + armSpan / 2, y: shaftBottom - armRise)
    let rightDip = CGPoint(x: centerX + armSpan / 4, y: shaftBottom + armDip)
    let rightThick = inner.width * 0.05
    path.move(to: CGPoint(x: rightBase.x, y: rightBase.y - rightThick))
    path.addQuadCurve(
        to: CGPoint(x: rightTip.x, y: rightTip.y),
        control: CGPoint(x: rightDip.x, y: rightDip.y - armDip * 0.4)
    )
    path.addLine(to: CGPoint(x: rightTip.x - rightThick * 0.6, y: rightTip.y + rightThick * 0.6))
    path.addQuadCurve(
        to: CGPoint(x: rightBase.x, y: rightBase.y + rightThick),
        control: CGPoint(x: rightDip.x, y: rightDip.y + rightThick * 0.4)
    )
    path.closeSubpath()

    let holeInset = ringDiameter * 0.32
    let holeRect = ringRect.insetBy(dx: holeInset, dy: holeInset)
    path.addEllipse(in: holeRect)

    return path
}

// MARK: - Pipeline

let here = FileManager.default.currentDirectoryPath
let iconsetDir = "\(here)/build/AppIcon.iconset"
let outIcns    = "\(here)/Sources/AnchorApp/Resources/AppIcon.icns"

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
