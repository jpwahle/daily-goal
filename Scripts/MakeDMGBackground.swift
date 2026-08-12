#!/usr/bin/env swift
// Renders the DMG installer window background (bg.png + bg@2x.png).
// Usage: swift Scripts/MakeDMGBackground.swift <output-dir>
//
// Canvas is 600x400 pt to match the Finder window content area set in
// create-dmg.sh. Icon centers there: app (150, 200), Applications (450, 200)
// in Finder's top-left coordinates.

import AppKit

let W: CGFloat = 600
let H: CGFloat = 400

// App accent gradient (same as CheckRing in GoalView.swift)
let indigo = NSColor(red: 0.33, green: 0.45, blue: 1.00, alpha: 1)
let violet = NSColor(red: 0.66, green: 0.35, blue: 0.99, alpha: 1)

// Icon centers in AppKit (bottom-left) coordinates
let appCenter = NSPoint(x: 150, y: H - 200)
let folderCenter = NSPoint(x: 450, y: H - 200)

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.cgContext.scaleBy(x: scale, y: scale)

    // Base: flat, faintly violet-tinted white. (A white→tint gradient looks
    // nicer in theory but CoreGraphics dithers it into a visible dot grid.)
    let cg = ctx.cgContext
    cg.setFillColor(NSColor(red: 0.978, green: 0.973, blue: 1.00, alpha: 1).cgColor)
    cg.fill(CGRect(x: 0, y: 0, width: W, height: H))

    // Arrow: straight, gradient-stroked, app → Applications
    let y = appCenter.y
    let start = CGPoint(x: appCenter.x + 82, y: y)
    let tip = CGPoint(x: folderCenter.x - 78, y: y)
    let headLength: CGFloat = 24

    let shaft = CGMutablePath()
    shaft.move(to: start)
    shaft.addLine(to: CGPoint(x: tip.x - headLength + 4, y: y))

    let head = CGMutablePath()
    head.move(to: tip)
    head.addLine(to: CGPoint(x: tip.x - headLength, y: y + 13))
    head.addLine(to: CGPoint(x: tip.x - headLength, y: y - 13))
    head.closeSubpath()

    // Gradient the shaft and head separately: a combined clip would knock
    // out their overlap (opposite winding), leaving a hole at the joint.
    let arrowGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [indigo.cgColor, violet.cgColor] as CFArray,
        locations: [0, 1])!
    let shaftFill = shaft.copy(strokingWithWidth: 7, lineCap: .round,
                               lineJoin: .round, miterLimit: 10)
    for path in [head, shaftFill] {
        cg.saveGState()
        cg.addPath(path)
        cg.clip()
        cg.drawLinearGradient(
            arrowGradient,
            start: CGPoint(x: start.x, y: 0), end: CGPoint(x: tip.x, y: 0),
            options: [])
        cg.restoreGState()
    }

    // Caption
    let caption = "Drag to Applications to install"
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor(white: 0.36, alpha: 1),
    ]
    let size = caption.size(withAttributes: attrs)
    caption.draw(at: NSPoint(x: (W - size.width) / 2, y: 38), withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    rep.size = NSSize(width: W, height: H)  // sets 72/144 dpi metadata
    return rep
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("Usage: MakeDMGBackground.swift <output-dir>\n".data(using: .utf8)!)
    exit(1)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for (scale, name) in [(CGFloat(1), "bg.png"), (CGFloat(2), "bg@2x.png")] {
    let rep = render(scale: scale)
    try rep.representation(using: .png, properties: [:])!
        .write(to: outDir.appendingPathComponent(name))
}
print("Wrote bg.png + bg@2x.png to \(outDir.path)")
