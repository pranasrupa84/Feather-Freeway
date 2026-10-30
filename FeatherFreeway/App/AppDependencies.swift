import Foundation
import SwiftData

/// Composition root: builds the stores and services the whole app shares.
@MainActor
final class AppDependencies {
    let container: ModelContainer
    let profileStore: ProfileStore
    let settings: SettingsStore
    let haptics: HapticsService
    let sound: SoundService
    let online: PlayerOnlineStore
    let isUITesting: Bool
    /// Lets the chicken drive itself (UI tests and screenshots).
    let autopilot: Bool
    /// Scripted demo run for the gameplay video: autopilot with every trick, then a crash.
    let showcase: Bool
    /// Bumps never end a run (UI tests that must not crash mid-way).
    let invincible: Bool

    static let uiTestingArgument = "--uitesting"
    static let freshStartArgument = "--freshstart"
    static let autopilotArgument = "--autopilot"
    static let showcaseArgument = "--showcase"
    static let invincibleArgument = "--invincible"
    private static let uiTestingDefaultsSuite = "com.featherfreeway.game27.uitesting"

    init(launchArguments: [String] = CommandLine.arguments) throws {
        #if DEBUG
        isUITesting = launchArguments.contains(Self.uiTestingArgument)
        showcase = launchArguments.contains(Self.showcaseArgument)
        invincible = launchArguments.contains(Self.invincibleArgument)
        autopilot = launchArguments.contains(Self.autopilotArgument) || showcase
        #else
        isUITesting = false
        autopilot = false
        showcase = false
        invincible = false
        #endif

        let defaults: UserDefaults
        if isUITesting, let suite = UserDefaults(suiteName: Self.uiTestingDefaultsSuite) {
            suite.removePersistentDomain(forName: Self.uiTestingDefaultsSuite)
            defaults = suite
        } else {
            defaults = .standard
        }

        container = try PersistenceController.makeContainer(inMemory: isUITesting)
        profileStore = try ProfileStore(container: container)
        settings = SettingsStore(defaults: defaults)
        // Online services stay off for UI tests and scripted runs so they never touch the live backend.
        online = PlayerOnlineStore(defaults: defaults, disabled: isUITesting || autopilot || invincible)
        let online = self.online
        profileStore.onFinishedRun = { summary in online.enqueue(summary) }

        let settings = self.settings
        haptics = HapticsService { settings.hapticsEnabled }
        if isUITesting && !showcase {
            sound = .silent
        } else if showcase {
            sound = SoundService(soundEnabled: { true }, musicEnabled: { true })
            let log = URL.documentsDirectory.appending(path: "showcase-sounds.tsv")
            try? FileManager.default.removeItem(at: log)
            sound.eventLog = log
        } else {
            sound = SoundService(soundEnabled: { settings.soundEnabled }, musicEnabled: { settings.musicEnabled })
        }

        if isUITesting && !launchArguments.contains(Self.freshStartArgument) {
            // Deterministic state so UI tests can buy things without playing first.
            settings.hasSeenGuide = true
            try profileStore.grantCorn(5000)
        }
    }

    /// A fresh random seed for a new trip.
    static func randomSeed() -> UInt64 {
        UInt64.random(in: 1...UInt64.max)
    }
}
