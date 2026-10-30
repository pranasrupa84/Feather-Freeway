import Foundation

/// Tuning for one run, derived from the mode, the garage and the chosen chicken.
struct RunConfig: Equatable, Sendable {
    var mechanics: Mechanics
    var startSpeed: Double
    var maxSpeed: Double
    var acceleration: Double
    /// Fixed traffic density for routes; `nil` ramps up over time (endless).
    var density: Double?
    var stats: Loadout.Stats
    var trait: BreedTrait

    init(mode: RunMode, loadout: Loadout) {
        stats = loadout.stats
        trait = loadout.breed.trait
        if let index = mode.routeIndex, let route = RouteCatalog.route(index) {
            mechanics = route.mechanics
            startSpeed = route.startSpeed
            maxSpeed = route.startSpeed + 220
            acceleration = 3.2
            density = route.density
        } else {
            mechanics = .all
            startSpeed = 460
            maxSpeed = 860
            acceleration = 3.6
            density = nil
        }
    }
}

/// The rules of one trip down the freeway. No SpriteKit or SwiftUI here, so everything is testable:
/// the scene calls `step(_:)` every frame and renders `entities`, the HUD reads the counters.
///
/// Coordinates: lanes are 100 units wide starting at x = 0; the chicken runs toward +y and its
/// position along the road is `distance`. Rows of traffic are scheduled in *time* so oncoming cars
/// and fixed obstacles of the same row reach the chicken together, and each row keeps one lane free
/// within one swipe of the previous free lane.
final class RunSession {
    // MARK: Tunables
    static let lookahead = 2.5
    static let jumpDuration = 0.62
    static let diveDuration = 0.62
    static let flapDuration = 1.3
    static let bumpGrace = 1.6
    static let laneSwitchSpeed = 1100.0
    static let carLaneChangeSpeed = 240.0
    static let eggSpeed = 1500.0
    static let streakWindow = 1.2
    static let streakEggEvery = 15
    static let streakDoubleAt = 30
    static let expressMinimumChicks = 3
    static let lateMergeWindow = 240.0
    static let maxFuel = 3
    static let chickenHalfHeight = 22.0

    // MARK: Inputs
    let setup: RunSetup
    let config: RunConfig
    let breed: Breed
    private(set) var plan: RoadPlan
    private var rng: SeededGenerator

    // MARK: Chicken state
    private(set) var time: Double = 0
    private(set) var distance: Double = 0
    private(set) var baseSpeed: Double
    private(set) var lane = 1
    private(set) var x: Double
    private(set) var jumpTime: Double = 0
    private(set) var diveTime: Double = 0
    private(set) var flapTime: Double = 0
    private(set) var graceTime: Double = 0
    private(set) var rigTime: Double = 0
    private(set) var magnetTime: Double = 0
    private(set) var doubleTime: Double = 0
    private(set) var feather: Double = 0
    private(set) var fuel = 0
    private(set) var eggs: Int
    private(set) var chicks: Int
    private(set) var streak = 0
    private var lastCornTime = -10.0
    private(set) var cushionAvailable: Bool
    private(set) var score: Double = 0
    private(set) var corn = 0
    private(set) var currentWorld: World

    // MARK: Stats
    private(set) var chicksRescued = 0
    private(set) var maxConvoy = 0
    private(set) var smashes = 0
    private(set) var closeCalls = 0
    private(set) var flaps = 0
    private(set) var splats = 0
    private(set) var lateMerges = 0
    private(set) var expressTolls = 0
    private(set) var bumps = 0

    // MARK: Road contents
    private(set) var entities: [Entity] = []
    private(set) var signals: [Signal] = []
    private(set) var isOver = false
    private(set) var result: RunResult?
    private var events: [RunEvent] = []
    private var nextID = 1
    private var nextRowTime = 2.8
    private var prevFree = 1
    private var nextJamTime: Double
    private var nextWaveTime: Double
    /// Lanes kept clear of ordinary traffic (red-light queues, green waves), in world y.
    private var reserved: [(lane: Int, range: ClosedRange<Double>)] = []
    private var spawnedTolls: Set<Double> = []
    private var announcedTolls: Set<Double> = []
    private var spawnedClosures: Set<Double> = []
    private var announcedClosures: Set<Double> = []
    private var lastInClosingLaneY: Double?

    init(setup: RunSetup, loadout: Loadout) {
        self.setup = setup
        breed = loadout.breed
        config = RunConfig(mode: setup.mode, loadout: loadout)
        rng = SeededGenerator(seed: setup.seed)
        if let index = setup.mode.routeIndex, let route = RouteCatalog.route(index) {
            plan = RoadPlan(route: route)
        } else {
            plan = RoadPlan(endlessSeed: setup.seed)
        }
        baseSpeed = config.startSpeed
        let startLanes = plan.lanes(at: 0)
        lane = min(1, startLanes - 1)
        x = RoadGeometry.laneCenter(lane)
        prevFree = lane
        eggs = config.mechanics.contains(.eggs) ? min(config.stats.maxEggs, config.trait.startEggs) : 0
        chicks = config.mechanics.contains(.chicks) ? min(config.stats.convoyCap + config.trait.convoyBonus, config.trait.startChicks) : 0
        maxConvoy = chicks
        cushionAvailable = config.trait.cushion
        currentWorld = plan.world(at: 0)
        nextJamTime = 9
        nextWaveTime = 15
    }

    // MARK: - Derived state

    var speed: Double { baseSpeed * config.trait.speedMultiplier * (isRigging ? 1.2 : 1) }
    var meters: Int { Int(distance / RoadGeometry.unitsPerMeter) }
    var lanesHere: Int { plan.lanes(at: distance) }
    var isJumping: Bool { jumpTime > 0 }
    var isDiving: Bool { diveTime > 0 }
    var isFlapping: Bool { flapTime > 0 }
    var isRigging: Bool { rigTime > 0 }
    var isFlapReady: Bool { config.mechanics.contains(.flap) && feather >= 1 }
    var isRigReady: Bool { config.mechanics.contains(.rig) && fuel >= Self.maxFuel && !isRigging }
    var convoyCap: Int { config.stats.convoyCap + config.trait.convoyBonus }
    var maxEggs: Int { config.stats.maxEggs }
    var multiplier: Double { Double(1 + chicks) * config.trait.scoreMultiplier }
    var displayScore: Int { Int(score) }
    var isInvulnerable: Bool { graceTime > 0 }
    var rigDuration: Double { config.stats.rigDuration + config.trait.rigBonusSeconds }
    var finishY: Double? { plan.finishY }
    /// 0...1 progress along a route.
    var progress: Double? { finishY.map { min(1, distance / $0) } }

    /// Events since the last call, oldest first.
    func drainEvents() -> [RunEvent] {
        defer { events.removeAll(keepingCapacity: true) }
        return events
    }

    // MARK: - Controls

    enum Swipe { case left, right, up, down }

    func swipe(_ direction: Swipe) {
        guard !isOver else { return }
        switch direction {
        case .left, .right:
            let target = lane + (direction == .left ? -1 : 1)
            guard target >= 0, target < lanesHere else { return }
            lane = target
            emit(.laneChange)
        case .up:
            guard !isRigging else { return }
            if isFlapReady && !isFlapping {
                flapTime = Self.flapDuration
                feather = 0
                jumpTime = 0
                diveTime = 0
                flaps += 1
                emit(.flap)
            } else if !isJumping && !isFlapping {
                jumpTime = Self.jumpDuration
                diveTime = 0
                emit(.jump)
            }
        case .down:
            guard !isRigging, !isFlapping else { return }
            diveTime = Self.diveDuration
            jumpTime = 0
            emit(.dive)
        }
    }

    @discardableResult
    func activateRig() -> Bool {
        guard !isOver, isRigReady else { return false }
        rigTime = rigDuration
        fuel = 0
        jumpTime = 0
        diveTime = 0
        flapTime = 0
        emit(.rigStart)
        return true
    }

    @discardableResult
    func throwEgg() -> Bool {
        guard !isOver, config.mechanics.contains(.eggs), eggs > 0 else { return false }
        eggs -= 1
        spawn(.egg, x: x, y: distance + 40)
        emit(.eggThrown)
        return true
    }

    // MARK: - Simulation

    func step(_ rawDt: Double) {
        guard !isOver else { return }
        let dt = min(max(rawDt, 0), 1.0 / 20)
        time += dt
        baseSpeed = min(config.maxSpeed, baseSpeed + config.acceleration * dt)
        let previousY = distance
        distance += speed * dt
        plan.extend(to: distance + 8000)
        score += (distance - previousY) / RoadGeometry.unitsPerMeter * multiplier

        tickTimers(dt)
        moveChicken(dt)
        scheduleContent()
        moveEntities(dt)
        resolveCollisions()
        checkCloseCalls()
        checkClosures(previousY: previousY)
        checkTolls()
        updateSignals()
        if let world = plan.worldChange(from: previousY, to: distance) {
            currentWorld = world
            emit(.worldEntered(world))
        }
        entities.removeAll { $0.y < distance - 500 || ($0.kind == .egg && $0.y > distance + 1400) }
        reserved.removeAll { $0.range.upperBound < distance - 200 }
        if let finishLine = finishY, distance >= finishLine, !isOver {
            finish(.cleared)
        }
    }

    private func tickTimers(_ dt: Double) {
        jumpTime = max(0, jumpTime - dt)
        diveTime = max(0, diveTime - dt)
        flapTime = max(0, flapTime - dt)
        graceTime = max(0, graceTime - dt)
        magnetTime = max(0, magnetTime - dt)
        doubleTime = max(0, doubleTime - dt)
        if rigTime > 0 {
            rigTime -= dt
            if rigTime <= 0 { endRig() }
        }
    }

    private func moveChicken(_ dt: Double) {
        // After flapping over a closure the lane may no longer exist.
        if lane >= lanesHere { lane = lanesHere - 1 }
        let target = RoadGeometry.laneCenter(lane)
        let stepX = Self.laneSwitchSpeed * dt
        if abs(target - x) <= stepX { x = target } else { x += target > x ? stepX : -stepX }
    }

    private func endRig() {
        rigTime = 0
        graceTime = max(graceTime, 1.0)
        emit(.rigEnd)
    }

    // MARK: - Spawning

    private var difficulty: Double {
        if let density = config.density { return density }
        return min(1, time / 200)
    }

    private var density: Double { config.density ?? (0.42 + 0.4 * difficulty) }

    private func trafficSpeed(at y: Double) -> Double {
        plan.world(at: y).trafficSpeed * (1 + 0.35 * difficulty)
    }

    private func rowInterval() -> Double {
        let base = config.density.map { 0.98 - 0.5 * $0 } ?? (0.92 - 0.42 * difficulty)
        return base * rng.value(in: 0.88...1.12)
    }

    private func scheduleContent() {
        // Big set pieces first so ordinary rows avoid their lanes.
        if config.mechanics.contains(.redLights), time >= nextJamTime { spawnRedLight(); nextJamTime = time + rng.value(in: 9...14) }
        if config.mechanics.contains(.greenWaves), time >= nextWaveTime { spawnGreenWave(); nextWaveTime = time + rng.value(in: 11...16) }
        spawnClosuresAndTolls()
        while nextRowTime < time + Self.lookahead {
            let lead = nextRowTime - time
            createRow(meetY: distance + speed * lead, lead: lead)
            nextRowTime += rowInterval()
        }
    }

    private func isReserved(_ lane: Int, at y: Double) -> Bool {
        reserved.contains { $0.lane == lane && $0.range.contains(y) }
    }

    /// True near toll plazas, lane closures and the finish, where rows would clutter the set piece.
    private func isQuietZone(_ y: Double) -> Bool {
        if let finish = finishY, y > finish - 200 { return true }
        if plan.tollYs.contains(where: { y > $0 - 480 && y < $0 + 360 }) { return true }
        if plan.usesLaneShift, plan.closures.contains(where: { y > $0.y - 140 && y < $0.y + 180 }) { return true }
        return false
    }

    private func createRow(meetY: Double, lead: Double) {
        guard !isQuietZone(meetY) else { return }
        let lanes = plan.lanes(at: meetY)
        let lanesSoon = plan.lanes(at: meetY + 500)
        var candidates = (0..<min(lanes, lanesSoon)).filter { !isReserved($0, at: meetY) }
        if candidates.isEmpty { candidates = (0..<lanes).filter { !isReserved($0, at: meetY) } }
        guard !candidates.isEmpty else { return }

        let wanted = min(lanes - 1, max(0, prevFree + Int.random(in: -1...1, using: &rng)))
        let free = candidates.min { abs($0 - wanted) < abs($1 - wanted) } ?? candidates[0]
        let world = plan.world(at: meetY)
        let traffic = trafficSpeed(at: meetY)

        for l in 0..<lanes where l != free && !isReserved(l, at: meetY) {
            let roll = rng.unit()
            let carChance = density * 0.62
            let center = RoadGeometry.laneCenter(l)
            if roll < carChance {
                let model = world.carPool[Int.random(in: 0..<world.carPool.count, using: &rng)]
                var car = makeEntity(.car(model), x: center, y: meetY + traffic * lead)
                car.velocity = traffic
                if config.mechanics.contains(.blinkers), abs(l - free) == 1, rng.unit() < 0.18 {
                    car.blinker = free > l ? 1 : -1
                }
                entities.append(car)
            } else if config.mechanics.contains(.hazards), roll < carChance + 0.13 {
                spawn(rng.unit() < 0.6 ? .cone : .pothole, x: center, y: meetY)
                if rng.unit() < 0.3 { spawn(.corn, x: center, y: meetY) }
            } else if config.mechanics.contains(.booms), roll < carChance + 0.21 {
                spawn(.boom, x: center, y: meetY)
            }
        }

        // Treats in the free lane.
        let freeX = RoadGeometry.laneCenter(free)
        let treat = rng.unit()
        // The showcase video wants convoys and rides sooner, so treats show up more often there.
        let chickEnd = debugGenerousTreats ? 0.56 : 0.48
        let fuelEnd = debugGenerousTreats ? 0.68 : 0.55
        if treat < 0.4 {
            for k in 0..<5 { spawn(.corn, x: freeX, y: meetY - 140 + Double(k) * 70) }
        } else if config.mechanics.contains(.chicks), treat < chickEnd, chicks < convoyCap {
            spawn(.chick, x: freeX, y: meetY)
        } else if config.mechanics.contains(.rig), treat < fuelEnd, !isRigging {
            spawn(.fuel, x: freeX, y: meetY)
        } else if config.mechanics.contains(.powerUps), treat < fuelEnd + 0.035 {
            spawn(.magnet, x: freeX, y: meetY)
        } else if config.mechanics.contains(.powerUps), treat < fuelEnd + 0.07 {
            spawn(.double, x: freeX, y: meetY)
        }
        prevFree = free
    }

    /// Clears ordinary content from a lane window that is still off screen.
    private func clearLane(_ lane: Int, from y0: Double, to y1: Double) {
        entities.removeAll { e in
            guard e.lane == lane, e.y - distance > 900 else { return false }
            if case .car = e.kind, e.velocity > 0 { return e.y > y0 && e.y < y1 + e.velocity * Self.lookahead }
            return e.y > y0 && e.y < y1
        }
    }

    /// Red light: a parked queue in one lane with corn between the cars (jump them one by one).
    private func spawnRedLight() {
        let meetY = distance + speed * Self.lookahead
        guard !isQuietZone(meetY), !isQuietZone(meetY + 1300) else { return }
        let lanes = plan.minLanes(in: meetY...(meetY + 1400))
        let options = (0..<lanes).filter { $0 != prevFree && !isReserved($0, at: meetY) && !isReserved($0, at: meetY + 1200) }
        guard let jamLane = options.randomElement(using: &rng) else { return }
        let x = RoadGeometry.laneCenter(jamLane)
        clearLane(jamLane, from: meetY - 240, to: meetY + 1300)
        reserved.append((jamLane, (meetY - 240)...(meetY + 1300)))
        let pool = plan.world(at: meetY).carPool.filter { $0.size.length < 150 }
        for k in 0..<4 {
            var car = makeEntity(.car(pool.randomElement(using: &rng) ?? .sedanRed), x: x, y: meetY + Double(k) * 360)
            car.parked = true
            entities.append(car)
            if k < 3 { for c in 0..<2 { spawn(.corn, x: x, y: meetY + Double(k) * 360 + 150 + Double(c) * 60) } }
        }
        let signal = Signal(id: nextSignalID(), kind: .red, lane: jamLane, y: meetY - 140, endY: meetY + 1200, phase: .active)
        signals.append(signal)
        emit(.signalWarning(.red))
    }

    /// Green wave: a warning, then four fast cars rush down one lane.
    private func spawnGreenWave() {
        let lead = Self.lookahead
        let firstMeet = distance + speed * lead
        let lastMeet = distance + speed * (lead + 0.84)
        guard !isQuietZone(firstMeet), !isQuietZone(lastMeet) else { return }
        let lanes = plan.minLanes(in: firstMeet...lastMeet)
        var options = (0..<lanes).filter { !isReserved($0, at: firstMeet) && !isReserved($0, at: lastMeet) }
        // Often aim at the chicken's own lane so the warning matters.
        if options.contains(lane), rng.unit() < 0.5 { options = [lane] }
        guard let waveLane = options.randomElement(using: &rng) else { return }
        let x = RoadGeometry.laneCenter(waveLane)
        clearLane(waveLane, from: firstMeet - 300, to: lastMeet + 300)
        reserved.append((waveLane, (firstMeet - 300)...(lastMeet + 300)))
        let velocity = trafficSpeed(at: firstMeet) * 1.7
        let pool = plan.world(at: firstMeet).carPool
        for k in 0..<4 {
            let t = lead + Double(k) * 0.28
            var car = makeEntity(.car(pool.randomElement(using: &rng) ?? .coupe), x: x, y: distance + (speed + velocity) * t)
            car.velocity = velocity
            car.wave = true
            entities.append(car)
        }
        // The light turns green 1.2 s before the first car arrives.
        let activation = distance + speed * (lead - 1.2)
        signals.append(Signal(id: nextSignalID(), kind: .green, lane: waveLane, y: activation, endY: lastMeet + 120, phase: .warning))
        emit(.signalWarning(.green))
    }

    private var signalCounter = 0
    private func nextSignalID() -> Int { signalCounter += 1; return signalCounter }

    private func spawnClosuresAndTolls() {
        if plan.usesLaneShift {
            for closure in plan.closures where closure.y - distance < 2400 && closure.y > distance && !spawnedClosures.contains(closure.y) {
                spawnedClosures.insert(closure.y)
                for l in closure.closing { spawn(.barricade, x: RoadGeometry.laneCenter(l), y: closure.y) }
            }
        }
        for tollY in plan.tollYs where tollY - distance < 2400 && tollY > distance && !spawnedTolls.contains(tollY) {
            spawnedTolls.insert(tollY)
            let lanes = plan.lanes(at: tollY)
            var kinds: [TollKind] = Array(repeating: .closed, count: lanes)
            let openCount = max(1, lanes / 3)
            var order = Array(0..<lanes)
            order.shuffle(using: &rng)
            for i in 0..<openCount { kinds[order[i]] = .open }
            if lanes >= 3, config.mechanics.contains(.chicks) { kinds[order[openCount]] = .express }
            for l in 0..<lanes { spawn(.toll(kinds[l]), x: RoadGeometry.laneCenter(l), y: tollY) }
        }
    }

    private func makeEntity(_ kind: EntityKind, x: Double, y: Double) -> Entity {
        defer { nextID += 1 }
        return Entity(id: nextID, kind: kind, x: x, y: y)
    }

    @discardableResult
    private func spawn(_ kind: EntityKind, x: Double, y: Double) -> Int {
        let e = makeEntity(kind, x: x, y: y)
        entities.append(e)
        return e.id
    }

    // MARK: - Movement

    private func moveEntities(_ dt: Double) {
        let magnetRadius = magnetTime > 0 ? 320 : config.trait.passiveMagnetRadius
        for i in entities.indices {
            var e = entities[i]
            switch e.kind {
            case .car:
                if e.parked { break }
                e.y -= e.velocity * dt
                if e.blinker != 0, e.targetX == nil, e.y - distance < 640 + speed * 0.15 {
                    let target = e.lane + e.blinker
                    if target >= 0, target < plan.lanes(at: e.y) { e.targetX = RoadGeometry.laneCenter(target) } else { e.blinker = 0 }
                }
                if let target = e.targetX {
                    let stepX = Self.carLaneChangeSpeed * dt
                    if abs(target - e.x) <= stepX { e.x = target; e.targetX = nil; e.blinker = 0 } else { e.x += target > e.x ? stepX : -stepX }
                }
            case .egg:
                e.y += Self.eggSpeed * dt
            case .corn where magnetRadius > 0:
                let dx = x - e.x, dy = (distance + 10) - e.y
                if dx * dx + dy * dy < magnetRadius * magnetRadius {
                    let k = min(1, dt * 9)
                    e.x += dx * k
                    e.y += dy * k
                }
            default:
                break
            }
            entities[i] = e
        }
        resolveEggs()
    }

    private func resolveEggs() {
        let eggIDs = entities.filter { $0.kind == .egg }.map(\.id)
        for eggID in eggIDs {
            guard let eggIndex = entities.firstIndex(where: { $0.id == eggID }) else { continue }
            let egg = entities[eggIndex]
            guard let carIndex = entities.firstIndex(where: { e in
                if case .car = e.kind { return !e.splatted && !e.parked && abs(e.x - egg.x) < 45 && e.y - egg.y > -40 && e.y - egg.y < 80 }
                return false
            }) else { continue }
            splat(carIndex)
            entities.removeAll { $0.id == eggID }
        }
    }

    private func splat(_ index: Int) {
        var car = entities[index]
        car.splatted = true
        let lanes = plan.lanes(at: car.y)
        let options = [car.lane - 1, car.lane + 1].filter { l in
            l >= 0 && l < lanes && !entities.contains { other in
                guard other.id != car.id, case .car = other.kind else { return false }
                return other.lane == l && abs(other.y - car.y) < 260
            }
        }
        if let target = options.randomElement(using: &rng) {
            car.targetX = RoadGeometry.laneCenter(target)
            car.blinker = target > car.lane ? 1 : -1
        } else {
            car.parked = true
            car.velocity = 0
        }
        entities[index] = car
        splats += 1
        score += 60 * multiplier
        emit(.splat(id: car.id))
    }

    // MARK: - Collisions

    private func overlaps(_ e: Entity) -> Bool {
        let half = e.halfSize
        return abs(e.x - x) < half.w + config.trait.hitboxHalfWidth && abs(e.y - distance) < half.h + Self.chickenHalfHeight
    }

    private func resolveCollisions() {
        var removals: Set<Int> = []
        for i in entities.indices {
            let e = entities[i]
            if e.kind.isPickup {
                if abs(e.x - x) < 44, abs(e.y - distance) < 46 { collect(e); removals.insert(e.id) }
                continue
            }
            guard overlaps(e) else { continue }
            switch e.kind {
            case .car:
                if isFlapping { continue }
                if isRigging { smash(e); removals.insert(e.id); continue }
                if e.parked && isJumping { continue }
                if bump(at: e) { removals.insert(e.id) }
            case .cone, .pothole:
                if isJumping || isFlapping { continue }
                if isRigging { if e.kind == .cone { smash(e); removals.insert(e.id) }; continue }
                if bump(at: e) { removals.insert(e.id) }
            case .boom:
                if isDiving || isFlapping { continue }
                if isRigging { smash(e); removals.insert(e.id); continue }
                if bump(at: e) { removals.insert(e.id) }
            case .barricade:
                if isFlapping { continue }
                if isRigging { endRig(); emit(.bump(x: e.x, y: e.y)); continue }
                _ = bump(at: e)
            case .toll(let kind):
                guard !e.opened else { continue }
                switch kind {
                case .open:
                    entities[i].opened = true
                    emit(.tollPassed(.open, bonus: 0))
                case .express where chicks >= Self.expressMinimumChicks:
                    entities[i].opened = true
                    let bonus = 10 * chicks
                    corn += bonus
                    score += Double(bonus) * 10
                    expressTolls += 1
                    emit(.tollPassed(.express, bonus: bonus))
                case .express, .closed:
                    if isFlapping { continue }
                    if isRigging { smash(e); removals.insert(e.id); continue }
                    _ = bump(at: e)
                }
            case .egg, .corn, .chick, .fuel, .magnet, .double:
                continue
            }
            if isOver { break }
        }
        if !removals.isEmpty { entities.removeAll { removals.contains($0.id) } }
    }

    /// Returns true when the obstacle should disappear (knocked aside by the bump).
    private func bump(at e: Entity) -> Bool {
        guard !isInvulnerable, !isOver else { return false }
        if debugInvincible { return true }
        if chicks > 0 {
            let lost = max(1, (chicks + 1) / 2)
            chicks -= lost
            bumps += 1
            graceTime = Self.bumpGrace
            baseSpeed = max(config.startSpeed, baseSpeed * 0.92)
            emit(.chicksLost(count: lost))
            emit(.bump(x: e.x, y: e.y))
            return isSmall(e)
        }
        if cushionAvailable {
            cushionAvailable = false
            bumps += 1
            graceTime = Self.bumpGrace
            emit(.cushion)
            emit(.bump(x: e.x, y: e.y))
            return isSmall(e)
        }
        bumps += 1
        emit(.crash(x: e.x, y: e.y))
        finish(.crashed)
        return false
    }

    private func isSmall(_ e: Entity) -> Bool {
        switch e.kind {
        case .cone, .boom: true
        default: false
        }
    }

    private func smash(_ e: Entity) {
        smashes += 1
        score += 100 * multiplier * (e.wave ? 2 : 1)
        corn += 2 * config.trait.smashCornMultiplier
        emit(.smash(id: e.id, x: e.x, y: e.y, wave: e.wave))
    }

    private func collect(_ e: Entity) {
        switch e.kind {
        case .corn:
            streak = time - lastCornTime <= Self.streakWindow ? streak + 1 : 1
            lastCornTime = time
            let value = (doubleTime > 0 ? 2 : 1) * (streak >= Self.streakDoubleAt ? 2 : 1)
            corn += value
            score += 5 * Double(value) * multiplier
            emit(.corn(x: e.x, y: e.y, streak: streak))
            if config.mechanics.contains(.eggs), streak % Self.streakEggEvery == 0 {
                if eggs < maxEggs { eggs += 1 } else { score += 50 * multiplier }
                emit(.streakEgg)
            }
        case .chick:
            if chicks < convoyCap {
                chicks += 1
                chicksRescued += 1
                maxConvoy = max(maxConvoy, chicks)
                emit(.chickRescued(count: chicks))
            } else {
                score += 100 * multiplier
                emit(.pickup(.chick))
            }
        case .fuel:
            if isRigging {
                rigTime += 1.5
            } else {
                fuel = min(Self.maxFuel, fuel + 1)
                if fuel == Self.maxFuel { emit(.rigReady) }
            }
            emit(.pickup(.fuel))
        case .magnet:
            magnetTime = config.stats.magnetDuration
            emit(.pickup(.magnet))
        case .double:
            doubleTime = config.stats.doubleDuration
            emit(.pickup(.double))
        default:
            break
        }
    }

    private func checkCloseCalls() {
        guard config.mechanics.contains(.flap) else { return }
        for i in entities.indices {
            let e = entities[i]
            guard case .car = e.kind, !e.passed, !e.parked, e.y < distance else { continue }
            entities[i].passed = true
            guard !isFlapping, !isRigging else { continue }
            let gap = abs(e.x - x) - (e.halfSize.w + config.trait.hitboxHalfWidth)
            guard gap >= 0, gap < 62 else { continue }
            closeCalls += 1
            let wasReady = feather >= 1
            feather = min(1, feather + config.stats.closeCallValue * config.trait.closeCallBoost)
            score += 25 * multiplier
            emit(.closeCall(x: (e.x + x) / 2, y: distance))
            if !wasReady && feather >= 1 { emit(.flapReady) }
        }
    }

    private func checkClosures(previousY: Double) {
        guard plan.usesLaneShift else { return }
        for closure in plan.closures where closure.y > previousY - 1 && closure.y - distance < 1200 {
            if !announcedClosures.contains(closure.y), closure.y - distance < 1100 {
                announcedClosures.insert(closure.y)
                emit(.laneEnds(lane: closure.closing.lowerBound))
            }
            if closure.closing.contains(RoadGeometry.lane(atX: x)), closure.y - distance < 700, closure.y > distance {
                lastInClosingLaneY = distance
            }
            if previousY < closure.y, distance >= closure.y {
                if let last = lastInClosingLaneY, closure.y - last <= Self.lateMergeWindow, !closure.closing.contains(lane) {
                    lateMerges += 1
                    score += 150 * multiplier
                    emit(.lateMerge(x: x, y: distance))
                }
                lastInClosingLaneY = nil
            }
        }
    }

    private func checkTolls() {
        for tollY in plan.tollYs where !announcedTolls.contains(tollY) && tollY - distance < 1300 && tollY > distance {
            announcedTolls.insert(tollY)
            emit(.tollAhead)
        }
    }

    private func updateSignals() {
        for i in signals.indices where signals[i].phase == .warning && distance >= signals[i].y {
            signals[i].phase = .active
            emit(.greenWave)
        }
        signals.removeAll { distance > $0.endY + 120 }
    }

    // MARK: - Finish

    private func finish(_ result: RunResult) {
        isOver = true
        self.result = result
        rigTime = 0
        emit(.finished)
    }

    private func emit(_ event: RunEvent) { events.append(event) }

    var summary: RunSummary {
        RunSummary(
            mode: setup.mode,
            result: result ?? .crashed,
            breed: breed,
            score: displayScore,
            meters: meters,
            corn: corn,
            chicksRescued: chicksRescued,
            finalChicks: chicks,
            maxConvoy: maxConvoy,
            smashes: smashes,
            closeCalls: closeCalls,
            flaps: flaps,
            splats: splats,
            lateMerges: lateMerges,
            expressTolls: expressTolls,
            bumps: bumps,
            duration: time,
            furthestWorld: currentWorld
        )
    }

    // MARK: - Autopilot (UI tests, screenshots and the showcase video)

    private var autopilotCooldown = 0.0
    private var eggCooldown = 0.0

    /// A simple driver: leaves blocked lanes, hops low hazards, ducks barriers, steers to the best toll
    /// gate, picks up treats and fires the Big Rig when it is ready. `showcase` also shows off Flap Hop,
    /// Egg Splat and late merges. Call once per frame before `step`.
    func autopilot(_ dt: Double, showcase: Bool = false) {
        guard !isOver else { return }
        autopilotCooldown -= dt
        eggCooldown -= dt
        if isRigReady { activateRig() }
        let look = 180 + speed * 0.55
        // Late merging means leaving a closing lane only when the barrier is close.
        let barrierLook = showcase ? 150 + speed * 0.12 : look
        func blocker(in l: Int, within range: Double) -> Entity? {
            entities.filter { e in
                guard e.lane == l, e.y > distance - 30, e.y - distance < range else { return false }
                switch e.kind {
                case .car: return !(e.parked && isJumping)
                case .barricade: return e.y - distance < barrierLook
                case .toll(let k): return !(k == .open || e.opened || (k == .express && chicks >= Self.expressMinimumChicks))
                default: return false
                }
            }.min { $0.y < $1.y }
        }
        func isClear(_ l: Int, _ range: Double) -> Bool { l >= 0 && l < lanesHere && blocker(in: l, within: range) == nil }

        if !isRigging {
            let ahead = blocker(in: lane, within: look)
            if showcase, isFlapReady, let car = ahead, case .car = car.kind {
                swipe(.up)
                return
            }
            if showcase, eggs > 0, eggCooldown <= 0,
               entities.contains(where: { e in
                   if case .car = e.kind { return e.lane == lane && !e.parked && !e.splatted && e.y - distance > 380 && e.y - distance < 900 }
                   return false
               }) {
                throwEgg()
                eggCooldown = 3
            }
            if ahead != nil, autopilotCooldown <= 0 {
                if let target = [lane - 1, lane + 1].first(where: { isClear($0, look * 1.1) }) {
                    swipe(target < lane ? .left : .right)
                    autopilotCooldown = 0.18
                } else if eggs > 0, let car = ahead, case .car = car.kind {
                    throwEgg()
                } else if isFlapReady {
                    swipe(.up)
                }
                return
            }
        }

        if showcase, autopilotCooldown <= 0 {
            // Big Rig: hunt cars in the neighbouring lanes.
            if isRigging {
                let prey = entities.filter { e in
                    if case .car = e.kind { return abs(e.lane - lane) == 1 && e.y - distance > 100 && e.y - distance < 700 }
                    return false
                }.min { $0.y < $1.y }
                if let prey, !entities.contains(where: { e in
                    if case .car = e.kind { return e.lane == lane && e.y > distance && e.y < prey.y }
                    return false
                }) {
                    swipe(prey.lane < lane ? .left : .right)
                    autopilotCooldown = 0.3
                    return
                }
            }
            // Lane Shift: ride in the closing lane so the merge out happens at the last moment.
            if let closure = plan.nextClosure(after: distance), closure.y - distance > 350, closure.y - distance < 1400,
               !closure.closing.contains(lane) {
                let next = lane + (closure.closing.lowerBound > lane ? 1 : -1)
                if isClear(next, look * 1.2) {
                    swipe(next > lane ? .right : .left)
                    autopilotCooldown = 0.3
                    return
                }
            }
        }

        // Toll plaza: line up with a passable gate, the Express one if the convoy is big enough.
        if let tollY = plan.tollYs.first(where: { $0 > distance && $0 - distance < 1100 }), autopilotCooldown <= 0 {
            let gates = entities.filter { e in
                if case .toll = e.kind { return abs(e.y - tollY) < 1 }
                return false
            }
            let express = gates.first { e in
                if case .toll(.express) = e.kind { return chicks >= Self.expressMinimumChicks }
                return false
            }
            let nearestOpen = gates.filter { $0.kind == .toll(.open) }.min { abs($0.lane - lane) < abs($1.lane - lane) }
            if let target = express ?? nearestOpen, target.lane != lane {
                let next = lane + (target.lane > lane ? 1 : -1)
                if isClear(next, look) || isRigging {
                    swipe(next > lane ? .right : .left)
                    autopilotCooldown = 0.25
                }
                return
            }
        }

        // Treats: chicks first, then fuel, power-ups and corn in a neighbouring lane.
        if autopilotCooldown <= 0 {
            func priority(_ k: EntityKind) -> Int {
                switch k {
                case .chick: chicks < convoyCap ? 0 : 9
                case .fuel: 1
                case .magnet, .double: 2
                case .corn: 3
                default: 9
                }
            }
            let treats = entities.filter { e in
                e.kind.isPickup && priority(e.kind) < 9 && abs(e.lane - lane) == 1 && e.y - distance > 120 && e.y - distance < 700
            }
            if let best = treats.min(by: { (priority($0.kind), $0.y) < (priority($1.kind), $1.y) }),
               !entities.contains(where: { $0.lane == lane && $0.kind.isPickup && priority($0.kind) <= priority(best.kind) && $0.y > distance && $0.y < best.y }),
               isClear(best.lane, look * 1.2) {
                swipe(best.lane < lane ? .left : .right)
                autopilotCooldown = 0.35
            }
        }

        for e in entities where e.lane == lane && e.y > distance && e.y - distance < 90 {
            switch e.kind {
            case .cone, .pothole: if !isJumping { swipe(.up) }
            case .car where e.parked: if !isJumping { swipe(.up) }
            case .boom: if !isDiving { swipe(.down) }
            default: break
            }
        }
    }

    // MARK: - Test hooks

    /// Ignores bumps entirely (unit tests that watch road events).
    var debugInvincible = false
    /// More chicks and fuel cans (showcase video only).
    var debugGenerousTreats = false

    /// Places an entity directly (unit tests and the tutorial use this).
    @discardableResult
    func debugPlace(_ kind: EntityKind, lane: Int, ahead: Double, velocity: Double = 0, parked: Bool = false, blinker: Int = 0) -> Int {
        var e = makeEntity(kind, x: RoadGeometry.laneCenter(lane), y: distance + ahead)
        e.velocity = velocity
        e.parked = parked
        e.blinker = blinker
        entities.append(e)
        return e.id
    }

    /// Removes generated traffic and stops new rows (unit tests).
    func debugClearRoad(stopSpawning: Bool = true) {
        entities.removeAll()
        if stopSpawning {
            nextRowTime = .greatestFiniteMagnitude
            nextJamTime = .greatestFiniteMagnitude
            nextWaveTime = .greatestFiniteMagnitude
        }
    }

    func debugSetFuel(_ value: Int) { fuel = value }
    func debugSetFeather(_ value: Double) { feather = value }
    func debugSetChicks(_ value: Int) { chicks = value }
    func debugSetEggs(_ value: Int) { eggs = value }
}
