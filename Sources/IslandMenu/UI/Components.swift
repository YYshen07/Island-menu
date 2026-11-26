import SwiftUI

/// Section title on the left, readout on the right.
struct SectionHead<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).title()
            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 20)
    }
}

/// Stacked horizontal meter; each segment is a fraction of the whole.
struct SegmentBar: View {
    let segments: [(fraction: Double, color: Color)]

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.track))
            var x: CGFloat = 0
            for segment in segments {
                let width = size.width * min(max(segment.fraction, 0), 1)
                context.fill(Path(CGRect(x: x, y: 0, width: width, height: size.height)), with: .color(segment.color))
                x += width
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
    }
}

/// Filled line chart. `mirrored` values are drawn below the baseline (upload under download).
struct Sparkline: View {
    let values: [Double]
    var mirrored: [Double] = []
    var ceiling: Double?
    var color: Color = .white

    var body: some View {
        Canvas { context, size in
            let peak = max(ceiling ?? (values + mirrored).max() ?? 0, 0.0001)
            let baseline = mirrored.isEmpty ? size.height : size.height * 0.66
            draw(values, in: &context, size: size, baseline: baseline, span: -(baseline - 1), peak: peak, opacity: 0.75)
            draw(mirrored, in: &context, size: size, baseline: baseline, span: size.height - baseline, peak: peak, opacity: 0.3)
        }
    }

    private func draw(_ data: [Double], in context: inout GraphicsContext, size: CGSize, baseline: CGFloat, span: CGFloat, peak: Double, opacity: Double) {
        guard data.count > 1 else { return }
        var path = Path()
        path.move(to: CGPoint(x: 0, y: baseline))
        for (index, value) in data.enumerated() {
            let x = size.width * CGFloat(index) / CGFloat(data.count - 1)
            path.addLine(to: CGPoint(x: x, y: baseline + span * CGFloat(min(value / peak, 1))))
        }
        path.addLine(to: CGPoint(x: size.width, y: baseline))
        path.closeSubpath()
        context.fill(path, with: .color(color.opacity(opacity * (mirrored.isEmpty ? 0.45 : 1))))
    }
}

/// Pill-shaped segmented control.
struct PillPicker<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    var height: CGFloat = 20

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { option in
                Text(option.1)
                    .font(.system(size: 11, weight: selection == option.0 ? .semibold : .regular))
                    .foregroundStyle(selection == option.0 ? Theme.primary : Theme.secondary)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(selection == option.0 ? Capsule().fill(.white.opacity(0.2)) : nil)
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(Theme.spring) { selection = option.0 } }
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.track))
    }
}

struct Hairline: View {
    var vertical = false

    var body: some View {
        Rectangle().fill(Theme.hairline).frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}
