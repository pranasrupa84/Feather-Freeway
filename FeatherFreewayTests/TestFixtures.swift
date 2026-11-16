import Foundation
import SwiftData
@testable import FeatherFreeway

@MainActor
enum Fixtures {
    static func store(now: Date = Date(timeIntervalSince1970: 1_800_000_000)) throws -> (ProfileStore, ModelContainer) {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = try ProfileStore(container: container, now: { now })
        return (store, container)
    }

    /// An endless session with generated traffic switched off, so tests place exactly what they need.
    static func quietSession(breed: Breed = .clover, levels: [UpgradeKind: Int] = [:], seed: UInt64 = 42) -> RunSession {
        let session = RunSession(setup: RunSetup(mode: .endless, seed: seed), loadout: Loadout(levels: levels, breed: breed))
        session.debugClearRoad()
        return session
    }

    static func advance(_ session: RunSession, seconds: Double, autopilot: Bool = false) {
        var t = 0.0
        while t < seconds && !session.isOver {
            if autopilot { session.autopilot(1.0 / 60) }
            session.step(1.0 / 60)
            t += 1.0 / 60
        }
    }

    static func summary(
        mode: RunMode = .endless, result: RunResult = .crashed, score: Int = 1000, meters: Int = 500, corn: Int = 40,
        chicks: Int = 0, finalChicks: Int = 0, smashes: Int = 0, closeCalls: Int = 0, bumps: Int = 1
    ) -> RunSummary {
        RunSummary(mode: mode, result: result, breed: .clover, score: score, meters: meters, corn: corn,
                   chicksRescued: chicks, finalChicks: finalChicks, maxConvoy: finalChicks, smashes: smashes,
                   closeCalls: closeCalls, flaps: 0, splats: 0, lateMerges: 0, expressTolls: 0, bumps: bumps,
                   duration: 30, furthestWorld: .farm)
    }
}
