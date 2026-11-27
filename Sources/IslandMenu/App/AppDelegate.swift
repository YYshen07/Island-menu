import AppKit
import IslandShared

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = MetricsEngine()
    private var island: IslandController?
    private var statusItem: NSStatusItem?
    private lazy var settings = SettingsWindowController(engine: engine)
    private var signalSources: [DispatchSourceSignal] = []
    private let airDrop = AirDropZone()
    /// An `AlertMonitor` on macOS 27.3 and later, where Live Activities exist.
    private var alerts: AnyObject?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Developer aid: `IslandMenu --add-sticker <picture>` makes a sticker the way settings does, then quits.
        if let flag = CommandLine.arguments.firstIndex(of: "--add-sticker"), CommandLine.arguments.count > flag + 1 {
            let data = FileManager.default.contents(atPath: CommandLine.arguments[flag + 1])
            Task {
                let made = await { () -> Bool in
                    guard let data, let image = try? await StickerMaker.make(from: data) else { return false }
                    return (try? StickerStore.shared.add(image)) != nil
                }()
                exit(made ? 0 : 1)
            }
            return
        }
        let controller = IslandController(engine: engine)
        controller.install()
        controller.state.showSettings = { [weak self] in self?.openSettings() }
        island = controller
        engine.startBackgroundTracking()
        installStatusItem()
        installToggleSignal()
        airDrop.install()
        LogoLight.shared.setMode(Preferences.shared.logoMode)
        FanController.shared.start()
        if #available(macOS 27.3, *) {
            let monitor = AlertMonitor()
            monitor.start()
            alerts = monitor
        }
        if CommandLine.arguments.contains("--open") { controller.setOpen(true) }
        if CommandLine.arguments.contains("--settings") { openSettings() }
        if CommandLine.arguments.contains("--install-helper") { FanController.shared.installHelper() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.flush()
        LogoLight.shared.restore()
        KeepAwake.shared.stop()
        FanController.shared.shutdown()
        if #available(macOS 27.3, *) { (alerts as? AlertMonitor)?.stop() }
    }

    /// The alert's link and tap target open `islandmenu://panel`.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == IslandLink.scheme {
            // `islandmenu://flip` and `islandmenu://lid` drive the model from scripts (demo recordings).
            switch url.host {
            case "flip", "lid": NotificationCenter.default.post(name: .machineCommand, object: url.host)
            case "top", "bottom": NotificationCenter.default.post(name: .scrollCommand, object: url.host)
            default: island?.setOpen(true)
            }
        }
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
    /// SIGTERM and SIGINT go through the normal quit path, so the logo light is handed back to macOS.
    private func installToggleSignal() {
        let handlers: [(Int32, @MainActor () -> Void)] = [
            (SIGUSR1, { [weak self] in self?.island?.toggle() }),
            (SIGTERM, { NSApp.terminate(nil) }),
            (SIGINT, { NSApp.terminate(nil) }),
        ]
        for (number, handler) in handlers {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { handler() } }
            source.resume()
            signalSources.append(source)
        }
    }

    @objc private func toggleCard() {
        island?.toggle()
    }

    @objc private func openSettings() {
        island?.setOpen(false)
        settings.show()
    }

    /// The Dynamic Island pill with a level meter cut into it, drawn as a template image so it
    /// follows the menu bar's colour.
    private static func pillIcon() -> NSImage {
        let size = NSSize(width: 28, height: 13)
        let barHeights: [CGFloat] = [3.5, 6, 8.5, 5]
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            // Punch the camera dot and the meter bars out of the pill.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: NSRect(x: 5, y: rect.midY - 1.75, width: 3.5, height: 3.5)).fill()
            for (index, height) in barHeights.enumerated() {
                let bar = NSRect(x: 12.5 + CGFloat(index) * 3.2, y: rect.midY - height / 2, width: 1.9, height: height)
                NSBezierPath(roundedRect: bar, xRadius: 0.95, yRadius: 0.95).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Island Menu"
        return image
    }
}

extension Notification.Name {
    /// Posted with "flip" or "lid" as the object to move the 3D model without a click.
    /// Posted with "top" or "bottom" as the object to scroll the card without a scroll event.
    static let scrollCommand = Notification.Name("dev.yan.islandmenu.scrollCommand")
    static let machineCommand = Notification.Name("dev.yan.islandmenu.machineCommand")
}
