// Draws the app icon: the menu bar pill (camera dot + level meter) on black, shedding monochrome particles.
// Usage: swift scripts/make_icon.swift <output.png>   (1024 x 1024; scripts/make_icns.sh turns it into an .icns)
import AppKit

struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

let side: CGFloat = 1024
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let pill = CGRect(x: 262, y: 396, width: 500, height: 232)
let barHeights: [CGFloat] = [62, 107, 152, 89]

func drawParticles(in context: CGContext) {
    var random = SplitMix(state: 27)
    let centre = CGPoint(x: pill.midX, y: pill.midY)
    for _ in 0..<420 {
        // Particles leave the pill's edge and thin out with distance; a slight upward drift.
        let angle = CGFloat.random(in: 0..<(2 * .pi), using: &random)
        let reach = pow(CGFloat.random(in: 0...1, using: &random), 1.9)
        let edge = CGPoint(x: centre.x + cos(angle) * pill.width * 0.5, y: centre.y + sin(angle) * pill.height * 0.5)
        let distance = 14 + reach * 300
        let point = CGPoint(x: edge.x + cos(angle) * distance, y: edge.y + sin(angle) * distance + reach * 40)
        let radius = CGFloat.random(in: 1.5...9, using: &random) * (1.15 - reach)
        let grey = CGFloat.random(in: 0.55...1, using: &random)
        let alpha = (1 - reach) * CGFloat.random(in: 0.35...1, using: &random)
        context.setShadow(offset: .zero, blur: radius * 2.5, color: NSColor(white: 1, alpha: alpha * 0.8).cgColor)
        context.setFillColor(NSColor(white: grey, alpha: alpha).cgColor)
        if Int.random(in: 0..<5, using: &random) == 0 {
            // A few square "pixels" among the round sparks.
            context.fill(CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2).insetBy(dx: radius * 0.25, dy: radius * 0.25))
        } else {
            context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }
    }
    context.setShadow(offset: .zero, blur: 0, color: nil)
}

func drawPill(in context: CGContext) {
    context.saveGState()
    context.setShadow(offset: .zero, blur: 60, color: NSColor(white: 1, alpha: 0.45).cgColor)
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.setFillColor(NSColor.white.cgColor)
    context.addPath(CGPath(roundedRect: pill, cornerWidth: pill.height / 2, cornerHeight: pill.height / 2, transform: nil))
    context.fillPath()
    // The camera dot and the meter bars are cut into the pill, as in the menu bar icon. They are
    // painted black rather than punched out so the pill's glow does not fill them.
    context.setFillColor(NSColor.black.cgColor)
    context.fillEllipse(in: CGRect(x: pill.minX + 88, y: pill.midY - 32, width: 64, height: 64))
    for (index, height) in barHeights.enumerated() {
        let bar = CGRect(x: pill.minX + 222 + CGFloat(index) * 57, y: pill.midY - height / 2, width: 34, height: height)
        context.addPath(CGPath(roundedRect: bar, cornerWidth: 17, cornerHeight: 17, transform: nil))
        context.fillPath()
    }
    context.endTransparencyLayer()
    context.restoreGState()
}

guard CommandLine.arguments.count > 1,
      let context = CGContext(data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write(Data("usage: make_icon.swift <output.png>\n".utf8))
    exit(1)
}
let plateShape = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185).cgPath
context.addPath(plateShape)
context.clip()
let colours = [NSColor(white: 0.16, alpha: 1).cgColor, NSColor(white: 0.0, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: nil, colors: colours, locations: [0, 1])!
context.drawRadialGradient(gradient, startCenter: CGPoint(x: 512, y: 512), startRadius: 0, endCenter: CGPoint(x: 512, y: 512), endRadius: 560, options: .drawsAfterEndLocation)
drawParticles(in: context)
drawPill(in: context)
context.resetClip()
context.addPath(plateShape)
context.setStrokeColor(NSColor(white: 1, alpha: 0.12).cgColor)
context.setLineWidth(3)
context.strokePath()
let image = NSBitmapImageRep(cgImage: context.makeImage()!)
try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
