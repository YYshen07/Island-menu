import SwiftUI

struct MemorySection: View {
    @EnvironmentObject private var engine: MetricsEngine
    private static let pressureNames = [1: "正常", 2: "警告", 4: "严重"]

    var body: some View {
        let memory = engine.snapshot.memory
        let total = Double(max(memory.total, 1))
        VStack(alignment: .leading, spacing: 8) {
            SectionHead(title: "内存") {
                Text(Format.gigabytes(memory.used)).value()
                Text("/ \(Format.gigabytes(memory.total, digits: 0)) GB").detail()
            }
            SegmentBar(segments: [
                (Double(memory.app) / total, Theme.primary),
                (Double(memory.wired) / total, .white.opacity(0.5)),
                (Double(memory.compressed) / total, .white.opacity(0.26)),
            ])
            Text("压力 \(Self.pressureNames[memory.pressure] ?? "正常") · 交换 \(Format.gigabytes(memory.swapUsed)) GB").label()
        }
        .section()
    }
}

struct StorageSection: View {
    @EnvironmentObject private var engine: MetricsEngine
    private static let trendDays = 90

    var body: some View {
        let disk = engine.snapshot.disk
        let trend = engine.days.sorted { $0.key < $1.key }.suffix(Self.trendDays).map { Double($0.value.diskUsed) }.filter { $0 > 0 }
        VStack(alignment: .leading, spacing: 8) {
            SectionHead(title: "储存") {
                Text(Format.decimalGigabytes(disk.used)).value()
                Text("/ \(Format.decimalGigabytes(disk.total)) GB").detail()
            }
            SegmentBar(segments: [(Double(disk.used) / Double(max(disk.total, 1)), Theme.primary)])
            if trend.count > 1 {
                Sparkline(values: trend.map { $0 - (trend.min() ?? 0) * 0.98 }).frame(height: 18)
            }
            Text("读 \(Format.rate(disk.readRate)) · 写 \(Format.rate(disk.writeRate))").label()
        }
        .section()
    }
}

struct GPUSection: View {
    @EnvironmentObject private var engine: MetricsEngine

    var body: some View {
        let gpu = engine.snapshot.gpu
        VStack(alignment: .leading, spacing: 8) {
            SectionHead(title: "GPU") { Text(Format.percent(gpu.usage)).value() }
            Sparkline(values: engine.gpuHistory.values, ceiling: 1).frame(height: 26)
            HStack(spacing: 0) {
                stat(Format.percent(gpu.memoryFraction), "显存")
                stat(Format.gigabytes(gpu.memoryUsed) + " GB", "显存占用")
                stat(Format.degrees(gpu.temperature), "温度")
            }
        }
        .section()
    }

    private func stat(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).value()
            Text(title).label()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BatterySection: View {
    @EnvironmentObject private var engine: MetricsEngine

    var body: some View {
        let battery = engine.snapshot.battery
        if battery.present {
            VStack(alignment: .leading, spacing: 8) {
                SectionHead(title: "电池") {
                    Text(summary(battery)).detail()
                    Text("\(battery.percent)%").value()
                }
                SegmentBar(segments: [(Double(battery.percent) / 100, battery.external ? Theme.live : Theme.primary)])
            }
            .section()
        }
    }

    private func summary(_ battery: BatterySnapshot) -> String {
        var parts = ["循环 \(battery.cycles) 次"]
        if let health = battery.health { parts.append("健康度 \(health)%") }
        if let watts = battery.adapterWatts { parts.append("\(watts) W 适配器") }
        return parts.joined(separator: " · ")
    }
}

struct NetworkSection: View {
    @EnvironmentObject private var engine: MetricsEngine

    var body: some View {
        let network = engine.snapshot.network
        let rows = network.interfaces.map { ($0.name, $0.detail, true) } + [("公共 IP", network.publicIP ?? "—", false)]
        VStack(alignment: .leading, spacing: 8) {
            SectionHead(title: "网络") {
                Text("↓").detail()
                Text(Format.rate(network.down)).value()
                Text("↑").detail().padding(.leading, 8)
                Text(Format.rate(network.up)).value()
            }
            Sparkline(values: engine.downHistory.values, mirrored: engine.upHistory.values).frame(height: 44)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible())], spacing: 6) {
                ForEach(rows, id: \.0) { row in
                    HStack(spacing: 6) {
                        if row.2 { Circle().fill(Theme.live).frame(width: 6, height: 6) }
                        Text(row.0).label().lineLimit(1)
                        Spacer(minLength: 6)
                        Text(row.1).font(.system(size: 11.5, weight: .medium)).monospacedDigit().foregroundStyle(Theme.primary).lineLimit(1)
                    }
                }
            }
        }
        .section()
    }
}

struct ProcessSection: View {
    enum Sort { case cpu, memory }
    @EnvironmentObject private var engine: MetricsEngine
    @State private var sort = Sort.cpu
    private static let rowLimit = 4

    var body: some View {
        let byMemory = sort == .memory
        let rows = engine.snapshot.processes.sorted { byMemory ? $0.memory > $1.memory : $0.cpu > $1.cpu }.prefix(Self.rowLimit)
        let peak = rows.first.map { byMemory ? Double($0.memory) : $0.cpu } ?? 1
        VStack(alignment: .leading, spacing: 8) {
            SectionHead(title: "进程") {
                PillPicker(options: [(Sort.cpu, "CPU"), (Sort.memory, "内存")], selection: $sort).frame(width: 108)
            }
            VStack(spacing: 6) {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Text(row.name).font(.system(size: 12)).foregroundStyle(Theme.primary).lineLimit(1)
                        Spacer(minLength: 8)
                        SegmentBar(segments: [((byMemory ? Double(row.memory) : row.cpu) / max(peak, 0.0001), Theme.secondary)])
                            .frame(width: 70, height: 3)
                        Text(byMemory ? Format.gigabytes(row.memory) + " GB" : String(format: "%.1f%%", row.cpu * 100))
                            .detail().frame(width: 64, alignment: .trailing)
                    }
                }
            }
        }
        .section()
    }
}
