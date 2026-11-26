import AppKit
import SceneKit

/// Thermal-camera colour for a temperature: blue when cool, through green and amber, to red.
enum HeatRamp {
    static let cool = 30.0
    static let hot = 90.0

    static func fraction(_ temperature: Double?) -> Double {
        min(max(((temperature ?? cool) - cool) / (hot - cool), 0), 1)
    }

    static func color(_ temperature: Double?, alpha: CGFloat = 1) -> NSColor {
        let heat = fraction(temperature)
        return NSColor(hue: 0.62 * (1 - heat), saturation: 0.9, brightness: 0.55 + 0.45 * heat, alpha: alpha)
    }
}

/// A soft, feathered heat map drawn over the internals: one blurred blob per sensed part. It is a
/// single textured plane just inside the bottom case, facing down, so it only shows from underneath.
@MainActor
final class HeatMapLayer {
    struct Spot {
        var centre: CGPoint
        var radius: CGFloat
        var temperature: Double?
    }

    private static let pixelsPerMetre: CGFloat = 1100
    /// How far a blob spreads past the part it belongs to.
    private static let feather: CGFloat = 2.3
    private static let insetFromBottom: CGFloat = 0.0012

    let node: SCNNode
    private let material = SCNMaterial()
    private let size: CGSize
    private var drawn: [Int] = []

    /// `size` is the body's footprint (x by z) and `bottom` the y of its underside, in the node's parent space.
    init(size: CGSize, bottom: CGFloat) {
        self.size = size
        material.lightingModel = .constant
        material.diffuse.contents = NSColor.black
        material.blendMode = .add
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.isDoubleSided = false
        let plane = SCNPlane(width: size.width, height: size.height)
        plane.materials = [material]
        node = SCNNode(geometry: plane)
        // Turn the plane's normal to point down, out through the bottom case.
        node.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        node.position = SCNVector3(0, bottom + Self.insetFromBottom, 0)
        node.renderingOrder = 10
    }

    /// Redraws only when a temperature has moved by a whole degree.
    func update(_ spots: [Spot]) {
        let key = spots.map { Int(($0.temperature ?? 0).rounded()) }
        guard key != drawn else { return }
        drawn = key
        material.emission.contents = render(spots)
    }

    private func render(_ spots: [Spot]) -> CGImage? {
        let width = Int(size.width * Self.pixelsPerMetre), height = Int(size.height * Self.pixelsPerMetre)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setBlendMode(.screen)
        for spot in spots {
            let heat = HeatRamp.fraction(spot.temperature)
            let strength = 0.75 + 0.25 * heat
            let colors = [HeatRamp.color(spot.temperature, alpha: strength), HeatRamp.color(spot.temperature, alpha: strength * 0.45), HeatRamp.color(spot.temperature, alpha: 0)]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: [0, 0.4, 1]) else { continue }
            // Texture x runs with the body's x; texture y runs from the front edge to the hinge edge.
            let centre = CGPoint(x: (spot.centre.x / size.width + 0.5) * CGFloat(width), y: (0.5 + spot.centre.y / size.height) * CGFloat(height))
            let radius = spot.radius * Self.feather * Self.pixelsPerMetre
            context.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius, options: [])
        }
        return context.makeImage()
    }
}

/// Stylised airflow for one fan: air drawn in around the rotor and blown out toward the hinge.
/// It is an effect, not a simulation; density and speed follow the fan's speed.
@MainActor
final class AirflowEffect {
    private static let intakeRadius: CGFloat = 0.043
    private static let rotorRadius: CGFloat = 0.026
    private static let fullBirthRate: CGFloat = 220
    private static let sprite: CGImage? = softDot()

    let node = SCNNode()
    private let intake = SCNParticleSystem()
    private let exhaust = SCNParticleSystem()

    /// `centre` is the rotor's position in the node's parent space; the hinge is toward -z there.
    init(centre: SCNVector3) {
        node.position = centre
        configure(intake, size: 0.0016, life: 0.5)
        intake.emitterShape = SCNCylinder(radius: Self.intakeRadius, height: 0.001)
        intake.birthLocation = .surface
        intake.birthDirection = .surfaceNormal
        intake.particleColor = NSColor(calibratedRed: 0.6, green: 0.82, blue: 1, alpha: 0.9)
        configure(exhaust, size: 0.003, life: 0.42)
        exhaust.birthDirection = .constant
        exhaust.emittingDirection = SCNVector3(0, 0, -1)
        exhaust.spreadingAngle = 34
        exhaust.stretchFactor = 2
        let outlet = SCNNode()
        outlet.position = SCNVector3(0, 0, -Self.rotorRadius)
        outlet.addParticleSystem(exhaust)
        node.addParticleSystem(intake)
        node.addChildNode(outlet)
        update(level: 0, temperature: nil)
    }

    private func configure(_ system: SCNParticleSystem, size: CGFloat, life: CGFloat) {
        system.particleImage = Self.sprite
        system.particleSize = size
        system.particleSizeVariation = size * 0.5
        system.particleLifeSpan = life
        system.particleLifeSpanVariation = life * 0.3
        system.blendMode = .additive
        system.isLocal = true
        system.isLightingEnabled = false
        system.writesToDepthBuffer = false
        system.birthRate = 0
        // Fade each particle out over its life so streams dissolve instead of popping.
        let fade = CABasicAnimation()
        fade.fromValue = 1.0
        fade.toValue = 0.0
        system.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
    }

    func update(level: Double, temperature: Double?) {
        let level = CGFloat(min(max(level, 0), 1))
        intake.birthRate = level > 0 ? Self.fullBirthRate * (0.25 + 0.75 * level) : 0
        exhaust.birthRate = intake.birthRate * 0.6
        // Negative speed along the surface normal carries intake particles inward to the rotor.
        intake.particleVelocity = -(0.05 + 0.09 * level)
        exhaust.particleVelocity = 0.05 + 0.13 * level
        exhaust.particleVelocityVariation = exhaust.particleVelocity * 0.35
        exhaust.particleColor = HeatRamp.color(temperature, alpha: 0.45)
    }

    private static func softDot() -> CGImage? {
        let side = 32
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1]) else { return nil }
        let centre = CGPoint(x: side / 2, y: side / 2)
        context.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: CGFloat(side) / 2, options: [])
        return context.makeImage()
    }
}
