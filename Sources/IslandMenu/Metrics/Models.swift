import Foundation

struct CPUSnapshot {
    /// Per-core load 0...1, Super cores first.
    var cores: [Double] = []
    var superCount = 0
    var user = 0.0
    var system = 0.0
    var load = 0.0
    var total: Double { user + system }
}

struct MemorySnapshot {
    var total: UInt64 = 0
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var swapUsed: UInt64 = 0
    var pressure = 1
    var used: UInt64 { app + wired + compressed }
}

struct DiskSnapshot {
    var total: UInt64 = 0
    var used: UInt64 = 0
    var readRate = 0.0
    var writeRate = 0.0
}

struct NetworkInterface: Identifiable {
    var id: String { name }
    var name: String
    var detail: String
}

struct NetworkSnapshot {
    var down = 0.0
    var up = 0.0
    var interfaces: [NetworkInterface] = []
    var publicIP: String?
}

struct BatterySnapshot {
    var present = false
    var percent = 0
    var cycles = 0
    var health: Int?
    var charging = false
    var external = false
    var adapterWatts: Int?
    /// Power drawn from the adapter right now, in watts; nil on battery or when the Mac does not report it.
    var inputPower: Double?
    /// What the whole machine is consuming, in watts.
    var systemPower: Double?
    /// Power into the battery in watts: positive while charging, negative while discharging.
    var batteryPower: Double?
}

struct GPUSnapshot {
    var usage = 0.0
    var memoryUsed: UInt64 = 0
    var memoryFraction = 0.0
    var temperature: Double?
}

struct ThermalSnapshot {
    /// Hottest and mean SoC die sensors, in °C.
    var dieMax: Double?
    var dieMean: Double?
    var ssd: Double?
    var battery: Double?
}

struct ProcessRow: Identifiable {
    var id: Int32
    var name: String
    var cpu: Double
    var memory: UInt64
}

struct Snapshot {
    var cpu = CPUSnapshot()
    var memory = MemorySnapshot()
    var disk = DiskSnapshot()
    var network = NetworkSnapshot()
    var battery = BatterySnapshot()
    var gpu = GPUSnapshot()
    var thermal = ThermalSnapshot()
    var fans: [FanSnapshot] = []
    var processes: [ProcessRow] = []
    var bootTime = Date()
}

/// Fixed-length history for sparklines.
struct Ring {
    private(set) var values: [Double]

    init(count: Int) {
        values = Array(repeating: 0, count: count)
    }

    mutating func push(_ value: Double) {
        values.removeFirst()
        values.append(value)
    }
}

enum Sysctl {
    static func value<T>(_ name: String, as type: T.Type) -> T? {
        var size = MemoryLayout<T>.size
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard sysctlbyname(name, pointer, &size, nil, 0) == 0 else { return nil }
        return pointer.pointee
    }
}
