import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = MetricsEngine()
    private var island: IslandController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = IslandController(engine: engine)
        controller.install()
        island = controller
        engine.startBackgroundTracking()
        installStatusItem()
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

    @objc private func toggleCard() {
        island?.toggle()
    }
}
