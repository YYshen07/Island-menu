import IslandShared

/// What this Mac physically has, read once. Sections for missing hardware are left out of the card.
/// `--no-fans` and `--no-logo` on the command line imitate a fanless Mac or one without a logo light.
@MainActor
enum Hardware {
    static let hasFans: Bool = !CommandLine.arguments.contains("--no-fans") && (SMC()?.value("FNum") ?? 0) > 0
    static let hasLogoLight: Bool = !CommandLine.arguments.contains("--no-logo") && LogoLight.shared.isSupported
}
