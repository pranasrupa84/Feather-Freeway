import SwiftUI

// MARK: - 9-slice panels

/// Generated panels and their cap insets in points (the art is @3x).
enum PanelArt {
    case sign, signBlue, signNight, plate, ticket, pump, board
    case button(ButtonColor)

    enum ButtonColor { case yellow, green, red, cream, grey }

    var name: String {
        switch self {
        case .sign: Art.Panel.sign
        case .signBlue: Art.Panel.signBlue
        case .signNight: Art.Panel.signNight
        case .plate: Art.Panel.plate
        case .ticket: Art.Panel.ticket
        case .pump: Art.Panel.pump
        case .board: Art.Panel.board
        case .button(let c):
            switch c {
            case .yellow: Art.Panel.yellow
            case .green: Art.Panel.green
            case .red: Art.Panel.red
            case .cream: Art.Panel.cream
            case .grey: Art.Panel.grey
            }
        }
    }

    var insets: EdgeInsets {
        switch self {
        case .sign, .signBlue, .signNight: EdgeInsets(top: 16, leading: 17, bottom: 22, trailing: 17)
        case .plate: EdgeInsets(top: 15, leading: 15, bottom: 16, trailing: 15)
        case .ticket: EdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 10)
        case .pump: EdgeInsets(top: 14, leading: 14, bottom: 16, trailing: 14)
        case .board: EdgeInsets(top: 22, leading: 18, bottom: 20, trailing: 18)
        case .button: EdgeInsets(top: 14, leading: 18, bottom: 18, trailing: 18)
        }
    }

    var isTiled: Bool {
        if case .ticket = self { return true }
        return false
    }
}

extension View {
    /// Places a stretchable generated panel behind the view.
    func panel(_ art: PanelArt) -> some View {
        background {
            Image(art.name)
                .resizable(capInsets: art.insets, resizingMode: art.isTiled ? .tile : .stretch)
                .accessibilityHidden(true)
        }
    }

    /// Full-bleed tiled texture that never widens the layout.
    func tiledBackground(_ name: String) -> some View {
        background {
            Rectangle()
                .fill(ImagePaint(image: Image(name), scale: 1))
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
    }

    /// Full-bleed illustration (scaled to fill) that never widens the layout.
    func artBackground(_ name: String, alignment: Alignment = .center) -> some View {
        background {
            GeometryReader { proxy in
                Image(name)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: alignment)
                    .clipped()
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Buttons

/// Chunky lip button painted with a generated 9-slice face.
struct PanelButtonStyle: ButtonStyle {
    var color: PanelArt.ButtonColor = .yellow
    var height: CGFloat = 60
    var fontSize: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sign(fontSize, relativeTo: .title3))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 22)
            .padding(.top, 4)
            .padding(.bottom, 10)
            .frame(minHeight: height)
            .frame(maxWidth: .infinity)
            .panel(.button(color))
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(.spring(duration: 0.18), value: configuration.isPressed)
            .contentShape(Rectangle())
    }

    /// Ink reads on every face colour (white on the light green and tomato faces does not).
    private var textColor: Color { color == .grey ? Theme.Colors.inkSoft : Theme.Colors.ink }
}

/// A road-sign image used as a round-ish icon button (back, pause, settings…).
struct SignButton: View {
    let art: String
    let label: String
    var size: CGFloat = 52
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(art)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .frame(minWidth: Theme.Metrics.minTapTarget, minHeight: Theme.Metrics.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(SignPressStyle())
        .accessibilityLabel(label)
    }
}

struct SignPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .rotationEffect(.degrees(configuration.isPressed ? -4 : 0))
            .animation(.spring(duration: 0.2, bounce: 0.5), value: configuration.isPressed)
    }
}

/// Blue U-turn sign that pops the navigation stack.
struct BackSign: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SignButton(art: Art.Sign.back, label: "Back", size: 50) { dismiss() }
            .accessibilityIdentifier(AccessibilityID.back)
    }
}

// MARK: - Headers and badges

/// Green highway sign with a screen title, an optional exit tab and subtitle.
struct HighwaySignHeader: View {
    let title: String
    var subtitle: String? = nil
    var exit: String? = nil
    var style: PanelArt = .sign

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let exit {
                Text(exit)
                    .font(.sign(16, relativeTo: .caption))
                    .foregroundStyle(Theme.Colors.ink)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 3)
                    .background(UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8).fill(Theme.Colors.bus).stroke(Theme.Colors.ink, lineWidth: 3))
                    .padding(.leading, 18)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 2) {
                Text(title.uppercased())
                    .font(.sign(34, relativeTo: .largeTitle))
                    .foregroundStyle(.white)
                    .kerning(2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.rounded(.subheadline, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 20)
            .panel(style)
        }
    }
}

/// Corn balance on a petrol-station price board.
struct CornBadge: View {
    let amount: Int
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            Image(Art.cornIcon)
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 24 : 30, height: compact ? 24 : 30)
                .accessibilityHidden(true)
            Text(Formatters.integer(amount))
                .font(.sign(compact ? 22 : 26, relativeTo: .headline))
                .foregroundStyle(Theme.Colors.bus)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .panel(.pump)
        .animation(.spring(duration: 0.4), value: amount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Corn")
        .accessibilityValue(Formatters.integer(amount))
        .accessibilityIdentifier(AccessibilityID.cornBalance)
    }
}

/// A light piece of art on a tinted disc, for rows on paper.
struct ArtIcon: View {
    let name: String
    var size: CGFloat = 44
    var tint: Color = Theme.Colors.sky.opacity(0.35)

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .padding(size * 0.12)
            .frame(width: size, height: size)
            .background(Circle().fill(tint))
            .accessibilityHidden(true)
    }
}

struct StarRow: View {
    let stars: Int
    var size: CGFloat = 22
    var spacing: CGFloat = 2

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { i in
                Image(i < stars ? Art.starFull : Art.starEmpty)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stars) of 3 stars")
    }
}

/// Small rounded label on cream, e.g. a perk name.
struct Chip: View {
    let text: String
    var color: Color = Theme.Colors.mint
    var textColor: Color = Theme.Colors.ink

    var body: some View {
        Text(text)
            .font(.rounded(.caption, weight: .heavy))
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color).stroke(Theme.Colors.ink, lineWidth: 2))
    }
}

/// Cream sticker card with a thick ink outline.
struct StickerCard: ViewModifier {
    var fill: Color = Theme.Colors.cream
    var padding: CGFloat = 14
    var radius: CGFloat = Theme.Metrics.corner

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius)
                    .fill(Theme.Colors.ink)
                    .offset(y: 5)
                RoundedRectangle(cornerRadius: radius)
                    .fill(fill)
                    .stroke(Theme.Colors.ink, lineWidth: 3.5)
            }
    }
}

extension View {
    func stickerCard(fill: Color = Theme.Colors.cream, padding: CGFloat = 14, radius: CGFloat = Theme.Metrics.corner) -> some View {
        modifier(StickerCard(fill: fill, padding: padding, radius: radius))
    }
}

// MARK: - Toast

struct ToastModifier: ViewModifier {
    @Binding var message: String?
    var isError = false
    var edge: VerticalAlignment = .bottom
    /// Extra distance from the edge (to clear floating chrome).
    var inset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: edge == .top ? .top : .bottom) {
                if let message {
                    HStack(spacing: 10) {
                        Image(isError ? Art.Sign.pause : Art.cornIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .accessibilityHidden(true)
                        Text(message)
                            .font(.rounded(.subheadline, weight: .bold))
                            .foregroundStyle(Theme.Colors.ink)
                            .multilineTextAlignment(.leading)
                    }
                    .stickerCard(fill: isError ? Color(hex: 0xFFE1DC) : Theme.Colors.cream, padding: 14, radius: 18)
                    .padding(.horizontal, 24)
                    .padding(edge == .top ? .top : .bottom, 18 + inset)
                    .transition(.move(edge: edge == .top ? .top : .bottom).combined(with: .opacity))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(AccessibilityID.toast)
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2.4))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.25)) { self.message = nil }
                    }
                }
            }
            .animation(.spring(duration: 0.35, bounce: 0.25), value: message)
    }
}

extension View {
    func toast(message: Binding<String?>, isError: Bool = false, edge: VerticalAlignment = .bottom, inset: CGFloat = 0) -> some View {
        modifier(ToastModifier(message: message, isError: isError, edge: edge, inset: inset))
    }
}
