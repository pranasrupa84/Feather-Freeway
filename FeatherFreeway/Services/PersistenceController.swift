import Foundation
import SwiftData

/// Builds the SwiftData container used by the app and by tests.
enum PersistenceController {
    static let schema = Schema([PlayerProfile.self, RunRecord.self])

    /// Pass `inMemory: true` for tests and UI-test runs so nothing touches real progress.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration("FeatherFreeway", schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
