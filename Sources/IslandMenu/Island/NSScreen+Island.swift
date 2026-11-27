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

/// How the top of the built-in display is cut out.
enum IslandStyle: String, CaseIterable {
    /// A floating pill below the top edge (PROLED MacBook Pro).
    case island
    /// A notch joined to the top bezel (2021-2025 MacBook Pro, M2 and later MacBook Air).
    case notch

    /// The user's override (settings, or `--notch` / `--island` on the command line), otherwise the
    /// hardware's. The public screen APIs report a pill and a notch the same way, so the logo
    /// light, which only the PROLED machines have, tells them apart.
    @MainActor static var current: IslandStyle {
        if CommandLine.arguments.contains("--notch") { return .notch }
        if CommandLine.arguments.contains("--island") { return .island }
        return Preferences.shared.islandStyle ?? detected
    }

    @MainActor static let detected: IslandStyle = Hardware.hasLogoLight ? .island : .notch
}

/// Where the island or notch sits. macOS has no API for the island's live size (it widens for
/// live activities), so the pill is derived from the camera cutout plus margins measured on Mac17,13.
/// A notch is exactly the cutout the screen reports.
struct IslandGeometry {
    /// Gap between the top of the screen and the top of the pill.
    private static let pillTopInset: CGFloat = 7
    /// Gap between the top of the screen and the open card. The system island is drawn above every
    /// window, so the card starts a little higher and keeps a black margin all round the pill.
    private static let pillCardTopInset: CGFloat = 2
    /// Gap between the bottom of the pill and the bottom of the safe area.
    private static let bottomInset: CGFloat = 1
    /// How far the pill extends past the camera cutout on each side.
    private static let sideExtension: CGFloat = 30
    private static let fallbackPill = CGSize(width: 120, height: 32)
    /// Notch of the 14-inch MacBook Pro at its default scaling; used on a display without one.
    private static let fallbackNotch = CGSize(width: 185, height: 32)
    /// A reported cutout narrower than this is a camera hole, not a notch.
    private static let narrowestNotch: CGFloat = 120

    let style: IslandStyle
    /// Pill or notch size in points.
    let size: CGSize
    /// Horizontal centre in screen coordinates.
    let midX: CGFloat
    /// Top edge of the screen in screen coordinates.
    let screenTop: CGFloat
    /// True when the display has no notch of its own and the app has to draw one (a notch layout
    /// forced on a pill machine or an external display).
    let isSimulated: Bool

    /// Gap between the top of the screen and the closed shape; a notch touches the bezel.
    var topInset: CGFloat { style == .notch ? 0 : Self.pillTopInset }
    /// Gap between the top of the screen and the open card.
    var cardTopInset: CGFloat { style == .notch ? 0 : Self.pillCardTopInset }

    init(screen: NSScreen, style: IslandStyle) {
        self.style = style
        midX = screen.frame.midX
        screenTop = screen.frame.maxY
        let safeTop = screen.safeAreaInsets.top
        var cutout: CGFloat?
        if let left = screen.auxiliaryTopLeftArea?.width, let right = screen.auxiliaryTopRightArea?.width, safeTop > 0 {
            cutout = screen.frame.width - left - right
        }
        switch style {
        case .island:
            isSimulated = false
            size = cutout.map { CGSize(width: $0 + Self.sideExtension * 2, height: safeTop - Self.pillTopInset - Self.bottomInset) } ?? Self.fallbackPill
        case .notch:
            if let cutout, cutout >= Self.narrowestNotch {
                isSimulated = false
                size = CGSize(width: cutout, height: safeTop)
            } else {
                isSimulated = true
                size = Self.fallbackNotch
            }
        }
    }

    /// The pill or notch itself in screen coordinates.
    var pillFrame: NSRect {
        NSRect(x: midX - size.width / 2, y: screenTop - topInset - size.height, width: size.width, height: size.height)
    }

    /// Window frame hugging the closed shape, including the strip above it.
    var closedFrame: NSRect {
        NSRect(x: midX - size.width / 2, y: screenTop - topInset - size.height, width: size.width, height: size.height + topInset)
    }
}
