import AppKit
import SceneKit

/// Thermal-camera colour for a temperature: blue when cool, through green and amber, to red.
enum HeatRamp {
    /// The span is kept to what the sensors actually cover in use, so a few degrees is a visible step.
    static let cool = 35.0
    static let hot = 80.0

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

    /// Redraws only when a temperature has moved by a whole degree. Returns whether it did.
    @discardableResult
    func update(_ spots: [Spot]) -> Bool {
        let key = spots.map { Int(($0.temperature ?? 0).rounded()) }
        guard key != drawn else { return false }
        drawn = key
        material.emission.contents = render(spots)
        return true
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

/// Stylised airflow for one fan, following the real path through the machine: cool air comes in
/// through the side vent, crosses to the fan, and leaves through the fins at the hinge. It is an
/// effect, not a simulation; density and speed follow the fan's speed.
@MainActor
final class AirflowEffect {
    private static let rotorRadius: CGFloat = 0.026
    private static let ventLength: CGFloat = 0.05
    private static let finWidth: CGFloat = 0.04
    /// How far past the hinge edge the exhaust is still visible before it has faded out.
    private static let exhaustOvershoot: CGFloat = 0.012
    private static let fullBirthRate: CGFloat = 90
    private static let life: CGFloat = 0.55
    private static let sprite: CGImage? = softDot()

    let node = SCNNode()
    private let intake = SCNParticleSystem()
    private let exhaust = SCNParticleSystem()
    private let vent = SCNNode()
    private let outlet = SCNNode()
    private var isEmitting = false
    private let intakeDistance: CGFloat
    private let exhaustDistance: CGFloat

    /// `centre` is the rotor's position in the node's parent space, where the hinge is toward -z;
    /// `sideEdge` and `hingeEdge` are the body's nearest side edge (x) and hinge edge (z) there.
    init(centre: SCNVector3, sideEdge: CGFloat, hingeEdge: CGFloat) {
        node.position = centre
        let inward: CGFloat = sideEdge > centre.x ? -1 : 1
        intakeDistance = abs(sideEdge - centre.x) - Self.rotorRadius
        exhaustDistance = abs(centre.z - hingeEdge) - Self.rotorRadius + Self.exhaustOvershoot

        configure(intake, size: 0.0022)
        intake.emitterShape = SCNBox(width: 0.001, height: 0.001, length: Self.ventLength, chamferRadius: 0)
        intake.emittingDirection = SCNVector3(inward, 0, 0)
        intake.particleColor = NSColor(calibratedRed: 0.62, green: 0.84, blue: 1, alpha: 0.5)
        vent.position = SCNVector3(sideEdge - centre.x, 0, 0)

        configure(exhaust, size: 0.0026)
        exhaust.emitterShape = SCNBox(width: Self.finWidth, height: 0.001, length: 0.001, chamferRadius: 0)
        exhaust.emittingDirection = SCNVector3(0, 0, -1)
        outlet.position = SCNVector3(0, 0, -Self.rotorRadius)

        node.addChildNode(vent)
        node.addChildNode(outlet)
        update(level: 0, temperature: nil)
    }

    private func configure(_ system: SCNParticleSystem, size: CGFloat) {
        system.particleImage = Self.sprite
        system.particleSize = size
        system.particleSizeVariation = size * 0.4
        system.particleLifeSpan = Self.life
        system.particleLifeSpanVariation = Self.life * 0.2
        system.birthLocation = .volume
        system.birthDirection = .constant
        system.spreadingAngle = 7
        system.blendMode = .additive
        system.isLocal = true
        system.isLightingEnabled = false
        system.writesToDepthBuffer = false
        system.birthRate = 0
        // Fade in, then out, so the streams appear at the vent and dissolve instead of popping.
        let fade = CAKeyframeAnimation()
        fade.values = [0.0, 1.0, 1.0, 0.0]
        fade.keyTimes = [0, 0.2, 0.6, 1]
        system.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
    }

    func update(level: Double, temperature: Double?) {
        let level = CGFloat(min(max(level, 0), 1))
        // A particle system in the scene keeps SceneKit drawing every frame even when it emits
        // nothing, so the systems are only attached while the fan is turning.
        if (level > 0) != isEmitting {
            isEmitting = level > 0
            if isEmitting {
                vent.addParticleSystem(intake)
                outlet.addParticleSystem(exhaust)
            } else {
                vent.removeAllParticleSystems()
                outlet.removeAllParticleSystems()
            }
        }
        let rate = level > 0 ? Self.fullBirthRate * (0.3 + 0.7 * level) : 0
        intake.birthRate = rate
        exhaust.birthRate = rate
        // Each stream covers its whole path in one lifetime; a faster fan shortens the lifetime.
        let life = Self.life / (0.6 + 0.9 * level)
        for (system, distance) in [(intake, intakeDistance), (exhaust, exhaustDistance)] {
            system.particleLifeSpan = life
            system.particleVelocity = distance / life
            system.particleVelocityVariation = system.particleVelocity * 0.15
        }
        exhaust.particleColor = HeatRamp.color(temperature, alpha: 0.5)
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
