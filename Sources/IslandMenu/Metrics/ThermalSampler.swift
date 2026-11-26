import Foundation
import IOKit.hid

// Private IOHID event-system entry points, the same ones `powermetrics` and other monitors use
// to read Apple silicon temperature sensors without root.
@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> IOHIDEventSystemClient
@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: IOHIDEventSystemClient, _ matching: CFDictionary) -> Int32
@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: IOHIDServiceClient, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: CFTypeRef, _ field: Int32) -> Double

final class ThermalSampler {
    private static let temperatureEvent: Int64 = 15
    private static let validRange = 0.0...130.0
    private let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
    private lazy var sensors: [(name: String, service: IOHIDServiceClient)] = {
        _ = IOHIDEventSystemClientSetMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        let services = (IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient]) ?? []
        return services.compactMap { service in
            guard let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String else { return nil }
            return (name, service)
        }
    }()

    func sample() -> ThermalSnapshot {
        var groups: [String: [Double]] = [:]
        for sensor in sensors {
            guard let key = Self.group(for: sensor.name),
                  let event = IOHIDServiceClientCopyEvent(sensor.service, Self.temperatureEvent, 0, 0) else { continue }
            let value = IOHIDEventGetFloatValue(event.takeRetainedValue(), Int32(Self.temperatureEvent << 16))
            if Self.validRange.contains(value) { groups[key, default: []].append(value) }
        }
        func mean(_ key: String) -> Double? {
            guard let values = groups[key], !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }
        return ThermalSnapshot(dieMax: groups["die"]?.max(), dieMean: mean("die"), ssd: mean("ssd"), battery: mean("battery"))
    }

    private static func group(for name: String) -> String? {
        if name.hasPrefix("PMU tdie") { return "die" }
        if name.hasPrefix("NAND") { return "ssd" }
        if name.contains("battery") { return "battery" }
        return nil
    }
}
