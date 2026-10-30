import Foundation

/// The chickens living in the Coop. Each one has a passive perk (Breed Traits).
enum Breed: String, CaseIterable, Codable, Sendable, Identifiable {
    case clover, pip, rusty, mabel, nova, duchess, zippy

    static let starter: Breed = .clover

    var id: String { rawValue }

    var name: String {
        switch self {
        case .clover: "Clover"
        case .pip: "Pip"
        case .rusty: "Rusty"
        case .mabel: "Mabel"
        case .nova: "Nova"
        case .duchess: "Duchess"
        case .zippy: "Zippy"
        }
    }

    var kind: String {
        switch self {
        case .clover: "White hen"
        case .pip: "Golden bantam"
        case .rusty: "Red rooster"
        case .mabel: "Lilac silkie"
        case .nova: "Speckled blue"
        case .duchess: "Brahma hen"
        case .zippy: "Racing leghorn"
        }
    }

    var price: Int {
        switch self {
        case .clover: 0
        case .pip: 600
        case .rusty: 1200
        case .mabel: 1800
        case .nova: 2500
        case .duchess: 3500
        case .zippy: 5000
        }
    }

    var traitName: String {
        switch self {
        case .clover: "Farm Fresh"
        case .pip: "Tiny Frame"
        case .rusty: "Rooster Roar"
        case .mabel: "Fluffy Cushion"
        case .nova: "Corn Nose"
        case .duchess: "Mother Hen"
        case .zippy: "Road Runner"
        }
    }

    var traitDetail: String {
        switch self {
        case .clover: "Starts every trip with an egg ready to throw."
        case .pip: "Slimmer hitbox, and close calls fill the feather meter 30% faster."
        case .rusty: "The Big Rig lasts 2 seconds longer and smashes pay double corn."
        case .mabel: "The first bump of every trip is forgiven, even with no chicks."
        case .nova: "A built-in mini magnet pulls nearby corn all the time."
        case .duchess: "Starts with 2 chicks and the convoy holds 2 more."
        case .zippy: "Runs 8% faster and earns 15% more score."
        }
    }

    /// Passive numbers the run session reads.
    var trait: BreedTrait {
        var t = BreedTrait()
        switch self {
        case .clover: t.startEggs = 1
        case .pip: t.hitboxHalfWidth = 20; t.closeCallBoost = 1.3
        case .rusty: t.rigBonusSeconds = 2; t.smashCornMultiplier = 2
        case .mabel: t.cushion = true
        case .nova: t.passiveMagnetRadius = 140
        case .duchess: t.startChicks = 2; t.convoyBonus = 2
        case .zippy: t.speedMultiplier = 1.08; t.scoreMultiplier = 1.15
        }
        return t
    }
}

/// Numeric effect of a breed's perk. Defaults mean "no perk".
struct BreedTrait: Equatable, Sendable {
    var startEggs = 0
    var startChicks = 0
    var convoyBonus = 0
    var hitboxHalfWidth: Double = 26
    var closeCallBoost: Double = 1
    var rigBonusSeconds: Double = 0
    var smashCornMultiplier = 1
    var cushion = false
    var passiveMagnetRadius: Double = 0
    var speedMultiplier: Double = 1
    var scoreMultiplier: Double = 1
}
