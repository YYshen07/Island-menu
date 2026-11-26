import SceneKit
import SwiftUI

/// Hosts the 3D model. Frames are only produced while the card is open.
struct MachineView: NSViewRepresentable {
    let machine: MachineScene
    let thermal: ThermalSnapshot
    let fans: [FanSnapshot]
    let isActive: Bool
    let isPartying: Bool

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = machine.scene
        view.pointOfView = machine.camera
        view.delegate = machine
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 30
        view.rendersContinuously = false
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        machine.setPartying(isPartying)
        machine.apply(thermal: thermal, fans: fans, logoLevel: 1)
        if isActive != view.isPlaying {
            machine.resetClock()
            view.isPlaying = isActive
        }
    }
}

struct MachineSection: View {
    @EnvironmentObject private var engine: MetricsEngine
    @EnvironmentObject private var state: IslandState
    /// Loaded when the card opens and dropped once it has closed, so SceneKit holds no memory in between.
    @State private var machine: MachineScene?
    @ObservedObject private var keepAwake = KeepAwake.shared
    private static let modelHeight: CGFloat = 236
    private static let releaseDelay: TimeInterval = 0.6

    var body: some View {
        let thermal = engine.snapshot.thermal
        VStack(spacing: 6) {
            ZStack {
                if let machine {
                    MachineView(machine: machine, thermal: thermal, fans: engine.snapshot.fans, isActive: state.isOpen, isPartying: keepAwake.isActive)
                        .overlay(Color.clear.contentShape(Rectangle()).onTapGesture { machine.setLidOpen(!machine.isLidOpen) })
                }
            }
            .frame(height: Self.modelHeight)
            HeatLegend()
            HStack(spacing: 0) {
                reading("芯片", thermal.dieMean)
                reading("芯片最高", thermal.dieMax)
                reading("SSD", thermal.ssd)
                reading("电池", thermal.battery)
            }
        }
        .padding(.horizontal, Theme.padding)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .onChange(of: state.isOpen, initial: true) { _, open in
            if open {
                if machine == nil { machine = MachineScene() }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseDelay) {
                    if !state.isOpen { machine = nil }
                }
            }
        }
    }

    private func reading(_ title: String, _ value: Double?) -> some View {
        VStack(spacing: 1) {
            Text(Format.degrees(value)).value()
            Text(title).label()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Colour key for the heat map on the model: the colour is a function of temperature alone.
private struct HeatLegend: View {
    private static let stops = 7

    var body: some View {
        let colors = (0..<Self.stops).map { step -> Color in
            let temperature = HeatRamp.cool + (HeatRamp.hot - HeatRamp.cool) * Double(step) / Double(Self.stops - 1)
            return Color(nsColor: HeatRamp.color(temperature))
        }
        HStack(spacing: 6) {
            Text("\(Int(HeatRamp.cool))°").label()
            Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)).frame(width: 120, height: 4)
            Text("\(Int(HeatRamp.hot))°").label()
        }
    }
}
