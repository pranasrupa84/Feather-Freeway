import Foundation

/// Garage parts. Each has five levels bought with corn.
enum UpgradeKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case rigTime, magnetTime, doubleTime, featherFill, eggCarton, convoyCap

    static let maxLevel = 5
    private static let costs = [150, 350, 700, 1200, 2000]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rigTime: "Big Rig Tank"
        case .magnetTime: "Corn Magnet"
        case .doubleTime: "Double Corn"
        case .featherFill: "Feather Gauge"
        case .eggCarton: "Egg Carton"
        case .convoyCap: "Convoy Whistle"
        }
    }

    var detail: String {
        switch self {
        case .rigTime: "A bigger fuel tank keeps the Big Rig on the road longer."
        case .magnetTime: "The corn magnet pulls kernels for longer."
        case .doubleTime: "Double Corn lasts longer."
        case .featherFill: "Close calls fill the feather meter faster, so you Flap Hop sooner."
        case .eggCarton: "Carry more eggs for Egg Splat."
        case .convoyCap: "More lost chicks can follow you at once."
        }
    }

    /// Cost of reaching `level` (1...5), or `nil` past the maximum.
    func cost(forLevel level: Int) -> Int? {
        guard (1...Self.maxLevel).contains(level) else { return nil }
        return Self.costs[level - 1]
    }

    /// Human-readable effect at a level, e.g. "8 s".
    func effectLabel(level: Int) -> String {
        let stats = Loadout.Stats(levels: [self: level])
        switch self {
        case .rigTime: return "\(Int(stats.rigDuration)) s ride"
        case .magnetTime: return "\(Int(stats.magnetDuration)) s pull"
        case .doubleTime: return "\(Int(stats.doubleDuration)) s boost"
        case .featherFill: return "\(Int(stats.closeCallValue * 100 + 0.5))% per close call"
        case .eggCarton: return "\(stats.maxEggs) eggs"
        case .convoyCap: return "\(stats.convoyCap) chicks"
        }
    }
}

/// Everything the player brings to a run: garage levels and the chosen chicken.
struct Loadout: Equatable, Sendable {
    var levels: [UpgradeKind: Int]
    var breed: Breed

    static let base = Loadout(levels: [:], breed: .starter)

    struct Stats: Equatable, Sendable {
        var rigDuration: Double
        var magnetDuration: Double
        var doubleDuration: Double
        var closeCallValue: Double
        var maxEggs: Int
        var convoyCap: Int

        init(levels: [UpgradeKind: Int]) {
            func lv(_ k: UpgradeKind) -> Int { min(UpgradeKind.maxLevel, max(0, levels[k] ?? 0)) }
            rigDuration = 6 + Double(lv(.rigTime))
            magnetDuration = 8 + 2 * Double(lv(.magnetTime))
            doubleDuration = 10 + 2 * Double(lv(.doubleTime))
            closeCallValue = 0.2 * (1 + 0.15 * Double(lv(.featherFill)))
            maxEggs = 3 + lv(.eggCarton)
            convoyCap = 5 + lv(.convoyCap)
        }
    }

    var stats: Stats { Stats(levels: levels) }
}
