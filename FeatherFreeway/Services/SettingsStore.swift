import Foundation
import Observation

/// User preferences backed by `UserDefaults`.
@MainActor
@Observable
final class SettingsStore {
    private enum Keys {
        static let soundEnabled = "settings.soundEnabled"
        static let musicEnabled = "settings.musicEnabled"
        static let hapticsEnabled = "settings.hapticsEnabled"
        static let hasSeenGuide = "settings.hasSeenGuide"
        static let leftHanded = "settings.leftHanded"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) } }
    var musicEnabled: Bool { didSet { defaults.set(musicEnabled, forKey: Keys.musicEnabled) } }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Keys.hapticsEnabled) } }
    /// Swaps the RIG and EGG buttons for left-handed play.
    var leftHanded: Bool { didSet { defaults.set(leftHanded, forKey: Keys.leftHanded) } }
    /// Whether the guide has been shown before the first trip.
    var hasSeenGuide: Bool { didSet { defaults.set(hasSeenGuide, forKey: Keys.hasSeenGuide) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        musicEnabled = defaults.object(forKey: Keys.musicEnabled) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Keys.hapticsEnabled) as? Bool ?? true
        leftHanded = defaults.bool(forKey: Keys.leftHanded)
        hasSeenGuide = defaults.bool(forKey: Keys.hasSeenGuide)
    }
}
