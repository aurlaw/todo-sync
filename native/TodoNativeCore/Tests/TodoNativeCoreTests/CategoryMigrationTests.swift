import Foundation
import SwiftData
import Testing
@testable import TodoNativeCore

/// `TodoItem` exactly as it was before N9b (no `categoryId`), and no `TodoCategory` entity at all.
/// SwiftData keys entities by type name, so this nested `TodoItem` is the same entity as the real one.
private enum PreN9b {
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
        var sortOrder: Double = 0

        init(id: UUID = UUID(), title: String, createdAt: Date, updatedAt: Date, sortOrder: Double) {
            self.id = id
            self.title = title
            self.isDone = false
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.isSoftDeleted = false
            self.dirty = false
            self.sortOrder = sortOrder
        }
    }
}

@Suite("categories schema migration (file-backed store)")
struct CategoryMigrationTests {
    @Test("a store written before N9b opens under the new schema: items are Unassigned and there are no categories")
    @MainActor
    func lightweightMigration() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "todonative-category-migration-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(filePath: url.path(percentEncoded: false) + suffix))
            }
        }

        let id = UUID()
        do {
            let legacySchema = Schema([PreN9b.TodoItem.self])
            let legacy = try ModelContainer(for: legacySchema, configurations: [ModelConfiguration(schema: legacySchema, url: url)])
            let context = ModelContext(legacy)
            context.insert(PreN9b.TodoItem(id: id, title: "before N9b", createdAt: at(1), updatedAt: at(1), sortOrder: 3))
            try context.save()
        }

        // The real schema, through the same entry point every process uses.
        let context = ModelContext(try TodoContainer.make(storeURL: url))
        let items = try context.fetch(FetchDescriptor<TodoItem>())

        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.id == id)
        #expect(item.title == "before N9b")
        #expect(item.sortOrder == 3)
        #expect(item.categoryId == nil)
        #expect(try context.fetchCount(FetchDescriptor<TodoCategory>()) == 0)

        // And the new entity is usable in the migrated store.
        let store = TodoStore(context: context)
        let work = try store.createCategory(name: "Work")
        try store.setCategory(item, to: work.id)
        #expect(try ModelContext(context.container).fetch(FetchDescriptor<TodoItem>()).first?.categoryId == work.id)
    }
}
