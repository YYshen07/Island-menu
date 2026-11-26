import SwiftUI

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Solid black around the island, fading into dark glass further down.
struct CardBackground: View {
    private static let solidUntil: CGFloat = 150
    private static let glassFrom: CGFloat = 420

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            ZStack {
                VisualEffect()
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: min(Self.solidUntil / height, 1)),
                    .init(color: .black.opacity(0.5), location: min(Self.glassFrom / height, 1)),
                    .init(color: .black.opacity(0.42), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The whole panel: invisible over the system island when closed, a card morphing out of the
/// pill when open.
struct IslandRootView: View {
    @EnvironmentObject private var state: IslandState
    @State private var contentHeight: CGFloat = 600
    private static let bottomGap: CGFloat = 24
    private static let headroom: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let open = state.isOpen
            let island = state.islandSize
            let topInset = open ? IslandGeometry.cardTopInset : IslandGeometry.topInset
            let header = island.height + IslandGeometry.topInset - IslandGeometry.cardTopInset + Self.headroom
            let limit = proxy.size.height - IslandGeometry.cardTopInset - Self.bottomGap
            let cardHeight = min(contentHeight + header, limit)
            let _ = (state.cardHeight = cardHeight)
            let size = open ? CGSize(width: IslandController.cardWidth, height: cardHeight) : island
            let shape = RoundedRectangle(cornerRadius: open ? Theme.cardRadius : island.height / 2, style: .continuous)
            ScrollView(.vertical, showsIndicators: false) {
                CardView()
                    .frame(width: IslandController.cardWidth)
                    .background(GeometryReader { Color.clear.preference(key: ContentHeightKey.self, value: $0.size.height) })
            }
            .padding(.top, header)
            .overlay(alignment: .topLeading) {
                KeepAwakeButton()
                    .padding(.top, (header - HeaderButton.side) / 2)
                    .padding(.leading, 14)
            }
            .overlay(alignment: .topTrailing) {
                Button { state.showSettings() } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: HeaderButton.glyph)).foregroundStyle(Theme.secondary)
                        .frame(width: HeaderButton.side, height: HeaderButton.side).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, (header - HeaderButton.side) / 2)
                .padding(.trailing, 14)
            }
            .opacity(open ? 1 : 0)
            .allowsHitTesting(open)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(CardBackground())
            .clipShape(shape)
            .overlay(shape.stroke(.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 18)
            .animation(Theme.spring, value: open)
            // Closed, the system island must show through, so the surface only exists while open.
            .opacity(open ? 1 : 0)
            .animation(open ? .easeOut(duration: 0.08) : .easeIn(duration: 0.12).delay(0.3), value: open)
            .padding(.top, topInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(Theme.spring, value: open)
            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        }
        .preferredColorScheme(.dark)
    }
}

/// Size of the two buttons that flank the island in the card's header.
private enum HeaderButton {
    static let side: CGFloat = 34
    static let glyph: CGFloat = 18
}

/// Apple mark in the card's top-left corner; toggles keep-awake and turns rainbow while it is on.
private struct KeepAwakeButton: View {
    @ObservedObject private var keepAwake = KeepAwake.shared
    private static let rainbow = AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red], center: .center)

    var body: some View {
        Button { keepAwake.toggle() } label: {
            Image(systemName: "apple.logo")
                .font(.system(size: HeaderButton.glyph + 2, weight: .semibold))
                // Plain grey until keep-awake is on; the colour is the "on" state.
                .foregroundStyle(keepAwake.isActive ? AnyShapeStyle(Self.rainbow) : AnyShapeStyle(Theme.secondary))
                .shadow(color: .white.opacity(keepAwake.isActive ? 0.6 : 0), radius: 6)
                .frame(width: HeaderButton.side, height: HeaderButton.side)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(keepAwake.isActive ? "防休眠已开启" : "开启防休眠")
        .animation(Theme.spring, value: keepAwake.isActive)
    }
}
