import Foundation
import IOKit

/// Boot volume capacity plus whole-machine read/write throughput.
final class DiskSampler {
    private var previous: (read: UInt64, written: UInt64, time: TimeInterval)?

    func sample() -> DiskSnapshot {
        var snapshot = DiskSnapshot()
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
           let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacityForImportantUsage {
            snapshot.total = UInt64(total)
            snapshot.used = UInt64(max(0, Int64(total) - free))
        }
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
