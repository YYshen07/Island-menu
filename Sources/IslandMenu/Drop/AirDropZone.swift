import AppKit
import SwiftUI

/// A drop target that appears under the island while files are being dragged anywhere on screen,
/// and hands whatever is dropped on it to AirDrop.
@MainActor
final class AirDropZone {
    private static let size = CGSize(width: 300, height: 96)
    private static let gapBelowIsland: CGFloat = 10
    private static let hideDelay: TimeInterval = 0.25

    private var panel: NSPanel?
    private let model = DropZoneModel()
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var monitors: [Any] = []

    func install() {
        // File drags are detected through the drag pasteboard: it changes when a drag session starts.
        let dragged = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated { self?.dragMoved() }
        }
        let released = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.dragEnded() }
        }
        monitors = [dragged, released].compactMap { $0 }
    }

    private func dragMoved() {
        guard panel?.isVisible != true else { return }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragChangeCount else { return }
        dragChangeCount = pasteboard.changeCount
        guard pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return }
        show()
    }

    private func dragEnded() {
        // The drop itself is delivered after mouse-up, so give it a moment before hiding.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDelay) { [weak self] in
            self?.panel?.orderOut(nil)
            self?.model.isTargeted = false
        }
    }

    private func show() {
        guard let screen = NSScreen.builtIn ?? NSScreen.main else { return }
        let island = IslandGeometry(screen: screen)
        let panel = self.panel ?? makePanel()
        let origin = NSPoint(x: island.midX - Self.size.width / 2, y: island.pillFrame.minY - Self.gapBelowIsland - Self.size.height)
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: true)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let target = DropTargetView(model: model)
        let host = NSHostingView(rootView: DropZoneView(model: model))
        host.frame = target.bounds
        host.autoresizingMask = [.width, .height]
        target.addSubview(host)
        panel.contentView = target
        self.panel = panel
        return panel
    }
}

@MainActor
final class DropZoneModel: ObservableObject {
    @Published var isTargeted = false
}

/// AppKit drop destination; SwiftUI's `onDrop` does not fire reliably in a non-activating panel.
private final class DropTargetView: NSView {
    private let model: DropZoneModel

    init(model: DropZoneModel) {
        self.model = model
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !fileURLs(sender).isEmpty else { return [] }
        model.isTargeted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        model.isTargeted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        model.isTargeted = false
        let urls = fileURLs(sender)
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else { return false }
        service.perform(withItems: urls)
        return true
    }
}

private struct DropZoneView: View {
    @ObservedObject var model: DropZoneModel

    var body: some View {
        HStack(spacing: 12) {
            if let icon = NSSharingService(named: .sendViaAirDrop)?.image {
                Image(nsImage: icon).resizable().frame(width: 36, height: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("隔空投送").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.primary)
                Text(model.isTargeted ? "松手发送" : "拖到这里").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.black))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(model.isTargeted ? 0.5 : 0.12), lineWidth: model.isTargeted ? 2 : 1))
        .scaleEffect(model.isTargeted ? 1.03 : 1)
        .animation(Theme.spring, value: model.isTargeted)
        .padding(4)
    }
}
