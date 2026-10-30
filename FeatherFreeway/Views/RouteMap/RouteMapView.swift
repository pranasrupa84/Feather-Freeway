import SwiftUI

/// A winding country road with a mile marker for each of the 30 routes. Route 1 is at the bottom;
/// the road climbs through the four worlds toward the neon night.
struct RouteMapView: View {
    let onPlay: (RunMode) -> Void

    @Environment(ProfileStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Route?

    private let spacing: CGFloat = 116
    private let topPad: CGFloat = 70
    private let bottomPad: CGFloat = 90

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, 700)
            let points = markerPoints(width: width)
            let height = topPad + bottomPad + spacing * CGFloat(RouteCatalog.count - 1)
            ScrollViewReader { reader in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        RoadPath(points: points)
                            .frame(width: width, height: height)
                            .accessibilityHidden(true)
                        ForEach(RouteCatalog.routes) { route in
                            let p = points[route.index]
                            MileMarker(route: route, stars: store.profile.stars(forRoute: route.index), isUnlocked: store.profile.isRouteUnlocked(route.index), isNext: route.index == store.profile.nextRouteIndex) {
                                selected = route
                            }
                            .position(p)
                            .id(route.index)
                            if isWorldStart(route) {
                                WorldBadge(world: route.world)
                                    .position(x: p.x < width / 2 ? min(width - 90, p.x + 150) : max(90, p.x - 150), y: p.y + 6)
                            }
                        }
                    }
                    .frame(width: width, height: height)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.bottom)
                .onAppear {
                    reader.scrollTo(store.profile.nextRouteIndex, anchor: .center)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                BackSign()
                HighwaySignHeader(title: "Route Map", subtitle: "\(store.profile.totalStars) of \(RouteCatalog.count * 3) stars")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .frame(maxWidth: Theme.Metrics.maxContentWidth)
            .frame(maxWidth: .infinity)
            .roadBand()
        }
        .tiledBackground(Art.Tile.map)
        .sheet(item: $selected) { route in
            TripTicket(route: route, stars: store.profile.stars(forRoute: route.index), isUnlocked: store.profile.isRouteUnlocked(route.index)) {
                selected = nil
                onPlay(.route(route.index))
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.RouteMap.screen)
    }

    private func isWorldStart(_ route: Route) -> Bool {
        route.index == 0 || RouteCatalog.routes[route.index - 1].world != route.world
    }

    /// Zig-zag positions, route 1 at the bottom.
    private func markerPoints(width: CGFloat) -> [CGPoint] {
        let amplitude = width * 0.26
        return (0..<RouteCatalog.count).map { i in
            let y = topPad + spacing * CGFloat(RouteCatalog.count - 1 - i)
            let x = width / 2 + sin(CGFloat(i) * 0.95) * amplitude
            return CGPoint(x: x, y: y)
        }
    }
}

/// The asphalt ribbon linking the markers.
private struct RoadPath: View {
    let points: [CGPoint]

    var body: some View {
        Canvas { context, _ in
            var path = Path()
            guard let first = points.first else { return }
            path.move(to: CGPoint(x: first.x, y: first.y + 200))
            path.addLine(to: first)
            for i in 1..<points.count {
                let a = points[i - 1], b = points[i]
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                path.addQuadCurve(to: mid, control: CGPoint(x: a.x, y: mid.y))
                path.addQuadCurve(to: b, control: CGPoint(x: b.x, y: mid.y))
            }
            if let last = points.last { path.addLine(to: CGPoint(x: last.x, y: last.y - 200)) }
            context.stroke(path, with: .color(Theme.Colors.ink), style: StrokeStyle(lineWidth: 54, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(Theme.Colors.asphalt), style: StrokeStyle(lineWidth: 44, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [14, 14]))
        }
    }
}

private struct MileMarker: View {
    let route: Route
    let stars: Int
    let isUnlocked: Bool
    let isNext: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                ZStack(alignment: .top) {
                    Image(!isUnlocked ? Art.Mile.locked : stars > 0 ? Art.Mile.done : Art.Mile.open)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 62, height: 84)
                    if isUnlocked {
                        Text("\(route.number)")
                            .font(.sign(30, relativeTo: .title2))
                            .foregroundStyle(.white)
                            .padding(.top, 14)
                    } else {
                        Image(Art.lock).resizable().scaledToFit().frame(width: 30).padding(.top, 12)
                    }
                }
                StarRow(stars: stars, size: 18, spacing: 0)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.Colors.cream).stroke(Theme.Colors.ink, lineWidth: 2))
            }
            .scaleEffect(isNext ? 1.12 : 1)
            .overlay(alignment: .topTrailing) {
                if isNext {
                    Image(Art.hen(.clover, frame: 2))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40)
                        .offset(x: 40, y: -26)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(SignPressStyle())
        .accessibilityLabel("Route \(route.number), \(route.name)")
        .accessibilityValue(isUnlocked ? "\(stars) of 3 stars" : "Locked")
        .accessibilityIdentifier(AccessibilityID.RouteMap.marker(route.index))
    }
}

private struct WorldBadge: View {
    let world: World

    var body: some View {
        VStack(spacing: 4) {
            Image(Art.world(world))
                .resizable()
                .scaledToFill()
                .frame(width: 130, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Colors.ink, lineWidth: 3))
            Text(world.title.uppercased())
                .font(.sign(16, relativeTo: .caption))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.Colors.signGreen).stroke(Theme.Colors.ink, lineWidth: 2))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(world.title)
    }
}

/// Pre-trip ticket: what the route asks for and what it pays.
struct TripTicket: View {
    let route: Route
    let stars: Int
    let isUnlocked: Bool
    let onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("TRIP TICKET")
                        .font(.sign(18, relativeTo: .caption))
                        .foregroundStyle(Theme.Colors.tomatoDeep)
                        .kerning(3)
                    Spacer()
                    Text("No. \(String(format: "%03d", route.number))")
                        .font(.sign(18, relativeTo: .caption))
                        .foregroundStyle(Theme.Colors.inkSoft)
                }
                Text(route.name.uppercased())
                    .font(.sign(40, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                Image(Art.world(route.world))
                    .resizable()
                    .scaledToFill()
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.Colors.ink, lineWidth: 3))
                    .accessibilityHidden(true)
                HStack(spacing: 10) {
                    fact("Distance", Formatters.meters(route.meters))
                    fact("Lanes", laneText)
                    fact("World", route.world.title)
                }
                if let feature = route.newFeature {
                    HStack(spacing: 8) {
                        Chip(text: "NEW", color: Theme.Colors.tomato, textColor: .white)
                        Text(feature).font(.rounded(.subheadline, weight: .heavy)).foregroundStyle(Theme.Colors.ink)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("STARS").font(.sign(20, relativeTo: .headline)).foregroundStyle(Theme.Colors.inkSoft)
                    goal(1, "Reach the finish line")
                    goal(2, "Collect \(route.cornGoal) corn")
                    goal(3, route.starGoal.label)
                }
                if isUnlocked {
                    Button(action: onStart) {
                        Text(stars > 0 ? "DRIVE AGAIN" : "HIT THE ROAD")
                    }
                    .buttonStyle(PanelButtonStyle(color: .yellow, height: 70, fontSize: 30))
                    .accessibilityIdentifier(AccessibilityID.RouteMap.start)
                } else {
                    Text("Earn a star on route \(route.number - 1) to open this road.")
                        .font(.rounded(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.Colors.danger)
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
            .panel(.ticket)
            .padding(18)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.Colors.grass)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.RouteMap.ticket)
    }

    private var laneText: String {
        let lo = route.lanePattern.min() ?? 3, hi = route.lanePattern.max() ?? 3
        return lo == hi || !route.mechanics.contains(.laneShift) ? "\(route.lanePattern.first ?? 3)" : "\(lo)–\(hi)"
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(.sign(14, relativeTo: .caption)).foregroundStyle(Theme.Colors.inkSoft)
            Text(value).font(.rounded(.subheadline, weight: .heavy)).foregroundStyle(Theme.Colors.ink).lineLimit(2).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func goal(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(stars >= n ? Art.starFull : Art.starEmpty).resizable().scaledToFit().frame(width: 28, height: 28)
            Text(text).font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.Colors.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(stars >= n ? "Earned" : "Not earned")
    }
}
