import AppKit
import os

/// The effects Messages offers for a sticker.
enum StickerStyle: String, Codable, CaseIterable, Identifiable {
    case original, outline, comic, puffy, shiny

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "原图"
        case .outline: "描边"
        case .comic: "漫画"
        case .puffy: "立体"
        case .shiny: "闪亮"
        }
    }
}

/// One sticker on the lid. Position is the sticker's centre measured from the lid's centre as a
/// fraction of the lid's width and height (right and up positive, logo upright).
struct Sticker: Codable, Identifiable, Equatable {
    var id = UUID()
    var x = 0.0
    var y = 0.0
    /// Longer side as a fraction of the lid's width.
    var size = 0.18
    /// Clockwise, in degrees.
    var rotation = 0.0
    /// Width divided by height of the picture.
    var aspect = 1.0
    var style = StickerStyle.outline
}

/// The stickers placed on the model's lid. Pictures live in the app's own folder; placement is in
/// the preferences.
@MainActor
final class StickerStore: ObservableObject {
    static let shared = StickerStore()
    static let sizeRange = 0.06...0.6
    private static let key = "stickers"
    private static let log = Logger(subsystem: "dev.yan.islandmenu", category: "stickers")

    @Published var stickers: [Sticker] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(stickers), forKey: Self.key) }
    }

    private let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("IslandMenu/stickers")
    /// Cut-outs as saved, and the same with each sticker's current effect applied.
    private var cutouts: [UUID: CGImage] = [:]
    private var styled: [UUID: (style: StickerStyle, image: CGImage)] = [:]

    private init() {
        stickers = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Sticker].self, from: $0) } ?? []
    }

    /// The sticker's picture with its effect. The aspect ratio is that of the cut-out; effects
    /// that add a border grow the picture evenly, so the placement stays the same.
    func image(for sticker: Sticker) -> CGImage? {
        if let cached = styled[sticker.id], cached.style == sticker.style { return cached.image }
        let cutout = cutouts[sticker.id] ?? NSImage(contentsOf: fileURL(sticker.id))?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        guard let cutout else { return nil }
        cutouts[sticker.id] = cutout
        let image = StickerMaker.styled(cutout, sticker.style)
        styled[sticker.id] = (sticker.style, image)
        return image
    }

    /// Saves the picture and puts the sticker a little off-centre, clear of the logo.
    func add(_ image: CGImage) throws {
        var sticker = Sticker(aspect: Double(image.width) / Double(max(image.height, 1)))
        sticker.x = -0.28 + 0.14 * Double(stickers.count % 5)
        sticker.y = -0.22
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw StickerMaker.Failure.unreadable }
        try png.write(to: fileURL(sticker.id))
        cutouts[sticker.id] = image
        stickers.append(sticker)
    }

    func remove(_ id: UUID) {
        stickers.removeAll { $0.id == id }
        cutouts[id] = nil
        styled[id] = nil
        do { try FileManager.default.removeItem(at: fileURL(id)) } catch { Self.log.error("could not delete sticker file: \(error.localizedDescription)") }
    }

    private func fileURL(_ id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).png") }
}
