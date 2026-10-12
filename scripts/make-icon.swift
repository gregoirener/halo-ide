// Renders Halo's app icon into an .iconset: a flat ring and caret on an ink tile.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)

    // macOS icon grid: an 824pt rounded square centred in the 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: color(0x000000, 0.25).cgColor)
    color(0x1C2028).setFill()
    shape.fill()
    ctx.restoreGState()

    // A hairline of light on the top edge, the only "effect".
    ctx.saveGState()
    shape.addClip()
    color(0xFFFFFF, 0.06).setStroke()
    let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 2, dy: 2), xRadius: 183, yRadius: 183)
    rim.lineWidth = 4
    rim.stroke()
    ctx.restoreGState()

    // The ring.
    let ring = NSBezierPath(ovalIn: CGRect(x: 272, y: 566, width: 480, height: 156))
    ring.lineWidth = 44
    color(0xF1EEE7).setStroke()
    ring.stroke()

    // The caret.
    let caret = NSBezierPath(roundedRect: CGRect(x: 488, y: 262, width: 48, height: 236), xRadius: 24, yRadius: 24)
    color(0x4C8DF6).setFill()
    caret.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("icon_\(name).png"))
}
print("ok")
