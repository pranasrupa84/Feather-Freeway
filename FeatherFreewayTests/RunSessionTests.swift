import Foundation
import Testing
@testable import FeatherFreeway

@MainActor
@Suite("Run session: controls and collisions")
struct RunSessionControlTests {
    @Test func laneChangesStayOnTheRoad() {
        let s = Fixtures.quietSession()
        #expect(s.lane == 1)
        s.swipe(.left)
        #expect(s.lane == 0)
        s.swipe(.left)
        #expect(s.lane == 0, "cannot leave the road on the left")
        for _ in 0..<5 { s.swipe(.right) }
        #expect(s.lane == s.lanesHere - 1)
    }

    @Test func standingStillChangesNothingButDistance() {
        let s = Fixtures.quietSession()
        Fixtures.advance(s, seconds: 2)
        #expect(s.lane == 1)
        #expect(s.distance > 800)
        #expect(!s.isOver)
        // Only lane-closure barriers from the road plan appear; no traffic is generated.
        #expect(s.entities.allSatisfy { $0.kind == .barricade })
    }

    @Test func movingCarCrashesAChickenWithoutProtection() {
        let s = Fixtures.quietSession()
        s.debugPlace(.car(.sedanRed), lane: 1, ahead: 300, velocity: 200)
        Fixtures.advance(s, seconds: 1.5)
        #expect(s.isOver)
        #expect(s.result == .crashed)
        #expect(s.summary.bumps == 1)
    }

    @Test func dodgingIntoAnotherLaneAvoidsTheCar() {
        let s = Fixtures.quietSession()
        s.debugPlace(.car(.sedanRed), lane: 1, ahead: 400, velocity: 200)
        s.swipe(.right)
        Fixtures.advance(s, seconds: 1.5)
        #expect(!s.isOver)
    }

    @Test func jumpClearsConesButNotWithoutJumping() {
        let jumper = Fixtures.quietSession()
        jumper.debugPlace(.cone, lane: 1, ahead: 120)
        jumper.swipe(.up)
        Fixtures.advance(jumper, seconds: 1)
        #expect(!jumper.isOver)

        let walker = Fixtures.quietSession()
        walker.debugPlace(.cone, lane: 1, ahead: 120)
        Fixtures.advance(walker, seconds: 1)
        #expect(walker.isOver)
    }

    @Test func diveGoesUnderBarrierArmsAndJumpDoesNot() {
        let diver = Fixtures.quietSession()
        diver.debugPlace(.boom, lane: 1, ahead: 120)
        diver.swipe(.down)
        Fixtures.advance(diver, seconds: 1)
        #expect(!diver.isOver)

        let jumper = Fixtures.quietSession()
        jumper.debugPlace(.boom, lane: 1, ahead: 120)
        jumper.swipe(.up)
        Fixtures.advance(jumper, seconds: 1)
        #expect(jumper.isOver)
    }

    @Test func parkedCarsCanBeJumpedButMovingOnesCannot() {
        let s = Fixtures.quietSession()
        s.debugPlace(.car(.hatch), lane: 1, ahead: 140, parked: true)
        s.swipe(.up)
        Fixtures.advance(s, seconds: 1)
        #expect(!s.isOver)

        let m = Fixtures.quietSession()
        m.debugPlace(.car(.hatch), lane: 1, ahead: 220, velocity: 150)
        m.swipe(.up)
        Fixtures.advance(m, seconds: 1)
        #expect(m.isOver)
    }
}

@MainActor
@Suite("Run session: signature mechanics")
struct RunSessionMechanicTests {
    @Test func chickConvoyRaisesMultiplierAndActsAsShield() {
        let s = Fixtures.quietSession()
        s.debugPlace(.chick, lane: 1, ahead: 60)
        s.debugPlace(.chick, lane: 1, ahead: 160)
        Fixtures.advance(s, seconds: 0.6)
        #expect(s.chicks == 2)
        #expect(s.multiplier == 3)
        s.debugPlace(.car(.van), lane: 1, ahead: 300, velocity: 200)
        Fixtures.advance(s, seconds: 1.2)
        #expect(!s.isOver, "the convoy scatters instead of crashing")
        #expect(s.chicks == 1, "half the convoy (rounded up) runs off")
        #expect(s.bumps == 1)
    }

    @Test func convoyIsCappedByTheGarageWhistle() {
        let s = Fixtures.quietSession(levels: [.convoyCap: 0])
        for k in 0..<8 { s.debugPlace(.chick, lane: 1, ahead: 60 + Double(k) * 50) }
        Fixtures.advance(s, seconds: 1.5)
        #expect(s.chicks == 5)
        #expect(s.convoyCap == 5)
        let duchess = Fixtures.quietSession(breed: .duchess, levels: [.convoyCap: 2])
        #expect(duchess.chicks == 2, "Mother Hen starts with chicks")
        #expect(duchess.convoyCap == 9)
    }

    @Test func fluffyCushionForgivesTheFirstBumpOnly() {
        let s = Fixtures.quietSession(breed: .mabel)
        s.debugPlace(.cone, lane: 1, ahead: 100)
        Fixtures.advance(s, seconds: 0.6)
        #expect(!s.isOver)
        #expect(!s.cushionAvailable)
        Fixtures.advance(s, seconds: 2)
        s.debugPlace(.cone, lane: 1, ahead: 100)
        Fixtures.advance(s, seconds: 0.6)
        #expect(s.isOver)
    }

    @Test func bigRigNeedsThreeCansThenSmashesTraffic() {
        let s = Fixtures.quietSession()
        #expect(!s.activateRig())
        for k in 0..<3 { s.debugPlace(.fuel, lane: 1, ahead: 60 + Double(k) * 80) }
        Fixtures.advance(s, seconds: 0.8)
        #expect(s.fuel == 3)
        #expect(s.isRigReady)
        #expect(s.activateRig())
        #expect(s.fuel == 0)
        let cornBefore = s.corn
        s.debugPlace(.car(.bus), lane: 1, ahead: 300, velocity: 200)
        s.debugPlace(.boom, lane: 1, ahead: 700)
        Fixtures.advance(s, seconds: 1.5)
        #expect(!s.isOver)
        #expect(s.smashes == 2)
        #expect(s.corn > cornBefore)
        Fixtures.advance(s, seconds: s.rigDuration)
        #expect(!s.isRigging, "the ride ends after its duration")
    }

    @Test func rigDurationGrowsWithGarageAndRooster() {
        let base = Fixtures.quietSession()
        let tuned = Fixtures.quietSession(breed: .rusty, levels: [.rigTime: 3])
        #expect(base.rigDuration == 6)
        #expect(tuned.rigDuration == 11)
    }

    @Test func concreteBarrierStopsTheRig() {
        let s = Fixtures.quietSession()
        s.debugSetFuel(3)
        s.activateRig()
        s.debugPlace(.barricade, lane: 1, ahead: 200)
        Fixtures.advance(s, seconds: 0.6)
        #expect(!s.isRigging)
        #expect(!s.isOver)
    }

    @Test func closeCallsFillTheFeatherMeterAndFlapHopsOverCars() {
        let s = Fixtures.quietSession()
        for k in 0..<5 {
            s.debugPlace(.car(.sedanBlue), lane: 2, ahead: 200 + Double(k) * 400, velocity: 150)
        }
        Fixtures.advance(s, seconds: 4)
        #expect(s.closeCalls == 5)
        #expect(s.isFlapReady)
        s.swipe(.up)
        #expect(s.isFlapping)
        #expect(s.feather == 0)
        s.debugPlace(.car(.truck), lane: 1, ahead: 200, velocity: 150)
        Fixtures.advance(s, seconds: 0.8)
        #expect(!s.isOver, "flapping chickens fly over traffic")
    }

    @Test func featherGaugeAndBantamFillFaster() {
        let s = Fixtures.quietSession(breed: .pip, levels: [.featherFill: 5])
        s.debugPlace(.car(.sedanBlue), lane: 2, ahead: 220, velocity: 150)
        Fixtures.advance(s, seconds: 1)
        let expected = 0.2 * 1.75 * 1.3
        #expect(abs(s.feather - expected) < 0.001)
    }

    @Test func eggSplatMakesTheCarSwerveOutOfTheLane() {
        let s = Fixtures.quietSession()
        s.debugSetEggs(1)
        let car = s.debugPlace(.car(.sedanRed), lane: 1, ahead: 700, velocity: 150)
        #expect(s.throwEgg())
        #expect(s.eggs == 0)
        Fixtures.advance(s, seconds: 0.5)
        #expect(s.splats == 1)
        let splatted = s.entities.first { $0.id == car }
        #expect(splatted?.splatted == true)
        Fixtures.advance(s, seconds: 1)
        #expect(!s.isOver)
        #expect(s.entities.first { $0.id == car }.map { $0.lane != 1 } ?? true)
        #expect(!s.throwEgg(), "no eggs left")
    }

    @Test func cornStreakLaysEggsAndDoublesCorn() {
        let s = Fixtures.quietSession(breed: .rusty)
        for k in 0..<32 { s.debugPlace(.corn, lane: 1, ahead: 50 + Double(k) * 40) }
        Fixtures.advance(s, seconds: 4)
        #expect(s.streak == 32)
        #expect(s.eggs == 2)
        // 29 kernels at 1 + 3 kernels from the 30th on at 2.
        #expect(s.corn == 29 + 3 * 2)
    }

    @Test func streakBreaksAfterAPause() {
        let s = Fixtures.quietSession()
        s.debugPlace(.corn, lane: 1, ahead: 50)
        s.debugPlace(.corn, lane: 1, ahead: 1400)
        Fixtures.advance(s, seconds: 3.5)
        #expect(s.streak == 1)
    }

    @Test func doubleCornAndMagnet() {
        let s = Fixtures.quietSession()
        s.debugPlace(.double, lane: 1, ahead: 50)
        s.debugPlace(.magnet, lane: 1, ahead: 100)
        Fixtures.advance(s, seconds: 0.4)
        #expect(s.doubleTime > 0)
        #expect(s.magnetTime > 0)
        // Magnet pulls corn from the next lane.
        s.debugPlace(.corn, lane: 2, ahead: 260)
        Fixtures.advance(s, seconds: 1)
        #expect(s.corn == 2)
    }

    @Test func expressTollNeedsThreeChicksAndPaysForEach() {
        let rich = Fixtures.quietSession()
        rich.debugSetChicks(4)
        rich.debugPlace(.toll(.express), lane: 1, ahead: 200)
        Fixtures.advance(rich, seconds: 1)
        #expect(!rich.isOver)
        #expect(rich.expressTolls == 1)
        #expect(rich.corn == 40)

        let poor = Fixtures.quietSession()
        poor.debugPlace(.toll(.express), lane: 1, ahead: 200)
        Fixtures.advance(poor, seconds: 1)
        #expect(poor.isOver, "without a convoy the express gate is shut")

        let open = Fixtures.quietSession()
        open.debugPlace(.toll(.open), lane: 1, ahead: 200)
        Fixtures.advance(open, seconds: 1)
        #expect(!open.isOver)
    }

    @Test func blinkerCarMovesIntoTheNeighbouringLane() {
        let s = Fixtures.quietSession()
        let id = s.debugPlace(.car(.sedanBlue), lane: 2, ahead: 1400, velocity: 150, blinker: -1)
        Fixtures.advance(s, seconds: 1.8)
        let car = s.entities.first { $0.id == id }
        #expect(car?.lane == 1)
        #expect(car?.blinker == 0)
    }

    @Test func endlessRunIsDeterministicForASeed() {
        let a = RunSession(setup: RunSetup(mode: .endless, seed: 7), loadout: .base)
        let b = RunSession(setup: RunSetup(mode: .endless, seed: 7), loadout: .base)
        Fixtures.advance(a, seconds: 6)
        Fixtures.advance(b, seconds: 6)
        #expect(a.entities.map(\.kind) == b.entities.map(\.kind))
        #expect(a.entities.map(\.y) == b.entities.map(\.y))
    }

    @Test func everyGeneratedRowLeavesAFreeLane() {
        // Sample the traffic at several moments: no "wall" of moving cars across all lanes.
        let s = RunSession(setup: RunSetup(mode: .endless, seed: 99), loadout: .base)
        for _ in 0..<40 {
            Fixtures.advance(s, seconds: 0.5, autopilot: true)
            let lanes = s.lanesHere
            let near = s.entities.filter { e in
                if case .car = e.kind { return abs(e.y - (s.distance + 300)) < 40 }
                return false
            }
            #expect(Set(near.map(\.lane)).count < lanes)
        }
    }
}

@MainActor
@Suite("Run session: road events")
struct RunSessionRoadTests {
    @Test func redLightParksAQueueWithCorn() {
        let route = RouteCatalog.routes[8]
        #expect(route.mechanics.contains(.redLights))
        let s = RunSession(setup: RunSetup(mode: .route(8), seed: 3), loadout: .base)
        s.debugInvincible = true
        var sawSignal = false, sawQueue = false
        for _ in 0..<(60 * 30) {
            s.step(1.0 / 60)
            if s.signals.contains(where: { $0.kind == .red }) { sawSignal = true }
            if s.entities.contains(where: \.parked) { sawQueue = true }
            if s.isOver { break }
        }
        #expect(sawSignal)
        #expect(sawQueue)
    }

    @Test func greenWaveWarnsThenTurnsGreen() {
        let s = RunSession(setup: RunSetup(mode: .route(9), seed: 5), loadout: .base)
        s.debugInvincible = true
        var phases: Set<String> = []
        var waveCars = false
        for _ in 0..<(60 * 30) {
            s.step(1.0 / 60)
            for sig in s.signals where sig.kind == .green { phases.insert(sig.phase == .warning ? "warning" : "active") }
            if s.entities.contains(where: \.wave) { waveCars = true }
            if s.isOver { break }
        }
        #expect(waveCars)
        #expect(phases.contains("warning"))
        #expect(phases.contains("active"))
    }

    @Test func lateMergeRewardsLeavingAClosingLaneAtTheLastMoment() {
        // Route 6 narrows 3 → 2 at its first boundary.
        let s = RunSession(setup: RunSetup(mode: .route(5), seed: 11), loadout: .base)
        s.debugClearRoad()
        guard let closure = s.plan.closures.first else { Issue.record("route 6 should close a lane"); return }
        s.swipe(.right)
        #expect(closure.closing.contains(2))
        while s.distance < closure.y - 200 && !s.isOver { s.step(1.0 / 60) }
        s.swipe(.left)
        while s.distance < closure.y + 50 && !s.isOver { s.step(1.0 / 60) }
        #expect(!s.isOver)
        #expect(s.lateMerges == 1)
    }

    @Test func autopilotClearsTheFirstRoute() {
        let s = RunSession(setup: RunSetup(mode: .route(0), seed: 21), loadout: .base)
        Fixtures.advance(s, seconds: 60, autopilot: true)
        #expect(s.result == .cleared)
        #expect(s.meters >= RouteCatalog.routes[0].meters)
    }
}

@MainActor
@Suite("Showcase autopilot")
struct ShowcaseTests {
    @Test func showcaseRunDemonstratesEveryMechanic() {
        let s = RunSession(setup: RunSetup(mode: .endless, seed: 2027), loadout: Loadout(levels: [.rigTime: 1, .eggCarton: 1], breed: .duchess))
        s.debugInvincible = true
        s.debugGenerousTreats = true
        var worlds: Set<World> = [s.currentWorld]
        var sawSignal = false
        for _ in 0..<(60 * 85) {
            s.autopilot(1.0 / 60, showcase: true)
            s.step(1.0 / 60)
            worlds.insert(s.currentWorld)
            if !s.signals.isEmpty { sawSignal = true }
        }
        let sum = s.summary
        #expect(sum.smashes > 0)
        #expect(sum.flaps > 0)
        #expect(sum.splats > 0)
        #expect(sum.chicksRescued > 0)
        #expect(sum.expressTolls > 0)
        #expect(sum.lateMerges > 0)
        #expect(sum.closeCalls > 0)
        #expect(worlds.count == World.allCases.count)
        #expect(sawSignal)
    }
}
