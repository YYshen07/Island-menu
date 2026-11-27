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
    case standard, spaceBlack, spaceGray, silver, midnight, starlight, skyBlue, custom

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
        case .custom: "自定义"
        }
    }

    /// Base colour of the anodised shell, nil to leave the model's own. These are matched by eye
    /// to the scene's lighting, which is bright; they are not Apple's published values.
    @MainActor var color: NSColor? {
        switch self {
        case .standard: nil
        case .spaceBlack: NSColor(srgbRed: 0.022, green: 0.022, blue: 0.024, alpha: 1)
        case .spaceGray: NSColor(srgbRed: 0.10, green: 0.10, blue: 0.105, alpha: 1)
        case .silver: NSColor(srgbRed: 0.36, green: 0.37, blue: 0.38, alpha: 1)
        case .midnight: NSColor(srgbRed: 0.03, green: 0.04, blue: 0.06, alpha: 1)
        case .starlight: NSColor(srgbRed: 0.38, green: 0.355, blue: 0.30, alpha: 1)
        case .skyBlue: NSColor(srgbRed: 0.28, green: 0.37, blue: 0.47, alpha: 1)
        case .custom: Preferences.shared.customFinish
        }
    }
}
