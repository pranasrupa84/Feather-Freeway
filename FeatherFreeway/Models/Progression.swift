import Foundation

/// Corn paid out for runs and route stars.
enum Economy {
    /// Corn kept after a run: everything picked up plus one per 25 m travelled.
    static func runReward(for summary: RunSummary) -> Int {
        summary.corn + summary.meters / 25
    }

    /// Bonus for stars earned on a route for the first time.
    static func starBonus(newStars: Int, routeIndex: Int) -> Int {
        newStars * (40 + routeIndex * 5)
    }
}

/// Lifetime numbers used by achievements and the Glovebox.
struct PlayerStats: Equatable, Sendable {
    var totalRuns = 0
    var totalCorn = 0
    var bestMeters = 0
    var totalSmashes = 0
    var totalCloseCalls = 0
    var totalFlaps = 0
    var totalSplats = 0
    var bestConvoy = 0
    var totalLateMerges = 0
    var totalExpressTolls = 0
    var totalStars = 0
    var unlockedBreeds = 1
}

/// The citation tickets in the Glovebox.
struct Achievement: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let goal: Int
    let progress: Int
    /// Art shown inside the medal.
    let art: String

    var isEarned: Bool { progress >= goal }
    var fraction: Double { min(1, Double(progress) / Double(max(goal, 1))) }
}

enum AchievementCatalog {
    static func evaluate(_ s: PlayerStats) -> [Achievement] {
        [
            Achievement(id: "first-trip", title: "Learner's Permit", detail: "Finish your first trip.", goal: 1, progress: s.totalRuns, art: Art.chickFace),
            Achievement(id: "corn-1000", title: "Corn Collector", detail: "Bring home 1,000 corn in total.", goal: 1000, progress: s.totalCorn, art: Art.cornIcon),
            Achievement(id: "km-club", title: "Kilometre Club", detail: "Run 1,000 m in a single trip.", goal: 1000, progress: s.bestMeters, art: Art.Sign.map),
            Achievement(id: "road-warrior", title: "Road Warrior", detail: "Smash 50 cars with the Big Rig.", goal: 50, progress: s.totalSmashes, art: Art.rig),
            Achievement(id: "close-shave", title: "Close Shave", detail: "Pull off 100 close calls.", goal: 100, progress: s.totalCloseCalls, art: Art.feather),
            Achievement(id: "frequent-flyer", title: "Frequent Flyer", detail: "Flap Hop 25 times.", goal: 25, progress: s.totalFlaps, art: Art.feather),
            Achievement(id: "egg-cellent", title: "Egg-cellent Aim", detail: "Splat 20 windscreens.", goal: 20, progress: s.totalSplats, art: Art.egg),
            Achievement(id: "mother-hen", title: "Mother Hen", detail: "Lead a convoy of 6 chicks.", goal: 6, progress: s.bestConvoy, art: Art.chickFace),
            Achievement(id: "merge-master", title: "Merge Master", detail: "Late merge 10 times.", goal: 10, progress: s.totalLateMerges, art: Art.signLaneEnds),
            Achievement(id: "express-lane", title: "Express Lane", detail: "Pass 5 Express toll gates.", goal: 5, progress: s.totalExpressTolls, art: Art.eggGolden),
            Achievement(id: "route-rookie", title: "Route Rookie", detail: "Collect 15 route stars.", goal: 15, progress: s.totalStars, art: Art.starFull),
            Achievement(id: "full-coop", title: "Full Coop", detail: "Welcome every chicken to the Coop.", goal: Breed.allCases.count, progress: s.unlockedBreeds, art: Art.portrait(.zippy)),
        ]
    }
}

/// Kinds of daily errands on the clipboard.
enum ErrandKind: String, CaseIterable, Codable, Sendable {
    case meters, corn, smashes, closeCalls, chicks, splats, lateMerges, flaps, stars

    func title(goal: Int) -> String {
        switch self {
        case .meters: "Run \(Formatters.meters(goal)) in one trip"
        case .corn: "Collect \(goal) corn"
        case .smashes: "Smash \(goal) cars in the Big Rig"
        case .closeCalls: "Make \(goal) close calls"
        case .chicks: "Rescue \(goal) chicks"
        case .splats: "Splat \(goal) cars with eggs"
        case .lateMerges: "Late merge \(goal) times"
        case .flaps: "Flap Hop \(goal) times"
        case .stars: "Earn \(goal) route stars"
        }
    }

    var goals: [Int] {
        switch self {
        case .meters: [600, 900, 1300]
        case .corn: [120, 220, 350]
        case .smashes: [8, 15, 25]
        case .closeCalls: [10, 18, 30]
        case .chicks: [6, 10, 16]
        case .splats: [3, 6, 10]
        case .lateMerges: [2, 4, 6]
        case .flaps: [3, 6, 10]
        case .stars: [2, 4, 6]
        }
    }

    /// Progress a single run adds. `meters` is "best in one trip", the rest accumulate.
    func value(from summary: RunSummary, newStars: Int) -> Int {
        switch self {
        case .meters: summary.meters
        case .corn: summary.corn
        case .smashes: summary.smashes
        case .closeCalls: summary.closeCalls
        case .chicks: summary.chicksRescued
        case .splats: summary.splats
        case .lateMerges: summary.lateMerges
        case .flaps: summary.flaps
        case .stars: newStars
        }
    }

    var isBestOf: Bool { self == .meters }
}

struct Errand: Identifiable, Equatable, Sendable {
    let slot: Int
    let kind: ErrandKind
    let goal: Int
    let reward: Int
    var progress: Int
    var claimed: Bool

    var id: Int { slot }
    var title: String { kind.title(goal: goal) }
    var isDone: Bool { progress >= goal }
}

enum ErrandBoard {
    /// Three distinct errands for a calendar day.
    static func errands(for dayKey: String) -> [(kind: ErrandKind, goal: Int, reward: Int)] {
        var rng = SeededGenerator(seed: PeriodKey.seed("errands-" + dayKey))
        var kinds = ErrandKind.allCases
        kinds.shuffle(using: &rng)
        return (0..<3).map { slot in
            let kind = kinds[slot]
            let tier = Int.random(in: 0..<3, using: &rng)
            return (kind, kind.goals[tier], 60 + tier * 45)
        }
    }
}
