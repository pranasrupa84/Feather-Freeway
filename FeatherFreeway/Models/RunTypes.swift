import Foundation

/// What a run is: an endless trip or a numbered route.
enum RunMode: Hashable, Sendable {
    case endless
    case route(Int)

    var routeIndex: Int? {
        if case .route(let i) = self { return i }
        return nil
    }

    var storageKey: String {
        switch self {
        case .endless: "endless"
        case .route(let i): "route-\(i)"
        }
    }
}

/// Everything needed to start a run.
struct RunSetup: Hashable, Sendable {
    var mode: RunMode
    var seed: UInt64
}

/// Things on the road. Cars move toward the chicken; everything else is fixed to the asphalt.
enum EntityKind: Equatable, Sendable {
    case car(CarModel)
    case cone
    case pothole
    case boom
    case barricade
    case corn
    case chick
    case fuel
    case magnet
    case double
    case toll(TollKind)
    case egg

    var isPickup: Bool {
        switch self {
        case .corn, .chick, .fuel, .magnet, .double: true
        default: false
        }
    }
}

enum TollKind: Equatable, Sendable {
    case open, closed, express
}

struct Entity: Identifiable, Equatable, Sendable {
    let id: Int
    var kind: EntityKind
    var x: Double
    var y: Double
    /// Speed toward the chicken in world units per second (0 = parked or fixed).
    var velocity: Double = 0
    /// -1 / +1 while a car signals a lane change, 0 otherwise.
    var blinker = 0
    var targetX: Double?
    /// Stopped at a red light.
    var parked = false
    /// Part of a green wave (smashing it in the Big Rig pays double).
    var wave = false
    /// Windscreen hit by an egg.
    var splatted = false
    /// Toll gate already opened for the chicken.
    var opened = false
    /// Car has already passed the chicken (close-call bookkeeping).
    var passed = false

    var lane: Int { RoadGeometry.lane(atX: x) }

    /// Half extents for collisions.
    var halfSize: (w: Double, h: Double) {
        switch kind {
        case .car(let model): (model.size.width * 0.42, model.size.length * 0.44)
        case .cone: (16, 16)
        case .pothole: (26, 18)
        case .boom: (48, 12)
        case .barricade: (48, 22)
        case .toll: (48, 18)
        case .corn: (18, 20)
        case .chick, .fuel, .magnet, .double: (22, 22)
        case .egg: (12, 16)
        }
    }
}

/// A traffic signal hanging over one lane.
struct Signal: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable { case red, green }
    enum Phase: Equatable, Sendable { case warning, active }
    let id: Int
    let kind: Kind
    let lane: Int
    /// Where the effect starts (world y).
    let y: Double
    /// Where it ends; the signal disappears once the chicken passes this.
    let endY: Double
    var phase: Phase
}

/// One-shot happenings the scene and HUD react to (effects, sounds, banners).
enum RunEvent: Equatable, Sendable {
    case laneChange
    case jump
    case dive
    case flap
    case closeCall(x: Double, y: Double)
    case corn(x: Double, y: Double, streak: Int)
    case streakEgg
    case chickRescued(count: Int)
    case chicksLost(count: Int)
    case pickup(EntityKind)
    case rigReady
    case rigStart
    case rigEnd
    case smash(id: Int, x: Double, y: Double, wave: Bool)
    case bump(x: Double, y: Double)
    case cushion
    case crash(x: Double, y: Double)
    case eggThrown
    case splat(id: Int)
    case lateMerge(x: Double, y: Double)
    case laneEnds(lane: Int)
    case tollAhead
    case flapReady
    case tollPassed(TollKind, bonus: Int)
    case signalWarning(Signal.Kind)
    case greenWave
    case worldEntered(World)
    case finished
}

enum RunResult: String, Codable, Sendable {
    case crashed, cleared
}

/// Lifetime-stat friendly summary of a finished run.
struct RunSummary: Equatable, Sendable {
    var mode: RunMode
    var result: RunResult
    var breed: Breed
    var score: Int
    var meters: Int
    var corn: Int
    var chicksRescued: Int
    var finalChicks: Int
    var maxConvoy: Int
    var smashes: Int
    var closeCalls: Int
    var flaps: Int
    var splats: Int
    var lateMerges: Int
    var expressTolls: Int
    var bumps: Int
    var duration: Double
    var furthestWorld: World
}
