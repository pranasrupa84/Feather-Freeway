import SwiftUI

@main
struct FeatherFreewayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let bootstrap: Result<AppDependencies, Error>

    init() {
        bootstrap = Result { try AppDependencies() }
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrap {
            case .success(let dependencies):
                LaunchRouterView(dependencies: dependencies)
                    .onOpenURL { AdjustAttributionStore.shared.processDeepLink($0.absoluteString) }
                    .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                        guard let url = activity.webpageURL else { return }
                        AdjustAttributionStore.shared.processDeepLink(url.absoluteString)
                    }
            case .failure(let error):
                StartupErrorView(message: error.localizedDescription)
            }
        }
    }
}

/// Shown only if the local save cannot be opened.
struct StartupErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(Art.portrait(.mabel))
                .resizable()
                .scaledToFit()
                .frame(width: 140)
                .accessibilityHidden(true)
            Text("Road closed")
                .font(.sign(34))
                .foregroundStyle(Theme.Colors.ink)
            Text("Feather Freeway could not open its save data. Please restart the app. If it keeps happening, reinstalling creates a fresh save.")
                .font(.rounded(.body))
                .foregroundStyle(Theme.Colors.inkSoft)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.Colors.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 24).fill(Theme.Colors.cream).stroke(Theme.Colors.ink, lineWidth: 4))
        .padding(28)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.grass)
        .preferredColorScheme(.light)
    }
}
