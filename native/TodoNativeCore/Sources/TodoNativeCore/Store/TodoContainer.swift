import Foundation
import SwiftData

public enum TodoContainer {
    /// The single source of truth for the SwiftData schema. Both the app and tests build
    /// their `ModelContainer` through this so they never drift.
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([TodoItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
