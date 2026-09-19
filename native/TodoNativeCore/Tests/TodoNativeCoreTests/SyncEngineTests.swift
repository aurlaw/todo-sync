import Foundation
import SwiftData
import Testing
@testable import TodoNativeCore

@MainActor
private struct Harness {
    let container: ModelContainer
    let main: ModelContext
    let client = FakeSyncClient()
    let cursors = makeCursorStore()
    let appliedCount = Counter()
    let engine: SyncEngine

    init(pushChunkSize: Int = 20, pullPageSize: Int = 500) throws {
        container = try TodoContainer.make(inMemory: true)
        main = ModelContext(container)
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

    /// A local item stamped at `updated`; `dirty` false simulates a row that already synced.
    @discardableResult
    func seed(_ title: String = "local", updated: Date, dirty: Bool = true) throws -> TodoItem {
        let store = TodoStore(context: main, clock: FixedTestClock(date: updated))
        let item = try store.create(title: title)
        if !dirty {
            item.dirty = false
            try main.save()
        }
        return item
    }

    func fetch(_ id: UUID) throws -> TodoItem? {
        try main.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == id })).first
    }

    /// Another context's saves reach an already-loaded instance only when something fetches it
    /// (which is what a live `@Query` does), so tests reload before asserting on loaded items.
    func reload() throws {
        _ = try main.fetch(FetchDescriptor<TodoItem>())
    }

    func count() throws -> Int {
        try main.fetchCount(FetchDescriptor<TodoItem>())
    }
}

@Suite("SyncEngine push")
struct SyncEnginePushTests {
    @Test("clears dirty and records serverSeq for applied rows only; stale and invalid stay dirty")
    @MainActor
    func clearsAppliedOnly() async throws {
        let h = try Harness()
        let applied = try h.seed("applied", updated: at(1))
        let stale = try h.seed("stale", updated: at(2))
        let invalid = try h.seed("invalid", updated: at(3))
        await h.client.setRejectStale([stale.id.uuidString.lowercased()])
        await h.client.setRejectInvalid([invalid.id.uuidString.lowercased()])

        let outcome = try await h.engine.sync()
        try h.reload()

        #expect(outcome.pushed == 1)
        #expect(outcome.rejectedStale == 1)
        #expect(outcome.rejectedInvalid == 1)
        #expect(applied.dirty == false)
        #expect(applied.serverSeq != nil)
        #expect(stale.dirty == true)
        #expect(invalid.dirty == true)
    }

    @Test("an item edited while its push is in flight stays dirty and goes out next cycle")
    @MainActor
    func editDuringPushStaysDirty() async throws {
        let h = try Harness()
        let item = try h.seed("before", updated: at(1))
        let id = item.id

        nonisolated(unsafe) let main = h.main
        await h.client.setOnPush { _ in
            await MainActor.run {
                let editor = TodoStore(context: main, clock: FixedTestClock(date: at(50)))
                let fetched = try? main.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == id })).first
                if let fetched {
                    try? editor.update(fetched, title: "after", notes: nil, dueAt: nil, recurrence: nil)
                }
            }
        }

        let first = try await h.engine.sync()
        try h.reload()
        #expect(first.pushed == 0)
        #expect(item.title == "after")
        #expect(item.dirty == true)

        await h.client.setOnPush(nil)
        let second = try await h.engine.sync()
        try h.reload()
        #expect(second.pushed == 1)
        #expect(item.dirty == false)
        let chunks = await h.client.pushedChunks
        #expect(chunks.last?.first?.updatedAt == Iso8601.format(at(50)))
    }

    @Test("45 dirty rows push as chunks of 20, 20 and 5")
    @MainActor
    func chunking() async throws {
        let h = try Harness()
        for index in 0..<45 { try h.seed("item \(index)", updated: at(TimeInterval(index))) }

        let outcome = try await h.engine.sync()

        #expect(outcome.pushed == 45)
        let sizes = await h.client.pushedChunks.map(\.count)
        #expect(sizes == [20, 20, 5])
    }

    @Test("nothing dirty means no push request")
    @MainActor
    func noDirtyNoPush() async throws {
        let h = try Harness()
        try h.seed(updated: at(1), dirty: false)

        _ = try await h.engine.sync()

        #expect(await h.client.pushedChunks.isEmpty)
    }
}

@Suite("SyncEngine pull")
struct SyncEnginePullTests {
    @Test("inserts rows it has never seen, including soft-deleted ones, as clean")
    @MainActor
    func inserts() async throws {
        let h = try Harness()
        let live = wire(title: "live", updatedAt: at(5), serverSeq: 1)
        let deleted = wire(title: "gone", updatedAt: at(6), isDeleted: true, serverSeq: 2)
        await h.client.setPages([ChangesResponse(items: [live, deleted], cursor: 2)])

        let outcome = try await h.engine.sync()

        #expect(outcome.applied == 2)
        #expect(try h.count() == 2)
        let liveItem = try #require(try h.fetch(UUID(uuidString: live.id)!))
        #expect(liveItem.dirty == false)
        #expect(liveItem.serverSeq == 1)
        let deletedItem = try #require(try h.fetch(UUID(uuidString: deleted.id)!))
        #expect(deletedItem.isSoftDeleted == true)
    }

    @Test("a newer incoming row overwrites a clean local row")
    @MainActor
    func newerOverwrites() async throws {
        let h = try Harness()
        let item = try h.seed("old", updated: at(1), dirty: false)
        await h.client.setPages([ChangesResponse(items: [wire(id: item.id, title: "new", updatedAt: at(9), isDone: true, serverSeq: 7)], cursor: 7)])

        _ = try await h.engine.sync()
        try h.reload()

        #expect(item.title == "new")
        #expect(item.isDone == true)
        #expect(item.serverSeq == 7)
        #expect(item.dirty == false)
    }

    @Test("an older incoming row is ignored")
    @MainActor
    func olderIgnored() async throws {
        let h = try Harness()
        let item = try h.seed("current", updated: at(9), dirty: false)
        await h.client.setPages([ChangesResponse(items: [wire(id: item.id, title: "stale", updatedAt: at(1))], cursor: 3)])

        let outcome = try await h.engine.sync()
        try h.reload()

        #expect(outcome.applied == 0)
        #expect(item.title == "current")
    }

    @Test("a dirty local row that is newer than the incoming row is kept and stays dirty")
    @MainActor
    func dirtyNewerKept() async throws {
        let h = try Harness()
        let item = try h.seed("mine", updated: at(50))
        await h.client.setRejectStale([item.id.uuidString.lowercased()])
        await h.client.setPages([ChangesResponse(items: [wire(id: item.id, title: "theirs", updatedAt: at(10))], cursor: 3)])

        _ = try await h.engine.sync()
        try h.reload()

        #expect(item.title == "mine")
        #expect(item.dirty == true)
    }

    @Test("a stale-rejected dirty row whose identical write is already on the server resolves instead of sticking")
    @MainActor
    func equalTimestampResolves() async throws {
        let h = try Harness()
        let item = try h.seed("same", updated: at(20))
        await h.client.setRejectStale([item.id.uuidString.lowercased()])
        await h.client.setPages([ChangesResponse(items: [wire(id: item.id, title: "same", updatedAt: at(20), serverSeq: 9)], cursor: 9)])

        _ = try await h.engine.sync()
        try h.reload()

        #expect(item.dirty == false)
        #expect(item.serverSeq == 9)
    }

    @Test("pagination drains every page and persists the final cursor")
    @MainActor
    func pagination() async throws {
        let h = try Harness(pullPageSize: 2)
        let rows = (1...5).map { wire(title: "row \($0)", updatedAt: at(TimeInterval($0)), serverSeq: Int64($0)) }
        await h.client.setPages([
            ChangesResponse(items: Array(rows[0..<2]), cursor: 2),
            ChangesResponse(items: Array(rows[2..<4]), cursor: 4),
            ChangesResponse(items: Array(rows[4..<5]), cursor: 5),
        ])

        let outcome = try await h.engine.sync()

        #expect(outcome.pulled == 5)
        #expect(try h.count() == 5)
        #expect(await h.client.changeRequests == [0, 2, 4])
        #expect(h.cursors.cursor(for: h.baseURL) == 5)
    }

    @Test("the next sync resumes from the stored cursor")
    @MainActor
    func resumesFromCursor() async throws {
        let h = try Harness()
        h.cursors.set(77, for: h.baseURL)

        _ = try await h.engine.sync()

        #expect(await h.client.changeRequests == [77])
    }

    @Test("a different base URL starts again from zero")
    @MainActor
    func differentURLResets() async throws {
        let h = try Harness()
        h.cursors.set(77, for: h.baseURL)
        await h.client.setBase(URL(string: "https://other.test")!)

        _ = try await h.engine.sync()

        #expect(await h.client.changeRequests == [0])
    }

    @Test("a bad row aborts the pull, rolls the page back, and leaves the cursor alone")
    @MainActor
    func badRowAborts() async throws {
        let h = try Harness()
        h.cursors.set(3, for: h.baseURL)
        var bad = wire(title: "bad", updatedAt: at(2))
        bad.createdAt = "yesterday"
        let good = wire(title: "good", updatedAt: at(1))
        await h.client.setPages([ChangesResponse(items: [good, bad], cursor: 10)])

        do {
            _ = try await h.engine.sync()
            Issue.record("expected an invalidRow error")
        } catch let error as SyncError {
            guard case .invalidRow = error else { Issue.record("wrong error: \(error)"); return }
        }

        #expect(try h.count() == 0)
        #expect(h.cursors.cursor(for: h.baseURL) == 3)
    }

    @Test("onChangesApplied fires only when rows were applied")
    @MainActor
    func appliedCallback() async throws {
        let h = try Harness()

        _ = try await h.engine.sync()
        #expect(await h.appliedCount.value == 0)

        await h.client.setPages([ChangesResponse(items: [wire(updatedAt: at(1))], cursor: 1)])
        _ = try await h.engine.sync()
        #expect(await h.appliedCount.value == 1)
    }
}

@Suite("SyncEngine lifecycle")
struct SyncEngineLifecycleTests {
    @Test("a missing configuration throws notConfigured before anything is sent")
    @MainActor
    func notConfigured() async throws {
        let h = try Harness()
        try h.seed(updated: at(1))
        await h.client.setBaseError(.notConfigured)

        await #expect(throws: SyncError.notConfigured) { try await h.engine.sync() }
        #expect(await h.client.pushedChunks.isEmpty)
        #expect(await h.client.changeRequests.isEmpty)
    }

    @Test("an overlapping sync is coalesced and leaves exactly one trailing rerun")
    @MainActor
    func coalescing() async throws {
        let h = try Harness()
        try h.seed(updated: at(1))
        await h.client.setOnPush { _ in try? await Task.sleep(for: .milliseconds(300)) }

        let engine = h.engine
        let first = Task { try await engine.sync() }
        try await Task.sleep(for: .milliseconds(100))
        let second = try await engine.sync()
        let firstOutcome = try await first.value

        #expect(second.coalesced == true)
        #expect(firstOutcome.coalesced == false)
        // One pull for the first cycle and one for the queued rerun.
        #expect(await h.client.changeRequests.count == 2)
    }

    @Test("resetCursor makes the next sync pull from zero")
    @MainActor
    func resetCursor() async throws {
        let h = try Harness()
        h.cursors.set(50, for: h.baseURL)

        await h.engine.resetCursor()
        _ = try await h.engine.sync()

        #expect(await h.client.changeRequests == [0])
    }
}
