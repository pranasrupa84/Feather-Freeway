import SwiftUI

extension EnvironmentValues {
    /// Space taken by the top bar and lane rail (including safe areas) on home pages.
    @Entry var chromeInsets = EdgeInsets()
}

/// Home is a road with three lanes: Garage | Roadside | Coop. Swipe sideways (like in a run)
/// or tap a lane on the rail to change screens.
struct HomePager: View {
    @Binding var lane: HomeLane
    let garage: GarageViewModel
    let coop: CoopViewModel
    let roadside: RoadsideViewModel
    let corn: Int
    let onOpen: (AppRoute) -> Void
    let onPlay: (RunMode) -> Void
    let onTap: () -> Void

    @State private var barHeight: CGFloat = 64
    @State private var railHeight: CGFloat = Theme.Metrics.laneRailHeight
    @State private var position: HomeLane? = .roadside

    var body: some View {
        GeometryReader { proxy in
            let safe = proxy.safeAreaInsets
            let full = CGSize(width: proxy.size.width + safe.leading + safe.trailing, height: proxy.size.height + safe.top + safe.bottom)
            let insets = EdgeInsets(top: safe.top + barHeight, leading: 0, bottom: safe.bottom + railHeight, trailing: 0)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(HomeLane.allCases) { item in
                        page(item)
                            .frame(width: full.width, height: full.height)
                            .id(item)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $position)
            .onChange(of: full) {
                // Rotation changes the page width; snap back onto the current lane.
                position = nil
                Task { @MainActor in position = lane }
            }
            .scrollIndicators(.hidden)
            .environment(\.chromeInsets, insets)
            .ignoresSafeArea()
            .accessibilityIdentifier(AccessibilityID.Home.pager)
            .overlay(alignment: .top) {
                TopBar(corn: corn, onOpen: onOpen, onTap: onTap)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
            }
            .overlay(alignment: .bottom) {
                LaneRail(lane: $lane, onTap: onTap)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { railHeight = $0 }
            }
        }
        .onAppear { position = lane }
        .onChange(of: position) { _, new in
            if let new, new != lane { lane = new }
        }
        .onChange(of: lane) { _, new in
            if position != new { withAnimation(.spring(duration: 0.4, bounce: 0.15)) { position = new } }
        }
    }

    @ViewBuilder
    private func page(_ item: HomeLane) -> some View {
        switch item {
        case .garage: GarageView(viewModel: garage)
        case .roadside: RoadsideView(viewModel: roadside, onOpen: onOpen, onPlay: onPlay)
        case .coop: CoopView(viewModel: coop)
        }
    }
}

private struct TopBar: View {
    let corn: Int
    let onOpen: (AppRoute) -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CornBadge(amount: corn)
            Spacer(minLength: 8)
            Button { onTap(); onOpen(.topPlayers) } label: {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 21, weight: .black))
                    .foregroundStyle(Theme.Colors.ink)
                    .frame(width: 46, height: 46)
                    .background(Theme.Colors.tomato, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Colors.ink, lineWidth: 3))
                    .shadow(color: Theme.Colors.ink, radius: 0, x: 0, y: 3)
            }
            .accessibilityLabel("TOP PLAYERS")
            .accessibilityIdentifier(AccessibilityID.Home.topPlayers)
            SignButton(art: Art.Sign.records, label: "Glovebox: records and citations", size: 46) { onOpen(.glovebox) }
                .accessibilityIdentifier(AccessibilityID.Home.records)
            SignButton(art: Art.Sign.settings, label: "Settings", size: 46) { onOpen(.settings) }
                .accessibilityIdentifier(AccessibilityID.Home.settings)
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
        .roadBand()
    }
}

extension View {
    /// Asphalt band with a yellow edge line behind a pinned header, reaching under the status bar.
    func roadBand() -> some View {
        background {
            VStack(spacing: 0) {
                Theme.Colors.asphalt
                Rectangle().fill(Theme.Colors.bus).frame(height: 4)
                Rectangle().fill(Theme.Colors.ink).frame(height: 3)
            }
            .ignoresSafeArea(edges: .top)
            .accessibilityHidden(true)
        }
    }
}

/// The asphalt strip at the bottom: one painted lane per home screen, with the chicken
/// standing on the active one.
private struct LaneRail: View {
    @Binding var lane: HomeLane
    let onTap: () -> Void
    @Namespace private var marker
    @Environment(ProfileStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HomeLane.allCases) { item in
                Button {
                    onTap()
                    lane = item
                } label: {
                    VStack(spacing: 2) {
                        Image(icon(for: item))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                        Text(item.title.uppercased())
                            .font(.sign(17, relativeTo: .caption))
                            .kerning(1)
                            .foregroundStyle(lane == item ? Theme.Colors.bus : .white.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .overlay(alignment: .top) {
                        if lane == item {
                            Image(Art.hen(store.profile.selectedBreed, frame: 0))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 34, height: 34)
                                .offset(x: 34, y: -16)
                                .matchedGeometryEffect(id: "hen", in: marker)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(lane == item ? .isSelected : [])
                .accessibilityIdentifier(identifier(for: item))
                if item != HomeLane.allCases.last {
                    DashedDivider()
                }
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.3), value: lane)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
        .background {
            ZStack(alignment: .top) {
                Theme.Colors.asphalt
                Rectangle().fill(Theme.Colors.bus).frame(height: 5)
                Rectangle().fill(Theme.Colors.ink).frame(height: 3).offset(y: -3)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func icon(for lane: HomeLane) -> String {
        switch lane {
        case .garage: Art.upgrade(.rigTime)
        case .roadside: Art.cornIcon
        case .coop: Art.chickFace
        }
    }

    private func identifier(for lane: HomeLane) -> String {
        switch lane {
        case .garage: AccessibilityID.Home.laneGarage
        case .roadside: AccessibilityID.Home.laneRoadside
        case .coop: AccessibilityID.Home.laneCoop
        }
    }
}

private struct DashedDivider: View {
    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { _ in
                Capsule().fill(.white.opacity(0.9)).frame(width: 4, height: 12)
            }
        }
        .accessibilityHidden(true)
    }
}
