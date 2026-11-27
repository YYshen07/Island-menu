import AppKit
import IslandShared

/// When an alert of one kind is raised.
struct AlertRule: Codable, Equatable {
    var enabled: Bool
    /// Percent, or °C for temperature.
    var limit: Double
}

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
    static let defaultChargeLimit = 85
    static let defaultAwakeBrightness = 0.2
    static let defaultAlertRules: [AlertKind: AlertRule] = [
        .cpu: AlertRule(enabled: true, limit: 90),
        .gpu: AlertRule(enabled: true, limit: 90),
        .temperature: AlertRule(enabled: true, limit: 95),
        .battery: AlertRule(enabled: true, limit: 20),
        .storage: AlertRule(enabled: true, limit: 95),
    ]
    /// Allowed range for each kind's limit in the settings UI.
    static let alertLimitRanges: [AlertKind: ClosedRange<Double>] = [.cpu: 50...100, .gpu: 50...100, .temperature: 60...105, .battery: 5...50, .storage: 70...99]
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
        static let chargeLimit = "chargeLimit"
        static let logoMode = "logoMode"
        static let awakeBrightness = "awakeBrightness"
        static let alertRules = "alertRules"
        static let colorful = "colorful"
        static let islandStyle = "islandStyle"
        static let machineModel = "machineModel"
        static let machineFinish = "machineFinish"
        static let screenContent = "screenContent"
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

    /// Where 养护 mode stops charging, in percent.
    @Published var chargeLimit: Int {
        didSet { defaults.set(chargeLimit, forKey: Key.chargeLimit) }
    }

    /// Whether modules use their accent colours; off is the all-white look.
    /// Island or notch layout; nil follows the hardware.
    @Published var islandStyle: IslandStyle? {
        didSet { defaults.set(islandStyle?.rawValue, forKey: Key.islandStyle) }
    }

    /// Which 3D model to show; nil follows the hardware. Not offered in settings (the model always
    /// matches the Mac); `defaults write dev.yan.islandmenu machineModel macbook-air-15` previews another.
    @Published var machineModel: MachineModel? {
        didSet { defaults.set(machineModel?.rawValue, forKey: Key.machineModel) }
    }

    @Published var machineFinish: MachineFinish {
        didSet { defaults.set(machineFinish.rawValue, forKey: Key.machineFinish) }
    }

    @Published var screenContent: ScreenContent {
        didSet { defaults.set(screenContent.rawValue, forKey: Key.screenContent) }
    }

    @Published var colorful: Bool {
        didSet { defaults.set(colorful, forKey: Key.colorful) }
    }

    /// Display brightness (0...1) held while keep-awake is on.
    @Published var awakeBrightness: Double {
        didSet { defaults.set(awakeBrightness, forKey: Key.awakeBrightness) }
    }

    @Published private(set) var alertRules: [AlertKind: AlertRule] {
        didSet {
            let stored = Dictionary(uniqueKeysWithValues: alertRules.map { ($0.key.rawValue, $0.value) })
            defaults.set(try? JSONEncoder().encode(stored), forKey: Key.alertRules)
        }
    }

    func alertRule(_ kind: AlertKind) -> AlertRule {
        alertRules[kind] ?? Self.defaultAlertRules[kind] ?? AlertRule(enabled: false, limit: 100)
    }

    func setAlertRule(_ rule: AlertRule, for kind: AlertKind) {
        alertRules[kind] = rule
    }

    /// Stored so the chosen logo effect comes back after a relaunch.
    var logoMode: LogoMode {
        get { defaults.string(forKey: Key.logoMode).flatMap(LogoMode.init) ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: Key.logoMode) }
    }

    private init() {
        fanMode = defaults.string(forKey: Key.fanMode).flatMap(FanMode.init) ?? .auto
        let stored = defaults.data(forKey: Key.fanCurve).flatMap { try? JSONDecoder().decode([FanCurvePoint].self, from: $0) }
        fanCurve = stored.flatMap { $0.count >= 2 ? $0 : nil } ?? Self.defaultCurve
        showPublicIP = defaults.object(forKey: Key.showPublicIP) as? Bool ?? true
        chargeLimit = defaults.object(forKey: Key.chargeLimit) as? Int ?? Self.defaultChargeLimit
        awakeBrightness = defaults.object(forKey: Key.awakeBrightness) as? Double ?? Self.defaultAwakeBrightness
        colorful = defaults.object(forKey: Key.colorful) as? Bool ?? true
        islandStyle = defaults.string(forKey: Key.islandStyle).flatMap(IslandStyle.init)
        machineModel = defaults.string(forKey: Key.machineModel).flatMap(MachineModel.init)
        machineFinish = defaults.string(forKey: Key.machineFinish).flatMap(MachineFinish.init) ?? .standard
        screenContent = defaults.string(forKey: Key.screenContent).flatMap(ScreenContent.init) ?? .off
        let storedRules = defaults.data(forKey: Key.alertRules).flatMap { try? JSONDecoder().decode([String: AlertRule].self, from: $0) } ?? [:]
        alertRules = Self.defaultAlertRules.merging(storedRules.compactMap { key, rule in AlertKind(rawValue: key).map { ($0, rule) } }) { _, stored in stored }
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
