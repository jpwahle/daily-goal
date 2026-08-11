// Renders the app icon (gradient squircle + target glyph) as an .iconset.
// Usage: swift Scripts/MakeIcon.swift <output-iconset-dir>
import AppKit
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(px: Int) -> CGImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: px, height: px,
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

    let s = CGFloat(px)
    let inset = s * 0.098 // macOS icon grid margin
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 0.2237
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    let colors = [
        CGColor(red: 0.45, green: 0.42, blue: 1.00, alpha: 1),
        CGColor(red: 0.55, green: 0.25, blue: 0.92, alpha: 1),
    ]
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: [])

    // Target glyph: ring + dot
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let ringRadius = rect.width * 0.26
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.97))
    ctx.setLineWidth(rect.width * 0.075)
    ctx.addEllipse(in: CGRect(
        x: center.x - ringRadius, y: center.y - ringRadius,
        width: ringRadius * 2, height: ringRadius * 2))
    ctx.strokePath()

    let dotRadius = rect.width * 0.095
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.97))
    ctx.fillEllipse(in: CGRect(
        x: center.x - dotRadius, y: center.y - dotRadius,
        width: dotRadius * 2, height: dotRadius * 2))

    ctx.restoreGState()
    return ctx.makeImage()!
}

func write(_ image: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("cannot create \(name)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

for base in [16, 32, 128, 256, 512] {
    write(render(px: base), "icon_\(base)x\(base).png")
    write(render(px: base * 2), "icon_\(base)x\(base)@2x.png")
}
print("iconset written to \(outDir)")
