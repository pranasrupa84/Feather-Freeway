import Foundation

/// Accessibility identifiers shared with the UI tests (duplicated there as strings).
enum AccessibilityID {
    static let toast = "toast"
    static let cornBalance = "corn.balance"
    static let back = "nav.back"

    enum Home {
        static let pager = "home.pager"
        static let laneGarage = "lane.garage"
        static let laneRoadside = "lane.roadside"
        static let laneCoop = "lane.coop"
        static let records = "home.records"
        static let settings = "home.settings"
        static let roadside = "screen.roadside"
        static let play = "home.play"
        static let topPlayers = "home.topPlayers"
        static let routeMap = "home.routeMap"
        static let errands = "home.errands"
        static let guide = "home.guide"
        static let hen = "home.hen"
    }

    enum Errands {
        static let sheet = "screen.errands"
        static func claim(_ slot: Int) -> String { "errand.claim.\(slot)" }
    }

    enum Garage {
        static let screen = "screen.garage"
        static func buy(_ kind: UpgradeKind) -> String { "garage.buy.\(kind.rawValue)" }
        static func level(_ kind: UpgradeKind) -> String { "garage.level.\(kind.rawValue)" }
    }

    enum Coop {
        static let screen = "screen.coop"
        static func action(_ breed: Breed) -> String { "coop.action.\(breed.rawValue)" }
    }

    enum RouteMap {
        static let screen = "screen.routeMap"
        static func marker(_ index: Int) -> String { "route.marker.\(index)" }
        static let ticket = "route.ticket"
        static let start = "route.start"
    }

    enum Glovebox {
        static let screen = "screen.glovebox"
        static let licence = "glovebox.licence"
    }

    enum Settings {
        static let screen = "screen.settings"
        static let sound = "settings.sound"
        static let music = "settings.music"
        static let haptics = "settings.haptics"
        static let leftHanded = "settings.leftHanded"
        static let reset = "settings.reset"
        static let resetConfirm = "settings.reset.confirm"
        static let guide = "settings.guide"
    }

    enum Guide {
        static let screen = "screen.guide"
        static let next = "guide.next"
        static let done = "guide.done"
    }

    enum Game {
        static let screen = "screen.game"
        static let go = "game.go"
        static let leave = "game.leave"
        static let pause = "game.pause"
        static let resume = "game.resume"
        static let restart = "game.restart"
        static let quit = "game.quit"
        static let rig = "game.rig"
        static let egg = "game.egg"
        static let score = "game.score"
        static let citation = "game.citation"
        static let again = "game.again"
        static let home = "game.home"
    }
}
