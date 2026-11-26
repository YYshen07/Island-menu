import CoreGraphics
import Foundation
import os

/// One row per calendar day: seconds the user was active and boot-volume bytes in use.
struct DayRecord: Codable {
    var active: TimeInterval = 0
    var diskUsed: UInt64 = 0
}

/// Long-term history, kept as a small JSON file. Runs on a slow timer even while the card is closed.
final class ActivityStore {
    static let tickInterval: TimeInterval = 60
    private static let saveEvery = 5
    private static let logger = Logger(subsystem: "dev.yan.islandmenu", category: "activity")
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private(set) var days: [String: DayRecord] = [:]
    private var ticksSinceSave = 0
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = base.appendingPathComponent("IslandMenu/history.json")
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            days = try JSONDecoder().decode([String: DayRecord].self, from: data)
        } catch {
            Self.logger.error("history unreadable: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func key(for date: Date) -> String { dayFormatter.string(from: date) }

    /// Credits one interval of activity if there was any input during it.
    func tick(diskUsed: UInt64) {
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        var record = days[Self.key(for: Date()), default: DayRecord()]
        if idle < Self.tickInterval { record.active += Self.tickInterval }
        if diskUsed > 0 { record.diskUsed = diskUsed }
        days[Self.key(for: Date())] = record
        ticksSinceSave += 1
        if ticksSinceSave >= Self.saveEvery { save() }
    }

    func save() {
        ticksSinceSave = 0
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(days).write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("history save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
