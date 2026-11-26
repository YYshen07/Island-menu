import Darwin

struct MemorySampler {
    private let total = Sysctl.value("hw.memsize", as: UInt64.self) ?? 0

    func sample() -> MemorySnapshot {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var snapshot = MemorySnapshot(total: total)
        guard result == KERN_SUCCESS else { return snapshot }
        let page = UInt64(vm_kernel_page_size)
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        snapshot.app = (internalPages > purgeable ? internalPages - purgeable : 0) * page
        snapshot.wired = UInt64(stats.wire_count) * page
        snapshot.compressed = UInt64(stats.compressor_page_count) * page
        snapshot.swapUsed = Sysctl.value("vm.swapusage", as: xsw_usage.self)?.xsu_used ?? 0
        snapshot.pressure = Int(Sysctl.value("kern.memorystatus_vm_pressure_level", as: Int32.self) ?? 1)
        return snapshot
    }
}
