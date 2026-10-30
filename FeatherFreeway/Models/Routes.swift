import Foundation

/// Which road features are switched on for a run. Routes introduce them one by one; Endless has all.
struct Mechanics: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let hazards = Mechanics(rawValue: 1 << 0)     // cones and potholes (jump)
    static let booms = Mechanics(rawValue: 1 << 1)       // barrier arms (dive)
    static let chicks = Mechanics(rawValue: 1 << 2)      // Chick Convoy
    static let rig = Mechanics(rawValue: 1 << 3)         // fuel cans and the Big Rig
    static let laneShift = Mechanics(rawValue: 1 << 4)   // lanes end and open
    static let flap = Mechanics(rawValue: 1 << 5)        // close calls and Flap Hop
    static let redLights = Mechanics(rawValue: 1 << 6)   // parked queues
    static let greenWaves = Mechanics(rawValue: 1 << 7)  // fast waves
    static let blinkers = Mechanics(rawValue: 1 << 8)    // cars changing lanes
    static let eggs = Mechanics(rawValue: 1 << 9)        // Corn Streak and Egg Splat
    static let tolls = Mechanics(rawValue: 1 << 10)      // Toll Plaza
    static let powerUps = Mechanics(rawValue: 1 << 11)   // magnet and Double Corn

    static let all: Mechanics = [.hazards, .booms, .chicks, .rig, .laneShift, .flap, .redLights, .greenWaves, .blinkers, .eggs, .tolls, .powerUps]
}

/// The third star of a route.
enum StarGoal: Equatable, Sendable {
    case chicks(Int)
    case noBumps

    var label: String {
        switch self {
        case .chicks(let n): "Finish with \(n)+ chicks"
        case .noBumps: "Finish without a bump"
        }
    }
}

/// One of the 30 hand-tuned trips on the Route Map.
struct Route: Identifiable, Equatable, Sendable {
    let index: Int
    let name: String
    let world: World
    let meters: Int
    /// Lane counts of consecutive, equally long road segments.
    let lanePattern: [Int]
    /// 0...1, how busy the traffic is.
    let density: Double
    let mechanics: Mechanics
    let cornGoal: Int
    let starGoal: StarGoal
    /// Feature introduced by this route, shown on its ticket.
    let newFeature: String?

    var id: Int { index }
    var number: Int { index + 1 }
    var startSpeed: Double { 430 + Double(index) * 7 }
}

enum RouteCatalog {
    static let routes: [Route] = build()

    static var count: Int { routes.count }

    static func route(_ index: Int) -> Route? {
        routes.indices.contains(index) ? routes[index] : nil
    }

    private static func build() -> [Route] {
        // name, world, metres, lanes, density, added mechanics, corn goal, third star, new feature
        typealias Row = (String, World, Int, [Int], Double, Mechanics, Int, StarGoal, String?)
        let basic: Mechanics = [.hazards]
        let rows: [Row] = [
            ("Barnyard Dash", .farm, 400, [3], 0.35, [], 25, .noBumps, "Swipe left and right to change lanes"),
            ("Haybale Hop", .farm, 450, [3], 0.4, basic, 35, .noBumps, "Swipe up to jump cones and potholes"),
            ("Lost and Found", .farm, 500, [3], 0.42, basic.union(.chicks), 40, .chicks(3), "Chick Convoy"),
            ("Gate Ducker", .farm, 550, [3], 0.45, basic.union([.chicks, .booms]), 45, .chicks(3), "Swipe down to dive under barriers"),
            ("Fuel Stop", .farm, 600, [3], 0.48, basic.union([.chicks, .booms, .rig]), 55, .chicks(4), "Big Rig"),
            ("Narrow Lane", .farm, 650, [3, 2, 3, 4], 0.48, basic.union([.chicks, .booms, .rig, .laneShift]), 60, .noBumps, "Lane Shift and Late Merge"),
            ("Close Shave", .farm, 700, [3, 4, 3], 0.52, basic.union([.chicks, .booms, .rig, .laneShift, .flap]), 70, .chicks(4), "Close calls and Flap Hop"),
            ("Harvest Run", .farm, 800, [2, 3, 4, 3], 0.55, basic.union([.chicks, .booms, .rig, .laneShift, .flap, .powerUps]), 85, .chicks(5), "Corn Magnet and Double Corn"),
            ("Red Light Row", .suburb, 750, [4, 3, 4], 0.52, [.hazards, .booms, .chicks, .rig, .laneShift, .flap, .powerUps, .redLights], 90, .noBumps, "Red lights park a lane"),
            ("Green Wave", .suburb, 800, [4, 5, 4], 0.55, [.hazards, .booms, .chicks, .rig, .laneShift, .flap, .powerUps, .redLights, .greenWaves], 95, .chicks(4), "Green waves rush a lane"),
            ("Blinker Lane", .suburb, 850, [4, 3, 4, 5], 0.56, [.hazards, .booms, .chicks, .rig, .laneShift, .flap, .powerUps, .redLights, .greenWaves, .blinkers], 100, .noBumps, "Watch the blinkers"),
            ("Egg Toss Avenue", .suburb, 900, [4, 5, 4], 0.58, Mechanics.all.subtracting(.tolls), 110, .chicks(5), "Corn Streak and Egg Splat"),
            ("Toll Road", .suburb, 950, [4, 5, 4, 3], 0.58, .all, 120, .chicks(3), "Toll Plaza and the Express lane"),
            ("Cul-de-sac Sprint", .suburb, 1000, [3, 4, 5, 4], 0.6, .all, 130, .chicks(5), nil),
            ("School Run", .suburb, 1050, [5, 4, 3, 4, 5], 0.62, .all, 140, .noBumps, nil),
            ("Maple Marathon", .suburb, 1150, [4, 5, 4, 5], 0.64, .all, 155, .chicks(6), nil),
            ("Taxi Rank", .downtown, 1000, [5, 4, 5], 0.62, .all, 150, .chicks(4), nil),
            ("Gridlock Glide", .downtown, 1050, [5, 6, 5, 4], 0.65, .all, 160, .noBumps, nil),
            ("Crosswalk Crush", .downtown, 1100, [4, 5, 6, 5], 0.66, .all, 170, .chicks(5), nil),
            ("Rush Hour", .downtown, 1150, [6, 5, 6], 0.7, .all, 180, .chicks(6), nil),
            ("Skyline Swerve", .downtown, 1200, [5, 6, 5, 4, 5], 0.7, .all, 190, .noBumps, nil),
            ("Uptown Express", .downtown, 1250, [6, 5, 4, 5, 6], 0.72, .all, 200, .chicks(6), nil),
            ("Downtown Derby", .downtown, 1300, [6, 6, 5, 6], 0.74, .all, 215, .chicks(7), nil),
            ("Neon Mile", .night, 1150, [5, 6, 7], 0.7, .all, 200, .chicks(5), nil),
            ("Diner Detour", .night, 1200, [6, 5, 6, 7], 0.72, .all, 210, .noBumps, nil),
            ("Moonlight Merge", .night, 1250, [7, 6, 5, 6, 7], 0.74, .all, 220, .chicks(6), nil),
            ("Midnight Convoy", .night, 1300, [6, 7, 6], 0.76, .all, 230, .chicks(8), nil),
            ("Starlight Sprint", .night, 1400, [7, 6, 7, 6], 0.78, .all, 245, .noBumps, nil),
            ("Seven Lane Showdown", .night, 1500, [7, 7, 6, 7], 0.8, .all, 260, .chicks(7), nil),
            ("Feather Freeway", .night, 1600, [5, 6, 7, 6, 7], 0.82, .all, 280, .chicks(8), nil),
        ]
        return rows.enumerated().map { index, row in
            Route(index: index, name: row.0, world: row.1, meters: row.2, lanePattern: row.3, density: row.4,
                  mechanics: row.5, cornGoal: row.6, starGoal: row.7, newFeature: row.8)
        }
    }

    /// Stars earned for a finished route trip (0 if it was not cleared).
    static func stars(for summary: RunSummary, route: Route) -> Int {
        guard summary.result == .cleared else { return 0 }
        var stars = 1
        if summary.corn >= route.cornGoal { stars += 1 }
        switch route.starGoal {
        case .chicks(let n): if summary.finalChicks >= n { stars += 1 }
        case .noBumps: if summary.bumps == 0 { stars += 1 }
        }
        return stars
    }
}
