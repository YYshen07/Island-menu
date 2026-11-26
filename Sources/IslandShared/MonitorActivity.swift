import ActivityKit
import Foundation

/// What Island Menu can raise an alert about.
public enum AlertKind: String, Codable, CaseIterable, Sendable {
    /// In priority order: when several are active, the earliest is the one shown.
    case temperature, battery, storage, cpu, gpu

    public var title: String {
        switch self {
        case .temperature: "温度过高"
        case .battery: "电量不足"
        case .storage: "储存空间不足"
        case .cpu: "CPU 占用过高"
        case .gpu: "GPU 占用过高"
        }
    }

    public var symbol: String {
        switch self {
        case .temperature: "thermometer.high"
        case .battery: "battery.25percent"
        case .storage: "internaldrive.fill"
        case .cpu: "cpu.fill"
        case .gpu: "square.stack.3d.up.fill"
        }
    }

    public var unit: String { self == .temperature ? "°" : "%" }

    /// Battery alerts when the reading falls to the limit; the others when it rises to it.
    public var triggersBelow: Bool { self == .battery }
}

/// The Live Activity Island Menu raises in the Dynamic Island while something needs attention. It
/// exists only for the duration of an alert. Shared by the app and the widget extension.
@available(macOS 27.3, *)
public struct MonitorActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var kind: AlertKind
        /// Current reading, in the kind's unit.
        public var value: Int
        /// The threshold it crossed.
        public var limit: Int
        /// How many other alerts are active behind this one.
        public var others: Int

        public init(kind: AlertKind, value: Int, limit: Int, others: Int) {
            self.kind = kind
            self.value = value
            self.limit = limit
            self.others = others
        }
    }

    public init() {}
}

public enum IslandLink {
    /// Opening this URL shows the full panel.
    public static let openPanel = URL(string: "islandmenu://panel")!
    public static let scheme = "islandmenu"
}
