import AppKit
import ApplicationServices

/// Swallows clicks on the Dynamic Island before the system island sees them, so only this app's
/// card opens. Needs the Accessibility permission; without it the tap cannot be created and the
/// controller's ordinary event monitors remain the only click path.
@MainActor
final class IslandClickTap {
    /// How far past the pill the intercepted strip reaches on each side. The system island grows
    /// sideways for live activities and has no API for its width.
    private static let sideMargin: CGFloat = 22

    private var tap: CFMachPort?
    private var swallowingRelease = false
    private let onClick: () -> Void
    /// Island strip in global display coordinates (origin top-left).
    var hitRect = CGRect.zero

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
    }

    var isActive: Bool { tap != nil }

    /// Asks for the permission if needed (the system shows its own prompt once) and starts the tap.
    @discardableResult
    func start(prompting: Bool) -> Bool {
        guard tap == nil else { return true }
        let options = ["AXTrustedCheckOptionPrompt": prompting] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return false }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue | 1 << CGEventType.leftMouseUp.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: islandTapCallback, userInfo: context) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        return true
    }

    func update(island: IslandGeometry, screenFrame: CGRect) {
        // Screen coordinates have the origin bottom-left of the primary display; event taps use top-left.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screenFrame.height
        let pill = island.pillFrame.insetBy(dx: -Self.sideMargin, dy: 0)
        hitRect = CGRect(x: pill.minX, y: primaryHeight - island.screenTop, width: pill.width, height: island.screenTop - pill.minY)
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .leftMouseDown where hitRect.contains(event.location):
            swallowingRelease = true
            DispatchQueue.main.async { [weak self] in self?.onClick() }
            return true
        case .leftMouseUp where swallowingRelease:
            swallowingRelease = false
            return true
        default:
            return false
        }
    }
}

private func islandTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, context: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let context else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<IslandClickTap>.fromOpaque(context).takeUnretainedValue()
    // The run-loop source is on the main run loop, so this is the main thread.
    let swallowed = MainActor.assumeIsolated { tap.handle(type: type, event: event) }
    return swallowed ? nil : Unmanaged.passUnretained(event)
}
