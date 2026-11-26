import Darwin

/// Top processes by CPU time delta. Processes owned by other users are not readable without
/// root and are skipped.
final class ProcessSampler {
    private var previous: (cpu: [pid_t: UInt64], time: UInt64)?
    func sample() -> [ProcessRow] {
        var pids = [pid_t](repeating: 0, count: Int(proc_listallpids(nil, 0)) + 32)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride)))
        let now = mach_absolute_time()
        var cpu: [pid_t: UInt64] = [:]
        var rows: [ProcessRow] = []
        // CPU time and wall time are both in mach units, so their ratio needs no conversion.
        let elapsed = previous.map { Double(now - $0.time) } ?? 0
        for pid in pids.prefix(max(count, 0)) where pid > 0 {
            var usage = rusage_info_v2()
            let status = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            guard status == 0 else { continue }
            let ticks = usage.ri_user_time + usage.ri_system_time
            cpu[pid] = ticks
            guard elapsed > 0, let before = previous?.cpu[pid], ticks >= before else { continue }
            rows.append(ProcessRow(id: pid, name: "", cpu: Double(ticks - before) / elapsed, memory: usage.ri_phys_footprint))
        }
        previous = (cpu, now)
        return rows
    }

    static func name(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "pid \(pid)" }
        return String(cString: buffer)
    }

    /// Keeps the `limit` heaviest rows by each key and resolves names only for those.
    static func top(_ rows: [ProcessRow], limit: Int) -> [ProcessRow] {
        let byCPU = rows.sorted { $0.cpu > $1.cpu }.prefix(limit)
        let byMemory = rows.sorted { $0.memory > $1.memory }.prefix(limit)
        var seen = Set<pid_t>()
        return (byCPU + byMemory).filter { seen.insert($0.id).inserted }.map {
            ProcessRow(id: $0.id, name: name(of: $0.id), cpu: $0.cpu, memory: $0.memory)
        }
    }
}
