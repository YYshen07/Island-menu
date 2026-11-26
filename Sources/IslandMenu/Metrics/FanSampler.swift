import IslandShared

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
