import os
import SceneKit

/// The MacBook model and everything live data drives on it. Closed, the machine stands facing the
/// camera showing one face: the lid with the glowing logo, or the underside with the internals
/// through a see-through bottom case, where die / SSD / battery glow by temperature and the fans
/// spin. A click turns it over; a double click settles it into a desk pose with the lid up.
/// It is drawn on demand: frames are produced only while something is actually moving.
@MainActor
final class MachineScene: NSObject, SCNSceneRendererDelegate {
    nonisolated static let resourceName = "macbook-pro-14"
    private static let bottomOpacity: CGFloat = 0.1
    private static let ghostOpacity: CGFloat = 0.25
    private static let cameraDistance: CGFloat = 0.72
    private static let tilt: CGFloat = -0.2
    private static let lidOpenAngle: CGFloat = 108 * .pi / 180
    private static let poseDuration = 0.9
    /// Extra time frames keep coming after a pose change, so the last frame is the settled one.
    private static let settleMargin = 0.15
    /// Desk pose: how far the base is tipped toward the camera, how far it is turned, and how far
    /// the camera backs off to fit the raised lid.
    private static let deskPitch: CGFloat = 0.5
    private static let deskYaw: CGFloat = -0.5
    private static let deskCameraDistance: CGFloat = 0.95
    private static let deskDrop: CGFloat = -0.09
    /// Seconds for one full turn of the machine.
    private static let flipDuration = 0.7
    /// Rotor speed on screen at full fan speed, in turns per second. Real speeds would strobe.
    private nonisolated static let maxTurnsPerSecond = 2.5
    private nonisolated static let minTurnsPerSecond = 0.25
    private nonisolated static let flashInterval = 0.14

    let scene: SCNScene
    let camera = SCNNode()
    /// Sensed parts, as heat-map spots, keyed by node name.
    private var spots: [String: HeatMapLayer.Spot] = [:]
    private var heatMap: HeatMapLayer?
    private var airflow: [AirflowEffect] = []
    private var housings: [SCNMaterial] = []
    private var logo: SCNMaterial?
    private var hinge: SCNNode?
    private var hingeRest = SCNVector3Zero
    private let upright = SCNNode()
    private let facing = SCNNode()
    private let stand = SCNNode()
    private(set) var isLidOpen = false
    /// Which face is toward the camera while closed; picked at random each time the card opens.
    private(set) var showsUnderside = Bool.random()
    private weak var view: SCNView?
    private var isCardOpen = false
    private var isPartying = false
    private var transitionEnd = Date.distantPast
    /// Starts as a value no reading can equal, so the first sample always gets applied.
    private var shownFanSteps: [Int] = [-1]
    private var shownLogoStep = -1
    private var needsStillFrame = true
    /// Everything SceneKit's render thread animates sits behind a lock.
    private let motion = OSAllocatedUnfairLock(initialState: Motion())

    init?(url: URL? = Bundle.main.url(forResource: MachineScene.resourceName, withExtension: "usdz")) {
        guard let url, let scene = try? SCNScene(url: url, options: nil) else { return nil }
        self.scene = scene
        super.init()
        scene.background.contents = NSColor.clear
        // The file carries a showcase animation; poses here are driven by the app instead.
        scene.rootNode.enumerateHierarchy { node, _ in node.removeAllAnimations() }
        bindNodes()
        mountOnTurntable()
        addCameraAndLights()
        let startAngle: CGFloat = showsUnderside ? .pi : 0
        motion.withLock { $0.turntable?.eulerAngles.y = startAngle }
    }

    private func geometryNode(_ name: String) -> SCNNode? {
        guard let node = scene.rootNode.childNode(withName: name, recursively: true) else { return nil }
        return node.geometry != nil ? node : node.childNodes.first { $0.geometry != nil }
    }

    private func bindNodes() {
        for side in ["L", "R"] {
            if let rotor = scene.rootNode.childNode(withName: "Fan_\(side)_Rotor", recursively: true) {
                motion.withLock { $0.rotors.append(rotor) }
            }
            if let housing = geometryNode("Fan_\(side)_Housing")?.geometry?.firstMaterial { housings.append(housing) }
        }
        logo = geometryNode("Logo")?.geometry?.firstMaterial
        logo?.lightingModel = .constant
        let logoMaterial = logo
        motion.withLock { $0.logo = logoMaterial }
        hinge = scene.rootNode.childNode(withName: "Lid_Hinge", recursively: true)
        hingeRest = hinge?.eulerAngles ?? SCNVector3Zero
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
        upright.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        facing.eulerAngles = SCNVector3(0, CGFloat.pi, 0)
        for child in scene.rootNode.childNodes { facing.addChildNode(child) }
        // Centre the closed body on the node's origin, whatever the model's own origin is.
        let (low, high) = facing.boundingBox
        let centre = SCNVector3((low.x + high.x) / 2, (low.y + high.y) / 2, (low.z + high.z) / 2)
        for child in facing.childNodes {
            child.position = SCNVector3(child.position.x - centre.x, child.position.y - centre.y, child.position.z - centre.z)
        }
        upright.addChildNode(facing)
        let turntable = SCNNode()
        turntable.addChildNode(upright)
        stand.eulerAngles = SCNVector3(Self.tilt, 0, 0)
        stand.addChildNode(turntable)
        scene.rootNode.addChildNode(stand)
        motion.withLock { $0.turntable = turntable }
        addEffects(bodyLow: SCNVector3(low.x - centre.x, low.y - centre.y, low.z - centre.z), bodyHigh: SCNVector3(high.x - centre.x, high.y - centre.y, high.z - centre.z))
    }

    /// Heat map and airflow live in the body's own space, so they turn and tilt with it.
    private func addEffects(bodyLow: SCNVector3, bodyHigh: SCNVector3) {
        let names = ["Die_Super", "Die_Perf", "Die_GPU", "SSD_0", "SSD_1"] + (0..<6).map { "Battery_Cell_\($0)" }
        for name in names {
            guard let part = geometryNode(name) else { continue }
            let (low, high) = part.boundingBox
            let middle = part.convertPosition(SCNVector3((low.x + high.x) / 2, (low.y + high.y) / 2, (low.z + high.z) / 2), to: facing)
            spots[name] = HeatMapLayer.Spot(centre: CGPoint(x: middle.x, y: middle.z), radius: max(high.x - low.x, high.z - low.z) / 2, temperature: nil)
        }
        let layer = HeatMapLayer(size: CGSize(width: bodyHigh.x - bodyLow.x, height: bodyHigh.z - bodyLow.z), bottom: bodyLow.y)
        facing.addChildNode(layer.node)
        heatMap = layer
        for rotor in motion.withLock({ $0.rotors }) {
            let centre = rotor.convertPosition(SCNVector3Zero, to: facing)
            let effect = AirflowEffect(centre: centre, sideEdge: centre.x < 0 ? bodyLow.x : bodyHigh.x, hingeEdge: bodyLow.z)
            facing.addChildNode(effect.node)
            airflow.append(effect)
        }
    }

    // MARK: - Poses

    /// Turns the closed machine over to its other face.
    func flip() {
        guard !isLidOpen else { return setLidOpen(false) }
        showsUnderside.toggle()
        let turntable = motion.withLock { $0.turntable }
        animate(Self.flipDuration) {
            turntable?.eulerAngles.y += CGFloat.pi
        }
    }

    /// Opens or closes the lid, moving between the standing pose and the desk pose.
    func setLidOpen(_ open: Bool, animated: Bool = true) {
        isLidOpen = open
        let turntable = motion.withLock { $0.turntable }
        animate(animated ? Self.poseDuration : 0) {
            hinge?.eulerAngles = SCNVector3(hingeRest.x - (open ? Self.lidOpenAngle : 0), hingeRest.y, hingeRest.z)
            upright.eulerAngles.x = open ? Self.deskPitch : CGFloat.pi / 2
            facing.eulerAngles.y = open ? 0 : CGFloat.pi
            stand.position.y = open ? Self.deskDrop : 0
            camera.position.z = open ? Self.deskCameraDistance : Self.cameraDistance
            guard let turntable else { return }
            // Go to the desk yaw, or back to the face that was showing, by the shortest way round.
            let target = open ? Self.deskYaw : (showsUnderside ? CGFloat.pi : 0)
            let turns = ((turntable.eulerAngles.y - target) / (2 * .pi)).rounded()
            turntable.eulerAngles.y = target + turns * 2 * .pi
        }
    }

    private func animate(_ duration: TimeInterval, _ changes: () -> Void) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        changes()
        SCNTransaction.commit()
        transitionEnd = Date().addingTimeInterval(duration + Self.settleMargin)
        needsStillFrame = true
        updatePlayback()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + Self.settleMargin + 0.05) { [weak self] in
            self?.updatePlayback()
        }
    }

    // MARK: - On-demand rendering

    func attach(_ view: SCNView) {
        self.view = view
    }

    func setCardOpen(_ open: Bool) {
        isCardOpen = open
        updatePlayback()
    }

    /// Frames are needed only during a pose change, while the fans are visibly turning, or while
    /// the logo is flashing. Otherwise the view holds its last frame and costs nothing.
    private func updatePlayback() {
        guard let view else { return }
        let fansTurning = motion.withLock { $0.fanLevels.contains { $0 > 0 } }
        let fansVisible = fansTurning && showsUnderside && !isLidOpen
        let logoVisible = isPartying && (isLidOpen || !showsUnderside)
        let play = isCardOpen && (Date() < transitionEnd || fansVisible || logoVisible)
        if play != view.isPlaying {
            motion.withLock { $0.lastTime = nil }
            view.isPlaying = play
        }
        // A paused view redraws once when something it shows has changed, and not otherwise.
        if !play, needsStillFrame { view.needsDisplay = true }
        needsStillFrame = false
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
        for name in ["Die_Super", "Die_Perf", "Die_GPU"] { spots[name]?.temperature = thermal.dieMean }
        for name in ["SSD_0", "SSD_1"] { spots[name]?.temperature = thermal.ssd }
        for index in 0..<6 { spots["Battery_Cell_\(index)"]?.temperature = thermal.battery }
        let heatChanged = heatMap?.update(spots.keys.sorted().compactMap { spots[$0] }) ?? false
        let fanLevels = fans.map { $0.rpm > 0 ? $0.level : 0 }
        // The underside is the only face where these readings show; a still frame is redrawn only
        // when one of them has visibly moved.
        let fansChanged = fanLevels.map { Int($0 * 20) } != shownFanSteps
        shownFanSteps = fanLevels.map { Int($0 * 20) }
        if (heatChanged || fansChanged) && showsUnderside { needsStillFrame = true }
        motion.withLock { $0.fanLevels = fanLevels }
        // Writing a material or particle property marks the scene dirty and makes SceneKit redraw,
        // even when the value is the same, so nothing is written unless it actually changed.
        if fansChanged {
            for (index, housing) in housings.enumerated() {
                let level = index < fanLevels.count ? fanLevels[index] : 0
                housing.emission.contents = NSColor(hue: 0.58 - 0.5 * level, saturation: 0.85, brightness: level > 0 ? 0.35 + 0.65 * level : 0, alpha: 1)
                if index < airflow.count { airflow[index].update(level: level, temperature: thermal.dieMean) }
            }
        }
        // While the logo is partying the render loop owns its colour.
        let logoStep = Int(min(max(logoLevel, 0), 1) * 100)
        if !isPartying, logoStep != shownLogoStep {
            shownLogoStep = logoStep
            logo?.emission.contents = NSColor(white: 0.15 + 0.85 * CGFloat(logoStep) / 100, alpha: 1)
            logo?.diffuse.contents = logo?.emission.contents
            if !showsUnderside { needsStillFrame = true }
        }
        updatePlayback()
    }

    /// Nightclub mode for the logo: hard colour changes on a beat, used while keep-awake is on.
    func setPartying(_ partying: Bool) {
        if partying != isPartying {
            needsStillFrame = true
            // Force the steady logo colour back in once the party is over.
            shownLogoStep = -1
        }
        isPartying = partying
        motion.withLock { $0.isPartying = partying }
    }

    /// Sets the turntable angle directly, in turns (0 = lid facing the camera).
    func setTurn(_ turns: Double) {
        motion.withLock { $0.turntable?.eulerAngles.y = CGFloat(turns * 2 * .pi) }
    }

    nonisolated func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        motion.withLock { motion in
            defer { motion.lastTime = time }
            guard let lastTime = motion.lastTime else { return }
            let elapsed = min(time - lastTime, 0.1)
            if motion.isPartying, time - motion.lastFlash > Self.flashInterval {
                motion.lastFlash = time
                // Jump around the colour wheel rather than sweeping it, with the odd white strobe.
                motion.flashHue = (motion.flashHue + CGFloat.random(in: 0.23...0.61)).truncatingRemainder(dividingBy: 1)
                let strobe = Int.random(in: 0..<6) == 0
                let color = NSColor(hue: motion.flashHue, saturation: strobe ? 0 : 1, brightness: 1, alpha: 1)
                motion.logo?.emission.contents = color
                motion.logo?.diffuse.contents = color
            }
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
    var logo: SCNMaterial?
    var isPartying = false
    var lastFlash: TimeInterval = 0
    var flashHue: CGFloat = 0
}
