import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = MetricsEngine()
    private var island: IslandController?
    private var statusItem: NSStatusItem?
    private lazy var settings = SettingsWindowController(engine: engine)
    private var toggleSignal: DispatchSourceSignal?
    private let airDrop = AirDropZone()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = IslandController(engine: engine)
        controller.install()
        controller.state.showSettings = { [weak self] in self?.openSettings() }
        island = controller
        engine.startBackgroundTracking()
        installStatusItem()
        installToggleSignal()
        airDrop.install()
        if CommandLine.arguments.contains("--open") { controller.setOpen(true) }
        if CommandLine.arguments.contains("--settings") { openSettings() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.flush()
    }

    /// Menu bar icon: a second way to open the card, and the only way to quit.
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.pillIcon()
        let menu = NSMenu()
        menu.addItem(withTitle: "打开 / 收起卡片", action: #selector(toggleCard), keyEquivalent: "").target = self
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",").target = self
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

    @objc private func openSettings() {
        island?.setOpen(false)
        settings.show()
    }

    /// A small Dynamic Island pill, drawn as a template image so it follows the menu bar's colour.
    private static func pillIcon() -> NSImage {
        let size = NSSize(width: 26, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Island Menu"
        return image
    }
}
