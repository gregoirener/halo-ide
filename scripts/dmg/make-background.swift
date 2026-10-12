// Draws the DMG window background (660×420 pt) at 1x and 2x.
// Usage: swift make-background.swift <out-dir>
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 660, height: 420)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func draw(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    color(0xF5F4F1).setFill()
    NSRect(origin: .zero, size: size).fill()

    let center = NSMutableParagraphStyle()
    center.alignment = .center

    // Title + instruction (y is from the bottom in AppKit).
    let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20, weight: .semibold),
                                                .foregroundColor: color(0x1C2028), .paragraphStyle: center]
    ("Install Halo" as NSString).draw(in: NSRect(x: 0, y: size.height - 62, width: size.width, height: 28), withAttributes: title)
    let sub: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: color(0x5F656F), .paragraphStyle: center]
    ("Drag Halo onto the Applications folder." as NSString).draw(in: NSRect(x: 0, y: size.height - 86, width: size.width, height: 20), withAttributes: sub)

    // Arrow between the two icons (icons sit at x 170 and 490, y 200 from the top).
    let y = size.height - 200
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 262, y: y))
    arrow.line(to: NSPoint(x: 392, y: y))
    arrow.lineWidth = 2.5
    arrow.lineCapStyle = .round
    color(0xB3B8C0).setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 380, y: y + 10))
    head.line(to: NSPoint(x: 394, y: y))
    head.line(to: NSPoint(x: 380, y: y - 10))
    head.lineWidth = 2.5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    // First-launch help, quietly at the bottom.
    let divider = NSBezierPath(rect: NSRect(x: 40, y: 84, width: size.width - 80, height: 1))
    color(0x1C2028, 0.08).setFill()
    divider.fill()
    let note: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: color(0x6B717A), .paragraphStyle: center]
    let help = "First launch: if macOS says it can’t verify Halo, open System Settings → Privacy & Security\nand click “Open Anyway” next to Halo. You only need to do this once."
    (help as NSString).draw(in: NSRect(x: 30, y: 32, width: size.width - 60, height: 40), withAttributes: note)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! draw(scale: 1).write(to: outDir.appendingPathComponent("background.png"))
try! draw(scale: 2).write(to: outDir.appendingPathComponent("background@2x.png"))
print("ok")
