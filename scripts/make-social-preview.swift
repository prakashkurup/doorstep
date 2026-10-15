// Renders docs/images/social-preview.png (1280×640) from the README screenshots.
// Usage: swift scripts/make-social-preview.swift "$PWD" docs/images/social-preview.png
import AppKit

let args = CommandLine.arguments
let repo = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args[2])
let W = 1280.0, H = 640.0

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.interpolationQuality = .high

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Background: the same soft blue-gray as the README hero.
NSGradient(starting: rgb(0xEEF2F8), ending: rgb(0xD6DFEC))!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -60)

// Screenshots on the right, bleeding off the bottom edge (AppKit's origin is bottom-left).
// Each PNG has the panel inset 58px on a gray backdrop; draw only the panel, with our own shadow.
func panel(_ name: String, x: Double, top: Double, scale: Double) {
    let img = NSImage(contentsOf: repo.appendingPathComponent("docs/images/\(name)"))!
    let px = img.representations.first!
    let inset = 58.0, radius = 40.0 * scale
    let srcW = Double(px.pixelsWide) - 2 * inset, srcH = Double(px.pixelsHigh) - inset
    let w = srcW * scale, h = srcH * scale
    let rect = NSRect(x: x, y: H - top - h, width: w, height: h)
    let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = rgb(0x1E2A44, 0.22)
    shadow.shadowBlurRadius = 34
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    rgb(0xF2F2F4).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    // NSImage points may differ from pixels; map the source rect in the image's own units.
    let k = img.size.width / Double(px.pixelsWide)
    let src = NSRect(x: inset * k, y: 0, width: srcW * k, height: srcH * k)  // bottom-left origin: drop the top inset
    img.draw(in: rect, from: src, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
}
panel("arriving.png", x: 640, top: 64, scale: 0.5)
panel("order-detail.png", x: 905, top: 150, scale: 0.5)

// Left column: icon, name, tagline, details.
let icon = NSImage(contentsOf: repo.appendingPathComponent("Resources/AppIcon.icns"))!
icon.draw(in: NSRect(x: 70, y: H - 92 - 112, width: 112, height: 112))

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, x: Double, top: Double, width: Double, kern: CGFloat = 0, lineHeight: CGFloat? = nil) {
    let para = NSMutableParagraphStyle()
    if let lineHeight { para.minimumLineHeight = lineHeight; para.maximumLineHeight = lineHeight }
    let attr = NSAttributedString(string: s, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .kern: kern, .paragraphStyle: para,
    ])
    let bounds = attr.boundingRect(with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin])
    attr.draw(with: NSRect(x: x, y: H - top - bounds.height, width: width, height: bounds.height), options: [.usesLineFragmentOrigin])
}
text("Doorstep", size: 76, weight: .bold, color: rgb(0x1D1D1F), x: 74, top: 226, width: 560, kern: -2)
text("Your deliveries,\nright in the menu bar.", size: 34, weight: .semibold, color: rgb(0x0063CC), x: 76, top: 326, width: 560, kern: -0.6, lineHeight: 42)
text("Reads the order emails in your Gmail, on your Mac.\nArrivals, returns, live tracking, and spending.", size: 20, weight: .regular, color: rgb(0x55595F), x: 77, top: 432, width: 560, lineHeight: 29)
text("macOS 26  ·  SwiftUI  ·  Open source", size: 16, weight: .semibold, color: rgb(0x86898F), x: 77, top: 540, width: 560, kern: 0.3)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote", out.path)
