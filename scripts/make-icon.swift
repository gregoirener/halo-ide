// Renders Halo's app icon into an .iconset from a photo of a halo: a square
// crop centred on its light (the moon), set in the macOS icon tile.
// Usage: swift scripts/make-icon.swift <photo> <output.iconset>
import AppKit

let photo = URL(fileURLWithPath: CommandLine.arguments[1])
let out = URL(fileURLWithPath: CommandLine.arguments[2])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
guard let image = NSImage(contentsOf: photo)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Can't read \(photo.path)")
}

/// The centroid of the brightest pixels, in image coordinates (origin top-left).
func light(in image: CGImage) -> CGPoint {
    let w = image.width, h = image.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var brightest = 0
    for i in stride(from: 0, to: pixels.count, by: 4) { brightest = max(brightest, Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])) }
    var sx = 0.0, sy = 0.0, n = 0.0
    for row in 0..<h {
        for x in 0..<w {
            let i = (row * w + x) * 4
            if Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2]) >= brightest - 8 { sx += Double(x); sy += Double(row); n += 1 }
        }
    }
    return CGPoint(x: sx / n, y: sy / n)
}

let center = light(in: image)
let side = min(image.width, image.height)
let crop = CGRect(x: min(max(0, Int(center.x) - side / 2), image.width - side),
                  y: min(max(0, Int(center.y) - side / 2), image.height - side), width: side, height: side)
let square = image.cropping(to: crop)!
print("light at \(Int(center.x)),\(Int(center.y)); crop \(crop)")

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)

    // macOS icon grid: an 824pt rounded square centred in the 1024 canvas, with a soft shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: NSColor(white: 0, alpha: 0.28).cgColor)
    NSColor(srgbRed: 0.09, green: 0.12, blue: 0.18, alpha: 1).setFill()
    shape.fill()
    ctx.restoreGState()

    // The photo, filling the tile.
    ctx.saveGState()
    shape.addClip()
    ctx.draw(square, in: tile)
    // A hairline of light around the edge so it holds its shape on dark backgrounds.
    NSColor(white: 1, alpha: 0.10).setStroke()
    let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 2, dy: 2), xRadius: 183, yRadius: 183)
    rim.lineWidth = 4
    rim.stroke()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("icon_\(name).png"))
}
print("ok")
