import SceneKit
import SwiftUI

/// Hosts the 3D model. Frames are only produced while the card is open and a fan is turning.
struct MachineView: NSViewRepresentable {
    let machine: MachineScene
    let thermal: ThermalSnapshot
    let fans: [FanSnapshot]
    let isActive: Bool

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = machine.scene
        view.pointOfView = machine.camera
        view.delegate = machine
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.rendersContinuously = false
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        let moving = machine.apply(thermal: thermal, fans: fans, logoLevel: 1)
        let play = isActive && moving
        if play != view.isPlaying {
            machine.resetClock()
            view.isPlaying = play
        }
    }
}

struct MachineSection: View {
    @EnvironmentObject private var engine: MetricsEngine
    @EnvironmentObject private var state: IslandState
    @State private var machine = MachineScene()

    var body: some View {
        let thermal = engine.snapshot.thermal
        VStack(spacing: 6) {
            if let machine {
                MachineView(machine: machine, thermal: thermal, fans: engine.snapshot.fans, isActive: state.isOpen)
                    .frame(height: 236)
            }
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
    }

    private func reading(_ title: String, _ value: Double?) -> some View {
        VStack(spacing: 1) {
            Text(Format.degrees(value)).value()
            Text(title).label()
        }
        .frame(maxWidth: .infinity)
    }
}
