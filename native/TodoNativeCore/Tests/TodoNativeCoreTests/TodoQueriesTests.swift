import Foundation
import SwiftData
import Testing
@testable import TodoNativeCore

private struct UTCCalendar {
    /// A fixed calendar so "today" does not depend on where the tests run.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}

/// 2026-03-10 15:00 UTC. Tomorrow starts at 2026-03-11 00:00 UTC.
private let now = Date(timeIntervalSince1970: 1_773_154_800)
private let startOfTomorrow = Date(timeIntervalSince1970: 1_773_187_200)

@MainActor
private func makeContext() throws -> ModelContext {
    ModelContext(try TodoContainer.make(inMemory: true))
}

@MainActor
@discardableResult
private func seed(
    _ context: ModelContext,
    _ title: String,
    order: Double = 0,
    created: TimeInterval = 0,
    due: Date? = nil,
    done: Bool = false,
    deleted: Bool = false
) throws -> TodoItem {
    let item = TodoItem(
        title: title, isDone: done, dueAt: due,
        createdAt: at(created), updatedAt: at(created),
        isSoftDeleted: deleted, dirty: false, sortOrder: order
    )
    context.insert(item)
    try context.save()
    return item
}

@Suite("TodoFilter")
struct TodoFilterTests {
    private func item(due: Date? = nil, done: Bool = false) -> TodoItem {
        TodoItem(title: "t", isDone: done, dueAt: due, createdAt: at(0), updatedAt: at(0))
    }

    @Test("active is every item not done, dated or not")
    func active() {
        #expect(TodoFilter.isActive(item()))
        #expect(TodoFilter.isActive(item(due: now)))
        #expect(!TodoFilter.isActive(item(done: true)))
    }

    @Test("today includes overdue and later today, and stops exactly at the start of tomorrow")
    func todayBoundary() {
        let cal = UTCCalendar.calendar
        #expect(TodoFilter.isDueTodayOrOverdue(item(due: now.addingTimeInterval(-86_400 * 30)), now: now, calendar: cal))
        #expect(TodoFilter.isDueTodayOrOverdue(item(due: startOfTomorrow.addingTimeInterval(-1)), now: now, calendar: cal))
        #expect(!TodoFilter.isDueTodayOrOverdue(item(due: startOfTomorrow), now: now, calendar: cal))
    }

    @Test("today and upcoming exclude undated and done items")
    func excludesUndatedAndDone() {
        let cal = UTCCalendar.calendar
        #expect(!TodoFilter.isDueTodayOrOverdue(item(), now: now, calendar: cal))
        #expect(!TodoFilter.isDueTodayOrOverdue(item(due: now, done: true), now: now, calendar: cal))
        #expect(!TodoFilter.isUpcoming(item(), now: now, calendar: cal))
        #expect(!TodoFilter.isUpcoming(item(due: startOfTomorrow, done: true), now: now, calendar: cal))
    }

    @Test("upcoming starts exactly where today stops")
    func upcomingBoundary() {
        let cal = UTCCalendar.calendar
        #expect(TodoFilter.isUpcoming(item(due: startOfTomorrow), now: now, calendar: cal))
        #expect(!TodoFilter.isUpcoming(item(due: startOfTomorrow.addingTimeInterval(-1)), now: now, calendar: cal))
    }
}

@Suite("TodoQueries.active")
struct ActiveQueryTests {
    @Test("rows come back in the app's manual order, ties newest first")
    @MainActor
    func manualOrder() throws {
        let context = try makeContext()
        try seed(context, "third", order: 5, created: 1)
        try seed(context, "first", order: -2, created: 2)
        try seed(context, "tie old", order: 1, created: 3)
        try seed(context, "tie new", order: 1, created: 4)

        let titles = try TodoQueries.active(in: context, now: now).map(\.title)

        #expect(titles == ["first", "tie new", "tie old", "third"])
    }

    @Test("done and soft-deleted items are excluded")
    @MainActor
    func excludes() throws {
        let context = try makeContext()
        try seed(context, "open")
        try seed(context, "finished", done: true)
        try seed(context, "gone", deleted: true)

        #expect(try TodoQueries.active(in: context, now: now).map(\.title) == ["open"])
    }

    @Test("the limit keeps the first rows of the order")
    @MainActor
    func limit() throws {
        let context = try makeContext()
        for index in 0..<5 { try seed(context, "item \(index)", order: Double(index)) }

        #expect(try TodoQueries.active(in: context, now: now, limit: 3).map(\.title) == ["item 0", "item 1", "item 2"])
        #expect(try TodoQueries.active(in: context, now: now, limit: 0).isEmpty)
        #expect(try TodoQueries.active(in: context, now: now, limit: 99).count == 5)
    }

    @Test("a snapshot copies the row and flags overdue only for open, past-due items")
    @MainActor
    func snapshots() throws {
        let context = try makeContext()
        let pastDue = try seed(context, "late", order: 0, due: now.addingTimeInterval(-60))
        try seed(context, "later", order: 1, due: now.addingTimeInterval(60))
        try seed(context, "undated", order: 2)

        let rows = try TodoQueries.active(in: context, now: now)

        #expect(rows.map(\.isOverdue) == [true, false, false])
        #expect(rows[0] == TodoSnapshot(id: pastDue.id, title: "late", dueAt: pastDue.dueAt, isOverdue: true))
    }
}

@Suite("TodoQueries.dueTodayOrOverdueCount")
struct DueCountTests {
    @Test("counts overdue and due-today open items and nothing else")
    @MainActor
    func counts() throws {
        let context = try makeContext()
        let cal = UTCCalendar.calendar
        try seed(context, "overdue", due: now.addingTimeInterval(-86_400 * 3))
        try seed(context, "later today", due: startOfTomorrow.addingTimeInterval(-1))
        try seed(context, "tomorrow", due: startOfTomorrow)
        try seed(context, "undated")
        try seed(context, "done today", due: now, done: true)
        try seed(context, "deleted today", due: now, deleted: true)

        #expect(try TodoQueries.dueTodayOrOverdueCount(in: context, now: now, calendar: cal) == 2)
    }

    @Test("the same store counts differently once the day rolls over")
    @MainActor
    func dayRollover() throws {
        let context = try makeContext()
        let cal = UTCCalendar.calendar
        try seed(context, "due tomorrow", due: startOfTomorrow.addingTimeInterval(3_600))

        #expect(try TodoQueries.dueTodayOrOverdueCount(in: context, now: now, calendar: cal) == 0)
        #expect(try TodoQueries.dueTodayOrOverdueCount(in: context, now: startOfTomorrow.addingTimeInterval(60), calendar: cal) == 1)
    }
}

@Suite("TodoStore complete by id")
struct CompleteByIDTests {
    private struct StepClock: Clock {
        let date: Date
        func now() -> Date { date }
    }

    @Test("completes the item and stamps it like any other write")
    @MainActor
    func completes() throws {
        let context = try makeContext()
        let item = try seed(context, "do it", created: 1)
        let store = TodoStore(context: context, clock: StepClock(date: at(50)))

        #expect(try store.complete(id: item.id))

        #expect(item.isDone)
        #expect(item.dirty)
        #expect(item.updatedAt == at(50))
    }

    @Test("a missing id changes nothing and reports false")
    @MainActor
    func missing() throws {
        let context = try makeContext()
        let item = try seed(context, "other", created: 1)
        let store = TodoStore(context: context, clock: StepClock(date: at(50)))

        #expect(try !store.complete(id: UUID()))

        #expect(!item.isDone)
        #expect(!item.dirty)
        #expect(item.updatedAt == at(1))
    }

    @Test("a soft-deleted item is treated as missing")
    @MainActor
    func deleted() throws {
        let context = try makeContext()
        let item = try seed(context, "removed", created: 1, deleted: true)
        let store = TodoStore(context: context, clock: StepClock(date: at(50)))

        #expect(try !store.complete(id: item.id))
        #expect(!item.isDone)
    }
}
