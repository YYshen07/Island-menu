import Combine
import Foundation
import IslandShared
import ServiceManagement

/// Runs the chosen fan mode through the privileged helper. In 自动 nothing is sent and macOS is in
/// charge; in 最大 and 策略 a slow loop keeps telling the helper what speed to hold, and the helper
/// falls back to automatic by itself if that loop ever stops.
@MainActor
final class FanController: ObservableObject {
    static let shared = FanController()

    enum HelperState: Equatable {
        case notInstalled, needsApproval, ready, unavailable(String)
    }

    private static let loopInterval: TimeInterval = 3
    /// Above this the fans go to full speed whatever the curve says.
    private static let emergencyTemperature = 95.0
    /// Speed changes smaller than this are not worth a write.
    private static let deadband = 150.0

    @Published private(set) var helperState = HelperState.notInstalled
    @Published private(set) var targetLevel: Double?

    private let service = SMAppService.daemon(plistName: FanHelper.daemonPlist)
    private let queue = DispatchQueue(label: "dev.yan.islandmenu.fans", qos: .utility)
    private let sensors = FanSensors()
    private var connection: NSXPCConnection?
    private var timer: DispatchSourceTimer?
    private var lastSent: [Double] = []
    private var lastSentAt: TimeInterval = -.infinity
    private var modeObserver: AnyCancellable?

    private init() {
        refreshHelperState()
        modeObserver = Preferences.shared.$fanMode.dropFirst().sink { [weak self] mode in
            self?.modeChanged(mode)
        }
    }

    /// Call once at launch to resume the stored mode.
    func start() {
        modeChanged(Preferences.shared.fanMode)
    }

    // MARK: - Helper lifecycle

    func refreshHelperState() {
        switch service.status {
        case .enabled: helperState = .ready
        case .requiresApproval: helperState = .needsApproval
        case .notRegistered, .notFound: helperState = .notInstalled
        @unknown default: helperState = .notInstalled
        }
    }

    /// Registers the daemon. macOS then asks the user to allow it under Login Items.
    func installHelper() {
        do {
            try service.register()
            refreshHelperState()
        } catch {
            refreshHelperState()
            // Registration reports an error while approval is still pending; that state is expected.
            if helperState != .needsApproval { helperState = .unavailable(error.localizedDescription) }
        }
        if helperState == .needsApproval { SMAppService.openSystemSettingsLoginItems() }
        if helperState == .ready { start() }
    }

    private func helper() -> FanHelperProtocol? {
        if connection == nil {
            let fresh = NSXPCConnection(machServiceName: FanHelper.machService, options: .privileged)
            fresh.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
            fresh.invalidationHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            fresh.resume()
            connection = fresh
        }
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in
                self?.connection = nil
                self?.helperState = .unavailable(error.localizedDescription)
            }
        } as? FanHelperProtocol
    }

    // MARK: - Control loop

    private func modeChanged(_ mode: FanMode) {
        timer?.cancel()
        timer = nil
        lastSent = []
        refreshHelperState()
        guard helperState == .ready else { return }
        guard mode != .auto else {
            targetLevel = nil
            helper()?.releaseFans { _ in }
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.loopInterval, leeway: .milliseconds(300))
        // At full speed the temperature decides nothing, so it is not read.
        let needsTemperature = mode == .curve
        timer.setEventHandler { [sensors, weak self] in
            let reading = sensors.read(temperature: needsTemperature)
            Task { @MainActor in self?.step(reading) }
        }
        timer.resume()
        self.timer = timer
    }

    private func step(_ reading: FanSensors.Reading) {
        let preferences = Preferences.shared
        guard preferences.fanMode != .auto, !reading.fans.isEmpty else { return }
        var level = preferences.fanMode == .max ? 1 : preferences.curveLevel(at: reading.temperature ?? Self.emergencyTemperature)
        // (A missing reading in curve mode is treated as an emergency; in max mode none is taken.)
        if let temperature = reading.temperature, temperature >= Self.emergencyTemperature { level = 1 }
        targetLevel = level
        // A curve that asks for nothing means "let macOS decide", not "hold the fans stopped".
        guard level > 0 else {
            if !lastSent.isEmpty { helper()?.releaseFans { _ in } }
            lastSent = []
            return
        }
        let speeds = reading.fans.map { $0.minimum + ($0.maximum - $0.minimum) * level }
        let changed = lastSent.count != speeds.count || zip(lastSent, speeds).contains { abs($0 - $1) > Self.deadband }
        let now = ProcessInfo.processInfo.systemUptime
        let renewalDue = now - lastSentAt > FanHelper.watchdogInterval / 3
        guard changed || renewalDue else { return }
        lastSent = speeds
        lastSentAt = now
        helper()?.setFanSpeeds(speeds) { [weak self] succeeded in
            guard !succeeded else { return }
            Task { @MainActor in self?.helperState = .unavailable("风扇拒绝了转速指令，请点击重试或检查系统设置里的登录项。") }
        }
    }

    /// Hands the fans back before the app exits. The helper's watchdog covers a crash.
    func shutdown() {
        timer?.cancel()
        timer = nil
        guard helperState == .ready, let proxy = helper() else { return }
        let done = DispatchSemaphore(value: 0)
        proxy.releaseFans { _ in done.signal() }
        _ = done.wait(timeout: .now() + 0.5)
    }
}

/// Temperature and fan range for the control loop, read off the main thread.
private final class FanSensors: @unchecked Sendable {
    struct Reading {
        var temperature: Double?
        var fans: [FanSnapshot]
    }

    private let thermal = ThermalSampler()
    private let fans = FanSampler()

    func read(temperature: Bool) -> Reading {
        Reading(temperature: temperature ? thermal.dieMax() : nil, fans: fans.sample())
    }
}
