import SwiftUI

/// The Garage: upgrade parts hang on a pegboard, each with a licence-plate level tag.
struct GarageView: View {
    @State private var viewModel: GarageViewModel
    @Environment(\.chromeInsets) private var chrome

    init(viewModel: GarageViewModel) {
        self.viewModel = viewModel
    }

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 520), spacing: 16)]

    var body: some View {
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(spacing: 18) {
                HighwaySignHeader(title: "Garage", subtitle: "Bolt on parts for every trip", exit: "EXIT 1")
                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(UpgradeKind.allCases) { kind in
                        PartTag(
                            kind: kind,
                            level: viewModel.level(of: kind),
                            effect: viewModel.effect(of: kind),
                            cost: viewModel.nextCost(of: kind),
                            canAfford: viewModel.canPurchase(kind),
                            swing: viewModel.swings[kind] ?? 0,
                            shake: viewModel.shakes[kind] ?? 0,
                            onBuy: { viewModel.purchase(kind) }
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
        .tiledBackground(Art.Tile.pegboard)
        .toast(message: $viewModel.toastMessage, isError: viewModel.toastIsError, inset: chrome.bottom)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Garage.screen)
    }
}

/// One part hanging from two pegboard hooks.
private struct PartTag: View {
    let kind: UpgradeKind
    let level: Int
    let effect: String
    let cost: Int?
    let canAfford: Bool
    let swing: Int
    let shake: Int
    let onBuy: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(Art.upgrade(kind))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .background(Circle().fill(Theme.Colors.sky.opacity(0.3)))
                    .phaseAnimator([0.0, 1.0, 0.0], trigger: swing) { content, phase in
                        content.rotationEffect(.degrees(phase * 12), anchor: .top)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.title.uppercased())
                        .font(.sign(24, relativeTo: .headline))
                        .foregroundStyle(Theme.Colors.ink)
                    Text(kind.detail)
                        .font(.rounded(.footnote, weight: .medium))
                        .foregroundStyle(Theme.Colors.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(effect)
                        .font(.rounded(.footnote, weight: .heavy))
                        .foregroundStyle(Theme.Colors.mintDeep)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                LevelPlate(level: level)
                    .accessibilityIdentifier(AccessibilityID.Garage.level(kind))
                if let cost {
                    Button(action: onBuy) {
                        HStack(spacing: 6) {
                            Image(Art.cornIcon).resizable().scaledToFit().frame(width: 24, height: 24)
                            Text(Formatters.integer(cost))
                        }
                    }
                    .buttonStyle(PanelButtonStyle(color: canAfford ? .yellow : .grey, height: 56, fontSize: 24))
                    .accessibilityLabel("Buy level \(level + 1) for \(cost) corn")
                    .accessibilityIdentifier(AccessibilityID.Garage.buy(kind))
                } else {
                    Text("MAXED OUT")
                        .font(.sign(24, relativeTo: .headline))
                        .foregroundStyle(Theme.Colors.success)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .accessibilityIdentifier(AccessibilityID.Garage.buy(kind))
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .stickerCard(fill: Theme.Colors.paper, padding: 14)
        .overlay(alignment: .top) { hooks }
        .padding(.top, 10)
        .phaseAnimator([0.0, -8, 8, -5, 0], trigger: shake) { content, x in content.offset(x: x) }
        .accessibilityElement(children: .contain)
    }

    private var hooks: some View {
        HStack {
            hook
            Spacer()
            hook
        }
        .padding(.horizontal, 40)
        .offset(y: -12)
        .accessibilityHidden(true)
    }

    private var hook: some View {
        Capsule()
            .fill(LinearGradient(colors: [.white, Color(hex: 0x8D93A8)], startPoint: .top, endPoint: .bottom))
            .stroke(Theme.Colors.ink, lineWidth: 3)
            .frame(width: 12, height: 26)
    }
}

/// "LV 3/5" on a licence plate with five bolts lit up to the level.
struct LevelPlate: View {
    let level: Int

    var body: some View {
        VStack(spacing: 2) {
            Text("LV \(level)/\(UpgradeKind.maxLevel)")
                .font(.sign(20, relativeTo: .headline))
                .foregroundStyle(Theme.Colors.ink)
                .monospacedDigit()
            HStack(spacing: 4) {
                ForEach(0..<UpgradeKind.maxLevel, id: \.self) { i in
                    Circle()
                        .fill(i < level ? Theme.Colors.bus : Color(hex: 0xD9D4C4))
                        .stroke(Theme.Colors.ink, lineWidth: 1.5)
                        .frame(width: 10, height: 10)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .panel(.plate)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(level) of \(UpgradeKind.maxLevel)")
        .accessibilityValue("\(level)")
    }
}
