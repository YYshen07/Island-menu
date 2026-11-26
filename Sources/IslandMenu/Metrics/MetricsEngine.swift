import Foundation

/// Samples on a background queue and publishes to the UI. The fast loop only runs while the
/// card is open; closed, the only work left is the once-a-minute activity tick.
@MainActor
final class MetricsEngine: ObservableObject {
    static let historyLength = 60
    /// Weeks shown in the activity heatmap.
    static let historyWeeks = 26

    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var gpuHistory = Ring(count: historyLength)
    @Published private(set) var downHistory = Ring(count: historyLength)
    @Published private(set) var upHistory = Ring(count: historyLength)
    @Published private(set) var days: [String: DayRecord] = [:]

    private let queue = DispatchQueue(label: "dev.yan.islandmenu.metrics", qos: .utility)
    private let samplers = Samplers()
    private let publicIP = PublicIPResolver()
    private var fastTimer: DispatchSourceTimer?
    private var slowTimer: DispatchSourceTimer?

    func startBackgroundTracking() {
        days = samplers.activity.days
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + ActivityStore.tickInterval, repeating: ActivityStore.tickInterval, leeway: .seconds(10))
        timer.setEventHandler { [samplers, weak self] in
            samplers.activity.tick(diskUsed: samplers.disk.sample().used)
            let days = samplers.activity.days
            Task { @MainActor in self?.days = days }
        }
        timer.resume()
        slowTimer = timer
    }

    /// Writes pending history to disk; call before the app exits.
    func flush() {
        queue.sync { samplers.activity.save() }
    }

    func setLive(_ live: Bool) {
        guard live != (fastTimer != nil) else { return }
        guard live else {
            fastTimer?.cancel()
            fastTimer = nil
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // Two quick samples first so rate-based metrics have a baseline, then once a second.
        timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(100))
        timer.setEventHandler { [samplers, weak self] in
            let snapshot = samplers.sample()
            Task { @MainActor in self?.publish(snapshot) }
        }
        timer.resume()
        fastTimer = timer
        Task { [weak self, publicIP] in
            let ip = await publicIP.resolve()
            self?.resolvedIP = ip
        }
    }

    private var resolvedIP: String?

    private func publish(_ fresh: Snapshot) {
        guard fastTimer != nil else { return }
        var fresh = fresh
        fresh.network.publicIP = resolvedIP
        snapshot = fresh
        gpuHistory.push(fresh.gpu.usage)
        downHistory.push(fresh.network.down)
        upHistory.push(fresh.network.up)
    }
}

/// All samplers, touched only from the metrics queue.
final class Samplers: @unchecked Sendable {
    let cpu = CPUSampler()
    let memory = MemorySampler()
    let disk = DiskSampler()
    let network = NetworkSampler()
    let battery = BatterySampler()
    let gpu = GPUSampler()
    let thermal = ThermalSampler()
    let processes = ProcessSampler()
    let activity = ActivityStore()
    private var tick = 0
    private var lastProcesses: [ProcessRow] = []
    private let bootTime: Date = {
        guard let boot = Sysctl.value("kern.boottime", as: timeval.self) else { return Date() }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec))
    }()

    func sample() -> Snapshot {
        tick += 1
        var snapshot = Snapshot(bootTime: bootTime)
        snapshot.cpu = cpu.sample()
        snapshot.memory = memory.sample()
        snapshot.disk = disk.sample()
        snapshot.network = network.sample()
        snapshot.battery = battery.sample()
        snapshot.gpu = gpu.sample()
        snapshot.thermal = thermal.sample()
        snapshot.gpu.temperature = snapshot.thermal.dieMean
        // The process walk is the most expensive sample, so it runs at half rate.
        if tick % 2 == 1 { lastProcesses = ProcessSampler.top(processes.sample(), limit: 4) }
        snapshot.processes = lastProcesses
        return snapshot
    }
}
