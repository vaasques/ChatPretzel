// Build-time only. Converts the user-supplied, text-free ChatPretzel artwork to an iconset.
import AppKit
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else { fatalError("Usage: swift make-icon.swift /path/AppIcon.iconset /path/icon-source.png") }
let output = URL(fileURLWithPath: arguments[0], isDirectory: true)
let sourceURL = URL(fileURLWithPath: arguments[1])
guard let source = NSImage(contentsOf: sourceURL) else { fatalError("Could not load icon source") }
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Bitmap creation failed") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        context.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        let iconRect = NSRect(x: 42, y: 42, width: 940, height: 940)
        NSBezierPath(roundedRect: iconRect, xRadius: 220, yRadius: 220).addClip()
        NSColor.white.setFill(); iconRect.fill()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1,
                    respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
