import AppKit

MainActor.assumeIsolated {
    // Developer aid: `IslandMenu --render-model <usdz> <png>` writes a still of the model and exits.
    if let flag = CommandLine.arguments.firstIndex(of: "--render-model"), CommandLine.arguments.count > flag + 2 {
        exit(ModelPreview.render(model: CommandLine.arguments[flag + 1], to: CommandLine.arguments[flag + 2]) ? 0 : 1)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    // `NSApplication.delegate` is weak, so keep the delegate alive for the run loop's lifetime.
    withExtendedLifetime(delegate) { app.run() }
}
