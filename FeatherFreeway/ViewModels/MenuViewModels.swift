import Foundation
import Observation

/// Upgrade purchases on the Garage pegboard.
@MainActor
@Observable
final class GarageViewModel {
    var toastMessage: String?
    private(set) var toastIsError = false
    /// Bumped per part to trigger a swing (bought) or shake (refused) animation.
    private(set) var swings: [UpgradeKind: Int] = [:]
    private(set) var shakes: [UpgradeKind: Int] = [:]

    private let store: ProfileStore
    private let haptics: HapticsService
    private let sound: SoundService

    init(store: ProfileStore, haptics: HapticsService, sound: SoundService) {
        self.store = store
        self.haptics = haptics
        self.sound = sound
    }

    var corn: Int { store.corn }
    func level(of kind: UpgradeKind) -> Int { store.level(of: kind) }
    func nextCost(of kind: UpgradeKind) -> Int? { store.nextCost(of: kind) }

    func canPurchase(_ kind: UpgradeKind) -> Bool {
        guard let cost = store.nextCost(of: kind) else { return false }
        return store.canAfford(cost)
    }

    /// "7 s ride → 8 s ride", or the final value once maxed.
    func effect(of kind: UpgradeKind) -> String {
        let level = store.level(of: kind)
        let now = kind.effectLabel(level: level)
        guard level < UpgradeKind.maxLevel else { return now }
        return "\(now) → \(kind.effectLabel(level: level + 1))"
    }

    func purchase(_ kind: UpgradeKind) {
        do {
            try store.purchaseUpgrade(kind)
            swings[kind, default: 0] += 1
            haptics.notify(.success)
            sound.play(.buy)
            toastIsError = false
            toastMessage = "\(kind.title) bolted on: level \(store.level(of: kind))!"
        } catch {
            shakes[kind, default: 0] += 1
            haptics.notify(.error)
            toastIsError = true
            toastMessage = error.localizedDescription
        }
    }
}

/// Choosing and welcoming chickens in the Coop.
@MainActor
@Observable
final class CoopViewModel {
    var toastMessage: String?
    private(set) var toastIsError = false
    private(set) var hops: [Breed: Int] = [:]

    private let store: ProfileStore
    private let haptics: HapticsService
    private let sound: SoundService

    init(store: ProfileStore, haptics: HapticsService, sound: SoundService) {
        self.store = store
        self.haptics = haptics
        self.sound = sound
    }

    var corn: Int { store.corn }
    var selected: Breed { store.profile.selectedBreed }
    func isUnlocked(_ breed: Breed) -> Bool { store.profile.isUnlocked(breed) }
    func canAfford(_ breed: Breed) -> Bool { store.canAfford(breed.price) }

    func act(on breed: Breed) {
        do {
            if isUnlocked(breed) {
                guard breed != selected else { return }
                try store.selectBreed(breed)
                toastMessage = "\(breed.name) is ready to run!"
            } else {
                try store.unlockBreed(breed)
                toastMessage = "Welcome to the coop, \(breed.name)!"
                sound.play(.buy)
            }
            hops[breed, default: 0] += 1
            toastIsError = false
            sound.play(.chick)
            haptics.notify(.success)
        } catch {
            toastIsError = true
            toastMessage = error.localizedDescription
            haptics.notify(.error)
        }
    }
}

/// The roadside home: current chicken, endless best, next route and the errand clipboard.
@MainActor
@Observable
final class RoadsideViewModel {
    var toastMessage: String?
    private(set) var toastIsError = false

    private let store: ProfileStore
    private let haptics: HapticsService
    private let sound: SoundService

    init(store: ProfileStore, haptics: HapticsService, sound: SoundService) {
        self.store = store
        self.haptics = haptics
        self.sound = sound
    }

    var breed: Breed { store.profile.selectedBreed }
    var bestScore: Int { store.profile.bestScore }
    var nextRoute: Route { RouteCatalog.route(store.profile.nextRouteIndex) ?? RouteCatalog.routes[0] }
    var totalStars: Int { store.profile.totalStars }
    var errands: [Errand] { store.errands }
    var errandsReady: Int { errands.filter { $0.isDone && !$0.claimed }.count }
    var errandsDone: Int { errands.filter(\.claimed).count }
    var refreshCountdown: String { Formatters.countdown(store.secondsUntilNewErrands) }

    func refresh() { store.refreshErrands() }

    func claim(_ errand: Errand) {
        do {
            let reward = try store.claimErrand(errand.slot)
            toastIsError = false
            toastMessage = "Errand done! +\(reward) corn"
            sound.play(.buy)
            haptics.notify(.success)
        } catch {
            toastIsError = true
            toastMessage = error.localizedDescription
            haptics.notify(.error)
        }
    }
}

/// Settings toggles and the progress reset.
@MainActor
@Observable
final class SettingsViewModel {
    var toastMessage: String?
    var isConfirmingReset = false

    let settings: SettingsStore
    private let store: ProfileStore
    private let haptics: HapticsService
    private let sound: SoundService

    init(settings: SettingsStore, store: ProfileStore, haptics: HapticsService, sound: SoundService) {
        self.settings = settings
        self.store = store
        self.haptics = haptics
        self.sound = sound
    }

    func musicChanged() { sound.refreshMusic(default: .menu) }

    func resetProgress() {
        do {
            try store.resetProgress()
            haptics.notify(.warning)
            toastMessage = "Fresh start! The coop and garage are empty again."
        } catch {
            toastMessage = error.localizedDescription
        }
    }
}
