import AppKit
import CoreGraphics

let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
let iconset = resources.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let plate = CGPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896),
                       cornerWidth: 202, cornerHeight: 202, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: CGColor(gray: 0, alpha: 0.18))
    context.addPath(plate)
    context.setFillColor(CGColor(red: 0.12, green: 0.68, blue: 0.58, alpha: 1))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(plate)
    context.clip()
    let colors = [CGColor(red: 0.41, green: 0.94, blue: 0.76, alpha: 1),
                  CGColor(red: 0.09, green: 0.65, blue: 0.62, alpha: 1)]
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 170, y: 950), end: CGPoint(x: 910, y: 120), options: [])
    context.restoreGState()

    let upper = CGMutablePath()
    upper.addRoundedRect(in: CGRect(x: 190, y: 490, width: 535, height: 310), cornerWidth: 78, cornerHeight: 78)
    upper.move(to: CGPoint(x: 265, y: 535))
    upper.addLine(to: CGPoint(x: 265, y: 440))
    upper.addLine(to: CGPoint(x: 385, y: 525))
    upper.closeSubpath()
    context.addPath(upper)
    context.setFillColor(CGColor(red: 0.98, green: 1, blue: 0.99, alpha: 1))
    context.fillPath()

    let ink = CGColor(red: 0.05, green: 0.19, blue: 0.19, alpha: 1)
    let lower = CGMutablePath()
    lower.addRoundedRect(in: CGRect(x: 385, y: 250, width: 450, height: 290), cornerWidth: 76, cornerHeight: 76)
    lower.move(to: CGPoint(x: 760, y: 495))
    lower.addLine(to: CGPoint(x: 760, y: 595))
    lower.addLine(to: CGPoint(x: 640, y: 510))
    lower.closeSubpath()
    context.addPath(lower)
    context.setFillColor(ink)
    context.fillPath()

    func wave(center: CGPoint, color: CGColor) {
        context.setFillColor(color)
        for (offset, height) in zip([-78.0, 0.0, 78.0], [66.0, 130.0, 86.0]) {
            context.addPath(CGPath(roundedRect: CGRect(x: center.x + offset - 18, y: center.y - height / 2,
                                                        width: 36, height: height),
                                   cornerWidth: 18, cornerHeight: 18, transform: nil))
            context.fillPath()
        }
    }
    wave(center: CGPoint(x: 452, y: 659), color: ink)
    wave(center: CGPoint(x: 610, y: 390), color: CGColor(red: 0.39, green: 0.94, blue: 0.76, alpha: 1))
    return context.makeImage()!
}

for (name, size) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                     ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256),
                     ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let bitmap = NSBitmapImageRep(cgImage: render(size: size))
    try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("\(name).png"))
}
print("Generated AppIcon.iconset")
