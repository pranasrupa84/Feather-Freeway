import SpriteKit
import SwiftUI

/// Full-screen trip: the SpriteKit road under a SwiftUI dashboard.
struct GameView: View {
    @State private var viewModel: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastScenePhase: ScenePhase = .active

    init(viewModel: GameViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ZStack {
            if let scene = viewModel.scene {
                SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder])
                    .id(viewModel.sceneID)
                    .ignoresSafeArea()
                    .accessibilityLabel("Road")
            } else {
                Theme.Colors.grass.ignoresSafeArea()
            }

            switch viewModel.phase {
            case .running, .ending:
                RunHUDView(viewModel: viewModel)
            case .ready:
                ReadyTicket(viewModel: viewModel, onLeave: leave)
            case .countdown(let n):
                RunHUDView(viewModel: viewModel).allowsHitTesting(false)
                CountdownLight(value: n)
            case .paused:
                RunHUDView(viewModel: viewModel).allowsHitTesting(false)
                PauseOverlay(viewModel: viewModel, onQuit: leave)
            case .finished(let outcome):
                CitationView(outcome: outcome, viewModel: viewModel, onHome: leave)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { viewModel.prepareScene() }
        .task {
            // Showcase video: start by itself after the ticket has been on screen for a moment.
            guard viewModel.isShowcase else { return }
            try? await Task.sleep(for: .seconds(2.5))
            viewModel.begin()
        }
        .onDisappear { viewModel.tearDown() }
        .onChange(of: scenePhase) { _, phase in
            lastScenePhase = phase
            if phase == .background {
                viewModel.handleScenePhaseChange(phase)
            } else if phase == .inactive {
                // Brief inactive blips (system gestures, test runners) should not pause; a lasting one does.
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    if lastScenePhase != .active { viewModel.handleScenePhaseChange(.inactive) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Game.screen)
    }

    private func leave() {
        viewModel.tearDown()
        dismiss()
    }
}

// MARK: - HUD

private struct RunHUDView: View {
    let viewModel: GameViewModel

    var body: some View {
        let hud = viewModel.hud
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                OdometerPlate(score: hud.score, meters: hud.meters, multiplier: hud.multiplier)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 6) {
                    CornBadge(amount: hud.corn, compact: true)
                    if hud.mechanics.contains(.chicks) { ConvoyBadge(chicks: hud.chicks, cap: hud.convoyCap) }
                }
                SignButton(art: Art.Sign.pause, label: "Pause", size: 50) { viewModel.pause() }
                    .accessibilityIdentifier(AccessibilityID.Game.pause)
            }
            if let progress = hud.progress { RouteProgress(progress: progress, breed: viewModel.breed) }
            HStack(spacing: 8) {
                if hud.mechanics.contains(.flap) { FeatherMeter(value: hud.feather, ready: hud.isFlapReady) }
                Spacer(minLength: 0)
                if hud.magnetLeft > 0 { TimerChip(art: Art.magnet, seconds: hud.magnetLeft) }
                if hud.doubleLeft > 0 { TimerChip(art: Art.double, seconds: hud.doubleLeft) }
                if hud.streak >= 5, hud.mechanics.contains(.eggs) {
                    Chip(text: "STREAK \(hud.streak)", color: hud.streak >= RunSession.streakDoubleAt ? Theme.Colors.tomato : Theme.Colors.bus, textColor: hud.streak >= RunSession.streakDoubleAt ? .white : Theme.Colors.ink)
                }
            }
            if let banner = viewModel.banner {
                BannerSign(banner: banner)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .id(banner.id)
                    .padding(.top, 6)
            }
            Spacer()
            HStack(alignment: .bottom) {
                if viewModel.settings.leftHanded { eggButton(hud) } else { rigButton(hud) }
                Spacer()
                if viewModel.settings.leftHanded { rigButton(hud) } else { eggButton(hud) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func rigButton(_ hud: RunHUD) -> some View {
        if hud.mechanics.contains(.rig) {
            VStack(spacing: 4) {
                HStack(spacing: 2) {
                    ForEach(0..<RunSession.maxFuel, id: \.self) { i in
                        Image(Art.fuelCan)
                            .resizable().scaledToFit().frame(width: 24, height: 26)
                            .saturation(i < hud.fuel || hud.isRigging ? 1 : 0)
                            .opacity(i < hud.fuel || hud.isRigging ? 1 : 0.45)
                    }
                }
                .accessibilityHidden(true)
                Button { viewModel.activateRig() } label: {
                    Image(hud.isRigReady || hud.isRigging ? Art.HUD.rig : Art.HUD.rigOff)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 84, height: 84)
                        .overlay {
                            if hud.isRigging {
                                Circle().trim(from: 0, to: hud.rigFraction)
                                    .stroke(Theme.Colors.tomato, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .padding(3)
                            }
                        }
                        .phaseAnimator([1.0, 1.08], trigger: hud.isRigReady) { content, s in content.scaleEffect(hud.isRigReady ? s : 1) }
                }
                .buttonStyle(SignPressStyle())
                .disabled(!hud.isRigReady)
                .accessibilityLabel("Big Rig")
                .accessibilityValue(hud.isRigging ? "Driving" : hud.isRigReady ? "Ready" : "\(hud.fuel) of 3 fuel cans")
                .accessibilityIdentifier(AccessibilityID.Game.rig)
            }
        } else {
            Color.clear.frame(width: 84, height: 1)
        }
    }

    @ViewBuilder
    private func eggButton(_ hud: RunHUD) -> some View {
        if hud.mechanics.contains(.eggs) {
            Button { viewModel.throwEgg() } label: {
                Image(hud.eggs > 0 ? Art.HUD.egg : Art.HUD.eggOff)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .overlay(alignment: .topTrailing) {
                        Text("\(hud.eggs)/\(hud.maxEggs)")
                            .font(.sign(18, relativeTo: .caption))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.top, 3).padding(.bottom, 1)
                            .background(Capsule().fill(Theme.Colors.ink))
                            .offset(x: 4, y: -2)
                    }
            }
            .buttonStyle(SignPressStyle())
            .disabled(hud.eggs == 0)
            .accessibilityLabel("Throw egg")
            .accessibilityValue("\(hud.eggs) eggs")
            .accessibilityIdentifier(AccessibilityID.Game.egg)
        } else {
            Color.clear.frame(width: 84, height: 1)
        }
    }
}

private struct OdometerPlate: View {
    let score: Int
    let meters: Int
    let multiplier: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(String(format: "%07d", min(score, 9_999_999)))
                    .font(.sign(30, relativeTo: .title))
                    .foregroundStyle(Theme.Colors.bus)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityIdentifier(AccessibilityID.Game.score)
                if multiplier > 1.01 {
                    Text("×\(multiplier.formatted(.number.precision(.fractionLength(0...2))))")
                        .font(.sign(20, relativeTo: .headline))
                        .foregroundStyle(Theme.Colors.ink)
                        .padding(.horizontal, 6).padding(.top, 2)
                        .background(Capsule().fill(Theme.Colors.mint))
                }
            }
            Text(Formatters.meters(meters))
                .font(.rounded(.caption, weight: .heavy))
                .foregroundStyle(.white.opacity(0.9))
                .monospacedDigit()
        }
        .padding(.leading, 14).padding(.trailing, 14).padding(.top, 8).padding(.bottom, 12)
        .panel(.pump)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score \(score), \(meters) metres")
    }
}

private struct ConvoyBadge: View {
    let chicks: Int
    let cap: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(Art.chickFace).resizable().scaledToFit().frame(width: 24, height: 24)
            Text("\(chicks)/\(cap)")
                .font(.sign(20, relativeTo: .headline))
                .foregroundStyle(Theme.Colors.ink)
                .monospacedDigit()
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(Theme.Colors.cream).stroke(Theme.Colors.ink, lineWidth: 2.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chick convoy \(chicks) of \(cap)")
    }
}

private struct FeatherMeter: View {
    let value: Double
    let ready: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(Art.feather).resizable().scaledToFit().frame(width: 22, height: 26)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.ink.opacity(0.75))
                Capsule()
                    .fill(ready ? AnyShapeStyle(LinearGradient(colors: [Theme.Colors.mint, .white, Theme.Colors.mint], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Theme.Colors.mint))
                    .frame(width: max(8, 96 * value))
                    .animation(.spring(duration: 0.3), value: value)
            }
            .frame(width: 96, height: 14)
            .overlay(Capsule().stroke(Theme.Colors.ink, lineWidth: 2))
            if ready {
                Text("SWIPE ↑")
                    .font(.sign(16, relativeTo: .caption))
                    .foregroundStyle(Theme.Colors.ink)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .fixedSize()
        .background(Capsule().fill(Theme.Colors.cream).stroke(Theme.Colors.ink, lineWidth: 2.5))
        .phaseAnimator([1.0, 1.06], trigger: ready) { c, s in c.scaleEffect(ready ? s : 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Feather meter")
        .accessibilityValue(ready ? "Full, swipe up to Flap Hop" : "\(Int(value * 100)) percent")
    }
}

private struct TimerChip: View {
    let art: String
    let seconds: Double

    var body: some View {
        HStack(spacing: 3) {
            Image(art).resizable().scaledToFit().frame(width: 22, height: 22)
            Text(Formatters.seconds(seconds))
                .font(.sign(18, relativeTo: .caption))
                .foregroundStyle(Theme.Colors.ink)
                .monospacedDigit()
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Theme.Colors.cream).stroke(Theme.Colors.ink, lineWidth: 2.5))
    }
}

private struct RouteProgress: View {
    let progress: Double
    let breed: Breed

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.asphalt).overlay(Capsule().stroke(Theme.Colors.ink, lineWidth: 2.5))
                Capsule().fill(Theme.Colors.bus).frame(width: max(10, proxy.size.width * progress)).padding(3)
                Image(Art.Scene.finishStrip).resizable().frame(width: 18).clipShape(Capsule()).frame(maxWidth: .infinity, alignment: .trailing).padding(3)
                Image(Art.hen(breed, frame: 0)).resizable().scaledToFit().frame(width: 28, height: 28)
                    .offset(x: max(0, proxy.size.width * progress - 16))
            }
        }
        .frame(height: 18)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Route progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

private struct BannerSign: View {
    let banner: GameViewModel.Banner

    var body: some View {
        HStack(spacing: 10) {
            if let art = banner.art {
                Image(art).resizable().scaledToFit().frame(width: 30, height: 30)
            }
            VStack(spacing: 0) {
                Text(banner.title)
                    .font(.sign(24, relativeTo: .title3))
                    .foregroundStyle(banner.style == .yellow ? Theme.Colors.ink : .white)
                    .kerning(1.5)
                if let detail = banner.detail {
                    Text(detail)
                        .font(.rounded(.caption, weight: .heavy))
                        .foregroundStyle(banner.style == .yellow ? Theme.Colors.ink : .white)
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 9).padding(.bottom, 15)
        .fixedSize()
        .panel(panel)
        .accessibilityElement(children: .combine)
    }

    private var panel: PanelArt {
        switch banner.style {
        case .green: .sign
        case .blue: .signBlue
        case .yellow: .button(.yellow)
        case .red: .button(.red)
        }
    }
}

// MARK: - Ready, countdown, pause

private struct ReadyTicket: View {
    let viewModel: GameViewModel
    let onLeave: () -> Void

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.route == nil ? "ENDLESS FREEWAY" : "ROUTE \(viewModel.route?.number ?? 1)")
                    .font(.sign(18, relativeTo: .caption))
                    .foregroundStyle(Theme.Colors.tomatoDeep)
                    .kerning(3)
                Text((viewModel.route?.name ?? "How far can you run?").uppercased())
                    .font(.sign(36, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.Colors.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 12) {
                    Image(Art.portrait(viewModel.breed)).resizable().scaledToFit().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(viewModel.breed.name) · \(viewModel.breed.traitName)").font(.rounded(.subheadline, weight: .heavy)).foregroundStyle(Theme.Colors.ink)
                        Text(viewModel.breed.traitDetail).font(.rounded(.caption, weight: .medium)).foregroundStyle(Theme.Colors.inkSoft).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let route = viewModel.route {
                    VStack(alignment: .leading, spacing: 4) {
                        goal(1, "Reach the finish (\(Formatters.meters(route.meters)))", route)
                        goal(2, "Collect \(route.cornGoal) corn", route)
                        goal(3, route.starGoal.label, route)
                    }
                } else {
                    Text(viewModel.bestScore > 0 ? "Best score: \(Formatters.integer(viewModel.bestScore))" : "Swipe to dodge. The road gets busier and wider as you go.")
                        .font(.rounded(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.Colors.ink)
                }
                Text("Swipe ← → lanes · ↑ jump · ↓ dive")
                    .font(.rounded(.caption, weight: .heavy))
                    .foregroundStyle(Theme.Colors.inkSoft)
                HStack(spacing: 10) {
                    Button("BACK", action: onLeave)
                        .buttonStyle(PanelButtonStyle(color: .cream, height: 62, fontSize: 24))
                        .frame(width: 120)
                        .accessibilityIdentifier(AccessibilityID.Game.leave)
                    Button("GO!") { viewModel.begin() }
                        .buttonStyle(PanelButtonStyle(color: .green, height: 62, fontSize: 32))
                        .accessibilityIdentifier(AccessibilityID.Game.go)
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 26)
            .panel(.ticket)
            .padding(16)
            .frame(maxWidth: 520)
        }
    }

    private func goal(_ n: Int, _ text: String, _ route: Route) -> some View {
        HStack(spacing: 8) {
            Image(viewModel.routeStars >= n ? Art.starFull : Art.starEmpty).resizable().scaledToFit().frame(width: 22, height: 22)
            Text(text).font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.Colors.ink)
        }
    }
}

/// A big traffic light counts down: red, amber, green.
private struct CountdownLight: View {
    let value: Int

    var body: some View {
        VStack(spacing: 4) {
            Image(value == 3 ? Art.Scene.signalRed : value == 2 ? Art.Scene.signalAmber : Art.Scene.signalGreen)
                .resizable()
                .scaledToFit()
                .frame(height: 200)
            Text(value == 1 ? "GO!" : "\(value)")
                .font(.sign(72, relativeTo: .largeTitle))
                .foregroundStyle(value == 1 ? Theme.Colors.mint : Theme.Colors.bus)
                .padding(.horizontal, 26)
                .padding(.top, 8)
                .background(Capsule().fill(Theme.Colors.ink).stroke(.white, lineWidth: 3))
        }
        .id(value)
            .transition(.scale(scale: 1.4).combined(with: .opacity))
            .accessibilityLabel(value == 1 ? "Go" : "\(value)")
    }
}

private struct PauseOverlay: View {
    let viewModel: GameViewModel
    let onQuit: () -> Void

    var body: some View {
        ZStack {
            Theme.Colors.ink.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                HazardStripe().frame(height: 18)
                Text("HAZARD LIGHTS ON")
                    .font(.sign(34, relativeTo: .title))
                    .foregroundStyle(Theme.Colors.ink)
                Text("Pulled over on the shoulder. Ready when you are.")
                    .font(.rounded(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.Colors.inkSoft)
                    .multilineTextAlignment(.center)
                Button("RESUME") { viewModel.resume() }
                    .buttonStyle(PanelButtonStyle(color: .green, height: 62))
                    .accessibilityIdentifier(AccessibilityID.Game.resume)
                HStack(spacing: 10) {
                    Button("RESTART") { viewModel.restart() }
                        .buttonStyle(PanelButtonStyle(color: .yellow, height: 56, fontSize: 22))
                        .accessibilityIdentifier(AccessibilityID.Game.restart)
                    Button("QUIT", action: onQuit)
                        .buttonStyle(PanelButtonStyle(color: .red, height: 56, fontSize: 22))
                        .accessibilityIdentifier(AccessibilityID.Game.quit)
                }
                HazardStripe().frame(height: 18)
            }
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 24).fill(Theme.Colors.cream).stroke(Theme.Colors.ink, lineWidth: 4))
            .padding(24)
            .frame(maxWidth: 460)
        }
    }
}

private struct HazardStripe: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.Colors.bus))
            var x: CGFloat = -size.height
            while x < size.width {
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                p.addLine(to: CGPoint(x: x + size.height * 2, y: 0))
                p.addLine(to: CGPoint(x: x + size.height, y: size.height))
                ctx.fill(p, with: .color(Theme.Colors.ink))
                x += size.height * 2
            }
        }
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}
