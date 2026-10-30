import Foundation
import SwiftData

/// The single persistent profile: corn, garage, coop, route stars, errands and lifetime stats.
@Model
final class PlayerProfile {
    var corn: Int = 0

    var rigTimeLevel: Int = 0
    var magnetTimeLevel: Int = 0
    var doubleTimeLevel: Int = 0
    var featherFillLevel: Int = 0
    var eggCartonLevel: Int = 0
    var convoyCapLevel: Int = 0

    var unlockedBreedIDs: [String] = [Breed.starter.rawValue]
    var selectedBreedID: String = Breed.starter.rawValue

    /// Stars per route index (0...3).
    var routeStars: [Int] = []

    var bestScore: Int = 0
    var bestMeters: Int = 0
    var totalRuns: Int = 0
    var totalCorn: Int = 0
    var totalMeters: Int = 0
    var totalChicks: Int = 0
    var bestConvoy: Int = 0
    var totalSmashes: Int = 0
    var totalCloseCalls: Int = 0
    var totalFlaps: Int = 0
    var totalSplats: Int = 0
    var totalLateMerges: Int = 0
    var totalExpressTolls: Int = 0

    var errandDayKey: String = ""
    var errandProgress: [Int] = [0, 0, 0]
    var errandClaimed: [Bool] = [false, false, false]
    var errandsCompleted: Int = 0

    var createdAt: Date = Date.now

    init() {}

    // MARK: - Derived values

    var selectedBreed: Breed { Breed(rawValue: selectedBreedID) ?? .starter }

    func isUnlocked(_ breed: Breed) -> Bool {
        breed.price == 0 || unlockedBreedIDs.contains(breed.rawValue)
    }

    func level(for kind: UpgradeKind) -> Int {
        switch kind {
        case .rigTime: rigTimeLevel
        case .magnetTime: magnetTimeLevel
        case .doubleTime: doubleTimeLevel
        case .featherFill: featherFillLevel
        case .eggCarton: eggCartonLevel
        case .convoyCap: convoyCapLevel
        }
    }

    func setLevel(_ level: Int, for kind: UpgradeKind) {
        switch kind {
        case .rigTime: rigTimeLevel = level
        case .magnetTime: magnetTimeLevel = level
        case .doubleTime: doubleTimeLevel = level
        case .featherFill: featherFillLevel = level
        case .eggCarton: eggCartonLevel = level
        case .convoyCap: convoyCapLevel = level
        }
    }

    func stars(forRoute index: Int) -> Int {
        routeStars.indices.contains(index) ? routeStars[index] : 0
    }

    /// Routes unlock one after another: the next one opens when the previous has a star.
    func isRouteUnlocked(_ index: Int) -> Bool {
        index == 0 || stars(forRoute: index - 1) > 0
    }

    var totalStars: Int { routeStars.reduce(0, +) }

    /// First route without a star (or the last one).
    var nextRouteIndex: Int {
        (0..<RouteCatalog.count).first { stars(forRoute: $0) == 0 } ?? RouteCatalog.count - 1
    }

    var loadout: Loadout {
        Loadout(levels: Dictionary(uniqueKeysWithValues: UpgradeKind.allCases.map { ($0, level(for: $0)) }), breed: selectedBreed)
    }

    var statsSnapshot: PlayerStats {
        PlayerStats(
            totalRuns: totalRuns,
            totalCorn: totalCorn,
            bestMeters: bestMeters,
            totalSmashes: totalSmashes,
            totalCloseCalls: totalCloseCalls,
            totalFlaps: totalFlaps,
            totalSplats: totalSplats,
            bestConvoy: bestConvoy,
            totalLateMerges: totalLateMerges,
            totalExpressTolls: totalExpressTolls,
            totalStars: totalStars,
            unlockedBreeds: Breed.allCases.filter { isUnlocked($0) }.count
        )
    }
}

/// One finished trip, for the Glovebox log.
@Model
final class RunRecord {
    var date: Date = Date.now
    var modeKey: String = "endless"
    var routeIndex: Int = -1
    var breedID: String = Breed.starter.rawValue
    var resultRaw: String = RunResult.crashed.rawValue
    var score: Int = 0
    var meters: Int = 0
    var corn: Int = 0
    var reward: Int = 0
    var stars: Int = 0

    init(summary: RunSummary, reward: Int, stars: Int, date: Date = .now) {
        self.date = date
        modeKey = summary.mode.storageKey
        routeIndex = summary.mode.routeIndex ?? -1
        breedID = summary.breed.rawValue
        resultRaw = summary.result.rawValue
        score = summary.score
        meters = summary.meters
        corn = summary.corn
        self.reward = reward
        self.stars = stars
    }

    var result: RunResult { RunResult(rawValue: resultRaw) ?? .crashed }
    var breed: Breed { Breed(rawValue: breedID) ?? .starter }
    var route: Route? { RouteCatalog.route(routeIndex) }
}
