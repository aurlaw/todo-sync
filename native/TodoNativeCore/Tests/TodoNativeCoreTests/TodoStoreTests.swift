import Foundation
import SwiftData
import Testing
@testable import TodoNativeCore

private struct FixedClock: Clock {
    let date: Date
    func now() -> Date { date }
}

@MainActor
private func makeStore(now: Date) throws -> (TodoStore, ModelContext) {
    let container = try TodoContainer.make(inMemory: true)
    let context = ModelContext(container)
    let store = TodoStore(context: context, clock: FixedClock(date: now))
    return (store, context)
}

@Suite("TodoStore mutation rules")
struct TodoStoreTests {
    @Test("create sets createdAt/updatedAt from the clock and marks dirty")
    @MainActor
    func createSetsTimestampsAndDirty() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let (store, _) = try makeStore(now: now)

        let item = try store.create(title: "Buy milk")

        #expect(item.title == "Buy milk")
        #expect(item.createdAt == now)
        #expect(item.updatedAt == now)
        #expect(item.dirty == true)
        #expect(item.isSoftDeleted == false)
        #expect(item.isDone == false)
    }

    @Test("update advances updatedAt and re-marks dirty")
    @MainActor
    func updateTouchesTimestampAndDirty() throws {
        let created = Date(timeIntervalSince1970: 1_000)
        let (store, context) = try makeStore(now: created)
        let item = try store.create(title: "Buy milk")

        item.dirty = false
        try context.save()

        let later = Date(timeIntervalSince1970: 2_000)
        let touchedStore = TodoStore(context: context, clock: FixedClock(date: later))
        try touchedStore.update(item, title: "Buy oat milk", notes: "2%", dueAt: nil, recurrence: nil)

        #expect(item.title == "Buy oat milk")
        #expect(item.notes == "2%")
        #expect(item.updatedAt == later)
        #expect(item.dirty == true)
    }

    @Test("complete toggles isDone and touches the item")
    @MainActor
    func completeTogglesIsDone() throws {
        let (store, _) = try makeStore(now: Date(timeIntervalSince1970: 1_000))
        let item = try store.create(title: "Buy milk")

        try store.complete(item)
        #expect(item.isDone == true)

        try store.complete(item, isDone: false)
        #expect(item.isDone == false)
    }

    @Test("softDelete sets isSoftDeleted, never removes the row")
    @MainActor
    func softDeleteSetsFlag() throws {
        let (store, context) = try makeStore(now: Date(timeIntervalSince1970: 1_000))
        let item = try store.create(title: "Buy milk")
        let id = item.id

        try store.softDelete(item)

        #expect(item.isSoftDeleted == true)
        let descriptor = FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == id })
        let stillPresent = try context.fetch(descriptor)
        #expect(stillPresent.count == 1)
    }
}
