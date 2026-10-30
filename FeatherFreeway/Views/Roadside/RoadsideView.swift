import SwiftUI

/// Home: a sunny roadside by the coop. The chicken waits on the shoulder; the big yellow sign
/// starts an endless run, the green one opens the Route Map.
struct RoadsideView: View {
    @State private var viewModel: RoadsideViewModel
    let onOpen: (AppRoute) -> Void
    let onPlay: (RunMode) -> Void

    @Environment(\.chromeInsets) private var chrome
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isShowingErrands = false

    init(viewModel: RoadsideViewModel, onOpen: @escaping (AppRoute) -> Void, onPlay: @escaping (RunMode) -> Void) {
        self.viewModel = viewModel
        self.onOpen = onOpen
        self.onPlay = onPlay
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        GeometryReader { proxy in
            let isWide = proxy.size.width > proxy.size.height * 1.15
            ScrollView {
                Group {
                    if isWide {
                        // Landscape iPad: the chicken and logo on the left, the road signs on the right.
                        HStack(alignment: .center, spacing: 28) {
                            VStack(spacing: 10) {
                                logo(maxWidth: 380)
                                HenOnShoulder(breed: viewModel.breed, compact: true)
                            }
                            .frame(maxWidth: .infinity)
                            actions
                                .frame(maxWidth: 440)
                        }
                        .frame(maxWidth: 1000)
                    } else {
                        VStack(spacing: 12) {
                            logo(maxWidth: sizeClass == .regular ? 460 : 340)
                            Spacer(minLength: 0)
                            HenOnShoulder(breed: viewModel.breed)
                            Spacer(minLength: 0)
                            actions
                        }
                        .frame(maxWidth: Theme.Metrics.maxContentWidth)
                    }
                }
                .padding(.horizontal, Theme.Metrics.screenPadding)
                .padding(.top, chrome.top + 4)
                .padding(.bottom, chrome.bottom + 22)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .artBackground(Art.homeBackdrop, alignment: .bottom)
        .sheet(isPresented: $isShowingErrands) {
            ErrandsSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .toast(message: $viewModel.toastMessage, isError: viewModel.toastIsError, inset: chrome.bottom)
        .onAppear { viewModel.refresh() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Home.roadside)
    }

    private func logo(maxWidth: CGFloat) -> some View {
        Image(Art.logo)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: maxWidth)
            .accessibilityLabel("Feather Freeway")
            .accessibilityAddTraits(.isHeader)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button { onPlay(.endless) } label: {
                VStack(spacing: 0) {
                    Text("ENDLESS FREEWAY")
                        .font(.sign(34, relativeTo: .title))
                    Text(viewModel.bestScore > 0 ? "Best score \(Formatters.integer(viewModel.bestScore))" : "How far can you run?")
                        .font(.rounded(.footnote, weight: .heavy))
                        .foregroundStyle(Theme.Colors.inkSoft)
                }
            }
            .buttonStyle(PanelButtonStyle(color: .yellow, height: 86))
            .accessibilityIdentifier(AccessibilityID.Home.play)

            HStack(spacing: 10) {
                Button { onOpen(.routeMap) } label: {
                    HStack(spacing: 8) {
                        Image(Art.Mile.open)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 40)
                            .overlay(alignment: .top) {
                                Text("\(viewModel.nextRoute.number)")
                                    .font(.sign(15, relativeTo: .caption))
                                    .foregroundStyle(.white)
                                    .padding(.top, 6)
                            }
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("ROUTE MAP").font(.sign(24, relativeTo: .headline))
                            Text("Next: \(viewModel.nextRoute.name)")
                                .font(.rounded(.caption, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(Theme.Colors.ink)
                    }
                }
                .buttonStyle(PanelButtonStyle(color: .green, height: 66))
                .accessibilityIdentifier(AccessibilityID.Home.routeMap)

                Button { isShowingErrands = true } label: {
                    VStack(spacing: 0) {
                        Image(Art.Panel.board)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                            .overlay(alignment: .top) { Image(Art.clipboardClip).resizable().scaledToFit().frame(width: 18).offset(y: -5) }
                            .accessibilityHidden(true)
                        Text("ERRANDS").font(.sign(18, relativeTo: .caption))
                    }
                    .overlay(alignment: .topTrailing) {
                        if viewModel.errandsReady > 0 {
                            Text("\(viewModel.errandsReady)")
                                .font(.sign(16, relativeTo: .caption))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Theme.Colors.tomato).stroke(Theme.Colors.ink, lineWidth: 2))
                                .offset(x: 16, y: -6)
                        }
                    }
                }
                .buttonStyle(PanelButtonStyle(color: .cream, height: 66))
                .frame(width: 112)
                .accessibilityLabel("Errands")
                .accessibilityValue("\(viewModel.errandsDone) of 3 claimed")
                .accessibilityIdentifier(AccessibilityID.Home.errands)

                SignButton(art: Art.Sign.help, label: "How to play", size: 54) { onOpen(.guide) }
                    .accessibilityIdentifier(AccessibilityID.Home.guide)
            }

        }
    }
}

/// The selected chicken bobbing on the road shoulder, with a licence plate for a name tag.
private struct HenOnShoulder: View {
    let breed: Breed
    var compact = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(spacing: -6) {
            PhaseAnimator([0.0, 1.0]) { phase in
                Image(Art.portrait(breed))
                    .resizable()
                    .scaledToFit()
                    .frame(width: compact ? 200 : sizeClass == .regular ? 260 : 190, height: compact ? 200 : sizeClass == .regular ? 260 : 190)
                    .scaleEffect(x: 1 - phase * 0.03, y: 1 + phase * 0.04, anchor: .bottom)
                    .offset(y: -phase * 4)
            } animation: { _ in .easeInOut(duration: 0.9) }
            .accessibilityHidden(true)
            VStack(spacing: 0) {
                Text(breed.name.uppercased())
                    .font(.sign(26, relativeTo: .title3))
                    .foregroundStyle(Theme.Colors.ink)
                    .kerning(3)
                Text("\(breed.traitName) · \(breed.kind)")
                    .font(.rounded(.caption, weight: .bold))
                    .foregroundStyle(Theme.Colors.inkSoft)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .panel(.plate)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(breed.name), \(breed.traitName): \(breed.traitDetail)")
        .accessibilityIdentifier(AccessibilityID.Home.hen)
    }
}

/// Today's three errands on a clipboard.
struct ErrandsSheet: View {
    let viewModel: RoadsideViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("TODAY'S ERRANDS")
                        .font(.sign(30, relativeTo: .title2))
                        .foregroundStyle(Theme.Colors.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("New in \(viewModel.refreshCountdown)")
                        .font(.rounded(.caption, weight: .bold))
                        .foregroundStyle(Theme.Colors.inkSoft)
                }
                ForEach(viewModel.errands) { errand in
                    ErrandRow(errand: errand) { viewModel.claim(errand) }
                }
                Text("Errands count runs in both Endless and Routes. They refresh every midnight.")
                    .font(.rounded(.footnote, weight: .medium))
                    .foregroundStyle(Theme.Colors.inkSoft)
            }
            .padding(.horizontal, 26)
            .padding(.top, 40)
            .padding(.bottom, 26)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
            .panel(.board)
            .overlay(alignment: .top) {
                Image(Art.clipboardClip).resizable().scaledToFit().frame(width: 120).offset(y: -18).accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.top, 34)
        }
        .background(Theme.Colors.grass)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Errands.sheet)
    }
}

private struct ErrandRow: View {
    let errand: Errand
    let onClaim: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: errand.claimed ? "checkmark.square.fill" : errand.isDone ? "square.dashed" : "square")
                .font(.title2.weight(.bold))
                .foregroundStyle(errand.claimed ? Theme.Colors.success : Theme.Colors.ink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(errand.title)
                    .font(.rounded(.subheadline, weight: .heavy))
                    .foregroundStyle(Theme.Colors.ink)
                    .strikethrough(errand.claimed)
                RoadMeter(fraction: Double(errand.progress) / Double(max(1, errand.goal)), done: errand.isDone)
                Text("\(min(errand.progress, errand.goal)) / \(errand.goal)")
                    .font(.rounded(.caption, weight: .bold))
                    .foregroundStyle(Theme.Colors.inkSoft)
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            if errand.claimed {
                Text("DONE").font(.sign(20, relativeTo: .headline)).foregroundStyle(Theme.Colors.success)
            } else {
                Button(action: onClaim) {
                    HStack(spacing: 4) {
                        Image(Art.cornIcon).resizable().scaledToFit().frame(width: 20, height: 20)
                        Text("+\(errand.reward)")
                    }
                }
                .buttonStyle(PanelButtonStyle(color: errand.isDone ? .green : .grey, height: 50, fontSize: 22))
                .frame(width: 104)
                .disabled(!errand.isDone)
                .accessibilityLabel(errand.isDone ? "Claim \(errand.reward) corn" : "Reward \(errand.reward) corn, not finished")
                .accessibilityIdentifier(AccessibilityID.Errands.claim(errand.slot))
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}

/// Chunky outlined progress bar (system bars are too faint on cream paper).
struct RoadMeter: View {
    let fraction: Double
    var done = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: 0xE3DCC8))
                if fraction > 0 {
                    Capsule()
                        .fill(done ? Theme.Colors.mint : Theme.Colors.bus)
                        .frame(width: max(10, proxy.size.width * min(1, fraction)))
                }
            }
            .overlay(Capsule().stroke(Theme.Colors.ink, lineWidth: 2))
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}
