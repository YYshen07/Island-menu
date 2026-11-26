import AppKit
import SwiftUI

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Shared open/closed state plus the pill size the card morphs from.
@MainActor
final class IslandState: ObservableObject {
    @Published var isOpen = false
    @Published var islandSize = CGSize(width: 120, height: 32)
    /// Height of the open card, reported by the view so clicks can be hit-tested against it.
    var cardHeight: CGFloat = 0
}

/// Owns the borderless panel that sits on the Dynamic Island. Closed, the panel hugs the pill and
/// draws nothing; open, it grows to the card frame and the SwiftUI content morphs out of the pill.
@MainActor
final class IslandController {
    static let cardWidth: CGFloat = 440
    private static let closeDuration: TimeInterval = 0.45
    /// Room on each side of the card for its drop shadow.
    private static let shadowMargin: CGFloat = 60
    private static let bottomMargin: CGFloat = 12
    private static let escapeKey: UInt16 = 53

    private let engine: MetricsEngine
    private let state = IslandState()
    private var panel: IslandPanel?
    private var island: IslandGeometry?
    private var pendingShrink: DispatchWorkItem?

    init(engine: MetricsEngine) {
        self.engine = engine
    }

    func install() {
        let panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        // Setting this explicitly stops AppKit from passing clicks through transparent pixels,
        // which is all the closed panel consists of.
        panel.ignoresMouseEvents = false
        let root = IslandRootView().environmentObject(state).environmentObject(engine)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel
        layout()
        panel.orderFrontRegardless()
        installMonitors()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    func setOpen(_ open: Bool) {
        guard open != state.isOpen, let panel else { return }
        pendingShrink?.cancel()
        if open {
            engine.setLive(true)
            layout(open: true)
            panel.makeKey()
            state.isOpen = true
        } else {
            state.isOpen = false
            let shrink = DispatchWorkItem { [weak self] in
                self?.layout(open: false)
                self?.engine.setLive(false)
            }
            pendingShrink = shrink
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeDuration, execute: shrink)
        }
    }

    private func layout(open: Bool? = nil) {
        guard let panel, let screen = NSScreen.builtIn ?? NSScreen.main else { return }
        let island = IslandGeometry(screen: screen)
        self.island = island
        state.islandSize = island.size
        guard open ?? state.isOpen else { return panel.setFrame(island.closedFrame, display: true) }
        let width = Self.cardWidth + Self.shadowMargin * 2
        let height = screen.frame.height - Self.bottomMargin
        panel.setFrame(NSRect(x: island.midX - width / 2, y: island.screenTop - height, width: width, height: height), display: true)
    }

    func toggle() {
        setOpen(!state.isOpen)
    }

    /// Clicks are handled at the event level rather than by SwiftUI gestures, so they work whether
    /// the click reaches this panel (local) or some other process's window (global).
    private func installMonitors() {
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.handleClick(at: NSEvent.mouseLocation) }
        }
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let isEscape = event.type == .keyDown && event.keyCode == Self.escapeKey
            let isClick = event.type != .keyDown
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                if isClick { return self.handleClick(at: NSEvent.mouseLocation) }
                guard isEscape, self.state.isOpen else { return false }
                self.setOpen(false)
                return true
            }
            return consumed ? nil : event
        }
    }

    /// Returns true when the click was consumed (it toggled or dismissed the card).
    private func handleClick(at point: NSPoint) -> Bool {
        guard let island else { return false }
        if island.pillFrame.contains(point) {
            toggle()
            return true
        }
        guard state.isOpen else { return false }
        let card = NSRect(x: island.midX - Self.cardWidth / 2, y: island.pillFrame.maxY - state.cardHeight, width: Self.cardWidth, height: state.cardHeight)
        guard !card.contains(point) else { return false }
        setOpen(false)
        return true
    }
}
