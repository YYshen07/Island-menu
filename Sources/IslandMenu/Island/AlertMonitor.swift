import ActivityKit
import AppKit
import IslandShared
import os

/// Watches a few readings in the background and raises a Live Activity in the Dynamic Island while
/// one of them is over the limit set in settings. Nothing is shown the rest of the time.
/// Live Activities reach the Mac in macOS 27.3; earlier systems run without alerts.
@available(macOS 27.3, *)
@MainActor
final class AlertMonitor {
    private static let interval: TimeInterval = 5
    /// A reading has to stay over (or back under) its limit for this many samples before the alert
    /// changes, so a brief spike does not raise it and a brief dip does not clear it.
    private static let sustain = 3
    private static let foregroundAttempts = 8
    private static let foregroundPoll = Duration.milliseconds(250)
    /// The system ends an activity after eight hours; a long-running alert is re-raised before that.
    private static let lifetime: TimeInterval = 7.5 * 3600
    private static let logger = Logger(subsystem: "dev.yan.islandmenu", category: "alerts")

    private let queue = DispatchQueue(label: "dev.yan.islandmenu.alerts", qos: .utility)
    private let sampler = AlertSampler()
    private var timer: DispatchSourceTimer?
    private var streak: [AlertKind: Int] = [:]
    private var active: Set<AlertKind> = []
    private var activity: Activity<MonitorActivityAttributes>?
    private var startedAt = Date.distantPast
    private var shown: MonitorActivityAttributes.ContentState?
    private var isRequesting = false

    func start() {
        // An alert left over from a previous run has nothing updating it.
        let stale = Activity<MonitorActivityAttributes>.activities
        Task { for old in stale { await old.end(nil, dismissalPolicy: .immediate) } }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.interval, repeating: Self.interval, leeway: .seconds(1))
        timer.setEventHandler { [sampler, weak self] in
            let readings = sampler.sample()
            Task { @MainActor in self?.evaluate(readings) }
        }
        timer.resume()
        self.timer = timer
    }

    private func evaluate(_ readings: [AlertKind: Double]) {
        let preferences = Preferences.shared
        for kind in AlertKind.allCases {
            let rule = preferences.alertRule(kind)
            guard rule.enabled, let value = readings[kind] else {
                active.remove(kind)
                streak[kind] = 0
                continue
            }
            let over = isOver(kind, value: value, limit: rule.limit)
            let changing = over != active.contains(kind)
            streak[kind] = changing ? (streak[kind] ?? 0) + 1 : 0
            guard changing, (streak[kind] ?? 0) >= kind.sustain(Self.sustain) else { continue }
            streak[kind] = 0
            if over { active.insert(kind) } else { active.remove(kind) }
        }
        present(readings)
    }

    /// Raising needs the reading to reach the limit; clearing needs it to come back past the limit
    /// by a margin, not just touch it.
    private func isOver(_ kind: AlertKind, value: Double, limit: Double) -> Bool {
        let margin = active.contains(kind) ? kind.recoveryMargin : 0
        return kind.triggersBelow ? value <= limit + margin : value >= limit - margin
    }

    private func present(_ readings: [AlertKind: Double]) {
        // `AlertKind.allCases` is in priority order: the first active one is the one shown.
        guard let kind = AlertKind.allCases.first(where: active.contains), let value = readings[kind], value.isFinite else {
            end()
            return
        }
        let limit = Int(Preferences.shared.alertRule(kind).limit.rounded())
        let state = MonitorActivityAttributes.ContentState(kind: kind, value: Int(value.rounded()), limit: limit, others: active.count - 1)
        guard let activity else {
            request(state)
            return
        }
        if Date().timeIntervalSince(startedAt) > Self.lifetime {
            end()
            return
        }
        guard state != shown else { return }
        shown = state
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// The system only accepts a request from the frontmost app, so this app steps forward for a
    /// moment, asks, and hands focus back to whatever was in front.
    private func request(_ state: MonitorActivityAttributes.ContentState) {
        guard !isRequesting, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        isRequesting = true
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            for _ in 0..<Self.foregroundAttempts {
                try? await Task.sleep(for: Self.foregroundPoll)
                guard NSApp.isActive else { continue }
                do {
                    activity = try Activity.request(attributes: MonitorActivityAttributes(), content: ActivityContent(state: state, staleDate: nil), pushType: nil)
                    startedAt = Date()
                    shown = state
                    break
                } catch {
                    Self.logger.error("alert could not be shown: \(String(describing: error), privacy: .public)")
                }
            }
            if let previous, previous != NSRunningApplication.current { previous.activate() }
            isRequesting = false
        }
    }

    private func end() {
        guard let activity else { return }
        self.activity = nil
        shown = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Takes any alert down before the app exits.
    func stop() {
        timer?.cancel()
        timer = nil
        guard let activity else { return }
        self.activity = nil
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await activity.end(nil, dismissalPolicy: .immediate)
            done.signal()
        }
        _ = done.wait(timeout: .now() + 1)
    }
}

private extension AlertKind {
    /// How far below the limit a reading must fall before the alert clears.
    var recoveryMargin: Double {
        switch self {
        case .cpu, .gpu: 10
        case .battery: 3
        case .temperature: 5
        case .storage: 1
        }
    }

    /// Storage and battery do not spike, so they alert on the first sample.
    func sustain(_ standard: Int) -> Int { self == .storage || self == .battery ? 1 : standard }
}

/// The readings alerts are judged on, sampled off the main thread.
private final class AlertSampler: @unchecked Sendable {
    private let cpu = CPUSampler()
    private let gpu = GPUSampler()
    private let thermal = ThermalSampler()
    private let disk = DiskSampler()
    private let battery = BatterySampler()

    /// Storage and battery move slowly and are comparatively costly to read, so they are refreshed
    /// once in this many samples (about a minute) and reused in between.
    private static let slowEvery = 12
    private var tick = 0
    private var slow: [AlertKind: Double] = [:]

    func sample() -> [AlertKind: Double] {
        var readings: [AlertKind: Double] = [.cpu: cpu.sample().total * 100, .gpu: gpu.sample().usage * 100]
        if let temperature = thermal.dieMax() { readings[.temperature] = temperature }
        if tick % Self.slowEvery == 0 { slow = slowReadings() }
        tick += 1
        return readings.merging(slow) { fast, _ in fast }
    }

    private func slowReadings() -> [AlertKind: Double] {
        var readings: [AlertKind: Double] = [:]
        let volume = disk.volume()
        if volume.total > 0 { readings[.storage] = Double(volume.used) / Double(volume.total) * 100 }
        // Only a battery that is actually draining can be low; on the charger there is nothing to do.
        let power = battery.sample()
        if power.present, !power.external { readings[.battery] = Double(power.percent) }
        return readings
    }
}
