import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Looks of the 3D model: body colour and what its screen shows. The model itself always matches
/// the Mac the app runs on.
struct MachineSettings: View {
    @ObservedObject private var preferences = Preferences.shared
    @State private var importError: String?
    @State private var hasCustomImage = FileManager.default.fileExists(atPath: ScreenContent.customImageURL.path)

    var body: some View {
        Form {
            Section {
                LabeledContent("机型") { Text(MachineModel.current.title).foregroundStyle(.secondary) }
            } footer: {
                Text("机型和比例跟随这台 Mac，不能更改；颜色可以选任意系列的。")
            }
            Section("机身颜色") {
                swatchRow("默认", [.standard])
                ForEach(MachineFinish.series, id: \.title) { series in swatchRow(series.title, series.finishes) }
            }
            Section {
                Picker("显示内容", selection: $preferences.screenContent) {
                    ForEach(ScreenContent.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if preferences.screenContent == .custom {
                    LabeledContent(hasCustomImage ? "已选择图片" : "还没有选择图片") {
                        Button(hasCustomImage ? "更换…" : "选择图片…") { chooseImage() }
                    }
                }
                if let importError { Text(importError).font(.caption).foregroundStyle(.red) }
            } header: {
                Text("开盖时的屏幕")
            } footer: {
                Text("双击机模打开屏幕时显示。图片只保存在本机。")
            }
        }
        .formStyle(.grouped).scrollDisabled(true).fixedSize(horizontal: false, vertical: true)
    }

    private func swatchRow(_ title: String, _ finishes: [MachineFinish]) -> some View {
        LabeledContent(title) {
            HStack(spacing: 14) {
                ForEach(finishes) { finish in
                    let selected = preferences.machineFinish == finish
                    Button { preferences.machineFinish = finish } label: {
                        VStack(spacing: 4) {
                            Circle().fill(Color(nsColor: finish.swatch))
                                .frame(width: 24, height: 24)
                                .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 0.5))
                                .padding(3)
                                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
                            Text(finish.title).font(.caption).foregroundStyle(selected ? .primary : .secondary)
                        }
                        .frame(minWidth: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Copies the chosen picture into the app's own folder, so it stays available.
    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let destination = ScreenContent.customImageURL
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.copyItem(at: source, to: destination)
            hasCustomImage = true
            importError = nil
        } catch {
            importError = "无法保存图片：\(error.localizedDescription)"
        }
    }
}
