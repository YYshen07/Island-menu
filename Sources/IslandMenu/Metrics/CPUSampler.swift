import Darwin

/// Per-core load from `host_processor_info` tick deltas.
final class CPUSampler {
    private var previous: [[UInt32]] = []
    private let superCount = max(0, Int(Sysctl.value("hw.perflevel0.logicalcpu", as: Int32.self) ?? 0))

    func sample() -> CPUSnapshot {
        let ticks = readTicks()
        defer { previous = ticks }
        var snapshot = CPUSnapshot(superCount: superCount)
        guard ticks.count == previous.count, !ticks.isEmpty else { return snapshot }
        var cores: [Double] = []
        var sums = (user: 0.0, system: 0.0, all: 0.0)
        for (now, before) in zip(ticks, previous) {
            let delta = zip(now, before).map { Double($0 &- $1) }
            let all = delta.reduce(0, +)
            let user = delta[Int(CPU_STATE_USER)] + delta[Int(CPU_STATE_NICE)]
            let system = delta[Int(CPU_STATE_SYSTEM)]
            cores.append(all > 0 ? (user + system) / all : 0)
            sums = (sums.user + user, sums.system + system, sums.all + all)
        }
        // The kernel lists the top-tier ("Super") cluster last; show it first.
        snapshot.cores = Array(cores.suffix(superCount) + cores.dropLast(superCount))
        snapshot.user = sums.all > 0 ? sums.user / sums.all : 0
        snapshot.system = sums.all > 0 ? sums.system / sums.all : 0
        var load = [Double](repeating: 0, count: 1)
        if getloadavg(&load, 1) == 1 { snapshot.load = load[0] }
        return snapshot
    }

    private func readTicks() -> [[UInt32]] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS, let info else { return [] }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        let states = Int(CPU_STATE_MAX)
        return (0..<Int(count)).map { core in
            (0..<states).map { UInt32(bitPattern: info[core * states + $0]) }
        }
    }
}
