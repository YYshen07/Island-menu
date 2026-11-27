import AppKit
import Metal
import SceneKit

/// Offscreen render of the model with representative data, for checking camera and lighting.
@MainActor
enum ModelPreview {
    /// An optional trailing argument sets the turntable angle in turns (0.5 shows the underside);
    /// `--lid-open` renders the desk pose instead; `--no-logo --glint 0.5` shows the mirror logo mid-glint.
    static func render(model: String, to output: String) -> Bool {
        guard let machine = MachineScene(url: URL(fileURLWithPath: model)), let device = MTLCreateSystemDefaultDevice() else { return false }
        let thermal = ThermalSnapshot(dieMax: 78, dieMean: 70, ssd: 48, battery: 36)
        machine.apply(thermal: thermal, fans: [FanSnapshot(rpm: 2400, minimum: 1200, maximum: 6000), FanSnapshot(rpm: 2600, minimum: 1200, maximum: 6000)], logoLevel: 1)
        if let turn = CommandLine.arguments.last.flatMap(Double.init) { machine.setTurn(turn) }
        if let flag = CommandLine.arguments.firstIndex(of: "--glint"), let position = Double(CommandLine.arguments[flag + 1]) { machine.setGlint(position) }
        if CommandLine.arguments.contains("--lid-open") { machine.setLidOpen(true, animated: false) }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = machine.scene
        renderer.pointOfView = machine.camera
        // Step the scene forward first so the particle systems have something to show.
        for step in 0..<40 { renderer.update(atTime: Double(step) / 30) }
        let image = renderer.snapshot(atTime: 40.0 / 30, with: CGSize(width: 800, height: 472), antialiasingMode: .multisampling4X)
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: output))) != nil
    }
}
