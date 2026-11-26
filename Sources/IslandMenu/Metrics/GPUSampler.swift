import Foundation
import IOKit

/// GPU utilisation and memory from the accelerator's `PerformanceStatistics`.
struct GPUSampler {
    private let totalMemory = Sysctl.value("hw.memsize", as: UInt64.self) ?? 0

    func sample() -> GPUSnapshot {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return GPUSnapshot() }
        defer { IOObjectRelease(iterator) }
        var snapshot = GPUSnapshot()
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] else { continue }
            snapshot.usage = max(snapshot.usage, ((stats["Device Utilization %"] as? NSNumber)?.doubleValue ?? 0) / 100)
            snapshot.memoryUsed = max(snapshot.memoryUsed, (stats["In use system memory"] as? NSNumber)?.uint64Value ?? 0)
        }
        // Apple silicon has unified memory, so the share is of total RAM.
        snapshot.memoryFraction = totalMemory > 0 ? Double(snapshot.memoryUsed) / Double(totalMemory) : 0
        return snapshot
    }
}
