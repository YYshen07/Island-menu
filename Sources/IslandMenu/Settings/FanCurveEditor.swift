import SwiftUI

/// Temperature → fan level curve with draggable nodes.
struct FanCurveEditor: View {
    @Binding var points: [FanCurvePoint]
    var currentTemperature: Double?
    private static let handleRadius: CGFloat = 6
    private static let minimumGap = 2.0
    @State private var dragging: Int?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Canvas { context, size in
                    for step in 1..<4 {
                        let y = size.height * CGFloat(step) / 4
                        context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) }, with: .color(.primary.opacity(0.08)))
                    }
                    let line = curvePath(in: size)
                    var area = line
                    area.addLine(to: CGPoint(x: size.width, y: size.height))
                    area.addLine(to: CGPoint(x: 0, y: size.height))
                    area.closeSubpath()
                    context.fill(area, with: .color(.accentColor.opacity(0.12)))
                    context.stroke(line, with: .color(.accentColor), lineWidth: 2)
                    if let currentTemperature {
                        let x = position(FanCurvePoint(temperature: currentTemperature, level: 0), in: size).x
                        context.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                                       with: .color(.orange), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                ForEach(points.indices, id: \.self) { index in
                    Circle()
                        .fill(.white)
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                        .frame(width: Self.handleRadius * 2, height: Self.handleRadius * 2)
                        .position(position(points[index], in: size))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let index = dragging ?? nearest(to: value.startLocation, in: size)
                    dragging = index
                    move(index, to: value.location, in: size)
                }
                .onEnded { _ in dragging = nil })
        }
    }

    private func position(_ point: FanCurvePoint, in size: CGSize) -> CGPoint {
        let range = Preferences.temperatureRange
        let x = (point.temperature - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGPoint(x: size.width * CGFloat(min(max(x, 0), 1)), y: size.height * CGFloat(1 - point.level))
    }

    private func curvePath(in size: CGSize) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: 0, y: position(first, in: size).y))
        for point in points { path.addLine(to: position(point, in: size)) }
        path.addLine(to: CGPoint(x: size.width, y: position(last, in: size).y))
        return path
    }

    private func nearest(to location: CGPoint, in size: CGSize) -> Int {
        points.indices.min { lhs, rhs in
            distance(position(points[lhs], in: size), location) < distance(position(points[rhs], in: size), location)
        } ?? 0
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// Nodes stay ordered: a node cannot be dragged past its neighbours.
    private func move(_ index: Int, to location: CGPoint, in size: CGSize) {
        let range = Preferences.temperatureRange
        let lower = index > 0 ? points[index - 1].temperature + Self.minimumGap : range.lowerBound
        let upper = index < points.count - 1 ? points[index + 1].temperature - Self.minimumGap : range.upperBound
        let temperature = range.lowerBound + Double(location.x / size.width) * (range.upperBound - range.lowerBound)
        points[index] = FanCurvePoint(temperature: min(max(temperature, lower), upper), level: Double(min(max(1 - location.y / size.height, 0), 1)))
    }
}
