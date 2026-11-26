import os
import SceneKit

/// The x-ray MacBook model and everything live data drives on it: die / SSD / battery glow by
/// temperature, fan rotors by speed, the lid logo by brightness.
@MainActor
final class MachineScene: NSObject, SCNSceneRendererDelegate {
    nonisolated static let resourceName = "macbook-pro-14-xray"
    private static let coolTemperature = 35.0
    private static let hotTemperature = 95.0
    /// Rotor speed on screen at full fan speed, in turns per second. Real speeds would strobe.
    private nonisolated static let maxTurnsPerSecond = 2.5
    private nonisolated static let minTurnsPerSecond = 0.25
    private static let lidOpacity: CGFloat = 0.22

    let scene: SCNScene
    let camera = SCNNode()
    private var heated: [String: SCNMaterial] = [:]
    /// Rotors and their speeds are read on SceneKit's render thread, so they sit behind a lock.
    private let spin = OSAllocatedUnfairLock(initialState: Spin())
    private var housings: [SCNMaterial] = []
    private var logo: SCNMaterial?

    init?(url: URL? = Bundle.main.url(forResource: MachineScene.resourceName, withExtension: "usdz")) {
        guard let url, let scene = try? SCNScene(url: url, options: nil) else { return nil }
        self.scene = scene
        super.init()
        scene.background.contents = NSColor.clear
        bindNodes()
        addCamera()
        addLights()
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
                spin.withLock { $0.rotors.append(rotor) }
            }
            if let housing = geometryNode("Fan_\(side)_Housing")?.geometry?.firstMaterial { housings.append(housing) }
        }
        logo = geometryNode("Logo")?.geometry?.firstMaterial
        logo?.lightingModel = .constant
        // The lid is a see-through skin so the internals read through it.
        for material in geometryNode("Shell_Lid")?.geometry?.materials ?? [] {
            material.transparency = Self.lidOpacity
            material.writesToDepthBuffer = false
            material.isDoubleSided = true
        }
    }

    private func addCamera() {
        let lens = SCNCamera()
        lens.fieldOfView = 24
        lens.zNear = 0.01
        lens.zFar = 5
        camera.camera = lens
        camera.position = SCNVector3(0, 0.5, 0.213)
        camera.look(at: SCNVector3(0, 0, -0.004), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        scene.rootNode.addChildNode(camera)
    }

    private func addLights() {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 420
        let key = SCNLight()
        key.type = .directional
        key.intensity = 900
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-1.1, 0.5, 0)
        scene.rootNode.addChildNode(ambientNode)
        scene.rootNode.addChildNode(keyNode)
    }

    /// Pushes a sample onto the model. Returns whether anything is moving and needs frames.
    @discardableResult
    func apply(thermal: ThermalSnapshot, fans: [FanSnapshot], logoLevel: Double) -> Bool {
        // The die sensors are not mapped to individual clusters, so all three regions share the mean.
        for name in ["Die_Super", "Die_Perf", "Die_GPU"] { setHeat(name, thermal.dieMean) }
        for name in ["SSD_0", "SSD_1"] { setHeat(name, thermal.ssd) }
        for index in 0..<6 { setHeat("Battery_Cell_\(index)", thermal.battery) }
        let fanLevels = fans.map { $0.rpm > 0 ? $0.level : 0 }
        spin.withLock { $0.levels = fanLevels }
        for (index, housing) in housings.enumerated() {
            let level = index < fanLevels.count ? fanLevels[index] : 0
            housing.emission.contents = NSColor(hue: 0.58 - 0.5 * level, saturation: 0.85, brightness: level > 0 ? 0.35 + 0.65 * level : 0, alpha: 1)
        }
        logo?.emission.contents = NSColor(white: 0.15 + 0.85 * min(max(logoLevel, 0), 1), alpha: 1)
        logo?.diffuse.contents = logo?.emission.contents
        return fanLevels.contains { $0 > 0 }
    }

    private func setHeat(_ name: String, _ temperature: Double?) {
        guard let material = heated[name] else { return }
        let range = Self.hotTemperature - Self.coolTemperature
        let heat = min(max(((temperature ?? Self.coolTemperature) - Self.coolTemperature) / range, 0), 1)
        // Dark when cool, amber through the middle, red at the top.
        material.emission.contents = NSColor(hue: 0.1 - 0.1 * heat, saturation: 0.9, brightness: heat, alpha: 1)
    }

    nonisolated func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        spin.withLock { spin in
            defer { spin.lastTime = time }
            guard let lastTime = spin.lastTime else { return }
            let elapsed = min(time - lastTime, 0.1)
            for (index, rotor) in spin.rotors.enumerated() where index < spin.levels.count && spin.levels[index] > 0 {
                let turns = Self.minTurnsPerSecond + (Self.maxTurnsPerSecond - Self.minTurnsPerSecond) * spin.levels[index]
                rotor.eulerAngles.y += CGFloat(turns * elapsed * 2 * .pi) * (index == 0 ? 1 : -1)
            }
        }
    }

    func resetClock() {
        spin.withLock { $0.lastTime = nil }
    }
}

private struct Spin: @unchecked Sendable {
    var rotors: [SCNNode] = []
    var levels: [Double] = []
    var lastTime: TimeInterval?
}
