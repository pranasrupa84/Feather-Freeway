import SwiftUI

struct DeliveryBoard: View {
    let profile: PlayerProfile
    let onPlay: (RunMode) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SignButton(art: Art.Sign.back, label: "Back", size: 48) { dismiss() }
                    Spacer()
                    Text("EGG EXPRESS").font(.sign(34, relativeTo: .largeTitle))
                    Spacer()
                    Image(Art.egg).resizable().scaledToFit().frame(width: 38, height: 48)
                }
                Text("Deliver your eggs intact. Take the roadworks shortcut for speed or the longer detour for a smoother ride.")
                    .font(.rounded(.subheadline, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .panel(.ticket)
                ForEach(DeliveryOrder.orders) { order in
                    let unlocked = order.id == 0 || profile.medals(forDelivery: order.id - 1) > 0
                    VStack(alignment: .leading, spacing: 8) {
                        Text(order.name).font(.sign(26, relativeTo: .title2))
                        Text("\(order.eggs) eggs · deliver at least \(order.minimum)")
                            .font(.rounded(.subheadline, weight: .bold))
                        HStack {
                            StarRow(stars: profile.medals(forDelivery: order.id), size: 22, spacing: 4)
                            Spacer()
                            Text("Gold: all eggs in \(order.goldTime)s")
                                .font(.rounded(.caption, weight: .heavy))
                        }
                        Button(unlocked ? "TAKE ORDER" : "COMPLETE PREVIOUS ORDER") {
                            onPlay(.delivery(order))
                        }
                        .buttonStyle(PanelButtonStyle(color: unlocked ? .green : .grey, height: 48, fontSize: 18))
                        .disabled(!unlocked)
                        .accessibilityIdentifier("delivery.order.\(order.id)")
                    }
                    .padding(20)
                    .panel(.ticket)
                }
            }
            .frame(maxWidth: 540)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Theme.Colors.ink)
        .background(Theme.Colors.grass.ignoresSafeArea())
    }
}
