import AppKit
import PhotosUI
import SwiftUI

/// Stickers for the model's lid: make one from a picture, then drag it into place on a flat view
/// of the lid (logo upright, as the card shows it).
struct StickerSettings: View {
    @ObservedObject private var store = StickerStore.shared
    @ObservedObject private var preferences = Preferences.shared
    @State private var selection: UUID?
    @State private var photo: PhotosPickerItem?
    @State private var isWorking = false
    @State private var failure: String?
    private static let lidWidth: CGFloat = 440

    var body: some View {
        Form {
            Section {
                lid.frame(maxWidth: .infinity).padding(.vertical, 6)
                HStack {
                    PhotosPicker(selection: $photo, matching: .images) { Label("从照片选择", systemImage: "photo.on.rectangle") }
                    Button { chooseFile() } label: { Label("从文件选择", systemImage: "folder") }
                    if isWorking { ProgressView().controlSize(.small) }
                    Spacer()
                    if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
                }
            } header: {
                Text("顶盖")
            } footer: {
                Text("选一张图片，系统会像「信息」里做贴纸那样把主体抠出来。拖动贴纸摆放位置；下次展开卡片时机模上就会贴好。")
            }
            if let index = store.stickers.firstIndex(where: { $0.id == selection }) {
                Section("选中的贴纸") {
                    effectGrid(index)
                    LabeledContent("大小") { Slider(value: $store.stickers[index].size, in: StickerStore.sizeRange).frame(width: 260) }
                    LabeledContent("旋转") { Slider(value: $store.stickers[index].rotation, in: -180...180).frame(width: 260) }
                    Button("删除这张贴纸", role: .destructive) {
                        store.remove(store.stickers[index].id)
                        selection = nil
                    }
                }
            }
        }
        .formStyle(.grouped).scrollDisabled(true).fixedSize(horizontal: false, vertical: true)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            Task { await add { try await item.loadTransferable(type: Data.self) } }
        }
    }

    /// Every effect applied to the selected sticker; click one to use it.
    private func effectGrid(_ index: Int) -> some View {
        let sticker = store.stickers[index]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 10) {
            ForEach(StickerStyle.allCases) { style in
                Button { store.stickers[index].style = style } label: {
                    VStack(spacing: 4) {
                        Group {
                            if let image = store.preview(of: sticker, in: style) { Image(decorative: image, scale: 1).resizable().scaledToFit() } else { Color.clear }
                        }
                        .frame(width: 56, height: 56)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: preferences.machineFinish.swatch)))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: sticker.style == style ? 2 : 0))
                        Text(style.title).font(.caption).foregroundStyle(sticker.style == style ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    /// The lid seen from above in the chosen finish, with the stickers on it.
    private var lid: some View {
        let size = CGSize(width: Self.lidWidth, height: Self.lidWidth / MachineModel.current.lidAspect)
        return ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: preferences.machineFinish.swatch))
                .onTapGesture { selection = nil }
            Image(systemName: "apple.logo").font(.system(size: 54)).foregroundStyle(.white.opacity(0.85)).allowsHitTesting(false)
            ForEach($store.stickers) { $sticker in
                StickerHandle(sticker: $sticker, image: store.image(for: sticker), lid: size, isSelected: selection == sticker.id) { selection = sticker.id }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await add { try Data(contentsOf: url) } }
    }

    /// Cuts the sticker out; the system's subject lifting takes a second or two.
    private func add(_ load: @escaping @Sendable () async throws -> Data?) async {
        isWorking = true
        failure = nil
        defer { isWorking = false }
        do {
            guard let data = try await load() else { throw StickerMaker.Failure.unreadable }
            let image = try await StickerMaker.make(from: data)
            try store.add(image)
            selection = store.stickers.last?.id
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// One sticker on the flat lid; drag to move it.
private struct StickerHandle: View {
    @Binding var sticker: Sticker
    let image: CGImage?
    let lid: CGSize
    let isSelected: Bool
    let select: () -> Void
    @State private var dragStart: CGPoint?
    /// How far a sticker's centre may go towards the edge, as a fraction of the lid.
    private static let reach = 0.48

    var body: some View {
        let longSide = lid.width * sticker.size
        let size = sticker.aspect >= 1 ? CGSize(width: longSide, height: longSide / sticker.aspect) : CGSize(width: longSide * sticker.aspect, height: longSide)
        Group {
            if let image { Image(decorative: image, scale: 1).resizable() } else { Color.gray }
        }
        .frame(width: size.width, height: size.height)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).opacity(isSelected ? 1 : 0))
        .rotationEffect(.degrees(sticker.rotation))
        .offset(x: lid.width * sticker.x, y: -lid.height * sticker.y)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { drag in
                select()
                let start = dragStart ?? CGPoint(x: sticker.x, y: sticker.y)
                dragStart = start
                sticker.x = min(max(start.x + drag.translation.width / lid.width, -Self.reach), Self.reach)
                sticker.y = min(max(start.y - drag.translation.height / lid.height, -Self.reach), Self.reach)
            }
            .onEnded { _ in dragStart = nil })
    }
}
