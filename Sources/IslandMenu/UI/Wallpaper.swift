import AppKit
import AVFoundation

/// The desktop picture as it is actually shown. `NSWorkspace.desktopImageURL` only knows about
/// plain picture files: with an aerial (video) wallpaper it reports the system's default image
/// instead. The wallpaper service's own store says what is really set, so that is read first.
@MainActor
enum Wallpaper {
    private static let store = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("com.apple.wallpaper")
    private static let aerialProvider = "com.apple.wallpaper.choice.aerials"
    private static let imageProvider = "com.apple.wallpaper.choice.image"
    private static let frameSize = CGSize(width: 1600, height: 1600)

    static func currentImage() -> CGImage? {
        if let choice = currentChoice(), let image = image(for: choice) { return image }
        guard let screen = NSScreen.builtIn ?? NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return picture(at: url)
    }

    /// The first desktop choice in the store: the one for all displays, else a per-display one,
    /// else the system default.
    private static func currentChoice() -> [String: Any]? {
        guard let data = try? Data(contentsOf: store.appendingPathComponent("Store/Index.plist")),
              let index = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        let perDisplay = (index["Displays"] as? [String: Any])?.values.first
        let entries = [index["AllSpacesAndDisplays"], perDisplay, index["SystemDefault"]]
        for case let entry as [String: Any] in entries {
            let content = (entry["Desktop"] as? [String: Any])?["Content"] as? [String: Any]
            if let choice = (content?["Choices"] as? [[String: Any]])?.first { return choice }
        }
        return nil
    }

    private static func image(for choice: [String: Any]) -> CGImage? {
        switch choice["Provider"] as? String {
        case aerialProvider:
            guard let data = choice["Configuration"] as? Data,
                  let configuration = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let asset = configuration["assetID"] as? String else { return nil }
            return videoFrame(at: store.appendingPathComponent("aerials/videos/\(asset).mov"))
                ?? picture(at: store.appendingPathComponent("aerials/thumbnails/\(asset).png"))
        case imageProvider:
            let file = (choice["Files"] as? [[String: Any]])?.first?["relative"] as? String
            return file.flatMap(URL.init(string:)).flatMap(picture)
        default:
            return nil
        }
    }

    private static func picture(at url: URL) -> CGImage? {
        NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// The opening frame of an aerial, which is what the desktop shows while the video is at rest.
    private static func videoFrame(at url: URL) -> CGImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = frameSize
        return try? generator.copyCGImage(at: .zero, actualTime: nil)
    }
}
