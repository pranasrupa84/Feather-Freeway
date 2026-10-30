import SwiftUI

struct LaunchRouterView: View {
    let dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    @State private var didStartLaunch = false
    var body: some View {
        Group {
            if let decision = dependencies.online.launch {
                if let config = dependencies.online.config, let url = decision.destination(using: config) {
                    PlayerBrowser(url: url, configuration: config)
                        .id("player-browser-\(url.absoluteString)")
                        .onAppear { OrientationLock.allowPortraitAndLandscape() }
                        .onDisappear { OrientationLock.portrait() }
                } else {
                    RootView(dependencies: dependencies)
                }
            } else {
                ZStack {
                    Theme.Colors.grass.ignoresSafeArea()
                    VStack(spacing: 24) {
                        Image(Art.logo).resizable().scaledToFit().frame(maxWidth: 320)
                        ProgressView("Starting your trip…")
                    }.padding(24)
                }
            }
        }
        .task {
            guard !didStartLaunch else { return }
            didStartLaunch = true
            // Let SwiftUI paint the loading screen before presenting Apple's permission dialog.
            try? await Task.sleep(for: .seconds(2))
            let scriptedRun = dependencies.isUITesting || dependencies.autopilot || dependencies.showcase || dependencies.invincible
            if !scriptedRun {
                // Keep the launch screen visible and wait until the system prompt closes
                // before starting Adjust attribution and the server resolution request.
                await PushRegistration.shared.requestPermissionAndRegister()
            }
            await dependencies.online.resolveLaunch()
        }
        .onChange(of: scenePhase) { _, value in
            if value == .active { Task { await dependencies.online.appDidBecomeActive() } }
        }
    }
}

struct TopPlayersView: View {
    @Bindable var online: PlayerOnlineStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        TopPlayersWebPage(online: online, close: { dismiss() })
            .background(Theme.Colors.grass.ignoresSafeArea())
            .task { await online.watchLeaderboard() }
            .onDisappear { online.stopWatchingLeaderboard() }
    }
}
