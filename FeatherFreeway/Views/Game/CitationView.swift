import SwiftUI

/// End of a trip as a Freeway Patrol citation: the numbers in ruled fields, a rubber stamp
/// and what the trip paid.
struct CitationView: View {
    let outcome: RunOutcome
    let viewModel: GameViewModel
    let onHome: () -> Void

    @State private var stamped = false

    private var summary: RunSummary { outcome.summary }

    var body: some View {
        ZStack {
            Theme.Colors.ink.opacity(0.5).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    Divider().overlay(Theme.Colors.ink)
                    HStack(alignment: .top, spacing: 12) {
                        Image(Art.portrait(summary.breed))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 84, height: 84)
                            .rotationEffect(.degrees(summary.result == .crashed ? -14 : 0))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            field("Driver", summary.breed.name)
                            field("Location", location)
                            field("Offence", offence)
                        }
                    }
                    grid
                    if let route = summary.mode.routeIndex.flatMap({ RouteCatalog.route($0) }) {
                        HStack(spacing: 10) {
                            StarRow(stars: outcome.stars, size: 34, spacing: 4)
                            if outcome.newStars > 0 {
                                Chip(text: "+\(outcome.newStars) NEW", color: Theme.Colors.bus)
                            }
                            Spacer()
                            Text("\(route.name)").font(.rounded(.caption2, weight: .bold)).foregroundStyle(Theme.Colors.inkSoft)
                        }
                    }
                    rewardLine
                    ForEach(outcome.completedErrands, id: \.self) { title in
                        note("Errand done: \(title)", art: Art.starFull)
                    }
                    ForEach(outcome.newAchievements, id: \.self) { title in
                        note("New citation medal: \(title)", art: Art.badgeEarned)
                    }
                    buttons
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 26)
                .panel(.ticket)
                .overlay(alignment: .topTrailing) { stamp }
                .padding(16)
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { withAnimation(.spring(duration: 0.35, bounce: 0.5).delay(0.35)) { stamped = true } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Game.citation)
    }

    private var location: String {
        if let route = summary.mode.routeIndex.flatMap({ RouteCatalog.route($0) }) { return "Route \(route.number), \(route.name)" }
        return "Endless Freeway, \(summary.furthestWorld.title)"
    }

    private var offence: String {
        if summary.result == .cleared { return "Excessive fun to the finish line" }
        return summary.smashes > 10 ? "Reckless trucking, then a crash" : "Crossing the road without looking"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("FREEWAY PATROL · CITATION")
                .font(.sign(18, relativeTo: .caption))
                .foregroundStyle(Theme.Colors.tomatoDeep)
                .kerning(2)
            Text(summary.result == .cleared ? "ROUTE CLEARED" : "TRIP OVER")
                .font(.sign(42, relativeTo: .largeTitle))
                .foregroundStyle(Theme.Colors.ink)
                .accessibilityAddTraits(.isHeader)
            Text("No. \(String(format: "%06d", summary.score % 1_000_000)) · \(Formatters.ticketDate(.now))")
                .font(.rounded(.caption, weight: .bold))
                .foregroundStyle(Theme.Colors.inkSoft)
        }
    }

    private var grid: some View {
        let cells: [(String, String)] = [
            ("Score", Formatters.integer(summary.score)),
            ("Distance", Formatters.meters(summary.meters)),
            ("Corn", Formatters.integer(summary.corn)),
            ("Chicks saved", "\(summary.chicksRescued)"),
            ("Cars smashed", "\(summary.smashes)"),
            ("Close calls", "\(summary.closeCalls)"),
            ("Splats", "\(summary.splats)"),
            ("Late merges", "\(summary.lateMerges)"),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 8) {
            ForEach(cells, id: \.0) { cell in field(cell.0, cell.1) }
        }
    }

    private var rewardLine: some View {
        HStack(spacing: 8) {
            Image(Art.cornIcon).resizable().scaledToFit().frame(width: 34, height: 34).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("FINE: NONE. YOU EARN")
                    .font(.sign(16, relativeTo: .caption))
                    .foregroundStyle(Theme.Colors.inkSoft)
                Text("+\(Formatters.integer(outcome.totalReward)) corn")
                    .font(.sign(30, relativeTo: .title2))
                    .foregroundStyle(Theme.Colors.mintDeep)
            }
            Spacer()
            if outcome.starBonus > 0 {
                Text("incl. +\(outcome.starBonus) star bonus").font(.rounded(.caption2, weight: .bold)).foregroundStyle(Theme.Colors.inkSoft)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.Colors.mint.opacity(0.18)).stroke(Theme.Colors.mintDeep, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
        .accessibilityElement(children: .combine)
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button(viewModel.playAgainTitle) { viewModel.playAgain() }
                .buttonStyle(PanelButtonStyle(color: .green, height: 62, fontSize: 28))
                .accessibilityIdentifier(AccessibilityID.Game.again)
            Button("BACK TO THE ROADSIDE", action: onHome)
                .buttonStyle(PanelButtonStyle(color: .cream, height: 56, fontSize: 22))
                .accessibilityIdentifier(AccessibilityID.Game.home)
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private var stamp: some View {
        let art = outcome.isNewBestScore || (summary.mode == .endless && outcome.isNewBestMeters) ? Art.stampRecord
            : summary.result == .cleared ? Art.stampClear : Art.stampCrash
        Image(art)
            .resizable()
            .scaledToFit()
            .frame(width: 170)
            .rotationEffect(.degrees(-10))
            .scaleEffect(stamped ? 1 : 2.4)
            .opacity(stamped ? 0.92 : 0)
            .offset(x: -6, y: 70)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(.sign(14, relativeTo: .caption)).foregroundStyle(Theme.Colors.inkSoft)
            Text(value)
                .font(.custom("Noteworthy-Bold", size: 19, relativeTo: .headline))
                .foregroundStyle(Theme.Colors.signBlue)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    private func note(_ text: String, art: String) -> some View {
        HStack(spacing: 8) {
            Image(art).resizable().scaledToFit().frame(width: 26, height: 26).accessibilityHidden(true)
            Text(text).font(.rounded(.footnote, weight: .heavy)).foregroundStyle(Theme.Colors.ink)
        }
    }
}
