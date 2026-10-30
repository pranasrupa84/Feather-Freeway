import Foundation

/// Names of the generated bitmaps in `Assets.xcassets/Generated` (see `Artwork/parts`).
enum Art {
    static let logo = "logo"
    static let homeBackdrop = "bg_home"
    static let corn = "corn"
    static let cornIcon = "corn_icon"
    static let fuelCan = "fuel_can"
    static let fuelEmpty = "fuel_empty"
    static let magnet = "magnet"
    static let double = "double"
    static let egg = "egg"
    static let eggGolden = "egg_golden"
    static let feather = "icon_feather"
    static let chickFace = "chick_face"
    static let lock = "lock"
    static let starFull = "star_full"
    static let starEmpty = "star_empty"
    static let badgeEarned = "badge_earned"
    static let badgeLocked = "badge_locked"
    static let stampRecord = "stamp_record"
    static let stampClear = "stamp_clear"
    static let stampCrash = "stamp_crash"
    static let clipboardClip = "clipboard_clip"
    static let signLaneEnds = "sign_lane_ends"
    static let rig = "rig"

    static func portrait(_ breed: Breed) -> String { "portrait_\(breed.rawValue)" }
    static func hen(_ breed: Breed, frame: Int) -> String { "hen_\(breed.rawValue)_\(frame)" }
    static func world(_ world: World) -> String { "world_\(world.key)" }

    enum Sign {
        static let back = "sign_back"
        static let pause = "sign_pause"
        static let help = "sign_help"
        static let settings = "sign_settings"
        static let records = "sign_records"
        static let map = "sign_map"
    }

    enum Panel {
        static let sign = "panel_sign"
        static let signBlue = "panel_sign_blue"
        static let signNight = "panel_sign_night"
        static let plate = "panel_plate"
        static let ticket = "panel_ticket"
        static let pump = "panel_pump"
        static let board = "panel_board"
        static let yellow = "btn_yellow"
        static let green = "btn_green"
        static let red = "btn_red"
        static let cream = "btn_cream"
        static let grey = "btn_grey"
    }

    enum Tile {
        static let pegboard = "tile_pegboard"
        static let coopWall = "tile_coopwall"
        static let leather = "tile_leather"
        static let map = "tile_map"
    }

    enum Mile {
        static let open = "mile_open"
        static let done = "mile_done"
        static let locked = "mile_locked"
    }

    enum HUD {
        static let rig = "btn_rig"
        static let rigOff = "btn_rig_off"
        static let egg = "btn_egg"
        static let eggOff = "btn_egg_off"
    }

    /// Sprites used only inside the SpriteKit scene.
    enum Scene {
        static func lane(_ world: World) -> String { "lane_\(world.key)" }
        static func shoulder(_ world: World, right: Bool) -> String { "shoulder_\(world.key)_\(right ? "r" : "l")" }
        static let divider = "lane_divider"
        static let edge = "edge_line"
        static let edgeYellow = "edge_line_yellow"
        static let chick0 = "chick_0"
        static let chick1 = "chick_1"
        static let rigLit = "rig_lit"
        static let cone = "cone"
        static let pothole = "pothole"
        static let boom = "boom"
        static let barricade = "barricade"
        static let arrowMerge = "arrow_merge"
        static let tollOpen = "toll_open"
        static let tollClosed = "toll_closed"
        static let tollExpress = "toll_express"
        static let tollExpressOpen = "toll_express_open"
        static let tollBanner = "toll_banner"
        static let finishStrip = "finish_strip"
        static let finishBanner = "finish_banner"
        static let signalRed = "signal_red"
        static let signalAmber = "signal_amber"
        static let signalGreen = "signal_green"
        static let blinker = "fx_blinker"
        static let brake = "fx_brake"
        static let splat = "fx_splat"
        static let soft = "p_soft"
        static let featherParticle = "p_feather"
        static let smoke = "p_smoke"
        static let star = "p_star"
        static let bolt = "p_bolt"
        static let glass = "p_glass"
        static let yolk = "p_yolk"
        static let streak = "p_streak"
        static let ring = "p_ring"
        static let shadow = "shadow_oval"
    }

    static func upgrade(_ kind: UpgradeKind) -> String {
        switch kind {
        case .rigTime: "up_rig"
        case .magnetTime: "up_magnet"
        case .doubleTime: "up_double"
        case .featherFill: "up_feather"
        case .eggCarton: "up_carton"
        case .convoyCap: "up_convoy"
        }
    }

    enum Guide {
        static let lanes = "guide_lanes"
        static let jump = "guide_jump"
        static let dive = "guide_dive"
        static let rig = "guide_rig"
        static let flap = "guide_flap"
        static let egg = "guide_egg"
        static let convoy = "guide_convoy"
        static let streak = "guide_streak"
        static let traits = "guide_traits"
        static let signals = "guide_signals"
        static let blinkers = "guide_blinkers"
        static let merge = "guide_merge"
        static let toll = "guide_toll"
    }
}
