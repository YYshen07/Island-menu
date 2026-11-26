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
                LabeledContent("防休眠时的屏幕亮度") {
                    HStack {
                        Slider(value: $preferences.awakeBrightness, in: 0...1)
                            .frame(width: 180)
                            .onChange(of: preferences.awakeBrightness) { _, _ in KeepAwake.shared.brightnessPreferenceChanged() }
                        Text("\(Int((preferences.awakeBrightness * 100).rounded()))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
            } footer: {
                Text("点卡片左上角的彩色苹果标开启防休眠：屏幕调到这个亮度并保持唤醒，再点一次恢复原来的亮度。")
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
