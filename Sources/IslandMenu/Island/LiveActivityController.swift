import ActivityKit
import AppKit
import IslandShared

/// Keeps Island Menu's Live Activity in the system Dynamic Island and feeds it a few headline
/// numbers. A light sampler runs for this even while the card is closed.
@MainActor
final class LiveActivityController {
    private static let updateInterval: TimeInterval = 5
    /// The system ends an activity after eight hours; restart a little before that.
    private static let lifetime: TimeInterval = 7.5 * 3600
    private static let foregroundAttempts = 8
    private static let foregroundPoll = Duration.milliseconds(250)

    private let queue = DispatchQueue(label: "dev.yan.islandmenu.glance", qos: .utility)
    private let sampler = GlanceSampler()
    private var activity: Activity<MonitorActivityAttributes>?
    private var startedAt = Date.distantPast
    private var timer: DispatchSourceTimer?
    private var lastState: MonitorActivityAttributes.ContentState?

    /// Whether the system island is showing our activity, in which case it owns clicks on the island.
    private(set) var isRunning = false

    func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Activities from a previous run would otherwise pile up next to the new one.
        let stale = Activity<MonitorActivityAttributes>.activities
        Task {
            for old in stale { await old.end(nil, dismissalPolicy: .immediate) }
            await MainActor.run { self.request() }
        }
    }

    /// The system only accepts a request from the frontmost app, so this app steps forward for a
    /// moment, asks, and hands focus back to whatever was in front.
    private func request() {
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            for _ in 0..<Self.foregroundAttempts {
                try? await Task.sleep(for: Self.foregroundPoll)
                guard NSApp.isActive else { continue }
                if self.requestNow() { break }
            }
            if let previous, previous != NSRunningApplication.current { previous.activate() }
        }
    }

    private func requestNow() -> Bool {
        let initial = MonitorActivityAttributes.ContentState(cpu: 0, temperature: nil, memory: 0, fanSpeed: 0)
        do {
            activity = try Activity.request(attributes: MonitorActivityAttributes(), content: ActivityContent(state: initial, staleDate: nil), pushType: nil)
            startedAt = Date()
            isRunning = true
            startUpdating()
            return true
        } catch {
            isRunning = false
            NSLog("Island Menu: Live Activity could not start: %@", String(describing: error))
            return false
        }
    }

    private func startUpdating() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: Self.updateInterval, leeway: .seconds(1))
        timer.setEventHandler { [sampler, weak self] in
            let state = sampler.sample()
            Task { @MainActor in self?.push(state) }
        }
        timer.resume()
        self.timer = timer
    }

    private func push(_ state: MonitorActivityAttributes.ContentState) {
        guard let activity else { return }
        if Date().timeIntervalSince(startedAt) > Self.lifetime {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
                await MainActor.run { self.request() }
            }
            return
        }
        guard state != lastState else { return }
        lastState = state
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// Ends the activity synchronously enough for app exit.
    func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false
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

/// The few readings the island shows, sampled off the main thread.
private final class GlanceSampler: @unchecked Sendable {
    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let thermal = ThermalSampler()
    private let fans = FanSampler()

    func sample() -> MonitorActivityAttributes.ContentState {
        let load = cpu.sample().total
        let usage = memory.sample()
        return MonitorActivityAttributes.ContentState(
            cpu: Int((load * 100).rounded()),
            temperature: thermal.sample().dieMax.map { Int($0.rounded()) },
            memory: usage.total > 0 ? Int((Double(usage.used) / Double(usage.total) * 100).rounded()) : 0,
            fanSpeed: Int((fans.sample().map(\.rpm).max() ?? 0).rounded())
        )
    }
}
