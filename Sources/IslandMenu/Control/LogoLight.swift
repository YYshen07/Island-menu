import AppKit
import ObjectiveC

enum LogoMode: String, CaseIterable {
    case auto, breathe, audio
}

/// The lid logo LED, driven through corebrightnessd's light-emitter keys on CoreBrightness's private
/// `BrightnessSystemClient` (no root). The key names and the fade technique come from
/// Ark0N/LogoLight and XZCendence/logoctl (both MIT): instead of writing a brightness every frame,
/// set a fade duration and flip the logical display state, and the hardware performs the fade.
@MainActor
final class LogoLight: ObservableObject {
    static let shared = LogoLight()

    private enum Key {
        static let fadeDuration = "LEPWMFactorFadeDuration"
        static let logicalState = "DisplayLogicalState"
        static let state = "LEPWMState"
    }
    private static let blank = 1
    private static let unblank = 2
    /// One full breath, in seconds.
    private static let breathPeriod = 4.5
    private static let attack = 0.04
    private static let decay = 0.32
    private static let beatOn = 0.55
    private static let beatOff = 0.3
    private static let restAfterSilence = 2.0
    private static let followInterval = 0.04

    private typealias SetFunction = @convention(c) (AnyObject, Selector, AnyObject, NSString) -> Bool
    private typealias SetKeyboardFunction = @convention(c) (AnyObject, Selector, AnyObject, NSString, UInt64) -> Bool

    private let client: NSObject?
    private let keyboardIDs: [UInt64]
    private var timer: Timer?
    private var headingLit = true
    private var silentSince: Date?
    private var displayAsleep = false
    private let audio = SystemAudioMeter()

    @Published private(set) var mode = LogoMode.auto
    @Published private(set) var lastError: String?

    private init() {
        client = Self.makeClient()
        keyboardIDs = Self.keyboardBacklightIDs()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.displayChanged(asleep: true) }
        }
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.displayChanged(asleep: false) }
        }
    }

    private static func makeClient() -> NSObject? {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let type = NSClassFromString("BrightnessSystemClient") as? NSObject.Type,
              type.instancesRespond(to: NSSelectorFromString("setProperty:forKey:")) else { return nil }
        return type.init()
    }

    private static func keyboardBacklightIDs() -> [UInt64] {
        let selector = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type, type.instancesRespond(to: selector) else { return [] }
        return (type.init().perform(selector)?.takeRetainedValue() as? [NSNumber])?.map(\.uint64Value) ?? []
    }

    /// Whether this Mac has a controllable logo light.
    var isSupported: Bool {
        guard let client else { return false }
        return client.perform(NSSelectorFromString("copyPropertyForKey:"), with: Key.state)?.takeRetainedValue() is [String: Any]
    }

    private func set(_ value: NSNumber, _ key: String) {
        guard let client else { return }
        let selector = NSSelectorFromString("setProperty:forKey:")
        let function = unsafeBitCast(client.method(for: selector), to: SetFunction.self)
        _ = function(client, selector, value, key as NSString)
    }

    /// The keyboard backlight follows the same logical state, so it is told separately that the
    /// display is still on whenever the logo is sent dark.
    private func keepKeyboardLit() {
        let selector = NSSelectorFromString("setProperty:withKey:keyboardID:")
        guard let client, client.responds(to: selector) else { return }
        let function = unsafeBitCast(client.method(for: selector), to: SetKeyboardFunction.self)
        for id in keyboardIDs {
            _ = function(client, selector, NSNumber(value: Self.unblank), Key.logicalState as NSString, id)
        }
    }

    private func fade(toLit lit: Bool, over seconds: Double) {
        set(NSNumber(value: seconds), Key.fadeDuration)
        set(NSNumber(value: lit ? Self.unblank : Self.blank), Key.logicalState)
        headingLit = lit
        if !lit { keepKeyboardLit() }
    }

    // MARK: - Modes

    func setMode(_ newMode: LogoMode) {
        guard isSupported else { return }
        stopEffect()
        lastError = nil
        mode = newMode
        guard !displayAsleep else { return }
        switch newMode {
        case .auto:
            break
        case .breathe:
            startBreathing()
        case .audio:
            startFollowingAudio()
        }
    }

    /// Hands the logo back to macOS: lit, with the system's own fade timing.
    private func stopEffect() {
        timer?.invalidate()
        timer = nil
        audio.stop()
        guard client != nil, !displayAsleep else { return }
        set(NSNumber(value: 0), Key.fadeDuration)
        set(NSNumber(value: Self.unblank), Key.logicalState)
        keepKeyboardLit()
        headingLit = true
    }

    private func startBreathing() {
        let half = Self.breathPeriod / 2
        let breathe: () -> Void = { [weak self] in
            guard let self else { return }
            self.fade(toLit: !self.headingLit, over: half)
        }
        breathe()
        schedule(every: half, breathe)
    }

    private func startFollowingAudio() {
        do {
            try audio.start()
        } catch {
            lastError = "无法读取系统声音。请在「系统设置 → 隐私与安全性 → 屏幕与系统录音」里允许 Island Menu 录制系统音频。"
            mode = .auto
            return
        }
        schedule(every: Self.followInterval) { [weak self] in self?.followAudio() }
    }

    /// Writes only when the direction changes: up fast on a beat, down slowly after it.
    private func followAudio() {
        let loudness = audio.loudness
        if loudness > Self.beatOn {
            silentSince = nil
            if !headingLit { fade(toLit: true, over: Self.attack) }
        } else if loudness < Self.beatOff {
            if loudness == 0, silentSince == nil { silentSince = Date() }
            let resting = silentSince.map { Date().timeIntervalSince($0) > Self.restAfterSilence } ?? false
            if resting {
                // Nothing playing: rest lit rather than dark.
                if !headingLit { fade(toLit: true, over: 1) }
            } else if headingLit {
                fade(toLit: false, over: Self.decay)
            }
        }
    }

    private func schedule(every interval: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// corebrightnessd drives the logo itself across display sleep, so effects pause until wake.
    private func displayChanged(asleep: Bool) {
        if asleep {
            stopEffect()
            displayAsleep = true
        } else {
            displayAsleep = false
            setMode(mode)
        }
    }

    /// Call before the app exits so the logo is not left mid-fade.
    func restore() {
        stopEffect()
    }
}
