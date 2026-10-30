import Foundation

/// The four stretches of road the freeway passes through, in order.
enum World: Int, CaseIterable, Codable, Sendable {
    case farm, suburb, downtown, night

    var key: String {
        switch self {
        case .farm: "farm"
        case .suburb: "suburb"
        case .downtown: "downtown"
        case .night: "night"
        }
    }

    var title: String {
        switch self {
        case .farm: "Farm Road"
        case .suburb: "Maple Suburb"
        case .downtown: "Downtown"
        case .night: "Neon Night Highway"
        }
    }

    /// How wide the road may get in this world (endless mode).
    var laneRange: ClosedRange<Int> {
        switch self {
        case .farm: 2...4
        case .suburb: 3...5
        case .downtown: 4...6
        case .night: 4...7
        }
    }

    /// Base speed of oncoming traffic in world units per second.
    var trafficSpeed: Double {
        switch self {
        case .farm: 170
        case .suburb: 220
        case .downtown: 250
        case .night: 320
        }
    }

    /// Cars that show up in this world, as sprite keys.
    var carPool: [CarModel] {
        switch self {
        case .farm: [.pickup, .hatch, .sedanRed, .van, .truck]
        case .suburb: [.sedanBlue, .hatch, .van, .icecream, .bus, .sedanRed]
        case .downtown: [.taxi, .sedanBlue, .bus, .truck, .coupe, .van]
        case .night: [.coupe, .taxi, .sedanRed, .truck, .sedanBlue]
        }
    }

    var next: World { World(rawValue: (rawValue + 1) % World.allCases.count) ?? .farm }
}

/// Every car sprite the traffic can use, with its size in world units (one lane = 100).
enum CarModel: String, CaseIterable, Codable, Sendable {
    case sedanRed = "car_sedan_red"
    case sedanBlue = "car_sedan_sky"
    case hatch = "car_hatch_mint"
    case taxi = "car_taxi"
    case coupe = "car_coupe"
    case van = "car_van"
    case pickup = "car_pickup"
    case bus = "car_bus"
    case truck = "car_truck"
    case icecream = "car_icecream"

    var size: (width: Double, length: Double) {
        switch self {
        case .sedanRed, .sedanBlue, .taxi: (70, 120)
        case .hatch: (68, 106)
        case .coupe: (68, 118)
        case .van, .icecream: (74, 142)
        case .pickup: (72, 132)
        case .bus: (82, 224)
        case .truck: (82, 200)
        }
    }
}
