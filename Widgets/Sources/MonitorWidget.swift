import ActivityKit
import SwiftUI
import WidgetKit

@main
struct IslandMenuWidgets: WidgetBundle {
    var body: some Widget {
        MonitorActivityWidget()
    }
}

/// The alert Island Menu raises in the Dynamic Island: an icon and the offending reading when
/// compact, a one-line explanation and a large way into the full panel when expanded.
struct MonitorActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MonitorActivityAttributes.self) { context in
            // Shown in the menu bar on displays without a Dynamic Island.
            AlertSummary(state: context.state)
                .padding(14)
                .widgetURL(IslandLink.openPanel)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    AlertSummary(state: context.state)
                }
            } compactLeading: {
                Image(systemName: context.state.kind.symbol).foregroundStyle(.orange)
            } compactTrailing: {
                Text(reading(context.state)).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(.orange)
            } minimal: {
                Image(systemName: context.state.kind.symbol).foregroundStyle(.orange)
            }
            .widgetURL(IslandLink.openPanel)
            .keylineTint(.orange)
        }
    }
}

private func reading(_ state: MonitorActivityAttributes.ContentState) -> String {
    "\(state.value)\(state.kind.unit)"
}

private struct AlertSummary: View {
    let state: MonitorActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: state.kind.symbol).font(.system(size: 26)).foregroundStyle(.orange).frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.kind.title).font(.system(size: 16, weight: .semibold))
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(reading(state)).font(.system(size: 26, weight: .semibold)).monospacedDigit()
            }
            Link(destination: IslandLink.openPanel) {
                Text("展开面板").font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    // Follows the island's own corner curve, so the gap around the button is even.
                    .background(ContainerRelativeShape().fill(.white.opacity(0.18)))
            }
        }
    }

    private var detail: String {
        let threshold = "提醒阈值 \(state.kind.triggersBelow ? "低于" : "高于") \(state.limit)\(state.kind.unit)"
        return state.others > 0 ? "\(threshold) · 另有 \(state.others) 项提醒" : threshold
    }
}
