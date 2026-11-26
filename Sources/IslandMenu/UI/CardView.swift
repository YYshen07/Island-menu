import SwiftUI

struct CardView: View {
    @ObservedObject private var preferences = Preferences.shared

    var body: some View {
        VStack(spacing: 0) {
            MachineSection()
            Hairline()
            FanSection()
            Hairline()
            CPUSection()
            Hairline()
            HStack(alignment: .top, spacing: 0) {
                MemorySection()
                Hairline(vertical: true)
                StorageSection()
            }
            .fixedSize(horizontal: false, vertical: true)
            Hairline()
            GPUSection()
            Hairline()
            BatterySection()
            Hairline()
            NetworkSection()
            Hairline()
            ProcessSection()
            Hairline()
            LogoLightSection()
            Hairline()
            ActivitySection()
        }
        // Tints are read when a section draws, so switching appearance rebuilds the card.
        .id(preferences.colorful)
    }
}

extension View {
    func section() -> some View {
        padding(.horizontal, Theme.padding).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ActivitySection: View {
    @EnvironmentObject private var engine: MetricsEngine

    var body: some View {
        let today = engine.days[ActivityStore.key(for: Date())]?.active ?? 0
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                big("已运行", Format.duration(Date().timeIntervalSince(engine.snapshot.bootTime)), .leading)
                Spacer()
                big("今日活跃", Format.duration(today), .trailing)
            }
            ActivityHeatmap(days: engine.days)
            Text("近 \(MetricsEngine.historyWeeks) 周活跃时长").label()
        }
        .section()
    }

    private func big(_ title: String, _ text: String, _ alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title).label()
            Text(text).font(.system(size: 19, weight: .semibold)).monospacedDigit().tracking(-0.4).foregroundStyle(Theme.primary)
        }
    }
}

/// GitHub-style grid: one column per week, Monday at the top, today in the last column.
struct ActivityHeatmap: View {
    let days: [String: DayRecord]
    private static let gap: CGFloat = 3
    private static let hourSteps: [TimeInterval] = [0, 1, 3, 6]
    private static let opacities: [Double] = [0.07, 0.2, 0.4, 0.65, 0.92]

    var body: some View {
        let weeks = MetricsEngine.historyWeeks
        let cell = (IslandController.cardWidth - Theme.padding * 2 - Self.gap * CGFloat(weeks - 1)) / CGFloat(weeks)
        Canvas { context, _ in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let weekday = (calendar.component(.weekday, from: today) + 5) % 7
            for week in 0..<weeks {
                for day in 0..<7 {
                    let offset = (weeks - 1 - week) * 7 + (weekday - day)
                    guard offset >= 0, let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                    let rect = CGRect(x: CGFloat(week) * (cell + Self.gap), y: CGFloat(day) * (cell + Self.gap), width: cell, height: cell)
                    let level = Self.level(days[ActivityStore.key(for: date)]?.active ?? 0)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2.5), with: .color(.white.opacity(Self.opacities[level])))
                }
            }
        }
        .frame(height: cell * 7 + Self.gap * 6)
    }

    private static func level(_ active: TimeInterval) -> Int {
        guard active > 0 else { return 0 }
        return hourSteps.lastIndex { active / 3600 >= $0 }.map { $0 + 1 } ?? 1
    }
}

struct CPUSection: View {
    @EnvironmentObject private var engine: MetricsEngine
    private static let groupGap: CGFloat = 8
    private static let gap: CGFloat = 4

    var body: some View {
        let cpu = engine.snapshot.cpu
        let tint = Module.cpu.tint
        VStack(alignment: .leading, spacing: 8) {
            SectionHead(title: "CPU") {
                Text("用户 \(Format.percent(cpu.user)) · 系统 \(Format.percent(cpu.system)) · 负载 \(String(format: "%.2f", cpu.load))").detail()
                Text(Format.percent(cpu.total)).value()
            }
            Canvas { context, size in
                let count = CGFloat(max(cpu.cores.count, 1))
                let width = (size.width - Self.gap * (count - 1) - Self.groupGap) / count
                for (index, load) in cpu.cores.enumerated() {
                    let x = CGFloat(index) * (width + Self.gap) + (index >= cpu.superCount ? Self.groupGap : 0)
                    let slot = CGRect(x: x, y: 0, width: width, height: size.height)
                    context.fill(Path(roundedRect: slot, cornerRadius: 3), with: .color(Theme.track))
                    let filled = slot.divided(atDistance: size.height * CGFloat(load), from: .maxYEdge).slice
                    var clipped = context
                    clipped.clip(to: Path(roundedRect: slot, cornerRadius: 3))
                    clipped.fill(Path(filled), with: .color(load > 0.85 ? Theme.heat : tint))
                }
            }
            .frame(height: 40)
            .animation(.easeOut(duration: 0.6), value: cpu.total)
            // Each name sits under the first bar of its cluster.
            GeometryReader { proxy in
                let count = CGFloat(max(cpu.cores.count, 1))
                let width = (proxy.size.width - Self.gap * (count - 1) - Self.groupGap) / count
                Text("Super").label()
                Text("Performance").label().offset(x: CGFloat(cpu.superCount) * (width + Self.gap) + Self.groupGap)
            }
            .frame(height: 14)
        }
        .section()
    }
}
