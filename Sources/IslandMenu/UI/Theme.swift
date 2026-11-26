import SwiftUI

enum Theme {
    static let primary = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.68)
    static let tertiary = Color.white.opacity(0.5)
    static let hairline = Color.white.opacity(0.08)
    static let track = Color.white.opacity(0.1)
    static let heat = Color(red: 1, green: 0.62, blue: 0.04)
    static let live = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let padding: CGFloat = 20
    static let cardRadius: CGFloat = 30
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.86)
}

enum Format {
    static func gigabytes(_ bytes: UInt64, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", Double(bytes) / 1_073_741_824)
    }

    static func decimalGigabytes(_ bytes: UInt64) -> String {
        String(format: "%.0f", Double(bytes) / 1_000_000_000)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let megabytes = bytesPerSecond / 1_000_000
        return megabytes >= 1 ? String(format: "%.1f MB/s", megabytes) : String(format: "%.0f KB/s", bytesPerSecond / 1000)
    }

    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let (days, hours) = (minutes / 1440, minutes % 1440 / 60)
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        return hours > 0 ? "\(hours) 小时 \(minutes % 60) 分" : "\(minutes) 分"
    }

    static func degrees(_ value: Double?) -> String { value.map { "\(Int($0.rounded()))°" } ?? "—" }
}

extension Text {
    /// Section name: the anchor the eye lands on first in each block.
    func title() -> some View { font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primary) }
    /// Caption under a value or a control.
    func label() -> some View { font(.system(size: 11)).foregroundStyle(Theme.tertiary) }
    func value() -> some View { font(.system(size: 14, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.primary) }
    func detail() -> some View { font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.secondary).lineLimit(1) }
}
