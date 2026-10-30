import SwiftUI

/// The Coop: a barn wall of wooden nest boxes, one chicken per box with its perk.
struct CoopView: View {
    @State private var viewModel: CoopViewModel
    @Environment(\.chromeInsets) private var chrome

    init(viewModel: CoopViewModel) {
        self.viewModel = viewModel
    }

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 14)]

    var body: some View {
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(spacing: 18) {
                HighwaySignHeader(title: "The Coop", subtitle: "Pick who runs. Every chicken has a perk.", exit: "EXIT 3", style: .signBlue)
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Breed.allCases) { breed in
                        NestBox(
                            breed: breed,
                            isUnlocked: viewModel.isUnlocked(breed),
                            isSelected: viewModel.selected == breed,
                            canAfford: viewModel.canAfford(breed),
                            hop: viewModel.hops[breed] ?? 0,
                            onAct: { viewModel.act(on: breed) }
                        )
                    }
                }
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.top, chrome.top + 6)
            .padding(.bottom, chrome.bottom + 20)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .tiledBackground(Art.Tile.coopWall)
        .toast(message: $viewModel.toastMessage, isError: viewModel.toastIsError, inset: chrome.bottom)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Coop.screen)
    }
}

private struct NestBox: View {
    let breed: Breed
    let isUnlocked: Bool
    let isSelected: Bool
    let canAfford: Bool
    let hop: Int
    let onAct: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                // The box opening with straw.
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: 0x5A3A22))
                    .overlay(alignment: .bottom) {
                        Capsule().fill(Color(hex: 0xF2C766)).frame(height: 26).padding(.horizontal, 6).offset(y: 6)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Image(Art.portrait(breed))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 128, height: 128)
                    .saturation(isUnlocked ? 1 : 0.15)
                    .opacity(isUnlocked ? 1 : 0.75)
                    .phaseAnimator([0.0, -16, 0], trigger: hop) { content, y in content.offset(y: y) }
                if !isUnlocked {
                    Image(Art.lock).resizable().scaledToFit().frame(width: 40).padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(height: 140)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(hex: 0xC98B55)).stroke(Theme.Colors.ink, lineWidth: 3.5))
            .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text(breed.name.uppercased())
                    .font(.sign(24, relativeTo: .headline))
                    .foregroundStyle(Theme.Colors.ink)
                Text(breed.kind)
                    .font(.rounded(.caption, weight: .bold))
                    .foregroundStyle(Theme.Colors.inkSoft)
            }
            Chip(text: breed.traitName, color: isSelected ? Theme.Colors.bus : Theme.Colors.mint)
            Text(breed.traitDetail)
                .font(.rounded(.caption, weight: .medium))
                .foregroundStyle(Theme.Colors.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: .infinity, alignment: .top)
            actionButton
        }
        .stickerCard(fill: isSelected ? Color(hex: 0xFFF0B8) : Theme.Colors.paper, padding: 10)
        .overlay(alignment: .topLeading) {
            if isSelected {
                Text("RUNNING")
                    .font(.sign(15, relativeTo: .caption))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.Colors.tomato).stroke(Theme.Colors.ink, lineWidth: 2))
                    .rotationEffect(.degrees(-8))
                    .offset(x: -4, y: -8)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actionButton: some View {
        if isSelected {
            Text("SELECTED")
                .font(.sign(22, relativeTo: .headline))
                .foregroundStyle(Theme.Colors.success)
                .frame(maxWidth: .infinity, minHeight: 50)
                .accessibilityIdentifier(AccessibilityID.Coop.action(breed))
        } else if isUnlocked {
            Button("CHOOSE", action: onAct)
                .buttonStyle(PanelButtonStyle(color: .green, height: 50, fontSize: 22))
                .accessibilityLabel("Choose \(breed.name)")
                .accessibilityIdentifier(AccessibilityID.Coop.action(breed))
        } else {
            Button(action: onAct) {
                HStack(spacing: 4) {
                    Image(Art.cornIcon).resizable().scaledToFit().frame(width: 22, height: 22)
                    Text(Formatters.integer(breed.price))
                }
            }
            .buttonStyle(PanelButtonStyle(color: canAfford ? .yellow : .grey, height: 50, fontSize: 22))
            .accessibilityLabel("Welcome \(breed.name) for \(breed.price) corn")
            .accessibilityIdentifier(AccessibilityID.Coop.action(breed))
        }
    }
}
