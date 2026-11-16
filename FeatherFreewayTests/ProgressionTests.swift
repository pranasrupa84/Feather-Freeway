import Foundation
import SwiftData
import Testing
@testable import FeatherFreeway

@MainActor
@Suite("Road plan")
struct RoadPlanTests {
    @Test func routePlanSpreadsTheLanePatternAndEndsAtTheFinish() throws {
        let route = try #require(RouteCatalog.route(5))
        let plan = RoadPlan(route: route)
        #expect(plan.finishY == Double(route.meters) * RoadGeometry.unitsPerMeter)
        #expect(plan.segments.map(\.lanes) == route.lanePattern)
        #expect(plan.segments.allSatisfy { $0.startY.truncatingRemainder(dividingBy: RoadGeometry.chunk) == 0 })
        #expect(plan.closures.count == route.lanePattern.indices.dropFirst().filter { route.lanePattern[$0] < route.lanePattern[$0 - 1] }.count)
    }

    @Test func routesWithoutLaneShiftKeepOneWidth() throws {
        let plan = RoadPlan(route: try #require(RouteCatalog.route(0)))
        #expect(plan.segments.count == 1)
        #expect(plan.closures.isEmpty)
    }

    @Test func endlessPlanCyclesWorldsAndStaysInTheirLaneRanges() {
        var plan = RoadPlan(endlessSeed: 1234)
        plan.extend(to: RoadGeometry.worldLength * 5)
        #expect(plan.world(at: 100) == .farm)
        #expect(plan.world(at: RoadGeometry.worldLength + 100) == .suburb)
        #expect(plan.world(at: RoadGeometry.worldLength * 2 + 100) == .downtown)
        #expect(plan.world(at: RoadGeometry.worldLength * 3 + 100) == .night)
        #expect(plan.world(at: RoadGeometry.worldLength * 4 + 100) == .farm)
        for s in plan.segments.dropFirst() {
            #expect(s.world.laneRange.contains(s.lanes))
            #expect(s.startY.truncatingRemainder(dividingBy: RoadGeometry.chunk) == 0)
        }
        #expect(plan.tollYs.count >= 4)
        for t in plan.tollYs {
            #expect(!plan.closures.contains { abs($0.y - t) < 400 }, "toll plazas sit on a steady road")
        }
        #expect(Set(plan.segments.map(\.lanes)).count >= 3, "the endless road changes width")
    }

    @Test func routeCatalogIntroducesMechanicsGradually() {
        #expect(RouteCatalog.count == 30)
        #expect(RouteCatalog.routes[0].mechanics.isEmpty)
        #expect(RouteCatalog.routes.last?.mechanics == .all)
        for i in 1..<RouteCatalog.count {
            #expect(RouteCatalog.routes[i].mechanics.isSuperset(of: RouteCatalog.routes[i - 1].mechanics) || RouteCatalog.routes[i - 1].mechanics == .all)
        }
    }

    @Test func routeStars() throws {
        let route = try #require(RouteCatalog.route(2)) // chicks(3), corn 40
        #expect(RouteCatalog.stars(for: Fixtures.summary(mode: .route(2), result: .crashed, corn: 999), route: route) == 0)
        #expect(RouteCatalog.stars(for: Fixtures.summary(mode: .route(2), result: .cleared, corn: 10), route: route) == 1)
        #expect(RouteCatalog.stars(for: Fixtures.summary(mode: .route(2), result: .cleared, corn: 40), route: route) == 2)
        #expect(RouteCatalog.stars(for: Fixtures.summary(mode: .route(2), result: .cleared, corn: 40, finalChicks: 3), route: route) == 3)
        let noBump = try #require(RouteCatalog.route(0))
        #expect(RouteCatalog.stars(for: Fixtures.summary(mode: .route(0), result: .cleared, corn: 0, bumps: 0), route: noBump) == 2)
    }
}

@MainActor
@Suite("Profile store")
struct ProfileStoreTests {
    @Test func buyingUpgradesSpendsCornUntilMaxed() throws {
        let (store, _) = try Fixtures.store()
        #expect(throws: ProfileError.notEnoughCorn(needed: 150)) { try store.purchaseUpgrade(.rigTime) }
        try store.grantCorn(10_000)
        for _ in 0..<UpgradeKind.maxLevel { try store.purchaseUpgrade(.rigTime) }
        #expect(store.level(of: .rigTime) == 5)
        #expect(store.corn == 10_000 - (150 + 350 + 700 + 1200 + 2000))
        #expect(throws: ProfileError.upgradeMaxed) { try store.purchaseUpgrade(.rigTime) }
        #expect(store.loadout.stats.rigDuration == 11)
    }

    @Test func unlockingAndSelectingChickens() throws {
        let (store, _) = try Fixtures.store()
        #expect(throws: ProfileError.breedLocked) { try store.selectBreed(.pip) }
        #expect(throws: ProfileError.notEnoughCorn(needed: 600)) { try store.unlockBreed(.pip) }
        try store.grantCorn(700)
        try store.unlockBreed(.pip)
        #expect(store.profile.selectedBreed == .pip)
        #expect(store.corn == 100)
        #expect(throws: ProfileError.breedAlreadyOwned) { try store.unlockBreed(.pip) }
        try store.selectBreed(.clover)
        #expect(store.loadout.breed == .clover)
    }

    @Test func recordingAnEndlessRunPaysAndTracksBests() throws {
        let (store, _) = try Fixtures.store()
        let outcome = store.recordRun(Fixtures.summary(score: 4200, meters: 750, corn: 60, smashes: 3))
        #expect(outcome.reward == 60 + 30)
        #expect(outcome.isNewBestScore)
        #expect(store.corn == 90)
        #expect(store.profile.bestScore == 4200)
        #expect(store.profile.bestMeters == 750)
        #expect(store.profile.totalSmashes == 3)
        #expect(store.recentRuns.count == 1)
        let second = store.recordRun(Fixtures.summary(score: 100, meters: 50, corn: 1))
        #expect(!second.isNewBestScore)
        #expect(store.profile.bestScore == 4200)
    }

    @Test func routeStarsPayOnceAndUnlockTheNextRoute() throws {
        let (store, _) = try Fixtures.store()
        #expect(!store.profile.isRouteUnlocked(1))
        #expect(throws: ProfileError.routeLocked) { _ = try store.setup(for: .route(1), seed: 1) }
        let cleared = Fixtures.summary(mode: .route(0), result: .cleared, corn: 30, bumps: 0)
        let first = store.recordRun(cleared)
        #expect(first.stars == 3)
        #expect(first.newStars == 3)
        #expect(first.starBonus == Economy.starBonus(newStars: 3, routeIndex: 0))
        #expect(store.profile.isRouteUnlocked(1))
        #expect(store.profile.nextRouteIndex == 1)
        let again = store.recordRun(cleared)
        #expect(again.newStars == 0)
        #expect(again.starBonus == 0)
        #expect(store.profile.totalStars == 3)
    }

    @Test func errandsTrackProgressAndPayWhenClaimed() throws {
        let (store, _) = try Fixtures.store()
        let errands = store.errands
        #expect(errands.count == 3)
        #expect(Set(errands.map(\.kind)).count == 3)
        #expect(throws: ProfileError.errandNotDone) { _ = try store.claimErrand(0) }
        // A huge run finishes every errand except possibly route stars.
        let big = RunSummary(mode: .endless, result: .crashed, breed: .clover, score: 99_999, meters: 5000, corn: 999,
                             chicksRescued: 99, finalChicks: 0, maxConvoy: 9, smashes: 99, closeCalls: 99, flaps: 99,
                             splats: 99, lateMerges: 99, expressTolls: 9, bumps: 1, duration: 300, furthestWorld: .night)
        store.recordRun(big)
        for errand in store.errands where errand.kind != .stars {
            #expect(errand.isDone)
            let before = store.corn
            let reward = try store.claimErrand(errand.slot)
            #expect(store.corn == before + reward)
            #expect(throws: ProfileError.errandAlreadyClaimed) { _ = try store.claimErrand(errand.slot) }
        }
    }

    @Test func errandsAreStableForADayAndChangeTheNext() {
        let a = ErrandBoard.errands(for: "2026-10-28").map(\.kind)
        let b = ErrandBoard.errands(for: "2026-10-28").map(\.kind)
        #expect(a == b)
        let week = (1...7).map { ErrandBoard.errands(for: "2026-11-0\($0)").map(\.kind) }
        #expect(Set(week.map { $0.map(\.rawValue).joined() }).count > 1)
    }

    @Test func progressSurvivesANewStoreOnTheSameContainer() throws {
        let (store, container) = try Fixtures.store()
        try store.grantCorn(1000)
        try store.purchaseUpgrade(.eggCarton)
        store.recordRun(Fixtures.summary())
        let reopened = try ProfileStore(container: container)
        #expect(reopened.level(of: .eggCarton) == 1)
        #expect(reopened.recentRuns.count == 1)
        #expect(reopened.corn == store.corn)
    }

    @Test func resetRestoresAFreshProfile() throws {
        let (store, _) = try Fixtures.store()
        try store.grantCorn(5000)
        try store.unlockBreed(.zippy)
        store.recordRun(Fixtures.summary())
        try store.resetProgress()
        #expect(store.corn == 0)
        #expect(store.profile.selectedBreed == .clover)
        #expect(store.recentRuns.isEmpty)
        #expect(!store.profile.isUnlocked(.zippy))
    }

    @Test func tripLogIsTrimmed() throws {
        let (store, _) = try Fixtures.store()
        for _ in 0..<(ProfileStore.recentRunLimit + 5) { store.recordRun(Fixtures.summary(score: 1, meters: 1, corn: 0)) }
        #expect(store.recentRuns.count == ProfileStore.recentRunLimit)
        #expect(store.profile.totalRuns == ProfileStore.recentRunLimit + 5)
    }

    @Test func achievementsUnlockFromLifetimeStats() throws {
        let (store, _) = try Fixtures.store()
        #expect(store.achievements.filter(\.isEarned).isEmpty)
        let outcome = store.recordRun(Fixtures.summary(meters: 1200, corn: 10, smashes: 50))
        let earned = Set(store.achievements.filter(\.isEarned).map(\.id))
        #expect(earned.isSuperset(of: ["first-trip", "km-club", "road-warrior"]))
        #expect(outcome.newAchievements.contains("Road Warrior"))
        #expect(store.achievements.count == 12)
    }
}

@MainActor
@Suite("Settings and economy")
struct SettingsAndEconomyTests {
    @Test func settingsPersistInDefaults() throws {
        let name = "ff.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let a = SettingsStore(defaults: defaults)
        #expect(a.soundEnabled && a.musicEnabled && a.hapticsEnabled)
        #expect(!a.hasSeenGuide && !a.leftHanded)
        a.musicEnabled = false
        a.leftHanded = true
        a.hasSeenGuide = true
        let b = SettingsStore(defaults: defaults)
        #expect(!b.musicEnabled)
        #expect(b.leftHanded)
        #expect(b.hasSeenGuide)
    }

    @Test func upgradeStatsAndCosts() {
        #expect(UpgradeKind.rigTime.cost(forLevel: 1) == 150)
        #expect(UpgradeKind.rigTime.cost(forLevel: 6) == nil)
        let maxed = Loadout.Stats(levels: Dictionary(uniqueKeysWithValues: UpgradeKind.allCases.map { ($0, 5) }))
        #expect(maxed.magnetDuration == 18)
        #expect(maxed.doubleDuration == 20)
        #expect(maxed.maxEggs == 8)
        #expect(maxed.convoyCap == 10)
        #expect(UpgradeKind.featherFill.effectLabel(level: 0) == "20% per close call")
    }

    @Test func breedPricesRiseAndEveryBreedHasAPerk() {
        let prices = Breed.allCases.map(\.price)
        #expect(prices == prices.sorted())
        #expect(Breed.allCases.filter { $0.trait == BreedTrait() }.isEmpty)
    }
}
