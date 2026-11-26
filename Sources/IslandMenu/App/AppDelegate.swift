import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = MetricsEngine()
    private var island: IslandController?
    private var statusItem: NSStatusItem?
    private var toggleSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = IslandController(engine: engine)
        controller.install()
        island = controller
        engine.startBackgroundTracking()
        installStatusItem()
        installToggleSignal()
        if CommandLine.arguments.contains("--open") { controller.setOpen(true) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.flush()
    }

    /// Menu bar icon: a second way to open the card, and the only way to quit.
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "Island Menu")
        let menu = NSMenu()
        menu.addItem(withTitle: "打开 / 收起卡片", action: #selector(toggleCard), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Island Menu", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    /// `kill -USR1 <pid>` toggles the card, so it can be driven from scripts without synthetic clicks.
    private func installToggleSignal() {
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.island?.toggle() }
        }
        source.resume()
        toggleSignal = source
    }

    @objc private func toggleCard() {
        island?.toggle()
    }
}
