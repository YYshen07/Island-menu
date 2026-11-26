import Foundation
import IOKit

// Read-only AppleSMC client. The struct layout and call sequence follow exelban/stats
// (MIT, https://github.com/exelban/stats), reduced to what fan readout needs.

private struct SMCKeyData {
    typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct LimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = Version()
    var pLimitData = LimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

final class SMC {
    private static let kernelIndex: UInt32 = 2
    private static let readBytes: UInt8 = 5
    private static let readKeyInfo: UInt8 = 9
    private static let floatType = SMC.code("flt ")

    private var connection: io_connect_t = 0
    private var keyInfo: [UInt32: SMCKeyData.KeyInfo] = [:]

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit {
        IOServiceClose(connection)
    }

    /// Numeric value of a key, or nil if the key is missing or not a type handled here.
    func value(_ key: String) -> Double? {
        guard let (info, bytes) = read(key) else { return nil }
        if info.dataType == Self.floatType, info.dataSize == 4 {
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float32.self) })
        }
        return info.dataSize == 1 ? Double(bytes[0]) : nil
    }

    private func read(_ key: String) -> (SMCKeyData.KeyInfo, [UInt8])? {
        var input = SMCKeyData()
        input.key = Self.code(key)
        let info: SMCKeyData.KeyInfo
        if let cached = keyInfo[input.key] {
            info = cached
        } else {
            input.data8 = Self.readKeyInfo
            guard let output = call(&input), output.result == 0, output.keyInfo.dataSize > 0 else { return nil }
            info = output.keyInfo
            keyInfo[input.key] = info
        }
        input.keyInfo.dataSize = info.dataSize
        input.data8 = Self.readBytes
        guard let output = call(&input), output.result == 0 else { return nil }
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(info.dataSize))) }
        return (info, bytes)
    }

    private func call(_ input: inout SMCKeyData) -> SMCKeyData? {
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let status = IOConnectCallStructMethod(connection, Self.kernelIndex, &input, MemoryLayout<SMCKeyData>.stride, &output, &outputSize)
        return status == kIOReturnSuccess ? output : nil
    }

    private static func code(_ key: String) -> UInt32 {
        key.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }
}

struct FanSnapshot {
    var rpm = 0.0
    var minimum = 0.0
    var maximum = 0.0
    /// 0 at rest, 1 at the fan's rated maximum.
    var level: Double { maximum > 0 ? min(max(rpm / maximum, 0), 1) : 0 }
}

final class FanSampler {
    private let smc = SMC()
    private lazy var count = Int(smc?.value("FNum") ?? 0)

    func sample() -> [FanSnapshot] {
        guard let smc else { return [] }
        return (0..<count).map { index in
            FanSnapshot(rpm: smc.value("F\(index)Ac") ?? 0, minimum: smc.value("F\(index)Mn") ?? 0, maximum: smc.value("F\(index)Mx") ?? 0)
        }
    }
}
