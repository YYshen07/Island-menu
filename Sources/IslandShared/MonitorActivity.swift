import ActivityKit
import Foundation

/// The Live Activity Island Menu keeps in the Dynamic Island: a few headline numbers, updated by
/// the app. Shared by the app (which starts and updates it) and the widget extension (which draws it).
@available(macOS 27.3, *)
public struct MonitorActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Whole-machine CPU load, 0...100.
        public var cpu: Int
        /// Hottest die temperature in °C, if readable.
        public var temperature: Int?
        /// Memory in use, 0...100.
        public var memory: Int
        /// Fastest fan in RPM; 0 when stopped.
        public var fanSpeed: Int

        public init(cpu: Int, temperature: Int?, memory: Int, fanSpeed: Int) {
            self.cpu = cpu
            self.temperature = temperature
            self.memory = memory
            self.fanSpeed = fanSpeed
        }
    }

    public init() {}
}

public enum IslandLink {
    /// Opening this URL shows the full panel.
    public static let openPanel = URL(string: "islandmenu://panel")!
    public static let scheme = "islandmenu"
}
