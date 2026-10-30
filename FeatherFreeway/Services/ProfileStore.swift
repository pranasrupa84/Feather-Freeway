import Foundation
import Observation
import SwiftData

/// Errors surfaced to the interface when a purchase or selection is not possible.
enum ProfileError: LocalizedError, Equatable {
    case notEnoughCorn(needed: Int)
    case upgradeMaxed
    case breedAlreadyOwned
    case breedLocked
    case routeLocked
    case errandNotDone
    case errandAlreadyClaimed

    var errorDescription: String? {
        switch self {
        case .notEnoughCorn(let needed): "You need \(Formatters.integer(needed)) more corn."
        case .upgradeMaxed: "This part is already maxed out."
        case .breedAlreadyOwned: "This chicken already lives in your coop."
        case .breedLocked: "Welcome this chicken to the coop first."
        case .routeLocked: "Earn a star on the previous route first."
        case .errandNotDone: "Finish this errand first."
        case .errandAlreadyClaimed: "You already took this reward."
        }
    }
}

/// What a finished run changed, for the citation screen.
struct RunOutcome: Equatable, Sendable {
    let summary: RunSummary
    let reward: Int
    let starBonus: Int
    let stars: Int
    let previousStars: Int
    let isNewBestScore: Bool
    let isNewBestMeters: Bool
    let completedErrands: [String]
    let newAchievements: [String]
    let totalCorn: Int

    var newStars: Int { max(0, stars - previousStars) }
    var totalReward: Int { reward + starBonus }
}

/// Owns the profile and run history on top of SwiftData. Every mutation goes through here.
@MainActor
@Observable
final class ProfileStore {
    /// Called for every finished run so the online store can queue the result for upload.
    @ObservationIgnored var onFinishedRun: ((RunSummary) -> Void)?
    private let context: ModelContext
    let now: () -> Date

    private(set) var profile: PlayerProfile
    private(set) var recentRuns: [RunRecord] = []
    private(set) var persistenceErrorMessage: String?

    static let recentRunLimit = 25

    init(container: ModelContainer, now: @escaping () -> Date = Date.init) throws {
        self.now = now
        context = ModelContext(container)
        context.autosaveEnabled = false
        var descriptor = FetchDescriptor<PlayerProfile>(sortBy: [SortDescriptor(\.createdAt)])
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            profile = existing
        } else {
            let created = PlayerProfile()
            context.insert(created)
            profile = created
            try context.save()
        }
        try reloadRuns()
        refreshErrands()
    }

    // MARK: - Derived state

    var corn: Int { profile.corn }
    var loadout: Loadout { profile.loadout }
    var achievements: [Achievement] { AchievementCatalog.evaluate(profile.statsSnapshot) }

    func level(of kind: UpgradeKind) -> Int { profile.level(for: kind) }

    func nextCost(of kind: UpgradeKind) -> Int? { kind.cost(forLevel: profile.level(for: kind) + 1) }

    func canAfford(_ amount: Int) -> Bool { profile.corn >= amount }

    var todayKey: String { PeriodKey.day(now()) }

    var errands: [Errand] {
        ErrandBoard.errands(for: profile.errandDayKey.isEmpty ? todayKey : profile.errandDayKey).enumerated().map { slot, e in
            Errand(slot: slot, kind: e.kind, goal: e.goal, reward: e.reward,
                   progress: profile.errandProgress.indices.contains(slot) ? profile.errandProgress[slot] : 0,
                   claimed: profile.errandClaimed.indices.contains(slot) ? profile.errandClaimed[slot] : false)
        }
    }

    /// Seconds until tomorrow's errands.
    var secondsUntilNewErrands: TimeInterval {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? now()
        return tomorrow.timeIntervalSince(now())
    }

    // MARK: - Garage and coop

    func purchaseUpgrade(_ kind: UpgradeKind) throws {
        guard let cost = nextCost(of: kind) else { throw ProfileError.upgradeMaxed }
        guard canAfford(cost) else { throw ProfileError.notEnoughCorn(needed: cost - profile.corn) }
        profile.corn -= cost
        profile.setLevel(profile.level(for: kind) + 1, for: kind)
        try save()
    }

    func unlockBreed(_ breed: Breed) throws {
        guard !profile.isUnlocked(breed) else { throw ProfileError.breedAlreadyOwned }
        guard canAfford(breed.price) else { throw ProfileError.notEnoughCorn(needed: breed.price - profile.corn) }
        profile.corn -= breed.price
        profile.unlockedBreedIDs.append(breed.rawValue)
        profile.selectedBreedID = breed.rawValue
        try save()
    }

    func selectBreed(_ breed: Breed) throws {
        guard profile.isUnlocked(breed) else { throw ProfileError.breedLocked }
        profile.selectedBreedID = breed.rawValue
        try save()
    }

    func setup(for mode: RunMode, seed: UInt64) throws -> RunSetup {
        if let index = mode.routeIndex, !profile.isRouteUnlocked(index) { throw ProfileError.routeLocked }
        return RunSetup(mode: mode, seed: seed)
    }

    // MARK: - Errands

    /// Starts a fresh clipboard when the calendar day changes.
    func refreshErrands() {
        let key = todayKey
        guard profile.errandDayKey != key else { return }
        profile.errandDayKey = key
        profile.errandProgress = [0, 0, 0]
        profile.errandClaimed = [false, false, false]
        persistQuietly()
    }

    func claimErrand(_ slot: Int) throws -> Int {
        refreshErrands()
        guard let errand = errands.first(where: { $0.slot == slot }) else { throw ProfileError.errandNotDone }
        guard !errand.claimed else { throw ProfileError.errandAlreadyClaimed }
        guard errand.isDone else { throw ProfileError.errandNotDone }
        profile.errandClaimed[slot] = true
        profile.corn += errand.reward
        profile.errandsCompleted += 1
        try save()
        return errand.reward
    }

    private func advanceErrands(with summary: RunSummary, newStars: Int) -> [String] {
        refreshErrands()
        var finished: [String] = []
        for errand in errands where !errand.claimed {
            let wasDone = errand.isDone
            let value = errand.kind.value(from: summary, newStars: newStars)
            let updated = errand.kind.isBestOf ? max(errand.progress, value) : errand.progress + value
            profile.errandProgress[errand.slot] = min(errand.goal, updated)
            if !wasDone && updated >= errand.goal { finished.append(errand.title) }
        }
        return finished
    }

    // MARK: - Runs

    @discardableResult
    func recordRun(_ summary: RunSummary) -> RunOutcome {
        onFinishedRun?(summary)
        let achievedBefore = Set(achievements.filter(\.isEarned).map(\.id))
        let reward = Economy.runReward(for: summary)
        var stars = 0
        var previousStars = 0
        var starBonus = 0
        if let index = summary.mode.routeIndex, let route = RouteCatalog.route(index) {
            previousStars = profile.stars(forRoute: index)
            stars = RouteCatalog.stars(for: summary, route: route)
            if profile.routeStars.count < RouteCatalog.count {
                profile.routeStars += Array(repeating: 0, count: RouteCatalog.count - profile.routeStars.count)
            }
            if stars > previousStars {
                profile.routeStars[index] = stars
                starBonus = Economy.starBonus(newStars: stars - previousStars, routeIndex: index)
            }
        }
        let isNewBestScore = summary.mode == .endless && summary.score > profile.bestScore
        let isNewBestMeters = summary.meters > profile.bestMeters
        if summary.mode == .endless { profile.bestScore = max(profile.bestScore, summary.score) }
        profile.bestMeters = max(profile.bestMeters, summary.meters)
        profile.corn += reward + starBonus
        profile.totalRuns += 1
        profile.totalCorn += summary.corn
        profile.totalMeters += summary.meters
        profile.totalChicks += summary.chicksRescued
        profile.bestConvoy = max(profile.bestConvoy, summary.maxConvoy)
        profile.totalSmashes += summary.smashes
        profile.totalCloseCalls += summary.closeCalls
        profile.totalFlaps += summary.flaps
        profile.totalSplats += summary.splats
        profile.totalLateMerges += summary.lateMerges
        profile.totalExpressTolls += summary.expressTolls

        let errandsDone = advanceErrands(with: summary, newStars: max(0, stars - previousStars))
        context.insert(RunRecord(summary: summary, reward: reward + starBonus, stars: stars, date: now()))
        persistQuietly()
        pruneOldRuns()
        let newAchievements = achievements.filter { $0.isEarned && !achievedBefore.contains($0.id) }.map(\.title)

        return RunOutcome(
            summary: summary, reward: reward, starBonus: starBonus, stars: stars, previousStars: previousStars,
            isNewBestScore: isNewBestScore, isNewBestMeters: isNewBestMeters,
            completedErrands: errandsDone, newAchievements: newAchievements, totalCorn: profile.corn
        )
    }

    /// Deletes every run and restores the first-launch profile.
    func resetProgress() throws {
        try context.delete(model: RunRecord.self)
        context.delete(profile)
        let fresh = PlayerProfile()
        context.insert(fresh)
        profile = fresh
        refreshErrands()
        try save()
    }

    /// Grants corn without playing. Used only to seed deterministic UI-test sessions.
    func grantCorn(_ amount: Int) throws {
        profile.corn += amount
        try save()
    }

    // MARK: - Persistence

    func save() throws {
        try context.save()
        try reloadRuns()
        persistenceErrorMessage = nil
    }

    func persistQuietly() {
        do { try save() } catch { persistenceErrorMessage = "Progress could not be saved: \(error.localizedDescription)" }
    }

    private func reloadRuns() throws {
        var descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = Self.recentRunLimit
        recentRuns = try context.fetch(descriptor)
    }

    private func pruneOldRuns() {
        let descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let all = try? context.fetch(descriptor), all.count > Self.recentRunLimit else { return }
        for record in all.dropFirst(Self.recentRunLimit) { context.delete(record) }
        persistQuietly()
    }
}
