import Foundation
import SwiftData
import Testing
@testable import TodoNativeCore

/// One device: its own store, cursors and engine, talking to whichever client it is given.
@MainActor
private struct Device<Client: SyncClient> {
    let container: ModelContainer
    let main: ModelContext
    let client: Client
    let cursors = makeCursorStore()
    let appliedCount = Counter()
    let clock = AdjustableClock()
    let engine: SyncEngine

    init(client: Client, pushChunkSize: Int = 20, pullPageSize: Int = 500) throws {
        container = try TodoContainer.make(inMemory: true)
        main = ModelContext(container)
        self.client = client
        let counter = appliedCount
        engine = SyncEngine(
            modelContainer: container,
            client: client,
            cursors: cursors,
            pushChunkSize: pushChunkSize,
            pullPageSize: pullPageSize,
            onChangesApplied: { await counter.increment() }
        )
    }

    var baseURL: URL { URL(string: "https://worker.test")! }

    func store(at seconds: TimeInterval) -> TodoStore {
        clock.date = at(seconds)
        return TodoStore(context: main, clock: clock)
    }

    /// Fresh copies of everything, since another context's saves reach loaded objects only on a fetch.
    func categories() throws -> [TodoCategory] { try main.fetch(FetchDescriptor<TodoCategory>()) }
    func items() throws -> [TodoItem] { try main.fetch(FetchDescriptor<TodoItem>()) }
    func tree() throws -> CategoryTree { CategoryTree(try categories()) }

    func category(_ id: UUID) throws -> TodoCategory? { try categories().first { $0.id == id } }

    /// A clean local category, as if it had already synced.
    @discardableResult
    func seedClean(_ name: String, updated: Date) throws -> TodoCategory {
        let category = TodoCategory(name: name, createdAt: updated, updatedAt: updated, dirty: false)
        main.insert(category)
        try main.save()
        return category
    }
}

@Suite("SyncEngine categories")
struct CategorySyncEngineTests {
    @Test("categories are pushed before todos and pulled before todos")
    @MainActor
    func order() async throws {
        let device = try Device(client: FakeSyncClient())
        let work = try device.store(at: 1).createCategory(name: "Work")
        try device.store(at: 2).create(title: "in work", categoryId: work.id)

        let outcome = try await device.engine.sync()

        #expect(await device.client.calls == ["pushCategories", "push", "categoryChanges", "changes"])
        #expect(outcome.pushed == 2)
        let pushedCategory = try #require(await device.client.pushedCategoryChunks.first?.first)
        #expect(pushedCategory.id == work.id.uuidString.lowercased())
        let pushedTodo = try #require(await device.client.pushedChunks.first?.first)
        #expect(pushedTodo.categoryId == work.id.uuidString.lowercased())
    }

    @Test("a push clears dirty and records serverSeq; stale and invalid categories stay dirty")
    @MainActor
    func pushClearsApplied() async throws {
        let device = try Device(client: FakeSyncClient())
        let applied = try device.store(at: 1).createCategory(name: "applied")
        let stale = try device.store(at: 2).createCategory(name: "stale")
        let invalid = try device.store(at: 3).createCategory(name: "invalid")
        await device.client.setRejectStale([stale.id.uuidString.lowercased()])
        await device.client.setRejectInvalid([invalid.id.uuidString.lowercased()])

        let outcome = try await device.engine.sync()

        #expect(outcome.pushed == 1)
        #expect(outcome.rejectedStale == 1)
        #expect(outcome.rejectedInvalid == 1)
        #expect(try device.category(applied.id)?.dirty == false)
        #expect(try device.category(applied.id)?.serverSeq != nil)
        #expect(try device.category(stale.id)?.dirty == true)
        #expect(try device.category(invalid.id)?.dirty == true)
    }

    @Test("nothing is pushed to /categories/push when no category is dirty")
    @MainActor
    func noEmptyPush() async throws {
        let device = try Device(client: FakeSyncClient())
        try device.seedClean("clean", updated: at(1))

        _ = try await device.engine.sync()
        #expect(await device.client.calls == ["categoryChanges", "changes"])
    }

    @Test("dirty categories go out in chunks")
    @MainActor
    func chunks() async throws {
        let device = try Device(client: FakeSyncClient(), pushChunkSize: 2)
        for index in 0..<5 { try device.store(at: Double(index)).createCategory(name: "c\(index)") }

        let outcome = try await device.engine.sync()
        #expect(await device.client.pushedCategoryChunks.map(\.count) == [2, 2, 1])
        #expect(outcome.pushed == 5)
        #expect(try device.categories().allSatisfy { !$0.dirty })
    }

    @Test("the category cursor is separate from the todo cursor, and each request resumes from its own")
    @MainActor
    func separateCursors() async throws {
        let device = try Device(client: FakeSyncClient())
        await device.client.setCategoryPages([
            CategoryChangesResponse(items: [categoryWire(name: "Work", updatedAt: at(1), serverSeq: 7)], cursor: 7),
        ])
        await device.client.setPages([ChangesResponse(items: [wire(updatedAt: at(1), serverSeq: 3)], cursor: 3)])

        _ = try await device.engine.sync()
        #expect(device.cursors.categoryCursor(for: device.baseURL) == 7)
        #expect(device.cursors.cursor(for: device.baseURL) == 3)

        _ = try await device.engine.sync()
        #expect(await device.client.categoryChangeRequests == [0, 7])
        #expect(await device.client.changeRequests == [0, 3])

        // A different Worker starts both from zero; a reset clears both.
        #expect(device.cursors.categoryCursor(for: URL(string: "https://other.test")!) == 0)
        await device.engine.resetCursor()
        #expect(device.cursors.categoryCursor(for: device.baseURL) == 0)
        #expect(device.cursors.cursor(for: device.baseURL) == 0)
    }

    @Test("category pages are pulled until a short page")
    @MainActor
    func paging() async throws {
        let device = try Device(client: FakeSyncClient(), pullPageSize: 2)
        let rows = (1...5).map { categoryWire(name: "c\($0)", updatedAt: at(Double($0)), serverSeq: Int64($0)) }
        await device.client.setCategoryPages([
            CategoryChangesResponse(items: Array(rows[0..<2]), cursor: 2),
            CategoryChangesResponse(items: Array(rows[2..<4]), cursor: 4),
            CategoryChangesResponse(items: Array(rows[4..<5]), cursor: 5),
        ])

        let outcome = try await device.engine.sync()
        #expect(await device.client.categoryChangeRequests == [0, 2, 4])
        #expect(outcome.pulled == 5)
        #expect(try device.categories().count == 5)
        #expect(device.cursors.categoryCursor(for: device.baseURL) == 5)
    }

    @Test("last write wins: a newer row applies, an older one is ignored, and a newer dirty local row is kept")
    @MainActor
    func lastWriteWins() async throws {
        let device = try Device(client: FakeSyncClient())
        let newer = try device.seedClean("local", updated: at(5))
        let older = try device.seedClean("local", updated: at(5))
        let edited = try device.seedClean("local edit", updated: at(5))
        edited.name = "local edit"
        edited.updatedAt = at(20)
        edited.dirty = true
        try device.main.save()
        // The push is rejected as stale, as the Worker would when it holds a different row.
        await device.client.setRejectStale([edited.id.uuidString.lowercased()])
        let parent = UUID()

        await device.client.setCategoryPages([CategoryChangesResponse(items: [
            categoryWire(id: newer.id, name: "theirs", parentId: parent, color: "#112233", sortOrder: 4,
                         updatedAt: at(9), serverSeq: 1),
            categoryWire(id: older.id, name: "stale", updatedAt: at(1), serverSeq: 2),
            categoryWire(id: edited.id, name: "theirs", updatedAt: at(10), serverSeq: 3),
            categoryWire(name: "brand new", updatedAt: at(2), isDeleted: true, serverSeq: 4),
        ], cursor: 4)])

        let outcome = try await device.engine.sync()

        let applied = try #require(try device.category(newer.id))
        #expect(applied.name == "theirs")
        #expect(applied.parentId == parent)
        #expect(applied.color == "#112233")
        #expect(applied.sortOrder == 4)
        #expect(applied.serverSeq == 1)
        #expect(applied.dirty == false)

        #expect(try device.category(older.id)?.name == "local")
        #expect(try device.category(edited.id)?.name == "local edit")
        #expect(try device.category(edited.id)?.dirty == true)

        let inserted = try #require(try device.categories().first { $0.name == "brand new" })
        #expect(inserted.isSoftDeleted)
        #expect(inserted.dirty == false)

        #expect(outcome.applied == 2)
        #expect(await device.appliedCount.value == 1)
    }

    @Test("onChangesApplied fires when only a category changed")
    @MainActor
    func onChangesAppliedForCategories() async throws {
        let device = try Device(client: FakeSyncClient())
        _ = try await device.engine.sync()
        #expect(await device.appliedCount.value == 0)

        await device.client.setCategoryPages([
            CategoryChangesResponse(items: [categoryWire(name: "Work", updatedAt: at(1))], cursor: 1),
        ])
        _ = try await device.engine.sync()
        #expect(await device.appliedCount.value == 1)
    }

    @Test("a malformed category row fails the page, leaves the cursor alone, and stores nothing from it")
    @MainActor
    func malformedRow() async throws {
        let device = try Device(client: FakeSyncClient())
        var bad = categoryWire(name: "bad", updatedAt: at(2), serverSeq: 2)
        bad.updatedAt = "yesterday"
        await device.client.setCategoryPages([
            CategoryChangesResponse(items: [categoryWire(name: "good", updatedAt: at(1)), bad], cursor: 2),
        ])

        await #expect(throws: SyncError.self) { try await device.engine.sync() }
        #expect(try device.categories().isEmpty)
        #expect(device.cursors.categoryCursor(for: device.baseURL) == 0)
    }

    @Test("an edit made while its push is in flight keeps its dirty flag")
    @MainActor
    func compareAndClear() async throws {
        let device = try Device(client: FakeSyncClient())
        let work = try device.store(at: 1).createCategory(name: "Work")
        let wire = CategoryWireDto(work)
        try device.store(at: 2).renameCategory(work, to: "Work 2")

        // What the engine would do with the response to the earlier snapshot.
        let response = try await device.client.pushCategories([wire])
        #expect(response.applied.count == 1)
        _ = try await device.engine.sync()

        // The rename was pushed by that sync with its own timestamp, so it is clean now.
        #expect(try device.category(work.id)?.dirty == false)
        #expect(await device.client.pushedCategoryChunks.last?.first?.name == "Work 2")
    }
}

@Suite("Two devices, one Worker")
struct TwoDeviceCategoryTests {
    @Test("a category tree and the items filed in it reach the other device")
    @MainActor
    func treeSyncs() async throws {
        let worker = InMemoryWorker()
        let a = try Device(client: worker)
        let b = try Device(client: worker)

        let work = try a.store(at: 1).createCategory(name: "Work", color: "#0a84ff")
        let clients = try a.store(at: 2).createCategory(name: "Clients", parentId: work.id)
        try a.store(at: 3).createCategory(name: "Home")
        try a.store(at: 4).create(title: "invoice", categoryId: clients.id)
        _ = try await a.engine.sync()
        _ = try await b.engine.sync()

        let tree = try b.tree()
        #expect(tree.topLevel.map(\.name) == ["Work", "Home"])
        #expect(tree.children(of: work.id).map(\.name) == ["Clients"])
        #expect(tree.resolve(work.id)?.color == "#0a84ff")
        let item = try #require(try b.items().first)
        #expect(item.categoryId == clients.id)
        #expect(tree.contains(item, in: .category(work.id)))
        #expect(try b.categories().allSatisfy { !$0.dirty })
    }

    @Test("moving an item to Unassigned on one device reaches the other")
    @MainActor
    func moveToUnassigned() async throws {
        let worker = InMemoryWorker()
        let a = try Device(client: worker)
        let b = try Device(client: worker)
        let work = try a.store(at: 1).createCategory(name: "Work")
        let item = try a.store(at: 2).create(title: "x", categoryId: work.id)
        _ = try await a.engine.sync()
        _ = try await b.engine.sync()
        #expect(try b.items().first?.categoryId == work.id)

        try a.store(at: 5).setCategory(item, to: nil)
        _ = try await a.engine.sync()
        _ = try await b.engine.sync()

        #expect(try b.items().first?.categoryId == nil)
    }

    @Test("A deletes a parent while B adds an item to one of its subcategories: both end with the sub at the top level holding B's item")
    @MainActor
    func deleteParentWhileOtherDeviceFilesIntoSub() async throws {
        let worker = InMemoryWorker()
        let a = try Device(client: worker)
        let b = try Device(client: worker)

        let work = try a.store(at: 1).createCategory(name: "Work")
        let clients = try a.store(at: 2).createCategory(name: "Clients", parentId: work.id)
        try a.store(at: 3).create(title: "work's own", categoryId: work.id)
        _ = try await a.engine.sync()
        _ = try await b.engine.sync()

        // Offline on both sides.
        try a.store(at: 10).deleteCategory(try #require(try a.category(work.id)))
        try b.store(at: 11).create(title: "from B", categoryId: clients.id)

        _ = try await a.engine.sync()
        _ = try await b.engine.sync()
        _ = try await a.engine.sync()

        for device in [a, b] {
            let tree = try device.tree()
            #expect(tree.topLevel.map(\.name) == ["Clients"])
            #expect(tree.resolve(work.id) == nil)
            #expect(try device.category(clients.id)?.parentId == nil)

            let items = try device.items()
            let fromB = try #require(items.first { $0.title == "from B" })
            #expect(fromB.categoryId == clients.id)
            #expect(tree.contains(fromB, in: .category(clients.id)))

            let own = try #require(items.first { $0.title == "work's own" })
            #expect(own.categoryId == nil)
            #expect(tree.contains(own, in: .unassigned))

            #expect(try device.categories().allSatisfy { !$0.dirty })
            #expect(items.allSatisfy { !$0.dirty })
        }
    }

    @Test("B edits a subcategory after A deleted its parent: the sub keeps its stale parentId and still shows at the top level on both")
    @MainActor
    func staleParentAfterMerge() async throws {
        let worker = InMemoryWorker()
        let a = try Device(client: worker)
        let b = try Device(client: worker)
        let work = try a.store(at: 1).createCategory(name: "Work")
        let clients = try a.store(at: 2).createCategory(name: "Clients", parentId: work.id)
        _ = try await a.engine.sync()
        _ = try await b.engine.sync()

        try a.store(at: 10).deleteCategory(try #require(try a.category(work.id)))
        // B's later write to the same row wins the whole row, parentId included.
        try b.store(at: 11).setCategoryColor(try #require(try b.category(clients.id)), "#ff0000")

        _ = try await a.engine.sync()
        _ = try await b.engine.sync()
        _ = try await a.engine.sync()

        for device in [a, b] {
            let merged = try #require(try device.category(clients.id))
            #expect(merged.parentId == work.id)
            #expect(merged.color == "#ff0000")
            #expect(try device.tree().topLevel.map(\.name) == ["Clients"])
        }
    }
}
