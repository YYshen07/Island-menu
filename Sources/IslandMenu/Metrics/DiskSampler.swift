import Foundation
import IOKit

/// Boot volume capacity plus whole-machine read/write throughput.
final class DiskSampler {
    /// Asking for "available for important usage" makes the system work out purgeable space, which
    /// takes tens of milliseconds; capacity moves slowly, so it is refreshed this often at most.
    private static let capacityLifetime: TimeInterval = 30
    private var previous: (read: UInt64, written: UInt64, time: TimeInterval)?
    private var capacity: (total: UInt64, used: UInt64, at: TimeInterval)?

    /// Total and used bytes of the boot volume, cached for `capacityLifetime`.
    func volume() -> (total: UInt64, used: UInt64) {
        let now = ProcessInfo.processInfo.systemUptime
        if let capacity, now - capacity.at < Self.capacityLifetime { return (capacity.total, capacity.used) }
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacityForImportantUsage else { return (0, 0) }
        let fresh = (total: UInt64(total), used: UInt64(max(0, Int64(total) - free)), at: now)
        capacity = fresh
        return (fresh.total, fresh.used)
    }

    func sample() -> DiskSnapshot {
        var snapshot = DiskSnapshot()
        (snapshot.total, snapshot.used) = volume()
        let (read, written) = ioBytes()
        let now = ProcessInfo.processInfo.systemUptime
        if let previous, now > previous.time, read >= previous.read, written >= previous.written {
            snapshot.readRate = Double(read - previous.read) / (now - previous.time)
            snapshot.writeRate = Double(written - previous.written) / (now - previous.time)
        }
        previous = (read, written, now)
        return snapshot
    }

    private func ioBytes() -> (UInt64, UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(iterator) }
        var totals: (UInt64, UInt64) = (0, 0)
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] else { continue }
            totals.0 += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            totals.1 += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return totals
    }
}
