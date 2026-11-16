import Foundation

enum DeliveryPath: String, Equatable, Sendable {
    case shortcut = "Shortcut"
    case detour = "Detour"
}

struct DeliveryOrder: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let routeIndex: Int
    let eggs: Int
    let minimum: Int
    let meters: Int
    let goldTime: Int

    static let orders: [Self] = [
        .init(id: 0, name: "Morning Market", routeIndex: 1, eggs: 6, minimum: 3, meters: 360, goldTime: 18),
        .init(id: 1, name: "Farmstand Refill", routeIndex: 5, eggs: 8, minimum: 4, meters: 440, goldTime: 21),
        .init(id: 2, name: "Bakery Rush", routeIndex: 9, eggs: 10, minimum: 6, meters: 520, goldTime: 23),
        .init(id: 3, name: "Diner Special", routeIndex: 12, eggs: 8, minimum: 6, meters: 590, goldTime: 25),
        .init(id: 4, name: "Pastry Parade", routeIndex: 18, eggs: 10, minimum: 8, meters: 660, goldTime: 27),
        .init(id: 5, name: "Midnight Soufflé", routeIndex: 24, eggs: 12, minimum: 10, meters: 740, goldTime: 29),
    ]

    var forkMeters: Int { meters / 3 }
    var shortcutMeters: Int { meters * 4 / 5 }

    var road: Route? {
        guard let source = RouteCatalog.route(routeIndex) else { return nil }
        // Delivery runs are shorter than campaign routes; avoid repeating their most punishing set pieces.
        return Route(index: source.index, name: name, world: source.world, meters: meters,
                     lanePattern: source.lanePattern, density: source.density * 0.7,
                     mechanics: source.mechanics.union(.hazards).subtracting([.eggs, .booms, .redLights, .greenWaves, .laneShift, .tolls]),
                     cornGoal: 0, starGoal: .noBumps, newFeature: nil)
    }

    func medals(eggs delivered: Int, duration: Double) -> Int {
        guard delivered >= minimum else { return 0 }
        if delivered == eggs && duration <= Double(goldTime) { return 3 }
        return delivered >= (minimum + eggs + 1) / 2 ? 2 : 1
    }
}

struct DeliveryResult: Equatable, Sendable {
    let eggs: Int
    let path: DeliveryPath?
}
