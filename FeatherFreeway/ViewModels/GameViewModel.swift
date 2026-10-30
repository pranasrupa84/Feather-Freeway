import Foundation
import Observation
import SpriteKit
import SwiftUI

/// Snapshot of the run for the SwiftUI HUD (refreshed about ten times a second).
struct RunHUD: Equatable {
    var score = 0
    var meters = 0
    var corn = 0
    var chicks = 0
    var convoyCap = 5
    var multiplier = 1.0
    var feather = 0.0
    var isFlapReady = false
    var fuel = 0
    var isRigReady = false
    var rigFraction = 0.0
    var isRigging = false
    var eggs = 0
    var maxEggs = 3
    var magnetLeft = 0.0
    var doubleLeft = 0.0
    var streak = 0
    var progress: Double?
    var world: World = .farm
    var lanes = 3
    var mechanics: Mechanics = .all

    @MainActor
    init(session: RunSession? = nil) {
        guard let s = session else { return }
        score = s.displayScore
        meters = s.meters
        corn = s.corn
        chicks = s.chicks
        convoyCap = s.convoyCap
        multiplier = s.multiplier
        feather = s.feather
        isFlapReady = s.isFlapReady
        fuel = s.fuel
        isRigReady = s.isRigReady
        isRigging = s.isRigging
        rigFraction = s.isRigging ? max(0, s.rigTime / s.rigDuration) : 0
        eggs = s.eggs
        maxEggs = s.maxEggs
        magnetLeft = s.magnetTime
        doubleLeft = s.doubleTime
        streak = s.streak
        progress = s.progress
        world = s.currentWorld
        lanes = s.lanesHere
        mechanics = s.config.mechanics
    }
}

/// Drives one trip: ticket, traffic-light countdown, the run, pause and the citation.
@MainActor
@Observable
final class GameViewModel {
    enum Phase: Equatable {
        case ready
        case countdown(Int)
        case running
        case paused
        /// The crash or finish line is playing out before the citation appears.
        case ending
        case finished(RunOutcome)
    }

    struct Banner: Equatable, Identifiable {
        enum Style { case green, yellow, red, blue }
        let id = UUID()
        let title: String
        let detail: String?
        let style: Style
        let art: String?
    }

    private(set) var phase: Phase = .ready
    private(set) var hud = RunHUD()
    private(set) var setup: RunSetup
    private(set) var scene: FreewayScene?
    private(set) var sceneID = UUID()
    private(set) var banner: Banner?
    /// Bumps when the run ends in a crash, to shake the citation in.
    private(set) var crashCount = 0

    private let profileStore: ProfileStore
    let settings: SettingsStore
    private let haptics: HapticsService
    private let sound: SoundService
    private let autopilot: Bool
    private let showcase: Bool
    private let invincible: Bool
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private var hudClock: Double = 0

    init(setup: RunSetup, profileStore: ProfileStore, settings: SettingsStore, haptics: HapticsService, sound: SoundService, autopilot: Bool = false, showcase: Bool = false, invincible: Bool = false) {
        self.invincible = invincible
        self.autopilot = autopilot
        self.showcase = showcase
        self.setup = setup
        self.profileStore = profileStore
        self.settings = settings
        self.haptics = haptics
        self.sound = sound
    }

    var route: Route? { setup.mode.routeIndex.flatMap(RouteCatalog.route) }
    var breed: Breed { profileStore.profile.selectedBreed }
    var isRunning: Bool { phase == .running }
    var isShowcase: Bool { showcase }
    var isPaused: Bool { phase == .paused }
    var bestScore: Int { profileStore.profile.bestScore }
    var routeStars: Int { route.map { profileStore.profile.stars(forRoute: $0.index) } ?? 0 }
    var title: String { route.map { "Route \($0.number): \($0.name)" } ?? "Endless Freeway" }

    // MARK: - Scene

    func prepareScene() {
        guard scene == nil else { return }
        installScene()
    }

    private func installScene() {
        scene?.runDelegate = nil
        let session = RunSession(setup: setup, loadout: profileStore.loadout)
        let newScene = FreewayScene(session: session)
        newScene.runDelegate = self
        newScene.autopilot = autopilot
        newScene.showcase = showcase
        session.debugInvincible = showcase || invincible
        session.debugGenerousTreats = showcase
        if showcase { session.debugSetEggs(2) }
        hud = RunHUD(session: session)
        scene = newScene
        sceneID = UUID()
    }

    // MARK: - Intents

    func begin() {
        guard phase == .ready else { return }
        prepareScene()
        haptics.prepare()
        sound.stopMusic()
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            for value in stride(from: 3, through: 1, by: -1) {
                guard let self, !Task.isCancelled else { return }
                withAnimation(.spring(duration: 0.3)) { self.phase = .countdown(value) }
                self.sound.play(value == 1 ? .go : .count)
                self.haptics.impact(.light)
                try? await Task.sleep(for: .milliseconds(620))
            }
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { self.phase = .running }
            self.scene?.isRunning = true
            self.sound.playMusic(.run)
        }
    }

    func pause() {
        guard phase == .running else { return }
        scene?.isRunning = false
        scene?.isPaused = true
        sound.pauseMusic()
        withAnimation(.easeOut(duration: 0.2)) { phase = .paused }
        haptics.selection()
    }

    func resume() {
        guard phase == .paused else { return }
        scene?.isPaused = false
        scene?.isRunning = true
        sound.resumeMusic()
        withAnimation(.easeOut(duration: 0.2)) { phase = .running }
        haptics.selection()
    }

    func handleScenePhaseChange(_ scenePhase: ScenePhase) {
        guard scenePhase != .active else { return }
        if case .countdown = phase {
            countdownTask?.cancel()
            phase = .ready
        } else {
            pause()
        }
    }

    func activateRig() {
        guard isRunning else { return }
        if scene?.session.activateRig() == true { refreshHUD() }
    }

    func throwEgg() {
        guard isRunning else { return }
        if scene?.session.throwEgg() == true { refreshHUD() }
    }

    /// Same mode again. A cleared route moves on to the next one.
    func playAgain() {
        var next = setup
        next.seed = AppDependencies.randomSeed()
        if case .finished(let outcome) = phase, outcome.summary.result == .cleared, let index = setup.mode.routeIndex,
           index + 1 < RouteCatalog.count, profileStore.profile.isRouteUnlocked(index + 1) {
            next.mode = .route(index + 1)
        }
        restart(with: next)
    }

    func restart() {
        var next = setup
        next.seed = AppDependencies.randomSeed()
        restart(with: next)
    }

    private func restart(with next: RunSetup) {
        countdownTask?.cancel()
        setup = next
        banner = nil
        installScene()
        withAnimation(.easeOut(duration: 0.25)) { phase = .ready }
    }

    func tearDown() {
        countdownTask?.cancel()
        bannerTask?.cancel()
        scene?.runDelegate = nil
        scene?.isRunning = false
        scene = nil
    }

    var playAgainTitle: String {
        guard case .finished(let outcome) = phase else { return "PLAY AGAIN" }
        if outcome.summary.result == .cleared, let index = setup.mode.routeIndex, index + 1 < RouteCatalog.count { return "NEXT ROUTE" }
        return "TRY AGAIN"
    }

    // MARK: - HUD and banners

    private func refreshHUD() {
        guard let session = scene?.session else { return }
        let next = RunHUD(session: session)
        if next != hud { hud = next }
    }

    private func show(_ banner: Banner, seconds: Double = 1.8) {
        bannerTask?.cancel()
        withAnimation(.spring(duration: 0.3, bounce: 0.35)) { self.banner = banner }
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { self.banner = nil }
        }
    }

    private func finishRun(_ session: RunSession) {
        scene?.isRunning = false
        let outcome = profileStore.recordRun(session.summary)
        sound.stopMusic()
        if outcome.summary.result == .cleared {
            sound.play(.finish)
            haptics.notify(.success)
        } else {
            crashCount += 1
            sound.play(.gameOver)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(outcome.summary.result == .cleared ? 500 : 900))
            guard let self else { return }
            withAnimation(.spring(duration: 0.45, bounce: 0.3)) { self.phase = .finished(outcome) }
            if outcome.newStars > 0 { self.sound.play(.star) }
        }
    }
}

// MARK: - FreewaySceneDelegate

extension GameViewModel: FreewaySceneDelegate {
    func scene(_ scene: FreewayScene, didStep session: RunSession, events: [RunEvent], dt: Double) {
        for event in events { react(to: event, session: session) }
        hudClock += dt
        if hudClock >= 0.1 || !events.isEmpty {
            hudClock = 0
            refreshHUD()
        }
        if session.isOver, case .running = phase {
            phase = .ending
            finishRun(session)
        }
    }

    private func react(to event: RunEvent, session: RunSession) {
        switch event {
        case .laneChange: sound.play(.lane, volume: 0.6); haptics.selection()
        case .jump: sound.play(.jump)
        case .dive: sound.play(.dive)
        case .flap: sound.play(.flap); haptics.impact(.medium)
        case .closeCall: sound.play(.closeCall); haptics.impact(.light)
        case .corn(_, _, let streak): sound.playCorn(streak: streak)
        case .streakEgg:
            sound.play(.powerUp)
            show(Banner(title: "EGG LAID!", detail: "Corn streak bonus: +1 egg", style: .yellow, art: Art.egg), seconds: 1.3)
        case .chickRescued(let count):
            sound.play(.chick)
            if count == RunSession.expressMinimumChicks, session.config.mechanics.contains(.tolls) {
                show(Banner(title: "CONVOY ×\(count + 1)", detail: "Express toll gates will open", style: .yellow, art: Art.chickFace))
            }
        case .chicksLost(let count):
            sound.play(.honk)
            haptics.notify(.warning)
            show(Banner(title: "BUMP!", detail: count == 1 ? "A chick ran off" : "\(count) chicks ran off", style: .red, art: Art.chickFace), seconds: 1.3)
        case .pickup(let kind):
            switch kind {
            case .fuel: sound.play(.fuel)
            case .magnet:
                sound.play(.powerUp)
                show(Banner(title: "CORN MAGNET", detail: nil, style: .blue, art: Art.magnet), seconds: 1.2)
            case .double:
                sound.play(.powerUp)
                show(Banner(title: "DOUBLE CORN", detail: nil, style: .blue, art: Art.double), seconds: 1.2)
            default: sound.play(.powerUp)
            }
        case .rigReady:
            sound.play(.powerUp)
            haptics.notify(.success)
            show(Banner(title: "BIG RIG READY", detail: "Tap RIG to ride", style: .yellow, art: Art.fuelCan))
        case .rigStart:
            sound.play(.rig)
            haptics.impact(.heavy)
            show(Banner(title: "BIG RIG!", detail: "Smash everything", style: .red, art: Art.rig), seconds: 1.4)
        case .rigEnd: sound.play(.dive)
        case .smash: sound.play(.smash); haptics.impact(.heavy)
        case .bump: haptics.impact(.heavy)
        case .cushion:
            sound.play(.honk)
            show(Banner(title: "FLUFFY CUSHION", detail: "Mabel shrugs off the bump", style: .blue, art: Art.portrait(.mabel)), seconds: 1.4)
        case .crash:
            sound.play(.crash)
            haptics.notify(.error)
        case .eggThrown: sound.play(.eggThrow)
        case .splat: sound.play(.splat); haptics.impact(.medium)
        case .lateMerge:
            sound.play(.merge)
            show(Banner(title: "LATE MERGE", detail: "+150 × \(Int(session.multiplier))", style: .green, art: Art.signLaneEnds), seconds: 1.3)
        case .laneEnds:
            sound.play(.signal)
            show(Banner(title: "LANE ENDS", detail: "Merge left before the barrier", style: .yellow, art: Art.signLaneEnds))
        case .tollAhead:
            show(Banner(title: "TOLL PLAZA", detail: session.chicks >= RunSession.expressMinimumChicks ? "Express gate open for your convoy" : "Green gates only. Express needs 3 chicks", style: .green, art: Art.eggGolden), seconds: 1.3)
        case .tollPassed(let kind, let bonus):
            sound.play(.toll)
            if kind == .express { show(Banner(title: "EXPRESS!", detail: "+\(bonus) corn", style: .yellow, art: Art.cornIcon), seconds: 1.4) }
        case .signalWarning(let kind):
            sound.play(.signal)
            if kind == .red { show(Banner(title: "RED LIGHT", detail: "Parked queue ahead: jump for corn", style: .red, art: nil), seconds: 1.4) }
            else { show(Banner(title: "GREEN WAVE", detail: "Fast cars coming in one lane", style: .green, art: nil), seconds: 1.4) }
        case .greenWave: sound.play(.honk, volume: 0.7)
        case .worldEntered(let world):
            show(Banner(title: "WELCOME TO", detail: world.title, style: world == .night ? .blue : .green, art: nil), seconds: 2)
        case .flapReady:
            sound.play(.powerUp, volume: 0.7)
            show(Banner(title: "FLAP READY", detail: "Swipe up to fly over traffic", style: .blue, art: Art.feather), seconds: 1.3)
        case .finished: break
        }
    }
}
