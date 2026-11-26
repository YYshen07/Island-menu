import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    // `NSApplication.delegate` is weak, so keep the delegate alive for the run loop's lifetime.
    withExtendedLifetime(delegate) { app.run() }
}
