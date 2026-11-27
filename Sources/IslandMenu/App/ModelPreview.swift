import AppKit
import Metal
import SceneKit

/// Offscreen render of the model with representative data, for checking camera and lighting.
@MainActor
enum ModelPreview {
    /// An optional trailing argument sets the turntable angle in turns (0.5 shows the underside);
    /// `--lid-open` renders the desk pose instead; `--no-logo --glint 0.5` shows the mirror logo mid-glint;
    /// `--finish silver` (a `MachineFinish` name) recolours the shell;
    /// `--screen wallpaper --lid-open` lights the screen (a `ScreenContent` name).
    static func render(model: String, to output: String) -> Bool {
        let finish = CommandLine.arguments.firstIndex(of: "--finish").flatMap { MachineFinish(rawValue: CommandLine.arguments[$0 + 1]) }
        let lit = !CommandLine.arguments.contains("--no-logo") && model.hasSuffix("macbook-pro-14.usdz")
        guard let machine = MachineScene(url: URL(fileURLWithPath: model), hasLogoLight: lit, finish: finish?.color, screen: CommandLine.arguments.firstIndex(of: "--screen").flatMap { ScreenContent(rawValue: CommandLine.arguments[$0 + 1]) } ?? .off), let device = MTLCreateSystemDefaultDevice() else { return false }
        // `--sticker <picture>` cuts a sticker out of the picture and puts it on the lid in every effect.
        if let flag = CommandLine.arguments.firstIndex(of: "--sticker"), let data = FileManager.default.contents(atPath: CommandLine.arguments[flag + 1]),
           let cutout = try? StickerMaker.makeWithVision(from: data) {
            let aspect = Double(cutout.width) / Double(cutout.height)
            let spots = (0..<StickerStyle.allCases.count).map { (-0.38 + 0.19 * Double($0 % 5), $0 < 5 ? 0.27 : -0.27) }
            machine.installStickers(zip(StickerStyle.allCases, spots).map { style, spot in
                (Sticker(x: spot.0, y: spot.1, size: 0.16, aspect: aspect, style: style), StickerMaker.styled(cutout, style))
            })
        }
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
