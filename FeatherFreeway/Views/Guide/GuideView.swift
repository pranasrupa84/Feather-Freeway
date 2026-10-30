import SwiftUI

/// How to play: one illustrated page per control and mechanic. Shown once before the first trip.
struct GuideView: View {
    let isOnboarding: Bool
    let onFinish: (() -> Void)?

    @State private var page = 0
    @Environment(\.dismiss) private var dismiss

    struct Page: Identifiable {
        let id: Int
        let art: String
        let tag: String
        let title: String
        let text: String
    }

    static let pages: [Page] = [
        Page(id: 0, art: Art.Guide.lanes, tag: "Control", title: "Change lanes", text: "Swipe left or right to hop between lanes. Roads have anywhere from 2 to 7 lanes, so keep an eye on the edges."),
        Page(id: 1, art: Art.Guide.jump, tag: "Control", title: "Jump", text: "Swipe up to jump over cones, potholes and cars parked at a red light. Moving cars are too tall: dodge them."),
        Page(id: 2, art: Art.Guide.dive, tag: "Control", title: "Dive", text: "Swipe down to duck under red-and-white barrier arms."),
        Page(id: 3, art: Art.Guide.rig, tag: "Active", title: "Big Rig", text: "Collect 3 fuel cans, then tap RIG. For a few seconds you drive a truck that smashes every car, cone and closed toll gate for score and corn. Concrete lane barriers still stop it."),
        Page(id: 4, art: Art.Guide.flap, tag: "Active", title: "Close calls & Flap Hop", text: "Brushing past a car without touching it is a close call. Close calls fill the feather meter. When it's full, swipe up to Flap Hop over everything for a moment."),
        Page(id: 5, art: Art.Guide.egg, tag: "Active", title: "Egg Splat", text: "Tap EGG to throw an egg up your lane. The first car it hits gets a splattered windscreen and swerves into the next lane, or stops if it can't."),
        Page(id: 6, art: Art.Guide.convoy, tag: "Passive", title: "Chick Convoy", text: "Pick up lost chicks. Each one adds +1 to your score multiplier. If you bump into something, the convoy scatters instead of you crashing: half the chicks run off."),
        Page(id: 7, art: Art.Guide.streak, tag: "Passive", title: "Corn Streak", text: "Grab corn without a break to build a streak. Every 15 in a row lays an egg for Egg Splat, and from 30 every kernel counts double."),
        Page(id: 8, art: Art.Guide.traits, tag: "Passive", title: "Breed perks", text: "Every chicken in the Coop has a perk: extra eggs, a slimmer hitbox, a longer Big Rig, a forgiven bump, a corn magnet, starting chicks or extra speed."),
        Page(id: 9, art: Art.Guide.signals, tag: "Road", title: "Traffic signals", text: "A red light parks a queue of cars in one lane: jump them one by one for the corn in between. A green light sends a fast wave down a lane. Get out of it, or ride through in the Big Rig for double points."),
        Page(id: 10, art: Art.Guide.blinkers, tag: "Road", title: "Blinkers", text: "A flashing orange light means a car is about to change lanes. It moves over right in front of you."),
        Page(id: 11, art: Art.Guide.merge, tag: "Road", title: "Lane Shift", text: "Lanes end behind concrete barriers and new ones open up. Watch for the yellow LANE ENDS sign. Merge out at the very last moment for a Late Merge bonus."),
        Page(id: 12, art: Art.Guide.toll, tag: "Road", title: "Toll Plaza", text: "Between worlds you reach a toll plaza. Go through a green gate. Red gates are closed. The gold Express gate only opens with 3 or more chicks, and it pays corn for each one."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if !isOnboarding { BackSign() }
                HighwaySignHeader(title: "How to play", subtitle: "\(page + 1) of \(Self.pages.count)", style: .signBlue)
            }
            .padding(.horizontal, 12)
            .padding(.top, isOnboarding ? 18 : 0)
            .frame(maxWidth: 600)

            TabView(selection: $page) {
                ForEach(Self.pages) { item in
                    GuidePageView(page: item).tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 5) {
                ForEach(Self.pages) { item in
                    Capsule()
                        .fill(item.id == page ? Theme.Colors.bus : .white.opacity(0.7))
                        .stroke(Theme.Colors.ink, lineWidth: 1.5)
                        .frame(width: item.id == page ? 22 : 8, height: 8)
                }
            }
            .animation(.spring(duration: 0.3), value: page)
            .accessibilityHidden(true)
            .padding(.bottom, 10)

            Group {
                if page < Self.pages.count - 1 {
                    Button("NEXT") { withAnimation { page += 1 } }
                        .buttonStyle(PanelButtonStyle(color: .yellow, height: 62))
                        .accessibilityIdentifier(AccessibilityID.Guide.next)
                } else {
                    Button(isOnboarding ? "HIT THE ROAD" : "GOT IT") { if let onFinish { onFinish() } else { dismiss() } }
                        .buttonStyle(PanelButtonStyle(color: .green, height: 62))
                        .accessibilityIdentifier(AccessibilityID.Guide.done)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: 520)
        }
        .tiledBackground(Art.Tile.map)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Guide.screen)
    }
}

private struct GuidePageView: View {
    let page: GuideView.Page

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(page.art)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 480)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Chip(text: page.tag.uppercased(), color: tagColor)
                        Spacer()
                    }
                    Text(page.title.uppercased())
                        .font(.sign(32, relativeTo: .title))
                        .foregroundStyle(Theme.Colors.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(page.text)
                        .font(.rounded(.body, weight: .medium))
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 480, alignment: .leading)
                .stickerCard(fill: Theme.Colors.paper)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var tagColor: Color {
        switch page.tag {
        case "Active": Theme.Colors.bus
        case "Passive": Theme.Colors.mint
        case "Road": Color(hex: 0xFFB3A8)
        default: Theme.Colors.sky
        }
    }
}
