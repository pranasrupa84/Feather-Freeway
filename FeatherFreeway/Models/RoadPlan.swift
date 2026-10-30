import Foundation

/// World geometry shared by the rules and the scene.
enum RoadGeometry {
    /// Width of one lane in world units.
    static let laneWidth: Double = 100
    /// World units per metre shown to the player.
    static let unitsPerMeter: Double = 25
    /// Road tiles and segment boundaries snap to this length.
    static let chunk: Double = 400
    /// Length of one world (Farm → Suburb → …) in endless mode.
    static let worldLength: Double = 9600

    static func laneCenter(_ lane: Int) -> Double { (Double(lane) + 0.5) * laneWidth }

    static func lane(atX x: Double) -> Int { Int(floor(x / laneWidth)) }
}

/// A stretch of road with a fixed number of lanes, starting at `startY`.
struct RoadSegment: Equatable, Sendable {
    var startY: Double
    var lanes: Int
    var world: World
}

/// A place where lanes end: lanes `closing` are walled off from `y` onward.
struct LaneClosure: Equatable, Sendable {
    let y: Double
    let closing: Range<Int>
}

/// The road ahead: lane counts per segment, which world you are in, and where the toll plazas are.
/// Routes have a fixed plan; endless mode keeps extending it as the chicken runs.
struct RoadPlan: Sendable {
    private(set) var segments: [RoadSegment]
    private(set) var tollYs: [Double] = []
    let isEndless: Bool
    let finishY: Double?
    let usesLaneShift: Bool
    private var rng: SeededGenerator
    private var generatedTo: Double

    /// Fixed plan for a route: the lane pattern is spread evenly over the route length.
    init(route: Route) {
        let length = Double(route.meters) * RoadGeometry.unitsPerMeter
        let pattern = route.mechanics.contains(.laneShift) ? route.lanePattern : [route.lanePattern.first ?? 3]
        let piece = (length / Double(pattern.count) / RoadGeometry.chunk).rounded(.down) * RoadGeometry.chunk
        segments = pattern.enumerated().map { RoadSegment(startY: Double($0.offset) * piece, lanes: $0.element, world: route.world) }
        if route.mechanics.contains(.tolls) {
            // One plaza in the middle of the trip, away from lane changes.
            let mid = (length * 0.5 / RoadGeometry.chunk).rounded() * RoadGeometry.chunk + 200
            tollYs = [mid]
        }
        isEndless = false
        finishY = length
        usesLaneShift = route.mechanics.contains(.laneShift)
        rng = SeededGenerator(seed: 1)
        generatedTo = length
    }

    /// Endless plan that grows as needed.
    init(endlessSeed seed: UInt64, startWorld: World = .farm) {
        rng = SeededGenerator(seed: seed ^ 0xA5A5_5A5A)
        segments = [RoadSegment(startY: 0, lanes: 3, world: startWorld)]
        isEndless = true
        finishY = nil
        usesLaneShift = true
        generatedTo = 0
        extend(to: 12_000)
    }

    /// Makes sure the endless plan covers the road up to `y`.
    mutating func extend(to y: Double) {
        guard isEndless else { return }
        while generatedTo < y {
            let last = segments[segments.count - 1]
            let worldIndex = Int(generatedTo / RoadGeometry.worldLength)
            let worldStart = Double(worldIndex) * RoadGeometry.worldLength
            let nextWorldStart = worldStart + RoadGeometry.worldLength
            // Segment lengths are whole chunks so road tiles line up.
            let lengthChunks = Double(Int.random(in: 5...9, using: &rng))
            var end = max(last.startY, generatedTo) + lengthChunks * RoadGeometry.chunk
            if end > nextWorldStart - 2 * RoadGeometry.chunk { end = nextWorldStart }
            if end >= nextWorldStart {
                // New world: its first segment is long and calm so the toll plaza sits on a steady road.
                let world = World(rawValue: (worldIndex + 1) % World.allCases.count) ?? .farm
                let lanes = clampLanes(last.lanes + Int.random(in: -1...1, using: &rng), world: world)
                segments.append(RoadSegment(startY: nextWorldStart, lanes: lanes, world: world))
                tollYs.append(nextWorldStart + 3 * RoadGeometry.chunk + 200)
                segments.append(RoadSegment(startY: nextWorldStart + 7 * RoadGeometry.chunk, lanes: lanes, world: world))
                generatedTo = nextWorldStart + 7 * RoadGeometry.chunk
                continue
            }
            let world = last.world
            var delta = [-2, -1, -1, 1, 1, 2][Int.random(in: 0..<6, using: &rng)]
            if last.lanes + delta < world.laneRange.lowerBound || last.lanes + delta > world.laneRange.upperBound { delta = -delta }
            let lanes = clampLanes(last.lanes + delta, world: world)
            segments.append(RoadSegment(startY: end, lanes: lanes, world: world))
            generatedTo = end
        }
    }

    private func clampLanes(_ lanes: Int, world: World) -> Int {
        min(world.laneRange.upperBound, max(world.laneRange.lowerBound, lanes))
    }

    func segment(at y: Double) -> RoadSegment {
        var result = segments[0]
        for s in segments where s.startY <= y { result = s }
        return result
    }

    func lanes(at y: Double) -> Int { segment(at: y).lanes }

    func world(at y: Double) -> World { segment(at: y).world }

    /// The widest road anywhere in `range` (used to place things that must stay on the road).
    func minLanes(in range: ClosedRange<Double>) -> Int {
        var value = lanes(at: range.lowerBound)
        for s in segments where s.startY > range.lowerBound && s.startY <= range.upperBound { value = min(value, s.lanes) }
        return value
    }

    /// Every boundary where lanes end.
    var closures: [LaneClosure] {
        var result: [LaneClosure] = []
        for i in 1..<max(1, segments.count) where segments[i].lanes < segments[i - 1].lanes {
            result.append(LaneClosure(y: segments[i].startY, closing: segments[i].lanes..<segments[i - 1].lanes))
        }
        return result
    }

    /// Next closure ahead of `y`, if any.
    func nextClosure(after y: Double) -> LaneClosure? {
        closures.first { $0.y > y }
    }

    /// World boundaries crossed between two positions.
    func worldChange(from y0: Double, to y1: Double) -> World? {
        let a = world(at: y0), b = world(at: y1)
        return a == b ? nil : b
    }
}
