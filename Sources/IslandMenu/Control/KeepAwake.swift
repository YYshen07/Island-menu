import AppKit
import IOKit.pwr_mgt

/// Keeps the Mac awake with the built-in display dimmed to a chosen level, like Caffeine: a power
/// assertion stops idle sleep, and the brightness in use before is put back when it is turned off.
@MainActor
final class KeepAwake: ObservableObject {
    static let shared = KeepAwake()

    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32

    @Published private(set) var isActive = false
    private var assertion: IOPMAssertionID = 0
    private var previousBrightness: Float?
    private let getBrightness: GetBrightness?
    private let setBrightness: SetBrightness?

    private init() {
        // DisplayServices is private; it is the same call the brightness keys end up in.
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW) else {
            getBrightness = nil
            setBrightness = nil
            return
        }
        getBrightness = dlsym(handle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetBrightness.self) }
        setBrightness = dlsym(handle, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetBrightness.self) }
    }

    func toggle() {
        isActive ? stop() : start()
    }

    func start() {
        guard !isActive else { return }
        let reason = "Island Menu 防休眠" as CFString
        guard IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertion) == kIOReturnSuccess else { return }
        isActive = true
        dim(to: Preferences.shared.awakeBrightness)
    }

    func stop() {
        guard isActive else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
        isActive = false
        if let previousBrightness, let display = builtInDisplay() { _ = setBrightness?(display, previousBrightness) }
        previousBrightness = nil
    }

    /// Applies a new dim level straight away if keep-awake is on (used by the settings slider).
    func brightnessPreferenceChanged() {
        if isActive { dim(to: Preferences.shared.awakeBrightness) }
    }

    private func dim(to level: Double) {
        guard let display = builtInDisplay(), let getBrightness, let setBrightness else { return }
        if previousBrightness == nil {
            var current: Float = 0
            if getBrightness(display, &current) == 0 { previousBrightness = current }
        }
        _ = setBrightness(display, Float(min(max(level, 0), 1)))
    }

    private func builtInDisplay() -> CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }
}
