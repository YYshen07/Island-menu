import Foundation
import IOKit

// AppleSMC client. The struct layout and call sequence follow exelban/stats
// (MIT, https://github.com/exelban/stats), reduced to what fan readout and control need.
// Reading works for any user; writing only succeeds as root.

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

public final class SMC {
    private static let kernelIndex: UInt32 = 2
    private static let readBytes: UInt8 = 5
    private static let writeBytes: UInt8 = 6
    private static let readKeyInfo: UInt8 = 9
    private static let floatType = SMC.code("flt ")

    private var connection: io_connect_t = 0
    private var keyInfo: [UInt32: SMCKeyData.KeyInfo] = [:]

    public init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit {
        IOServiceClose(connection)
    }

    /// Numeric value of a key, or nil if the key is missing or not a type handled here.
    public func value(_ key: String) -> Double? {
        guard let (info, bytes) = read(key) else { return nil }
        if info.dataType == Self.floatType, info.dataSize == 4 {
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float32.self) })
        }
        return info.dataSize == 1 ? Double(bytes[0]) : nil
    }

    /// Type code and raw bytes of a key, for keys that are not plain numbers.
    public func raw(_ key: String) -> (type: String, bytes: [UInt8])? {
        guard let (info, bytes) = read(key) else { return nil }
        let type = String(bytes: withUnsafeBytes(of: info.dataType.bigEndian) { Array($0) }, encoding: .ascii) ?? "?"
        return (type, bytes)
    }

    /// Writes a 32-bit float key. Returns false if the key is missing, not a float, or the SMC refuses.
    public func write(_ key: String, float value: Float32) -> Bool {
        guard let (info, _) = read(key), info.dataType == Self.floatType, info.dataSize == 4 else { return false }
        return write(key, bytes: withUnsafeBytes(of: value) { Array($0) }, size: info.dataSize)
    }

    /// Writes a one-byte key.
    public func write(_ key: String, byte value: UInt8) -> Bool {
        guard let (info, _) = read(key), info.dataSize == 1 else { return false }
        return write(key, bytes: [value], size: info.dataSize)
    }

    private func write(_ key: String, bytes: [UInt8], size: UInt32) -> Bool {
        var input = SMCKeyData()
        input.key = Self.code(key)
        input.data8 = Self.writeBytes
        input.keyInfo.dataSize = size
        withUnsafeMutableBytes(of: &input.bytes) { $0.copyBytes(from: bytes.prefix(32)) }
        // The call can succeed at the IOKit level while the SMC itself rejects the write.
        guard let output = call(&input) else { return false }
        return output.result == 0
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
