import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let shape = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 210, yRadius: 210)
        NSGradient(starting: NSColor(calibratedRed: 0.02, green: 0.32, blue: 0.40, alpha: 1),
                   ending: NSColor(calibratedRed: 0.07, green: 0.78, blue: 0.72, alpha: 1))?.draw(in: shape, angle: 70)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 426, y: 300, width: 172, height: 480), xRadius: 86, yRadius: 86).fill()
        NSBezierPath(ovalIn: NSRect(x: 370, y: 220, width: 284, height: 284)).fill()
        NSColor(calibratedRed: 0.03, green: 0.50, blue: 0.52, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 485, y: 350, width: 54, height: 350), xRadius: 27, yRadius: 27).fill()
        NSBezierPath(ovalIn: NSRect(x: 433, y: 283, width: 158, height: 158)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
