import Foundation
import IOKit

struct BatterySampler {
    func sample() -> BatterySnapshot {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return BatterySnapshot() }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = unmanaged?.takeRetainedValue() as? [String: Any] else { return BatterySnapshot() }
        func int(_ key: String) -> Int? { (props[key] as? NSNumber)?.intValue }
        var snapshot = BatterySnapshot(present: true)
        snapshot.percent = int("CurrentCapacity") ?? 0
        snapshot.cycles = int("CycleCount") ?? 0
        snapshot.charging = (props["IsCharging"] as? Bool) ?? false
        snapshot.external = (props["ExternalConnected"] as? Bool) ?? false
        if let raw = int("AppleRawMaxCapacity"), let design = int("DesignCapacity"), design > 0 {
            snapshot.health = min(100, Int((Double(raw) / Double(design) * 100).rounded()))
        }
        if snapshot.external, let watts = ((props["AdapterDetails"] as? [String: Any])?["Watts"] as? NSNumber)?.intValue, watts > 0 {
            snapshot.adapterWatts = watts
        }
        // Signed values arrive as unsigned 64-bit numbers; `int64Value` restores the sign.
        if let milliamps = (props["Amperage"] as? NSNumber)?.int64Value, let millivolts = int("Voltage") {
            snapshot.batteryPower = Double(milliamps) * Double(millivolts) / 1_000_000
        }
        if let telemetry = props["PowerTelemetryData"] as? [String: Any] {
            func watts(_ key: String) -> Double? { (telemetry[key] as? NSNumber).map { Double($0.int64Value) / 1000 } }
            snapshot.systemPower = watts("SystemLoad")
            if snapshot.external { snapshot.inputPower = watts("SystemPowerIn") }
        }
        return snapshot
    }
}
