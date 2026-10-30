import SwiftUI

/// Hosts the three-lane home pager, pushes secondary screens and presents trips full screen.
struct RootView: View {
    let dependencies: AppDependencies

    @State private var path: [AppRoute] = []
    @State private var lane: HomeLane = .roadside
    @State private var playRequest: PlayRequest?
    @State private var pendingSetup: RunSetup?
    @State private var isGuidePresented = false
    @State private var garage: GarageViewModel
    @State private var coop: CoopViewModel
    @State private var roadside: RoadsideViewModel

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        garage = GarageViewModel(store: dependencies.profileStore, haptics: dependencies.haptics, sound: dependencies.sound)
        coop = CoopViewModel(store: dependencies.profileStore, haptics: dependencies.haptics, sound: dependencies.sound)
        roadside = RoadsideViewModel(store: dependencies.profileStore, haptics: dependencies.haptics, sound: dependencies.sound)
    }

    var body: some View {
        NavigationStack(path: $path) {
            HomePager(
                lane: $lane,
                garage: garage,
                coop: coop,
                roadside: roadside,
                corn: dependencies.profileStore.corn,
                onOpen: { path.append($0) },
                onPlay: requestPlay,
                onTap: { dependencies.sound.play(.tap) }
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AppRoute.self) { route in
                destination(for: route)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .tint(Theme.Colors.ink)
        .preferredColorScheme(.light)
        // The interface is English, so numbers and dates follow English conventions too.
        .environment(\.locale, Locale(identifier: "en_US"))
        .fullScreenCover(item: $playRequest, onDismiss: { dependencies.sound.playMusic(.menu) }) { request in
            GameView(viewModel: GameViewModel(
                setup: request.setup,
                profileStore: dependencies.profileStore,
                settings: dependencies.settings,
                haptics: dependencies.haptics,
                sound: dependencies.sound,
                autopilot: dependencies.autopilot,
                showcase: dependencies.showcase,
                invincible: dependencies.invincible
            ))
        }
        .sheet(isPresented: $isGuidePresented, onDismiss: startPendingRun) {
            GuideView(isOnboarding: true) {
                dependencies.settings.hasSeenGuide = true
                isGuidePresented = false
            }
            .presentationDragIndicator(.visible)
        }
        .environment(dependencies.profileStore)
        .environment(dependencies.settings)
        .onAppear {
            OrientationLock.portrait()
            dependencies.sound.playMusic(.menu)
        }
        .task {
            if dependencies.showcase { await runShowcaseTour() }
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .topPlayers:
            TopPlayersView(online: dependencies.online)
        case .routeMap:
            RouteMapView(onPlay: requestPlay)
        case .glovebox:
            GloveboxView()
        case .settings:
            SettingsView(viewModel: SettingsViewModel(
                settings: dependencies.settings,
                store: dependencies.profileStore,
                haptics: dependencies.haptics,
                sound: dependencies.sound
            ), onGuide: { path.append(.guide) })
        case .guide:
            GuideView(isOnboarding: false, onFinish: nil)
        }
    }

    /// Demo for the gameplay video: visits every screen, makes a few purchases, then starts an
    /// endless run that the showcase autopilot drives.
    private func runShowcaseTour() async {
        func pause(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
        func go(_ next: HomeLane) { dependencies.sound.play(.tap); withAnimation(.spring(duration: 0.45)) { lane = next } }
        await pause(3)
        go(.coop); await pause(2.5)
        coop.act(on: .duchess); await pause(3)
        go(.garage); await pause(2.2)
        garage.purchase(.rigTime); await pause(2)
        garage.purchase(.magnetTime); await pause(2.2)
        go(.roadside); await pause(2)
        for route in [AppRoute.glovebox, .routeMap, .guide] {
            dependencies.sound.play(.tap)
            path.append(route)
            await pause(3.2)
            path.removeLast()
            await pause(1.2)
        }
        dependencies.sound.play(.tap)
        requestPlay(.endless)
    }

    /// Shows the guide before the very first trip, then starts it.
    private func requestPlay(_ mode: RunMode) {
        let setup = RunSetup(mode: mode, seed: AppDependencies.randomSeed())
        if dependencies.settings.hasSeenGuide {
            playRequest = PlayRequest(setup: setup)
        } else {
            pendingSetup = setup
            isGuidePresented = true
        }
    }

    private func startPendingRun() {
        guard let setup = pendingSetup, dependencies.settings.hasSeenGuide else {
            pendingSetup = nil
            return
        }
        pendingSetup = nil
        playRequest = PlayRequest(setup: setup)
    }
}
