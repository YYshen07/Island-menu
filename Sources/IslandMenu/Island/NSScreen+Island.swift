import AppKit

extension NSScreen {
    /// The built-in display, the only one with a Dynamic Island.
    static var builtIn: NSScreen? {
        screens.first { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }
    }
}

/// Where the Dynamic Island sits. macOS has no API for the island's live size (it widens for
/// live activities), so the pill is derived from the camera cutout plus margins measured on Mac17,13.
struct IslandGeometry {
    /// Gap between the top of the screen and the top of the pill.
    static let topInset: CGFloat = 7
    /// Gap between the bottom of the pill and the bottom of the safe area.
    private static let bottomInset: CGFloat = 1
    /// How far the pill extends past the camera cutout on each side.
    private static let sideExtension: CGFloat = 30
    private static let fallbackSize = CGSize(width: 120, height: 32)

    /// Pill size in points.
    let size: CGSize
    /// Horizontal centre of the pill in screen coordinates.
    let midX: CGFloat
    /// Top edge of the screen in screen coordinates.
    let screenTop: CGFloat

    init(screen: NSScreen) {
        midX = screen.frame.midX
        screenTop = screen.frame.maxY
        guard let left = screen.auxiliaryTopLeftArea?.width, let right = screen.auxiliaryTopRightArea?.width, screen.safeAreaInsets.top > 0 else {
            size = Self.fallbackSize
            return
        }
        let cutout = screen.frame.width - left - right
        size = CGSize(width: cutout + Self.sideExtension * 2, height: screen.safeAreaInsets.top - Self.topInset - Self.bottomInset)
    }

    /// The pill itself in screen coordinates.
    var pillFrame: NSRect {
        NSRect(x: midX - size.width / 2, y: screenTop - Self.topInset - size.height, width: size.width, height: size.height)
    }

    /// Window frame hugging the pill, including the strip above it.
    var closedFrame: NSRect {
        NSRect(x: midX - size.width / 2, y: screenTop - Self.topInset - size.height, width: size.width, height: size.height + Self.topInset)
    }
}
