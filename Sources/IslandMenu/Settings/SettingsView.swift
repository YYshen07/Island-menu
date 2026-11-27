import IslandShared
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("通用", systemImage: "gearshape") }
            AlertSettings().tabItem { Label("提醒", systemImage: "bell.badge") }
            if Hardware.hasFans { FanSettings().tabItem { Label("风扇", systemImage: "fan") } }
            BatterySettings().tabItem { Label("电池", systemImage: "battery.75percent") }
        }
        .frame(width: 520)
    }
}

private extension View {
    /// Shared look for every settings tab: grouped rows, as tall as its content, no inner scrolling.
    func settingsPane() -> some View {
        formStyle(.grouped).scrollDisabled(true).fixedSize(horizontal: false, vertical: true)
    }
}

/// One settings row: icon and title on the left, the control on the right.
private struct SettingRow<Control: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var control: Control

    var body: some View {
        LabeledContent {
            control
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}

private struct FanSettings: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var engine: MetricsEngine
    @ObservedObject private var fans = FanController.shared
    private static let modeNames: [FanMode: String] = [.auto: "自动", .max: "最大", .curve: "策略"]

    var body: some View {
        let temperature = engine.snapshot.thermal.dieMax
        Form {
            Section {
                Picker("模式", selection: $preferences.fanMode) {
                    ForEach(FanMode.allCases, id: \.self) { Text(Self.modeNames[$0] ?? "").tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(fans.helperState == .ready ? "「策略」模式按下面的曲线控制转速；曲线为 0 的温度段交给 macOS。芯片达到 95°C 时无论曲线如何都会全速。" : "风扇控制组件尚未启用，模式和曲线只会保存。请在卡片的风扇栏里安装。")
            }
            Section("策略曲线") {
                FanCurveEditor(points: $preferences.fanCurve, currentTemperature: temperature)
                    .frame(height: 170)
                    .padding(.vertical, 4)
                HStack {
                    Text("40°C").foregroundStyle(.secondary)
                    Spacer()
                    if let temperature {
                        Text("芯片 \(Int(temperature.rounded()))° → \(Int((preferences.curveLevel(at: temperature) * 100).rounded()))%")
                            .monospacedDigit()
                    }
                    Spacer()
                    Text("100°C").foregroundStyle(.secondary)
                }
                .font(.caption)
                Button("恢复默认曲线") { preferences.fanCurve = Preferences.defaultCurve }
            }
        }
        .settingsPane()
    }
}

private struct AlertSettings: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Form {
            Section {
                ForEach(AlertKind.allCases, id: \.self) { kind in
                    let rule = preferences.alertRule(kind)
                    HStack(spacing: 12) {
                        Toggle(isOn: Binding(get: { rule.enabled }, set: { preferences.setAlertRule(AlertRule(enabled: $0, limit: rule.limit), for: kind) })) {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                        Spacer()
                        Slider(value: Binding(get: { rule.limit }, set: { preferences.setAlertRule(AlertRule(enabled: rule.enabled, limit: $0.rounded()), for: kind) }),
                               in: Preferences.alertLimitRanges[kind] ?? 50...100)
                            .frame(width: 150)
                            .disabled(!rule.enabled)
                        Text("\(Int(rule.limit))\(kind.unit)").monospacedDigit().frame(width: 44, alignment: .trailing)
                            .foregroundStyle(rule.enabled ? .primary : .secondary)
                    }
                }
            } footer: {
                Text("读数持续超过阈值约 15 秒后，灵动岛右侧会出现提醒，回落后自动消失。储存空间超过阈值、未接电源时电量低于阈值会立即提醒。提醒出现的一瞬间，Island Menu 会短暂切到前台再切回，这是系统对发起提醒的要求。")
            }
        }
        .settingsPane()
    }
}

private struct BatterySettings: View {
    @EnvironmentObject private var preferences: Preferences
    @ObservedObject private var limiter = ChargeLimiter.shared

    var body: some View {
        Form {
            if limiter.isSupported {
                Section {
                    Picker("充电上限", selection: $preferences.chargeLimit) {
                        ForEach(limiter.availableLimits, id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .onChange(of: preferences.chargeLimit) { _, limit in
                        // Already limiting: move the live limit too, not just the stored preference.
                        if limiter.mode != .auto { limiter.apply(limiter.mode, limit: limit) }
                    }
                } footer: {
                    Text("「养护」模式下充到这个电量就停止。使用的是 macOS 自带的充电上限，由系统执行，Island Menu 退出后依然有效。")
                }
                if let error = limiter.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } else {
                Text("这台 Mac 的系统不支持充电上限。").foregroundStyle(.secondary)
            }
        }
        .settingsPane()
        .onAppear { limiter.refresh() }
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var preferences: Preferences
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    private var customFinish: Binding<Color> {
        Binding(get: { Color(nsColor: preferences.customFinish) }, set: { preferences.customFinish = NSColor($0) })
    }

    var body: some View {
        Form {
            Section("外观") {
                SettingRow(title: "配色", symbol: "paintpalette") {
                    Picker("", selection: $preferences.colorful) {
                        Text("彩色").tag(true)
                        Text("纯白").tag(false)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 160)
                }
                SettingRow(title: "屏幕形态", symbol: "macbook") {
                    Picker("", selection: $preferences.islandStyle) {
                        Text("自动").tag(IslandStyle?.none)
                        Text("灵动岛").tag(IslandStyle?.some(.island))
                        Text("刘海").tag(IslandStyle?.some(.notch))
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                }
            }
            Section("机模") {
                SettingRow(title: "机型", symbol: "laptopcomputer") {
                    Picker("", selection: $preferences.machineModel) {
                        Text("自动（\(MachineModel.detected.title)）").tag(MachineModel?.none)
                        ForEach(MachineModel.allCases) { Text($0.title).tag(MachineModel?.some($0)) }
                    }
                    .labelsHidden().frame(width: 260)
                }
                SettingRow(title: "颜色", symbol: "paintbrush") {
                    HStack(spacing: 8) {
                        if preferences.machineFinish == .custom {
                            ColorPicker("", selection: customFinish, supportsOpacity: false).labelsHidden()
                        }
                        Picker("", selection: $preferences.machineFinish) {
                            ForEach(MachineFinish.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden().frame(width: 130)
                    }
                }
            }
            Section("启动") {
                SettingRow(title: "登录时启动", symbol: "power") {
                    Toggle("", isOn: $launchAtLogin).labelsHidden()
                        .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
            Section {
                SettingRow(title: "屏幕亮度", symbol: "sun.min") {
                    HStack(spacing: 10) {
                        Slider(value: $preferences.awakeBrightness, in: 0...1)
                            .frame(width: 180)
                            .onChange(of: preferences.awakeBrightness) { _, _ in KeepAwake.shared.brightnessPreferenceChanged() }
                        Text("\(Int((preferences.awakeBrightness * 100).rounded()))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                Text("防休眠")
            } footer: {
                Text("点卡片左上角的苹果标开启：屏幕调到这个亮度并保持唤醒，再点一次恢复。")
            }
            Section {
                SettingRow(title: "显示公共 IP", symbol: "network") {
                    Toggle("", isOn: $preferences.showPublicIP).labelsHidden()
                }
            } header: {
                Text("网络")
            } footer: {
                Text("卡片展开时向 api.ipify.org 查询，最多每 10 分钟一次。")
            }
        }
        .settingsPane()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// The settings window. An accessory app has no Settings scene, so the window is managed by hand.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let engine: MetricsEngine

    init(engine: MetricsEngine) {
        self.engine = engine
    }

    func show() {
        let window = self.window ?? makeWindow()
        // The curve editor shows live temperature, so sampling runs while the window is up.
        if !window.isVisible { engine.retainLive() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsView().environmentObject(Preferences.shared).environmentObject(engine)
        let host = NSHostingController(rootView: root)
        // The window follows the selected tab's height.
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = "Island Menu 设置"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        engine.releaseLive()
    }
}
