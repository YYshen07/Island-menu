import ActivityKit
import SwiftUI
import WidgetKit

@main
struct IslandMenuWidgets: WidgetBundle {
    var body: some Widget {
        MonitorActivityWidget()
    }
}

/// Island Menu's presence in the Dynamic Island: CPU and temperature when compact, a short summary
/// and a way into the full panel when expanded.
struct MonitorActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MonitorActivityAttributes.self) { context in
            // Shown in the menu bar on displays without a Dynamic Island.
            HStack(spacing: 18) {
                Stat(title: "CPU", value: "\(context.state.cpu)%")
                Stat(title: "温度", value: temperature(context.state))
                Stat(title: "内存", value: "\(context.state.memory)%")
                Spacer()
                PanelLink()
            }
            .padding(14)
            .widgetURL(IslandLink.openPanel)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Stat(title: "CPU", value: "\(context.state.cpu)%")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Stat(title: "温度", value: temperature(context.state))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 18) {
                        Stat(title: "内存", value: "\(context.state.memory)%")
                        Stat(title: "风扇", value: context.state.fanSpeed > 0 ? "\(context.state.fanSpeed)" : "停转")
                        Spacer()
                        PanelLink()
                    }
                }
            } compactLeading: {
                Label("\(context.state.cpu)%", systemImage: "cpu")
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit()
            } compactTrailing: {
                Text(temperature(context.state))
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(tint(context.state))
            } minimal: {
                Text("\(context.state.cpu)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            .widgetURL(IslandLink.openPanel)
            .keylineTint(tint(context.state))
        }
    }

    private func temperature(_ state: MonitorActivityAttributes.ContentState) -> String {
        state.temperature.map { "\($0)°" } ?? "—"
    }

    /// White when cool, amber then red as the chip heats up.
    private func tint(_ state: MonitorActivityAttributes.ContentState) -> Color {
        guard let temperature = state.temperature else { return .white }
        return temperature >= 85 ? .red : (temperature >= 70 ? .orange : .white)
    }
}

private struct Stat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit()
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

private struct PanelLink: View {
    var body: some View {
        Link(destination: IslandLink.openPanel) {
            Text("打开面板").font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(0.18)))
        }
    }
}
