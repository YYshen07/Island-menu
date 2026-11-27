import os
import SceneKit

/// The MacBook model and everything live data drives on it. Closed, the machine stands facing the
/// camera showing one face: the lid with the glowing logo, or the underside with the internals
/// through a see-through bottom case, where die / SSD / battery glow by temperature and the fans
/// spin. A click turns it over; a double click settles it into a desk pose with the lid up.
/// It is drawn on demand: frames are produced only while something is actually moving.
@MainActor
final class MachineScene: NSObject, SCNSceneRendererDelegate {
    /// Chip regions; which of them exist depends on the model.
    private static let dieNodes = ["Die_Super", "Die_Perf", "Die_Eff", "Die_GPU"]
    /// Nodes that make up the coloured shell, and the materials on them that carry its colour.
    private static let shellNodes = ["Shell_Lid", "Shell_Bottom", "Chassis_Rail", "Keyboard_Deck"]
    private static let shellMaterials: Set<String> = ["Smoked_titanium", "Graphite", "Machined_graphite", "Bottom_case_opacity"]
    private static let bottomOpacity: CGFloat = 0.1
    private static let cameraDistance: CGFloat = 0.72
    private static let tilt: CGFloat = -0.2
    private static let lidOpenAngle: CGFloat = 108 * .pi / 180
    /// Pose changes are drawn at full rate; turning fans and the logo's flashing get by on less.
    private static let transitionFrameRate = 60
    private static let ambientFrameRate = 20
    private static let poseDuration = 1.5
    /// Extra time frames keep coming after a pose change, so the last frame is the settled one.
    private static let settleMargin = 0.15
    /// Desk pose: how far the base is tipped toward the camera, how far it is turned, and how far
    /// the camera backs off to fit the raised lid.
    private static let deskPitch: CGFloat = 0.5
    private static let deskYaw: CGFloat = -0.5
    private static let deskCameraDistance: CGFloat = 0.95
    private static let deskDrop: CGFloat = -0.09
    /// Seconds for one full turn of the machine.
    private static let flipDuration = 1.2
    /// Rotor speed on screen at full fan speed, in turns per second. Real speeds would strobe.
    private nonisolated static let maxTurnsPerSecond = 2.5
    private nonisolated static let minTurnsPerSecond = 0.25
    private nonisolated static let flashInterval = 0.14
    /// The glint on a mirror logo: where the band starts and ends in view space (metres, well clear
    /// of the logo on both sides) and how long one pass plus the pause after it takes.
    private nonisolated static let sweepStart = -0.045
    private nonisolated static let sweepEnd = 0.045
    private nonisolated static let sweepPeriod = 2.4
    private nonisolated static let sweepTravel = 0.9
    private nonisolated static let sweepKey = "sweep"
    private static let mirrorShader = """
    #pragma arguments
    float sweep;
    #pragma body
    float d = _surface.position.x + _surface.position.y * 0.55 - sweep;
    float band = exp(-d * d / 0.00006);
    float sheen = clamp(0.5 + 4.0 * _surface.position.y, 0.38, 0.66);
    _surface.emission = float4(sheen + band, sheen + band, sheen + band, 1.0);
    """
    /// Whether the logo is a light (PROLED machines) or polished metal.
    private let hasLogoLight: Bool
    private let screenContent: ScreenContent
    private var screenInstalled = false
    /// How far the picture sits in front of the panel's glass, in metres.
    private static let screenLift: CGFloat = 0.00004

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

    /// Loads the model for this Mac (or the one chosen in settings) in the chosen finish.
    static func current() -> MachineScene? {
        let model = MachineModel.current
        let scene = MachineScene(url: model.url, hasLogoLight: model.hasLogoLight, finish: Preferences.shared.machineFinish.color, screen: Preferences.shared.screenContent)
        let store = StickerStore.shared
        scene?.installStickers(store.stickers.compactMap { sticker in store.image(for: sticker).map { (sticker, $0) } })
        return scene
    }

    init?(url: URL?, hasLogoLight: Bool, finish: NSColor?, screen: ScreenContent) {
        guard let url, let scene = try? SCNScene(url: url, options: nil) else { return nil }
        self.scene = scene
        self.hasLogoLight = hasLogoLight
        self.screenContent = screen
        super.init()
        if let finish { paintShell(finish) }
        scene.background.contents = NSColor.clear
        // The file carries a showcase animation; poses here are driven by the app instead.
        scene.rootNode.enumerateHierarchy { node, _ in node.removeAllAnimations() }
        bindNodes()
        mountOnTurntable()
        addCameraAndLights()
        updateAirflowVisibility()
        let startAngle: CGFloat = showsUnderside ? .pi : 0
        motion.withLock { $0.turntable?.eulerAngles.y = startAngle }
    }

    /// Lights the screen with the chosen picture. Done the first time the lid opens, since the
    /// screen cannot be seen before that. The panel mesh has no texture coordinates, so the
    /// picture goes on a plane laid just over it, facing out of the lid with its top at the lid's edge.
    private func installScreenImage() {
        guard !screenInstalled, let display = geometryNode("Display") else { return }
        screenInstalled = true
        let (low, high) = display.boundingBox
        let size = CGSize(width: high.x - low.x, height: high.z - low.z)
        guard let image = screenContent.image(aspect: size.width / max(size.height, 0.001)) else { return }
        let plane = SCNPlane(width: size.width, height: size.height)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.position = SCNVector3((low.x + high.x) / 2, low.y - Self.screenLift, (low.z + high.z) / 2)
        node.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        display.addChildNode(node)
    }

    /// Recolours the anodised parts. Materials are copied first: the file shares some of them
    /// with internal parts, which keep their own colour.
    private func paintShell(_ color: NSColor) {
        for name in Self.shellNodes {
            guard let geometry = geometryNode(name)?.geometry else { continue }
            geometry.materials = geometry.materials.map { material in
                guard Self.shellMaterials.contains(material.name ?? ""), let copy = material.copy() as? SCNMaterial else { return material }
                copy.diffuse.contents = color
                return copy
            }
        }
    }

    func geometryNode(_ name: String) -> SCNNode? {
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
        if !hasLogoLight, let logo {
            // Older machines have a polished metal logo, not a lit one: a steady silver, with a
            // glint that crosses it while keep-awake is on (the band is placed by `sweep`).
            logo.diffuse.contents = NSColor.black
            logo.emission.contents = NSColor.black
            logo.shaderModifiers = [.surface: Self.mirrorShader]
            logo.setValue(NSNumber(value: Float(Self.sweepStart)), forKey: Self.sweepKey)
        }
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
        let names = Self.dieNodes + ["SSD_0", "SSD_1"] + (0..<6).map { "Battery_Cell_\($0)" }
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

    /// The airflow belongs to the underside; from the lid side its particles would show past the edges.
    private func updateAirflowVisibility() {
        for effect in airflow { effect.node.isHidden = !showsUnderside || isLidOpen }
    }

    /// Turns the closed machine over to its other face.
    func flip() {
        guard !isLidOpen else { return setLidOpen(false) }
        showsUnderside.toggle()
        updateAirflowVisibility()
        let turntable = motion.withLock { $0.turntable }
        animate(Self.flipDuration) {
            turntable?.eulerAngles.y += CGFloat.pi
        }
    }

    /// Opens or closes the lid, moving between the standing pose and the desk pose.
    func setLidOpen(_ open: Bool, animated: Bool = true) {
        isLidOpen = open
        if open { installScreenImage() }
        updateAirflowVisibility()
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
        let rate = Date() < transitionEnd ? Self.transitionFrameRate : Self.ambientFrameRate
        if view.preferredFramesPerSecond != rate { view.preferredFramesPerSecond = rate }
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
        for name in Self.dieNodes { spots[name]?.temperature = thermal.dieMean }
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
        if hasLogoLight, !isPartying, logoStep != shownLogoStep {
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
        let mirror = !hasLogoLight
        motion.withLock {
            $0.isPartying = partying
            $0.isMirror = mirror
        }
        if mirror, !partying { logo?.setValue(NSNumber(value: Float(Self.sweepStart)), forKey: Self.sweepKey) }
    }

    /// Sets the turntable angle directly, in turns (0 = lid facing the camera).
    /// Places the mirror logo's glint directly, 0 to 1 across the logo; for offscreen previews.
    func setGlint(_ position: Double) {
        logo?.setValue(NSNumber(value: Float(Self.sweepStart + (Self.sweepEnd - Self.sweepStart) * position)), forKey: Self.sweepKey)
    }

    func setTurn(_ turns: Double) {
        motion.withLock { $0.turntable?.eulerAngles.y = CGFloat(turns * 2 * .pi) }
    }

    nonisolated func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        motion.withLock { motion in
            defer { motion.lastTime = time }
            guard let lastTime = motion.lastTime else { return }
            let elapsed = min(time - lastTime, 0.1)
            if motion.isPartying, motion.isMirror {
                // One pass of the glint, then a pause, like the foil on a trading card.
                let phase = min(time.truncatingRemainder(dividingBy: Self.sweepPeriod) / Self.sweepTravel, 1)
                let eased = phase * phase * (3 - 2 * phase)
                motion.logo?.setValue(NSNumber(value: Float(Self.sweepStart + (Self.sweepEnd - Self.sweepStart) * eased)), forKey: Self.sweepKey)
            } else if motion.isPartying, time - motion.lastFlash > Self.flashInterval {
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
    var isMirror = false
    var lastFlash: TimeInterval = 0
    var flashHue: CGFloat = 0
}
