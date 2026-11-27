import SwiftUI

struct MemorySection: View {
    @EnvironmentObject private var engine: MetricsEngine
    private static let pressureNames = [1: "正常", 2: "警告", 4: "严重"]

    var body: some View {
        let memory = engine.snapshot.memory
        let total = Double(max(memory.total, 1))
        let tint = Module.memory.tint
        VStack(alignment: .leading, spacing: 8) {
            SectionHead(title: "内存") {
                Text(Format.gigabytes(memory.used)).value()
                Text("/ \(Format.gigabytes(memory.total, digits: 0)) GB").detail()
            }
            SegmentBar(segments: [
                (Double(memory.app) / total, tint),
                (Double(memory.wired) / total, tint.opacity(0.55)),
                (Double(memory.compressed) / total, tint.opacity(0.3)),
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
            SegmentBar(segments: [(Double(disk.used) / Double(max(disk.total, 1)), Module.storage.tint)])
            // A trend line only means something once the usage has actually moved.
            if trend.count > 1, let low = trend.min(), let high = trend.max(), high > low {
                // Stretch the span between the lowest and highest day over the chart, off a small floor.
                Sparkline(values: trend.map { 0.15 + 0.85 * ($0 - low) / (high - low) }, ceiling: 1, color: Module.storage.tint).frame(height: 18)
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
            Sparkline(values: engine.gpuHistory.values, ceiling: 1, color: Module.gpu.tint).frame(height: 26)
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
    @EnvironmentObject private var state: IslandState
    @ObservedObject private var limiter = ChargeLimiter.shared
    @ObservedObject private var preferences = Preferences.shared

    var body: some View {
        let battery = engine.snapshot.battery
        if battery.present {
            VStack(alignment: .leading, spacing: 8) {
                SectionHead(title: "电池") {
                    Text(summary(battery)).detail()
                    Text("\(battery.percent)%").value()
                }
                SegmentBar(segments: [(Double(battery.percent) / 100, battery.external ? Theme.live : Theme.primary)])
                if battery.systemPower != nil || battery.batteryPower != nil {
                    HStack(alignment: .top, spacing: 0) {
                        power(battery.inputPower, "电源输入")
                        power(battery.systemPower, "整机功耗")
                        power(battery.batteryPower.map(abs), batteryPowerTitle(battery))
                    }
                    .padding(.top, 2)
                }
                if limiter.isSupported {
                    PillPicker(options: [(BatteryMode.auto, "自动"), (.care, "养护"), (.full, "满充")], selection: modeBinding, height: 26)
                        .padding(.top, 4)
                    Text(limiter.lastError ?? modeNote).label()
                }
            }
            .section()
            .onChange(of: state.isOpen, initial: true) { _, open in
                if open { limiter.refresh() }
            }
        }
    }

    private var modeBinding: Binding<BatteryMode> {
        Binding(get: { limiter.mode }, set: { limiter.apply($0, limit: preferences.chargeLimit) })
    }

    private var modeNote: String {
        switch limiter.mode {
        case .auto: "由 macOS 管理充电"
        case .care: "充到 \(preferences.chargeLimit)% 停止"
        case .full: "这一次充到 100%，之后回到 \(preferences.chargeLimit)%"
        }
    }

    private func power(_ watts: Double?, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(watts.map { String(format: "%.1f W", $0) } ?? "—").value()
            Text(title).label()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func batteryPowerTitle(_ battery: BatterySnapshot) -> String {
        guard let watts = battery.batteryPower, abs(watts) >= 0.05 else { return "电池" }
        return watts > 0 ? "电池充电" : "电池放电"
    }

    private func summary(_ battery: BatterySnapshot) -> String {
        var parts = ["循环 \(battery.cycles) 次"]
        if let health = battery.health { parts.append("健康度 \(health)%") }
        if let watts = battery.adapterWatts { parts.append("\(watts) W 适配器") }
        return parts.joined(separator: " · ")
    }
}

struct FanSection: View {
    @EnvironmentObject private var engine: MetricsEngine
    @EnvironmentObject private var state: IslandState
    @ObservedObject private var fans = FanController.shared
    @ObservedObject private var preferences = Preferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHead(title: "风扇") { Text(readout).detail() }
            switch fans.helperState {
            case .ready:
                PillPicker(options: [(FanMode.auto, "自动"), (.max, "最大"), (.curve, "策略")], selection: $preferences.fanMode, height: 26)
                Text(note).label()
            case .notInstalled:
                action("安装风扇控制组件", note: "控制转速需要一个后台组件，安装时系统会请你批准。") { fans.installHelper() }
            case .needsApproval:
                action("打开登录项设置", note: "请在「系统设置 → 通用 → 登录项与扩展」里允许 Island Menu，然后回到这里。") { fans.installHelper() }
            case .unavailable(let reason):
                action("重试", note: "风扇控制不可用：\(reason)") { fans.installHelper() }
            }
        }
        .section()
        .onChange(of: state.isOpen, initial: true) { _, open in
            if open { fans.refreshHelperState() }
        }
    }

    private var readout: String {
        let speeds = engine.snapshot.fans.map { $0.rpm < 1 ? "停转" : "\(Int($0.rpm.rounded())) 转" }
        return speeds.joined(separator: " · ")
    }

    private var note: String {
        switch preferences.fanMode {
        case .auto: "跟随 macOS 温控策略"
        case .max: "全速运行"
        case .curve: fans.targetLevel.map { $0 > 0 ? "按设置里的曲线，当前 \(Int(($0 * 100).rounded()))%" : "按设置里的曲线，当前温度下交给 macOS" } ?? "按设置里的曲线"
        }
    }

    private func action(_ title: String, note: String, perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: perform) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity, minHeight: 28).background(Capsule().fill(.white.opacity(0.16)))
            }
            .buttonStyle(.plain)
            Text(note).label().fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct LogoLightSection: View {
    @ObservedObject private var light = LogoLight.shared
    private static let notes: [LogoMode: String] = [
        .auto: "跟随 macOS 默认行为",
        .breathe: "缓慢呼吸，4.5 秒一次",
        .audio: "随系统声音（含提示音）律动",
    ]

    var body: some View {
        if Hardware.hasLogoLight {
            VStack(alignment: .leading, spacing: 8) {
                SectionHead(title: "信仰灯") { EmptyView() }
                PillPicker(options: [(LogoMode.auto, "自动"), (.breathe, "呼吸"), (.audio, "音跃")], selection: modeBinding, height: 26)
                Text(light.lastError ?? Self.notes[light.mode] ?? "").label().fixedSize(horizontal: false, vertical: true)
            }
            .section()
        }
    }

    private var modeBinding: Binding<LogoMode> {
        Binding(get: { light.mode }, set: { mode in
            light.setMode(mode)
            Preferences.shared.logoMode = light.mode
        })
    }
}

struct NetworkSection: View {
    @EnvironmentObject private var engine: MetricsEngine
    @ObservedObject private var preferences = Preferences.shared

    var body: some View {
        let network = engine.snapshot.network
        let publicIP = preferences.showPublicIP ? [("公共 IP", network.publicIP ?? "—", false)] : []
        let rows = network.interfaces.map { ($0.name, $0.detail, true) } + publicIP
        VStack(alignment: .leading, spacing: 8) {
            SectionHead(title: "网络") {
                Text("↓").detail()
                Text(Format.rate(network.down)).value()
                Text("↑").detail().padding(.leading, 8)
                Text(Format.rate(network.up)).value()
            }
            Sparkline(values: engine.downHistory.values, mirrored: engine.upHistory.values, color: Module.network.tint).frame(height: 44)
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
                        SegmentBar(segments: [((byMemory ? Double(row.memory) : row.cpu) / max(peak, 0.0001), (byMemory ? Module.memory : Module.cpu).tint.opacity(0.75))])
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
