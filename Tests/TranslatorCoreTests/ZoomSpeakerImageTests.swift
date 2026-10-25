import AppKit
import Testing
@testable import TranslatorCore

@MainActor @Test func readsOnlyNameInsideTheSingleGreenSpeakerFrame() throws {
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 480,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let graphics = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    NSColor.black.setFill()
    NSRect(x: 0, y: 0, width: 640, height: 480).fill()
    NSColor(red: 0.1, green: 0.8, blue: 0.2, alpha: 1).setStroke()
    let border = NSBezierPath(rect: NSRect(x: 30, y: 40, width: 450, height: 370))
    border.lineWidth = 3
    border.stroke()
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.white]
    ("Alice Smith" as NSString).draw(at: NSPoint(x: 45, y: 52), withAttributes: attributes)
    ("Unrelated participant" as NSString).draw(at: NSPoint(x: 45, y: 440), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    let image = try #require(bitmap.cgImage)
    #expect(try ZoomSpeakerImageReader.speaker(in: image) == "Alice Smith")
}
