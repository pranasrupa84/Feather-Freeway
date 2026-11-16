import Testing
import UIKit
@testable import FeatherFreeway

@MainActor
@Suite("Generated art and sounds ship in the bundle")
struct AssetTests {
    @Test func everyCarBreedAndWorldTextureExists() {
        var names = CarModel.allCases.map(\.rawValue)
        for breed in Breed.allCases {
            names.append(Art.portrait(breed))
            names += (0..<3).map { Art.hen(breed, frame: $0) }
        }
        for world in World.allCases {
            names += [Art.world(world), Art.Scene.lane(world), Art.Scene.shoulder(world, right: false), Art.Scene.shoulder(world, right: true)]
        }
        names += UpgradeKind.allCases.map { Art.upgrade($0) }
        names += GuideView.pages.map(\.art)
        names += [Art.logo, Art.homeBackdrop, Art.rig, Art.Scene.rigLit, Art.Scene.cone, Art.Scene.boom, Art.Scene.barricade,
                  Art.Scene.tollOpen, Art.Scene.tollClosed, Art.Scene.tollExpress, Art.Scene.tollExpressOpen,
                  Art.Scene.signalRed, Art.Scene.signalAmber, Art.Scene.signalGreen, Art.Scene.chick0, Art.Scene.chick1,
                  Art.corn, Art.fuelCan, Art.magnet, Art.double, Art.egg, Art.Panel.ticket, Art.Panel.sign, Art.Tile.map]
        let missing = names.filter { UIImage(named: $0) == nil }
        #expect(missing.isEmpty, "missing: \(missing)")
    }

    @Test func everySoundFileExists() {
        let missing = SoundEffect.allCases.map(\.rawValue).filter { Bundle.main.url(forResource: $0, withExtension: "wav") == nil }
        #expect(missing.isEmpty, "missing: \(missing)")
        #expect(Bundle.main.url(forResource: MusicTrack.run.rawValue, withExtension: "wav") != nil)
        #expect(Bundle.main.url(forResource: MusicTrack.menu.rawValue, withExtension: "wav") != nil)
    }
}
