import Foundation

/// One node of the fan curve: at `temperature` °C the fans run at `level` (0...1 of their range).
struct FanCurvePoint: Codable, Equatable {
    var temperature: Double
    var level: Double
}

enum FanMode: String, Codable, CaseIterable {
    case auto, max, curve
}

/// User settings, persisted in UserDefaults.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    static let temperatureRange = 40.0...100.0
    static let defaultCurve = [
        FanCurvePoint(temperature: 45, level: 0),
        FanCurvePoint(temperature: 60, level: 0.25),
        FanCurvePoint(temperature: 80, level: 0.65),
        FanCurvePoint(temperature: 95, level: 1),
    ]
    private enum Key {
        static let fanMode = "fanMode"
        static let fanCurve = "fanCurve"
        static let showPublicIP = "showPublicIP"
    }

    private let defaults = UserDefaults.standard

    @Published var fanMode: FanMode {
        didSet { defaults.set(fanMode.rawValue, forKey: Key.fanMode) }
    }

    @Published var fanCurve: [FanCurvePoint] {
        didSet { defaults.set(try? JSONEncoder().encode(fanCurve), forKey: Key.fanCurve) }
    }

    @Published var showPublicIP: Bool {
        didSet { defaults.set(showPublicIP, forKey: Key.showPublicIP) }
    }

    private init() {
        fanMode = defaults.string(forKey: Key.fanMode).flatMap(FanMode.init) ?? .auto
        let stored = defaults.data(forKey: Key.fanCurve).flatMap { try? JSONDecoder().decode([FanCurvePoint].self, from: $0) }
        fanCurve = stored.flatMap { $0.count >= 2 ? $0 : nil } ?? Self.defaultCurve
        showPublicIP = defaults.object(forKey: Key.showPublicIP) as? Bool ?? true
    }

    /// Fan level the curve asks for at a temperature, interpolating between nodes.
    func curveLevel(at temperature: Double) -> Double {
        guard let first = fanCurve.first, let last = fanCurve.last else { return 0 }
        if temperature <= first.temperature { return first.level }
        if temperature >= last.temperature { return last.level }
        guard let upper = fanCurve.firstIndex(where: { $0.temperature > temperature }), upper > 0 else { return last.level }
        let (a, b) = (fanCurve[upper - 1], fanCurve[upper])
        return a.level + (b.level - a.level) * (temperature - a.temperature) / (b.temperature - a.temperature)
    }
}
