import Foundation
import SwiftData
import Testing
@testable import TodoNativeCore

/// A store whose clock the test can advance, so "which rows did this operation touch" is visible
/// as "which rows have the new `updatedAt`".
@MainActor
private final class Rig {
    let context: ModelContext
    private let clock = MutableClock(at(0))

    init() throws {
        context = ModelContext(try TodoContainer.make(inMemory: true))
    }

    var store: TodoStore { TodoStore(context: context, clock: clock) }

    func advance(to seconds: TimeInterval) { clock.date = at(seconds) }

    /// Inserts a row directly so a test controls `sortOrder` and `createdAt` exactly.
    @discardableResult
    func seed(_ title: String, order: Double, created: TimeInterval, dirty: Bool = false) throws -> TodoItem {
        let item = TodoItem(
            title: title, createdAt: at(created), updatedAt: at(created),
            dirty: dirty, sortOrder: order
        )
        context.insert(item)
        try context.save()
        return item
    }

    func order() throws -> [String] {
        try context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { !$0.isSoftDeleted }))
            .sorted(by: TodoItem.manualOrder).map(\.title)
    }
}

private final class MutableClock: Clock, @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
    func now() -> Date { date }
}

@Suite("Manual ordering: create")
struct CreateOrderingTests {
    @Test("the first item is 0 and each new item lands below the current last")
    @MainActor
    func newItemsGoToEnd() throws {
        let rig = try Rig()
        let a = try rig.store.create(title: "a")
        let b = try rig.store.create(title: "b")
        let c = try rig.store.create(title: "c")

        #expect(a.sortOrder == 0)
        #expect(b.sortOrder == 1)
        #expect(c.sortOrder == 2)
        #expect(try rig.order() == ["a", "b", "c"])
    }

    @Test("soft-deleted rows do not count toward the end")
    @MainActor
    func ignoresDeleted() throws {
        let rig = try Rig()
        let gone = try rig.seed("gone", order: 50, created: 1)
        gone.isSoftDeleted = true
        try rig.seed("live", order: 3, created: 2)

        #expect(try rig.store.create(title: "new").sortOrder == 4)
    }
}

@Suite("Manual ordering: move")
struct MoveOrderingTests {
    @MainActor
    private func rig3() throws -> (Rig, TodoItem, TodoItem, TodoItem) {
        let rig = try Rig()
        return (
            rig,
            try rig.seed("a", order: 0, created: 1),
            try rig.seed("b", order: 1, created: 2),
            try rig.seed("c", order: 2, created: 3)
        )
    }

    @Test("to the head: one below the old first")
    @MainActor
    func head() throws {
        let (rig, _, _, c) = try rig3()
        rig.advance(to: 10)
        try rig.store.move(fromOffsets: [2], toOffset: 0, in: try rig.context.fetch(FetchDescriptor<TodoItem>()).sorted(by: TodoItem.manualOrder))

        #expect(c.sortOrder == -1)
        #expect(try rig.order() == ["c", "a", "b"])
    }

    @Test("to the tail: one above the old last")
    @MainActor
    func tail() throws {
        let (rig, a, _, _) = try rig3()
        rig.advance(to: 10)
        try rig.store.move(fromOffsets: [0], toOffset: 3, in: try rig.context.fetch(FetchDescriptor<TodoItem>()).sorted(by: TodoItem.manualOrder))

        #expect(a.sortOrder == 3)
        #expect(try rig.order() == ["b", "c", "a"])
    }

    @Test("to the middle: the midpoint of the new neighbours")
    @MainActor
    func middle() throws {
        let (rig, _, _, c) = try rig3()
        rig.advance(to: 10)
        try rig.store.move(fromOffsets: [2], toOffset: 1, in: try rig.context.fetch(FetchDescriptor<TodoItem>()).sorted(by: TodoItem.manualOrder))

        #expect(c.sortOrder == 0.5)
        #expect(try rig.order() == ["a", "c", "b"])
    }

    @Test("a move dirties and re-stamps exactly the moved row")
    @MainActor
    func dirtiesOneRow() throws {
        let (rig, a, b, c) = try rig3()
        rig.advance(to: 10)
        try rig.store.move(fromOffsets: [2], toOffset: 0, in: [a, b, c])

        #expect(c.dirty == true)
        #expect(c.updatedAt == at(10))
        #expect(a.dirty == false && a.updatedAt == at(1))
        #expect(b.dirty == false && b.updatedAt == at(2))
    }

    @Test("dropping a row where it already is changes nothing")
    @MainActor
    func noOp() throws {
        let (rig, a, b, c) = try rig3()
        rig.advance(to: 10)
        try rig.store.move(fromOffsets: [1], toOffset: 1, in: [a, b, c])
        try rig.store.move(fromOffsets: [1], toOffset: 2, in: [a, b, c])

        #expect([a, b, c].allSatisfy { !$0.dirty })
        #expect([a, b, c].map(\.sortOrder) == [0, 1, 2])
    }

    @Test("neighbours come from the displayed list, so hidden rows between them are ignored")
    @MainActor
    func filteredNeighbours() throws {
        let rig = try Rig()
        let a = try rig.seed("a", order: 0, created: 1)
        try rig.seed("hidden", order: 3, created: 2)
        let c = try rig.seed("c", order: 10, created: 3)
        let d = try rig.seed("d", order: 20, created: 4)
        rig.advance(to: 10)

        // Displayed list is [a, c, d]; move d between a and c.
        try rig.store.move(fromOffsets: [2], toOffset: 1, in: [a, c, d])

        #expect(d.sortOrder == 5)
        #expect(try rig.order() == ["a", "hidden", "d", "c"])
    }

    @Test("moving several rows keeps them together and in their original relative order")
    @MainActor
    func multipleRows() throws {
        let (rig, a, b, c) = try rig3()
        rig.advance(to: 10)
        try rig.store.move(fromOffsets: [0, 1], toOffset: 3, in: [a, b, c])

        #expect(try rig.order() == ["c", "a", "b"])
    }

    @Test("moveToTop goes above every live row, including ones a filter would hide")
    @MainActor
    func moveToTop() throws {
        let (rig, _, _, c) = try rig3()
        rig.advance(to: 10)
        try rig.store.moveToTop(c)

        #expect(c.sortOrder == -1)
        #expect(try rig.order() == ["c", "a", "b"])
    }

    @Test("moveToTop on the row that is already first does nothing")
    @MainActor
    func moveToTopAlreadyFirst() throws {
        let (rig, a, _, _) = try rig3()
        rig.advance(to: 10)
        try rig.store.moveToTop(a)

        #expect(a.dirty == false)
    }
}

@Suite("Manual ordering: renormalize")
struct RenormalizeTests {
    @Test("a gap under the threshold respaces the whole list before the move, keeping every relative order")
    @MainActor
    func thresholdTriggersRespace() throws {
        let rig = try Rig()
        let a = try rig.seed("a", order: 0, created: 1)
        let b = try rig.seed("b", order: 1e-7, created: 2)
        let c = try rig.seed("c", order: 5, created: 3)
        rig.advance(to: 10)

        // c goes between a and b, which are 1e-7 apart.
        try rig.store.move(fromOffsets: [2], toOffset: 1, in: [a, b, c])

        #expect(try rig.order() == ["a", "c", "b"])
        let keys = [a, c, b].map(\.sortOrder)
        #expect(zip(keys, keys.dropFirst()).allSatisfy { $1 - $0 >= 1e-6 })
    }

    @Test("equal keys are treated as a zero gap")
    @MainActor
    func equalKeys() throws {
        let rig = try Rig()
        let a = try rig.seed("a", order: 2, created: 3)
        let b = try rig.seed("b", order: 2, created: 2)
        let c = try rig.seed("c", order: 9, created: 1)
        rig.advance(to: 10)

        try rig.store.move(fromOffsets: [2], toOffset: 1, in: [a, b, c])

        #expect(try rig.order() == ["a", "c", "b"])
        #expect(Set([a, b, c].map(\.sortOrder)).count == 3)
    }

    @Test("renormalize spaces the list at integer steps and dirties only rows that changed")
    @MainActor
    func integerSteps() throws {
        let rig = try Rig()
        let a = try rig.seed("a", order: 0, created: 1)
        let b = try rig.seed("b", order: 0.25, created: 2)
        let c = try rig.seed("c", order: 2, created: 3)
        rig.advance(to: 10)

        try rig.store.renormalize()

        #expect([a, b, c].map(\.sortOrder) == [0, 1, 2])
        #expect(a.dirty == false && c.dirty == false)
        #expect(b.dirty == true && b.updatedAt == at(10))
    }

    @Test("renormalize on an already even list is a no-op")
    @MainActor
    func idempotent() throws {
        let rig = try Rig()
        let items = try (0..<3).map { try rig.seed("i\($0)", order: Double($0), created: TimeInterval($0)) }
        rig.advance(to: 10)

        try rig.store.renormalize()

        #expect(items.allSatisfy { !$0.dirty })
    }
}

@Suite("Manual ordering: backfill")
struct BackfillTests {
    @Test("numbers never-ordered items newest first, and marks them dirty so they push")
    @MainActor
    func numbersNewestFirst() throws {
        let rig = try Rig()
        let oldest = try rig.seed("oldest", order: 0, created: 1)
        let middle = try rig.seed("middle", order: 0, created: 2)
        let newest = try rig.seed("newest", order: 0, created: 3)
        rig.advance(to: 10)

        let changed = try rig.store.backfillSortOrderIfNeeded()

        #expect(changed == true)
        #expect([newest, middle, oldest].map(\.sortOrder) == [0, 1, 2])
        #expect(try rig.order() == ["newest", "middle", "oldest"])
        // The newest keeps 0, so it is the one row that has nothing to push.
        #expect(newest.dirty == false)
        #expect(middle.dirty == true && middle.updatedAt == at(10))
        #expect(oldest.dirty == true && oldest.updatedAt == at(10))
    }

    @Test("running it again changes nothing")
    @MainActor
    func idempotent() throws {
        let rig = try Rig()
        try rig.seed("a", order: 0, created: 1)
        try rig.seed("b", order: 0, created: 2)
        #expect(try rig.store.backfillSortOrderIfNeeded() == true)

        rig.advance(to: 20)
        #expect(try rig.store.backfillSortOrderIfNeeded() == false)
    }

    @Test("skips when any live row already has a real order")
    @MainActor
    func skipsWhenOrdered() throws {
        let rig = try Rig()
        try rig.seed("a", order: 0, created: 1)
        try rig.seed("b", order: -1, created: 2)
        try rig.seed("c", order: 0, created: 3)

        #expect(try rig.store.backfillSortOrderIfNeeded() == false)
    }

    @Test("skips a list of fewer than two items")
    @MainActor
    func skipsTinyLists() throws {
        let rig = try Rig()
        #expect(try rig.store.backfillSortOrderIfNeeded() == false)
        try rig.seed("only", order: 0, created: 1)
        #expect(try rig.store.backfillSortOrderIfNeeded() == false)
    }

    @Test("soft-deleted rows are neither counted nor renumbered")
    @MainActor
    func ignoresDeleted() throws {
        let rig = try Rig()
        let gone = try rig.seed("gone", order: 0, created: 5)
        gone.isSoftDeleted = true
        try rig.seed("a", order: 0, created: 1)
        try rig.seed("b", order: 0, created: 2)
        rig.advance(to: 10)

        #expect(try rig.store.backfillSortOrderIfNeeded() == true)
        #expect(gone.sortOrder == 0 && gone.dirty == false)
    }
}
