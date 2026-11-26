import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            FanSettings().tabItem { Label("风扇", systemImage: "fan") }
            BatterySettings().tabItem { Label("电池", systemImage: "battery.75percent") }
            GeneralSettings().tabItem { Label("通用", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 400)
    }
}

private struct FanSettings: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var engine: MetricsEngine
    private static let modeNames: [FanMode: String] = [.auto: "自动", .max: "最大", .curve: "策略"]

    var body: some View {
        let temperature = engine.snapshot.thermal.dieMean
        Form {
            Section {
                Picker("模式", selection: $preferences.fanMode) {
                    ForEach(FanMode.allCases, id: \.self) { Text(Self.modeNames[$0] ?? "").tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("风扇控制组件尚未安装，目前选择的模式和曲线只会保存，不会改变实际转速。")
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
        .formStyle(.grouped)
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
        .formStyle(.grouped)
        .onAppear { limiter.refresh() }
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var preferences: Preferences
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("登录时启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
            Section {
                Toggle("显示公共 IP", isOn: $preferences.showPublicIP)
            } footer: {
                Text("开启后，卡片展开时会向 api.ipify.org 查询公共 IP，最多每 10 分钟一次。")
            }
        }
        .formStyle(.grouped)
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
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
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
