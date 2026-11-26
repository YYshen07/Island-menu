import os
import SceneKit

/// The MacBook model and everything live data drives on it. The machine stands facing the camera
/// and turns slowly: the lid side shows the glowing logo, the underside shows the internals through
/// a see-through bottom case, where die / SSD / battery glow by temperature and the fans spin.
@MainActor
final class MachineScene: NSObject, SCNSceneRendererDelegate {
    nonisolated static let resourceName = "macbook-pro-14-xray"
    private static let coolTemperature = 35.0
    private static let hotTemperature = 95.0
    private static let bottomOpacity: CGFloat = 0.1
    private static let ghostOpacity: CGFloat = 0.25
    private static let bodyThickness: CGFloat = 0.015
    private static let cameraDistance: CGFloat = 0.72
    private static let tilt: CGFloat = -0.2
    /// Seconds for one full turn of the machine.
    private nonisolated static let turnPeriod = 16.0
    /// Rotor speed on screen at full fan speed, in turns per second. Real speeds would strobe.
    private nonisolated static let maxTurnsPerSecond = 2.5
    private nonisolated static let minTurnsPerSecond = 0.25

    let scene: SCNScene
    let camera = SCNNode()
    private var heated: [String: SCNMaterial] = [:]
    private var housings: [SCNMaterial] = []
    private var logo: SCNMaterial?
    /// Everything SceneKit's render thread animates sits behind a lock.
    private let motion = OSAllocatedUnfairLock(initialState: Motion())

    init?(url: URL? = Bundle.main.url(forResource: MachineScene.resourceName, withExtension: "usdz")) {
        guard let url, let scene = try? SCNScene(url: url, options: nil) else { return nil }
        self.scene = scene
        super.init()
        scene.background.contents = NSColor.clear
        bindNodes()
        mountOnTurntable()
        addCameraAndLights()
    }

    private func geometryNode(_ name: String) -> SCNNode? {
        guard let node = scene.rootNode.childNode(withName: name, recursively: true) else { return nil }
        return node.geometry != nil ? node : node.childNodes.first { $0.geometry != nil }
    }

    private func bindNodes() {
        let names = ["Die_Super", "Die_Perf", "Die_GPU", "SSD_0", "SSD_1"] + (0..<6).map { "Battery_Cell_\($0)" }
        for name in names {
            heated[name] = geometryNode(name)?.geometry?.firstMaterial
        }
        for side in ["L", "R"] {
            if let rotor = scene.rootNode.childNode(withName: "Fan_\(side)_Rotor", recursively: true) {
                motion.withLock { $0.rotors.append(rotor) }
            }
            if let housing = geometryNode("Fan_\(side)_Housing")?.geometry?.firstMaterial { housings.append(housing) }
        }
        logo = geometryNode("Logo")?.geometry?.firstMaterial
        logo?.lightingModel = .constant
        // The internals are only meant to be seen from underneath, through the bottom case.
        // The model stores opacity in `transparent`, so the lid is closed up and the bottom opened there.
        for material in geometryNode("Shell_Lid")?.geometry?.materials ?? [] {
            material.transparent.contents = 1.0
        }
        for material in geometryNode("Shell_Bottom")?.geometry?.materials ?? [] where material.name == "Bottom_case_opacity" {
            material.transparent.contents = Self.bottomOpacity
            material.writesToDepthBuffer = false
        }
        // In the model the chips sit on the lid side of the board. Seen from underneath they would be
        // hidden, so the board and package are ghosted, and the etched label (mirrored from here) dropped.
        for name in ["Board", "SoC_Package"] {
            for material in geometryNode(name)?.geometry?.materials ?? [] {
                material.transparent.contents = material.name == "Laser_etch" ? 0 : Self.ghostOpacity
                material.writesToDepthBuffer = false
            }
        }
    }

    /// Re-parents the model so it stands upright facing the camera (lid forward, hinge down, which
    /// puts the logo the right way up) on a node that turns about the vertical axis.
    private func mountOnTurntable() {
        let upright = SCNNode()
        upright.position = SCNVector3(0, 0, Self.bodyThickness / 2)
        upright.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        let facing = SCNNode()
        facing.eulerAngles = SCNVector3(0, CGFloat.pi, 0)
        facing.position = SCNVector3(0, -Self.bodyThickness, 0)
        for child in scene.rootNode.childNodes { facing.addChildNode(child) }
        upright.addChildNode(facing)
        let turntable = SCNNode()
        turntable.addChildNode(upright)
        // Centre the model on the turning axis, whatever its own origin is.
        let (low, high) = turntable.boundingBox
        upright.position.x -= (low.x + high.x) / 2
        upright.position.y -= (low.y + high.y) / 2
        upright.position.z -= (low.z + high.z) / 2
        let stand = SCNNode()
        stand.eulerAngles = SCNVector3(Self.tilt, 0, 0)
        stand.addChildNode(turntable)
        scene.rootNode.addChildNode(stand)
        motion.withLock { $0.turntable = turntable }
    }

    private func addCameraAndLights() {
        let lens = SCNCamera()
        lens.fieldOfView = 24
        lens.zNear = 0.01
        lens.zFar = 5
        camera.camera = lens
        camera.position = SCNVector3(0, 0, Self.cameraDistance)
        // The key light rides with the camera so both faces are lit the same as they come round.
        let key = SCNLight()
        key.type = .directional
        key.intensity = 900
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.5, 0.35, 0)
        camera.addChildNode(keyNode)
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 420
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(camera)
        scene.rootNode.addChildNode(ambientNode)
    }

    /// Pushes a sample onto the model.
    func apply(thermal: ThermalSnapshot, fans: [FanSnapshot], logoLevel: Double) {
        // The die sensors are not mapped to individual clusters, so all three regions share the mean.
        for name in ["Die_Super", "Die_Perf", "Die_GPU"] { setHeat(name, thermal.dieMean) }
        for name in ["SSD_0", "SSD_1"] { setHeat(name, thermal.ssd) }
        for index in 0..<6 { setHeat("Battery_Cell_\(index)", thermal.battery) }
        let fanLevels = fans.map { $0.rpm > 0 ? $0.level : 0 }
        motion.withLock { $0.fanLevels = fanLevels }
        for (index, housing) in housings.enumerated() {
            let level = index < fanLevels.count ? fanLevels[index] : 0
            housing.emission.contents = NSColor(hue: 0.58 - 0.5 * level, saturation: 0.85, brightness: level > 0 ? 0.35 + 0.65 * level : 0, alpha: 1)
        }
        logo?.emission.contents = NSColor(white: 0.15 + 0.85 * min(max(logoLevel, 0), 1), alpha: 1)
        logo?.diffuse.contents = logo?.emission.contents
    }

    private func setHeat(_ name: String, _ temperature: Double?) {
        guard let material = heated[name] else { return }
        let range = Self.hotTemperature - Self.coolTemperature
        let heat = min(max(((temperature ?? Self.coolTemperature) - Self.coolTemperature) / range, 0), 1)
        // Dark when cool, amber through the middle, red at the top.
        material.emission.contents = NSColor(hue: 0.1 - 0.1 * heat, saturation: 0.9, brightness: heat, alpha: 1)
    }

    /// Sets the turntable angle directly, in turns (0 = lid facing the camera).
    func setTurn(_ turns: Double) {
        motion.withLock { $0.turntable?.eulerAngles.y = CGFloat(turns * 2 * .pi) }
    }

    func resetClock() {
        motion.withLock { $0.lastTime = nil }
    }

    nonisolated func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        motion.withLock { motion in
            defer { motion.lastTime = time }
            guard let lastTime = motion.lastTime else { return }
            let elapsed = min(time - lastTime, 0.1)
            motion.turntable?.eulerAngles.y += CGFloat(elapsed / Self.turnPeriod * 2 * .pi)
            for (index, rotor) in motion.rotors.enumerated() where index < motion.fanLevels.count && motion.fanLevels[index] > 0 {
                let turns = Self.minTurnsPerSecond + (Self.maxTurnsPerSecond - Self.minTurnsPerSecond) * motion.fanLevels[index]
                rotor.eulerAngles.y += CGFloat(turns * elapsed * 2 * .pi) * (index == 0 ? 1 : -1)
            }
        }
    }
}

private struct Motion: @unchecked Sendable {
    var turntable: SCNNode?
    var rotors: [SCNNode] = []
    var fanLevels: [Double] = []
    var lastTime: TimeInterval?
}
