import Foundation
import SwiftData
import Testing
@testable import TodoNativeCore

/// `TodoItem` exactly as it was before N8 (no `sortOrder`). SwiftData keys entities by type name,
/// so this nested `TodoItem` describes the same entity as the real one in a store on disk.
private enum PreN8 {
    @Model
    final class TodoItem {
        @Attribute(.unique) var id: UUID
        var title: String
        var notes: String?
        var isDone: Bool
        var dueAt: Date?
        var recurrence: RecurrenceRule?
        var createdAt: Date
        var updatedAt: Date
        var isSoftDeleted: Bool
        var dirty: Bool
        var serverSeq: Int64?

        init(id: UUID = UUID(), title: String, createdAt: Date, updatedAt: Date) {
            self.id = id
            self.title = title
            self.isDone = false
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.isSoftDeleted = false
            self.dirty = false
        }
    }
}

@Suite("sortOrder schema migration (file-backed store)")
struct SortOrderMigrationTests {
    @Test("a store written before N8 opens under the new schema; existing rows read sortOrder 0")
    @MainActor
    func lightweightMigration() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "todonative-migration-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(at: URL(filePath: url.path() + suffix)) }
        }

        let id = UUID()
        do {
            let legacySchema = Schema([PreN8.TodoItem.self])
            let legacy = try ModelContainer(for: legacySchema, configurations: [ModelConfiguration(schema: legacySchema, url: url)])
            let context = ModelContext(legacy)
            context.insert(PreN8.TodoItem(id: id, title: "before N8", createdAt: at(1), updatedAt: at(1)))
            try context.save()
        }

        let schema = Schema([TodoItem.self])
        let migrated = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let items = try ModelContext(migrated).fetch(FetchDescriptor<TodoItem>())

        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.id == id)
        #expect(item.title == "before N8")
        #expect(item.sortOrder == 0)
    }
}
