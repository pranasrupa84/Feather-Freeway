import SwiftUI

/// The Glovebox: your driver's licence (records), citation medals (achievements),
/// the odometer (lifetime stats) and the trip log.
struct GloveboxView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let badgeColumns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                LicenceCard(profile: store.profile)
                    .accessibilityIdentifier(AccessibilityID.Glovebox.licence)
                section("Citations", subtitle: "\(store.achievements.filter(\.isEarned).count) of \(store.achievements.count) earned")
                LazyVGrid(columns: badgeColumns, spacing: 12) {
                    ForEach(store.achievements) { BadgeTile(achievement: $0) }
                }
                section("Odometer", subtitle: "Lifetime numbers")
                Odometer(profile: store.profile)
                section("Trip log", subtitle: store.recentRuns.isEmpty ? "No trips yet" : "Last \(store.recentRuns.count) trips")
                VStack(spacing: 10) {
                    if store.recentRuns.isEmpty {
                        Text("Your trips will be logged here. Hit the road!")
                            .font(.rounded(.subheadline, weight: .bold))
                            .foregroundStyle(Theme.Colors.ink)
                            .frame(maxWidth: .infinity)
                            .stickerCard()
                    }
                    ForEach(store.recentRuns) { TripRow(record: $0) }
                }
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.top, 14)
            .padding(.bottom, 30)
            .frame(maxWidth: Theme.Metrics.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                BackSign()
                HighwaySignHeader(title: "Glovebox", subtitle: "Licence, citations and the trip log", style: .signBlue)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .frame(maxWidth: Theme.Metrics.maxContentWidth)
            .frame(maxWidth: .infinity)
            .roadBand()
        }
        .tiledBackground(Art.Tile.leather)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Glovebox.screen)
    }

    private func section(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.sign(28, relativeTo: .title2))
                .foregroundStyle(Theme.Colors.bus)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Text(subtitle)
                .font(.rounded(.footnote, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

private struct LicenceCard: View {
    let profile: PlayerProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FEATHER FREEWAY · DRIVER LICENCE")
                    .font(.sign(17, relativeTo: .caption))
                    .foregroundStyle(.white)
                    .kerning(1.5)
                Spacer()
                Text("CLASS C")
                    .font(.sign(17, relativeTo: .caption))
                    .foregroundStyle(Theme.Colors.bus)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16).fill(Theme.Colors.signBlue))
            HStack(alignment: .top, spacing: 14) {
                Image(Art.portrait(profile.selectedBreed))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 120)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.Colors.sky.opacity(0.4)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.Colors.ink, lineWidth: 2.5))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    field("Driver", profile.selectedBreed.name)
                    field("Best score", Formatters.integer(profile.bestScore))
                    field("Best distance", Formatters.meters(profile.bestMeters))
                    field("Route stars", "\(profile.totalStars) / \(RouteCatalog.count * 3)")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0xE9F7F1)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.Colors.ink, lineWidth: 3.5))
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.Colors.ink).offset(y: 5))
        .accessibilityElement(children: .combine)
    }

    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(.sign(14, relativeTo: .caption)).foregroundStyle(Theme.Colors.inkSoft)
            Text(value).font(.rounded(.headline, weight: .heavy)).foregroundStyle(Theme.Colors.ink).monospacedDigit()
        }
    }
}

private struct BadgeTile: View {
    let achievement: Achievement

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Image(achievement.isEarned ? Art.badgeEarned : Art.badgeLocked)
                    .resizable()
                    .scaledToFit()
                Image(achievement.art)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                    .saturation(achievement.isEarned ? 1 : 0)
                    .opacity(achievement.isEarned ? 1 : 0.55)
                    .offset(y: -6)
            }
            .frame(width: 84, height: 86)
            .accessibilityHidden(true)
            Text(achievement.title)
                .font(.rounded(.subheadline, weight: .heavy))
                .foregroundStyle(Theme.Colors.ink)
                .multilineTextAlignment(.center)
            Text(achievement.detail)
                .font(.rounded(.caption, weight: .medium))
                .foregroundStyle(Theme.Colors.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            RoadMeter(fraction: achievement.fraction, done: achievement.isEarned)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .stickerCard(fill: Theme.Colors.paper, padding: 10, radius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityValue(achievement.isEarned ? "Earned" : "\(min(achievement.progress, achievement.goal)) of \(achievement.goal)")
    }
}

private struct Odometer: View {
    let profile: PlayerProfile

    var body: some View {
        let rows: [(String, String, String)] = [
            (Art.Sign.map, "Trips", Formatters.integer(profile.totalRuns)),
            (Art.hen(.clover, frame: 0), "Distance run", Formatters.meters(profile.totalMeters)),
            (Art.cornIcon, "Corn picked up", Formatters.integer(profile.totalCorn)),
            (Art.chickFace, "Chicks rescued", Formatters.integer(profile.totalChicks)),
            (Art.rig, "Cars smashed", Formatters.integer(profile.totalSmashes)),
            (Art.feather, "Close calls", Formatters.integer(profile.totalCloseCalls)),
            (Art.egg, "Windscreens splatted", Formatters.integer(profile.totalSplats)),
            (Art.signLaneEnds, "Late merges", Formatters.integer(profile.totalLateMerges)),
            (Art.eggGolden, "Express tolls", Formatters.integer(profile.totalExpressTolls)),
            (Art.Panel.board, "Errands done", Formatters.integer(profile.errandsCompleted)),
        ]
        VStack(spacing: 0) {
            ForEach(rows, id: \.1) { row in
                HStack(spacing: 12) {
                    ArtIcon(name: row.0, size: 38)
                    Text(row.1).font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.Colors.ink)
                    Spacer()
                    Text(row.2)
                        .font(.sign(24, relativeTo: .headline))
                        .foregroundStyle(Theme.Colors.bus)
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.Colors.ink))
                }
                .padding(.vertical, 7)
                .accessibilityElement(children: .combine)
                if row.1 != rows.last?.1 { Divider() }
            }
        }
        .stickerCard(fill: Theme.Colors.paper)
    }
}

private struct TripRow: View {
    let record: RunRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(Art.portrait(record.breed)).resizable().scaledToFit().frame(width: 46, height: 46).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.route.map { "Route \($0.number): \($0.name)" } ?? "Endless Freeway")
                    .font(.rounded(.subheadline, weight: .heavy))
                    .foregroundStyle(Theme.Colors.ink)
                Text("\(Formatters.tripDate(record.date)) · \(Formatters.meters(record.meters)) · \(record.result == .cleared ? "cleared" : "crashed")")
                    .font(.rounded(.caption, weight: .medium))
                    .foregroundStyle(Theme.Colors.inkSoft)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatters.integer(record.score)).font(.sign(22, relativeTo: .headline)).foregroundStyle(Theme.Colors.ink).monospacedDigit()
                if record.route != nil { StarRow(stars: record.stars, size: 14, spacing: 0) }
                Text("+\(record.reward) corn").font(.rounded(.caption2, weight: .heavy)).foregroundStyle(Theme.Colors.mintDeep)
            }
        }
        .stickerCard(fill: Theme.Colors.paper, padding: 10, radius: 14)
        .accessibilityElement(children: .combine)
    }
}
