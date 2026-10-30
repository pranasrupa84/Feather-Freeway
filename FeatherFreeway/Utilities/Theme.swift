import SwiftUI

/// Colours, fonts and metrics of the "Sunny Roadside Pop" look: comic stickers with thick navy
/// outlines, school-bus yellow, tomato, mint and cream over slate asphalt.
enum Theme {
    enum Colors {
        /// Outline and primary text colour (matches the art's ink).
        static let ink = Color(hex: 0x1E2347)
        /// Secondary text on cream and paper (≥ 4.5:1).
        static let inkSoft = Color(hex: 0x434A70)
        static let cream = Color(hex: 0xFFF4DC)
        static let paper = Color(hex: 0xFFFAEE)
        static let bus = Color(hex: 0xFFC93C)
        static let busDeep = Color(hex: 0xF09A1E)
        static let tomato = Color(hex: 0xFF5A47)
        static let tomatoDeep = Color(hex: 0xC8302B)
        static let mint = Color(hex: 0x5FD3B0)
        static let mintDeep = Color(hex: 0x1F7F66)
        static let sky = Color(hex: 0x7FC8F8)
        static let signGreen = Color(hex: 0x1F8A5B)
        static let signGreenDeep = Color(hex: 0x146B45)
        static let signBlue = Color(hex: 0x2F6FD0)
        static let asphalt = Color(hex: 0x56627F)
        static let asphaltDeep = Color(hex: 0x2E3150)
        static let grass = Color(hex: 0x8CCB5E)
        static let leather = Color(hex: 0x2A3158)
        static let neon = Color(hex: 0xFF4FD8)
        static let danger = Color(hex: 0xB3261E)
        static let success = Color(hex: 0x1F7A4A)
    }

    enum Metrics {
        static let maxContentWidth: CGFloat = 680
        static let screenPadding: CGFloat = 18
        static let corner: CGFloat = 20
        static let minTapTarget: CGFloat = 44
        /// Height of the lane rail at the bottom of the home pager.
        static let laneRailHeight: CGFloat = 74
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension Font {
    /// Road-sign lettering (DIN Condensed) that scales with Dynamic Type.
    static func sign(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("DINCondensed-Bold", size: size, relativeTo: style)
    }

    /// Body copy in the rounded family.
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}
