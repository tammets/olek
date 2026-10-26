// Draws Olek's app icon and writes Resources/AppIcon.icns.
// Run from the repository root: swift scripts/make-icon.swift
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

    // Rounded square on Apple's icon grid: 824 points inside a 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    ctx.addPath(tilePath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let colors = [
        NSColor(red: 0.13, green: 0.52, blue: 0.43, alpha: 1).cgColor,
        NSColor(red: 0.07, green: 0.30, blue: 0.27, alpha: 1).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    let center = CGPoint(x: 512, y: 512)
    let radius: CGFloat = 270

    // The lower half of the face is filled like a level: time in balance.
    ctx.saveGState()
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi, clockwise: true)
    ctx.closePath()
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.28).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(56)
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.strokePath()

    // One hand pointing to about one o'clock.
    ctx.setLineCap(.round)
    ctx.setLineWidth(44)
    let angle = CGFloat.pi / 2 - CGFloat.pi / 6
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x + cos(angle) * 190, y: center.y + sin(angle) * 190))
    ctx.strokePath()

    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: center.x - 40, y: center.y - 40, width: 80, height: 80))
    return true
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

func writePNG(pixels: Int, to url: URL) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

for points in [16, 32, 128, 256, 512] {
    try writePNG(pixels: points, to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try writePNG(pixels: points * 2, to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let output = URL(fileURLWithPath: "Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
try writePNG(pixels: 512, to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("olek-icon-preview.png"))
print("Wrote \(output.path)")
