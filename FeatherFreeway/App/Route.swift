import Foundation

/// Screens pushed on top of the lane pager.
enum AppRoute: String, Hashable, CaseIterable {
    case routeMap
    case topPlayers
    case glovebox
    case settings
    case guide
}

/// The three lanes of the home pager, left to right.
enum HomeLane: Int, CaseIterable, Identifiable, Hashable {
    case garage, roadside, coop

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .garage: "Garage"
        case .roadside: "Roadside"
        case .coop: "Coop"
        }
    }
}

/// A trip the root view should present full screen.
struct PlayRequest: Identifiable, Equatable {
    let id = UUID()
    let setup: RunSetup
}
