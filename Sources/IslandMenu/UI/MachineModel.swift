import AppKit

/// The 3D models that ship in the app bundle, one per body.
enum MachineModel: String, CaseIterable, Identifiable {
    case pro14 = "macbook-pro-14"
    case pro14Notch = "macbook-pro-14-notch"
    case pro16Notch = "macbook-pro-16-notch"
    case air13 = "macbook-air-13"
    case air15 = "macbook-air-15"

    /// Screen diagonals, in inches, that separate the 13/14-inch bodies from the 15/16-inch ones.
    private static let largeAirDiagonal = 14.5
    private static let largeProDiagonal = 15.5
    private static let millimetresPerInch = 25.4

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pro14: "Pro 14 寸 · PROLED"
        case .pro14Notch: "Pro 14 寸 · 刘海"
        case .pro16Notch: "Pro 16 寸 · 刘海"
        case .air13: "Air 13 寸"
        case .air15: "Air 15 寸"
        }
    }

    /// Only the PROLED body has a lit logo; the others have a polished one.
    var hasLogoLight: Bool { self == .pro14 }

    /// Width divided by depth of the closed lid, from Apple's published dimensions.
    var lidAspect: CGFloat {
        switch self {
        case .pro14: 310.8 / 216.3
        case .pro14Notch: 312.6 / 221.2
        case .pro16Notch: 355.7 / 248.1
        case .air13: 304.1 / 215.0
        case .air15: 340.4 / 237.6
        }
    }

    var url: URL? { Bundle.main.url(forResource: rawValue, withExtension: "usdz") }

    /// The user's choice in settings, otherwise the body this Mac most likely is.
    @MainActor static var current: MachineModel { Preferences.shared.machineModel ?? detected }

    /// Told apart by what the hardware has rather than by a table of model identifiers, so new
    /// revisions of the same body need no update: a logo light, fans, and the panel's diagonal.
    @MainActor static let detected: MachineModel = {
        if Hardware.hasLogoLight { return .pro14 }
        let size = NSScreen.builtIn.flatMap { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID }.map(CGDisplayScreenSize) ?? .zero
        let diagonal = Double(hypot(size.width, size.height)) / millimetresPerInch
        if Hardware.hasFans { return diagonal >= largeProDiagonal ? .pro16Notch : .pro14Notch }
        return diagonal >= largeAirDiagonal ? .air15 : .air13
    }()
}

/// Body colour of the model. `standard` keeps the colour the model file was built with.
enum MachineFinish: String, CaseIterable, Identifiable {
    case standard, spaceBlack, spaceGray, silver, midnight, starlight, skyBlue, blush, citrus, indigo

    /// Apple's finishes grouped by the line they are sold on. Any of them can go on any body.
    static let series: [(title: String, finishes: [MachineFinish])] = [
        ("Pro 系列", [.spaceBlack, .spaceGray, .silver]),
        ("Air 系列", [.midnight, .starlight, .skyBlue, .silver]),
        ("Neo 系列", [.blush, .citrus, .indigo, .silver]),
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "机型默认"
        case .spaceBlack: "深空黑"
        case .spaceGray: "深空灰"
        case .silver: "银色"
        case .midnight: "午夜色"
        case .starlight: "星光色"
        case .skyBlue: "天蓝色"
        case .blush: "Blush"
        case .citrus: "Citrus"
        case .indigo: "Indigo"
        }
    }

    /// Base colour of the anodised shell, nil to leave the model's own. These are matched by eye
    /// to the scene's lighting, which is bright; they are not Apple's published values.
    var color: NSColor? {
        switch self {
        case .standard: nil
        case .spaceBlack: NSColor(srgbRed: 0.022, green: 0.022, blue: 0.024, alpha: 1)
        case .spaceGray: NSColor(srgbRed: 0.10, green: 0.10, blue: 0.105, alpha: 1)
        case .silver: NSColor(srgbRed: 0.36, green: 0.37, blue: 0.38, alpha: 1)
        case .midnight: NSColor(srgbRed: 0.03, green: 0.04, blue: 0.06, alpha: 1)
        case .starlight: NSColor(srgbRed: 0.38, green: 0.355, blue: 0.30, alpha: 1)
        case .skyBlue: NSColor(srgbRed: 0.28, green: 0.37, blue: 0.47, alpha: 1)
        case .blush: NSColor(srgbRed: 0.50, green: 0.33, blue: 0.34, alpha: 1)
        case .citrus: NSColor(srgbRed: 0.50, green: 0.47, blue: 0.20, alpha: 1)
        case .indigo: NSColor(srgbRed: 0.12, green: 0.16, blue: 0.30, alpha: 1)
        }
    }

    /// How the finish looks under the scene's lights, for the swatch in settings.
    var swatch: NSColor {
        guard let base = color?.usingColorSpace(.sRGB) else { return .darkGray }
        func lift(_ value: CGFloat) -> CGFloat { min(pow(value, 0.55) * 1.1, 1) }
        return NSColor(srgbRed: lift(base.redComponent), green: lift(base.greenComponent), blue: lift(base.blueComponent), alpha: 1)
    }
}

/// What the model's screen shows when its lid is opened.
enum ScreenContent: String, CaseIterable, Identifiable {
    case off, wallpaper, custom

    private static let maxPixelWidth: CGFloat = 1280
    /// Corner radius of the panel as a fraction of its width.
    private static let cornerFraction: CGFloat = 0.022

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "熄屏"
        case .wallpaper: "当前壁纸"
        case .custom: "自定义图片"
        }
    }

    /// Where an uploaded picture is kept, so it survives the original being moved or deleted.
    static var customImageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("IslandMenu/screen-image")
    }

    @MainActor private var source: CGImage? {
        switch self {
        case .off: nil
        case .wallpaper: Wallpaper.currentImage()
        case .custom: NSImage(contentsOf: Self.customImageURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
    }

    /// The picture scaled to fill a panel of the given aspect ratio (width / height), with the
    /// panel's rounded corners cut off; nil when there is nothing to show.
    @MainActor func image(aspect: CGFloat) -> CGImage? {
        guard let source, source.width > 0, source.height > 0, aspect > 0 else { return nil }
        let width = min(CGFloat(source.width), Self.maxPixelWidth).rounded()
        let size = CGSize(width: width, height: (width / aspect).rounded())
        guard size.width >= 1, size.height >= 1, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let radius = size.width * Self.cornerFraction
        context.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        let scale = max(size.width / CGFloat(source.width), size.height / CGFloat(source.height))
        let drawn = CGSize(width: CGFloat(source.width) * scale, height: CGFloat(source.height) * scale)
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2, width: drawn.width, height: drawn.height))
        return context.makeImage()
    }
}
