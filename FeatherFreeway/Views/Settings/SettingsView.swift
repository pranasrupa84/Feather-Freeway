import SwiftUI

/// Sound, music and haptics switches, a left-handed layout and the progress reset.
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    let onGuide: () -> Void

    init(viewModel: SettingsViewModel, onGuide: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onGuide = onGuide
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        @Bindable var settings = viewModel.settings
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    toggle("Sound effects", detail: "Clucks, honks and crunches.", symbol: "speaker.wave.2.fill", isOn: $settings.soundEnabled, id: AccessibilityID.Settings.sound)
                    Divider()
                    toggle("Music", detail: "The road-trip tunes.", symbol: "music.note", isOn: $settings.musicEnabled, id: AccessibilityID.Settings.music)
                    Divider()
                    toggle("Vibration", detail: "Bumps and smashes you can feel.", symbol: "iphone.radiowaves.left.and.right", isOn: $settings.hapticsEnabled, id: AccessibilityID.Settings.haptics)
                    Divider()
                    toggle("Left-handed buttons", detail: "Puts EGG on the left and RIG on the right.", symbol: "hand.raised.fill", isOn: $settings.leftHanded, id: AccessibilityID.Settings.leftHanded)
                }
                .stickerCard(fill: Theme.Colors.paper)
                .onChange(of: settings.musicEnabled) { viewModel.musicChanged() }

                Button(action: onGuide) {
                    Label { Text("HOW TO PLAY") } icon: { Image(Art.Sign.help).resizable().scaledToFit().frame(width: 30) }
                }
                .buttonStyle(PanelButtonStyle(color: .cream, height: 60))
                .accessibilityIdentifier(AccessibilityID.Settings.guide)

                VStack(alignment: .leading, spacing: 8) {
                    Text("ABOUT").font(.sign(22, relativeTo: .headline)).foregroundStyle(Theme.Colors.ink)
                    Text("Feather Freeway works fully offline. No ads, no accounts, no tracking. Your progress is saved on this device only.")
                        .font(.rounded(.footnote, weight: .medium))
                        .foregroundStyle(Theme.Colors.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .stickerCard(fill: Theme.Colors.paper)

                Button("RESET ALL PROGRESS") { viewModel.isConfirmingReset = true }
                    .buttonStyle(PanelButtonStyle(color: .red, height: 58, fontSize: 24))
                    .accessibilityIdentifier(AccessibilityID.Settings.reset)
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.top, 16)
            .padding(.bottom, 30)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                BackSign()
                HighwaySignHeader(title: "Settings", subtitle: "Tune the trip")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .roadBand()
        }
        .tiledBackground(Art.Tile.pegboard)
        .confirmationDialog("Reset all progress?", isPresented: $viewModel.isConfirmingReset, titleVisibility: .visible) {
            Button("Reset everything", role: .destructive) { viewModel.resetProgress() }
                .accessibilityIdentifier(AccessibilityID.Settings.resetConfirm)
            Button("Keep my progress", role: .cancel) {}
        } message: {
            Text("Corn, parts, chickens, route stars and the trip log will be erased.")
        }
        .toast(message: $viewModel.toastMessage)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Settings.screen)
    }

    private func toggle(_ title: String, detail: String, symbol: String, isOn: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.Colors.ink)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.Colors.bus).stroke(Theme.Colors.ink, lineWidth: 2.5))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.rounded(.headline, weight: .heavy)).foregroundStyle(Theme.Colors.ink)
                    Text(detail).font(.rounded(.caption, weight: .medium)).foregroundStyle(Theme.Colors.inkSoft)
                }
            }
        }
        .tint(Theme.Colors.signGreen)
        .padding(.vertical, 8)
        .accessibilityIdentifier(id)
    }
}
