import AppKit

// Draws Lookout's icon: warm paper, two quiet rings, and the blue "you are here" dot from Pacer,
// as if something just pinged. Writes a 1024 px PNG to the path given.

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor(srgbRed: 0.969, green: 0.961, blue: 0.953, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: NSColor(srgbRed: 0.985, green: 0.978, blue: 0.97, alpha: 1),
               ending: NSColor(srgbRed: 0.93, green: 0.918, blue: 0.902, alpha: 1))?.draw(in: shape, angle: -90)

    let center = NSPoint(x: 512, y: 512)
    let ink = NSColor(srgbRed: 0.05, green: 0.05, blue: 0.05, alpha: 1)
    for (radius, alpha) in [(300.0, 0.12), (205.0, 0.28)] as [(CGFloat, CGFloat)] {
        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        ring.lineWidth = 34
        ink.withAlphaComponent(alpha).setStroke()
        ring.stroke()
    }

    // A sweep on the outer ring, where the ping came from.
    let sweep = NSBezierPath()
    sweep.appendArc(withCenter: center, radius: 300, startAngle: 70, endAngle: 20, clockwise: true)
    sweep.lineWidth = 34
    sweep.lineCapStyle = .round
    ink.setStroke()
    sweep.stroke()

    let blue = NSColor(srgbRed: 0.145, green: 0.388, blue: 0.922, alpha: 1)
    blue.withAlphaComponent(0.25).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 150, y: center.y - 150, width: 300, height: 300)).fill()
    blue.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 88, y: center.y - 88, width: 176, height: 176)).fill()
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = image.size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
