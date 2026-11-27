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

private enum NotchMetrics {
    /// Bottom corner radius of the hardware notch.
    static let closedRadius: CGFloat = 9
    /// Radius of the concave corners that join the shape to the bezel.
    static let closedEar: CGFloat = 6
    static let openEar: CGFloat = 14
}

/// Outline of the card. For the island it is a rounded rectangle floating below the bezel. For a
/// notch it hangs from the top edge: square at the top, flared into the bezel by two concave
/// "ears" that sit outside the rect, and rounded at the bottom.
struct CardShape: Shape {
    var notch: Bool
    var radius: CGFloat
    var ear: CGFloat
    /// The outline without the top edge, which lies on the bezel and must not be stroked.
    var open = false

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(radius, ear) }
        set { radius = newValue.first; ear = newValue.second }
    }

    var outline: CardShape { CardShape(notch: notch, radius: radius, ear: ear, open: notch) }

    func path(in rect: CGRect) -> Path {
        guard notch else { return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect) }
        let radius = max(0, min(radius, rect.height - ear, rect.width / 2))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - ear, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + ear), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - radius), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + ear))
        path.addQuadCurve(to: CGPoint(x: rect.maxX + ear, y: rect.minY), control: CGPoint(x: rect.maxX, y: rect.minY))
        if !open { path.closeSubpath() }
        return path
    }
}

private enum ScrollAnchor { case card }

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
            let notch = state.style == .notch
            let topInset = open ? state.cardTopInset : state.topInset
            let header = island.height + state.topInset - state.cardTopInset + Self.headroom
            let limit = proxy.size.height - state.cardTopInset - Self.bottomGap
            let cardHeight = min(contentHeight + header, limit)
            let _ = (state.cardHeight = cardHeight)
            let size = open ? CGSize(width: IslandController.cardWidth, height: cardHeight) : island
            let shape = CardShape(notch: notch, radius: open ? Theme.cardRadius : (notch ? NotchMetrics.closedRadius : island.height / 2),
                                  ear: notch ? (open ? NotchMetrics.openEar : NotchMetrics.closedEar) : 0)
            // A notch is black hardware, so the black shape can stay drawn while closed and the card
            // grows straight out of it. The system island has to show through instead.
            let surfaceVisible = open || (notch && state.drawsNotch)
            cardScrollView
                .padding(.top, header)
                .overlay(alignment: .topLeading) {
                    KeepAwakeButton()
                        .padding(.top, (header - HeaderButton.side) / 2)
                        .padding(.leading, 14)
                }
                .overlay(alignment: .topTrailing) { settingsButton(header: header) }
                .opacity(open ? 1 : 0)
                .allowsHitTesting(open)
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(CardBackground().padding(.horizontal, -NotchMetrics.openEar))
                .clipShape(shape)
                .overlay(shape.outline.stroke(.white.opacity(open ? 0.1 : 0), lineWidth: 1))
                .shadow(color: .black.opacity(open ? 0.4 : 0), radius: 30, y: 18)
                .animation(Theme.spring, value: open)
                // Closed, the system island must show through, so the surface only exists while open.
                .opacity(surfaceVisible ? 1 : 0)
                .animation(open ? .easeOut(duration: 0.08) : .easeIn(duration: 0.12).delay(0.3), value: open)
                .padding(.top, topInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(Theme.spring, value: open)
                .onPreferenceChange(ContentHeightKey.self) { if $0 > 0 { contentHeight = $0 } }
        }
        .preferredColorScheme(.dark)
    }

    private var cardScrollView: some View {
        ScrollViewReader { scroller in
            ScrollView(.vertical, showsIndicators: false) {
                // The card exists only while the panel is expanded. Closed, nothing of it is
                // kept: no view graph, no observers of the metrics, no model.
                if state.isMounted {
                    CardView()
                        .frame(width: IslandController.cardWidth)
                        .background(GeometryReader { Color.clear.preference(key: ContentHeightKey.self, value: $0.size.height) })
                        .id(ScrollAnchor.card)
                }
            }
            // `islandmenu://bottom` and `islandmenu://top`, for scripted screenshots.
            .onReceive(NotificationCenter.default.publisher(for: .scrollCommand)) { note in
                withAnimation(Theme.spring) { scroller.scrollTo(ScrollAnchor.card, anchor: note.object as? String == "bottom" ? .bottom : .top) }
            }
        }
    }

    private func settingsButton(header: CGFloat) -> some View {
        Button { state.showSettings() } label: {
            Image(systemName: "gearshape.fill").font(.system(size: HeaderButton.glyph)).foregroundStyle(Theme.secondary)
                .frame(width: HeaderButton.side, height: HeaderButton.side).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.top, (header - HeaderButton.side) / 2)
        .padding(.trailing, 14)
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
