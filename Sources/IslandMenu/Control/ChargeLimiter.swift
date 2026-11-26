import Foundation
import ObjectiveC

enum BatteryMode: Hashable {
    /// macOS decides; no limit set.
    case auto
    /// Stop charging at the configured limit.
    case care
    /// The limit is set but lifted for this charge.
    case full
}

/// macOS's own manual charge limit, reached through PowerUI's `PowerUISmartChargeClient` (private
/// API, no root needed). The system enforces the limit itself, so nothing here has to keep running.
@MainActor
final class ChargeLimiter: ObservableObject {
    static let shared = ChargeLimiter()
    private static let noLimit = 100
    private static let enabledState: UInt64 = 1

    private typealias ErrorOut = UnsafeMutablePointer<NSError?>
    private typealias ReadByte = @convention(c) (AnyObject, Selector, ErrorOut) -> UInt8
    private typealias ReadWord = @convention(c) (AnyObject, Selector, ErrorOut) -> UInt64
    private typealias ReadObject = @convention(c) (AnyObject, Selector, ErrorOut) -> Unmanaged<AnyObject>?
    private typealias WriteByte = @convention(c) (AnyObject, Selector, UInt8, ErrorOut) -> Bool
    private typealias Action = @convention(c) (AnyObject, Selector, ErrorOut) -> Bool
    private typealias Flag = @convention(c) (AnyObject, Selector) -> Bool

    private let client: NSObject?
    @Published private(set) var mode = BatteryMode.auto
    @Published private(set) var availableLimits: [Int] = []
    @Published private(set) var lastError: String?

    private init() {
        client = Self.makeClient()
        refresh()
    }

    private static func makeClient() -> NSObject? {
        guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW) != nil,
              let type = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type,
              type.instancesRespond(to: NSSelectorFromString("setMCLLimit:error:")) else { return nil }
        let allocated = type.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
        return allocated?.perform(NSSelectorFromString("initWithClientName:"), with: "IslandMenu")?.takeUnretainedValue() as? NSObject
    }

    private func function<T>(_ name: String, as type: T.Type) -> (T, Selector)? {
        let selector = NSSelectorFromString(name)
        guard let client, client.responds(to: selector) else { return nil }
        return (unsafeBitCast(client.method(for: selector), to: type), selector)
    }

    var isSupported: Bool {
        guard let client, let (supported, selector) = function("isMCLSupported", as: Flag.self) else { return false }
        return supported(client, selector)
    }

    /// Re-reads the limit from the system, which is the source of truth for the mode.
    func refresh() {
        guard let client, isSupported else { return }
        var error: NSError?
        if let (read, selector) = function("availableChargeLimitsWithError:", as: ReadObject.self),
           let limits = read(client, selector, &error)?.takeUnretainedValue() as? [NSNumber] {
            availableLimits = limits.map(\.intValue).filter { $0 < Self.noLimit }.sorted()
        }
        guard let (readLimit, limitSelector) = function("getMCLLimitWithError:", as: ReadByte.self) else { return }
        let limit = Int(readLimit(client, limitSelector, &error))
        var state = Self.enabledState
        if let (readState, stateSelector) = function("isMCLCurrentlyEnabled:", as: ReadWord.self) {
            state = readState(client, stateSelector, &error)
        }
        mode = limit >= Self.noLimit ? .auto : (state == Self.enabledState ? .care : .full)
    }

    func apply(_ mode: BatteryMode, limit: Int) {
        guard let client else { return }
        var error: NSError?
        var succeeded = false
        switch mode {
        case .auto, .care:
            guard let (write, selector) = function("setMCLLimit:error:", as: WriteByte.self) else { return }
            succeeded = write(client, selector, UInt8(mode == .auto ? Self.noLimit : limit), &error)
        case .full:
            // Only meaningful on top of a limit, so make sure one is set first.
            if self.mode == .auto, let (write, selector) = function("setMCLLimit:error:", as: WriteByte.self) {
                _ = write(client, selector, UInt8(limit), &error)
            }
            guard let (lift, selector) = function("temporarilyDisableMCL:", as: Action.self) else { return }
            succeeded = lift(client, selector, &error)
        }
        lastError = succeeded ? nil : (error?.localizedDescription ?? "系统拒绝了这次更改")
        refresh()
    }
}
