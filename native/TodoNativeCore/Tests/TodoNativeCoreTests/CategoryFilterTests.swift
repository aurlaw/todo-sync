import Foundation
import SwiftData
import Testing
@testable import TodoNativeCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

/// 2026-03-10 15:00 UTC.
private let now = Date(timeIntervalSince1970: 1_773_154_800)
private let yesterday = now.addingTimeInterval(-86_400)
private let nextWeek = now.addingTimeInterval(7 * 86_400)

private final class ChangeCount: @unchecked Sendable {
    var value = 0
}

private func makeStore(onChange: @escaping @Sendable () -> Void = {}) -> ActiveCategoryStore {
    ActiveCategoryStore(defaults: UserDefaults(suiteName: "todonative.tests.\(UUID().uuidString)")!, onChange: onChange)
}

@Suite("ActiveCategoryStore")
struct ActiveCategoryStoreTests {
    @Test("defaults to Unassigned")
    func defaultsToUnassigned() {
        let store = makeStore()
        #expect(store.storedID == nil)
        #expect(store.effectiveSelection(in: CategoryTree([category("Work")])) == .unassigned)
    }

    @Test("a stored id that resolves is the selection, and survives a new store on the same defaults")
    func storedResolves() {
        let defaults = UserDefaults(suiteName: "todonative.tests.\(UUID().uuidString)")!
        let work = category("Work")
        ActiveCategoryStore(defaults: defaults, onChange: {}).set(.category(work.id))

        let reopened = ActiveCategoryStore(defaults: defaults, onChange: {})
        #expect(reopened.storedID == work.id)
        #expect(reopened.effectiveSelection(in: CategoryTree([work])) == .category(work.id))
    }

    @Test("a stored id whose category was deleted, or never arrived, falls back to Unassigned")
    func deletedFallsBack() {
        let store = makeStore()
        let work = category("Work", deleted: true)
        store.set(.category(work.id))

        #expect(store.effectiveSelection(in: CategoryTree([work])) == .unassigned)
        #expect(store.effectiveSelection(in: CategoryTree([])) == .unassigned)
        // The id is kept, so the selection comes back if the category does.
        #expect(store.storedID == work.id)
    }

    @Test("a stored category demoted to top level by the display rule still resolves")
    func demotedStillResolves() {
        let store = makeStore()
        let clients = category("Clients", parent: UUID())
        store.set(.category(clients.id))
        #expect(store.effectiveSelection(in: CategoryTree([clients])) == .category(clients.id))
    }

    @Test("setting Unassigned clears the stored id, and every write reports a change")
    func setUnassigned() {
        let changes = ChangeCount()
        let store = makeStore(onChange: { changes.value += 1 })
        store.set(.category(UUID()))
        store.set(.unassigned)

        #expect(store.storedID == nil)
        #expect(changes.value == 2)
    }
}

@MainActor
private struct Fixture {
    let context: ModelContext
    let work: TodoCategory
    let clients: TodoCategory
    let home: TodoCategory
    let gone: TodoCategory

    init() throws {
        context = ModelContext(try TodoContainer.make(inMemory: true))
        work = category("Work", order: 0)
        clients = category("Clients", parent: work.id)
        home = category("Home", order: 1)
        gone = category("Gone", order: 2, deleted: true)
        for row in [work, clients, home, gone] { context.insert(row) }
        try context.save()
    }

    var tree: CategoryTree {
        get throws { try TodoQueries.categoryTree(in: context) }
    }

    @discardableResult
    func add(
        _ title: String,
        in categoryId: UUID?,
        due: Date? = nil,
        done: Bool = false,
        deleted: Bool = false,
        order: Double = 0
    ) throws -> TodoItem {
        let item = TodoItem(
            title: title, isDone: done, dueAt: due, createdAt: at(0), updatedAt: at(0),
            isSoftDeleted: deleted, dirty: false, sortOrder: order, categoryId: categoryId
        )
        context.insert(item)
        try context.save()
        return item
    }
}

@Suite("Category filter")
struct CategoryFilterTests {
    @Test("a parent shows its own items and its subcategories'; a subcategory shows only its own")
    @MainActor
    func scopes() throws {
        let f = try Fixture()
        try f.add("work", in: f.work.id, order: 0)
        try f.add("clients", in: f.clients.id, order: 1)
        try f.add("home", in: f.home.id, order: 2)

        #expect(try TodoQueries.active(in: f.context, selection: .category(f.work.id)).map(\.title) == ["work", "clients"])
        #expect(try TodoQueries.active(in: f.context, selection: .category(f.clients.id)).map(\.title) == ["clients"])
        #expect(try TodoQueries.active(in: f.context, selection: .category(f.home.id)).map(\.title) == ["home"])
    }

    @Test("Unassigned shows uncategorised items and orphans, and is the default selection")
    @MainActor
    func unassigned() throws {
        let f = try Fixture()
        try f.add("none", in: nil, order: 0)
        try f.add("unknown category", in: UUID(), order: 1)
        try f.add("deleted category", in: f.gone.id, order: 2)
        try f.add("work", in: f.work.id, order: 3)

        let expected = ["none", "unknown category", "deleted category"]
        #expect(try TodoQueries.active(in: f.context, selection: .unassigned).map(\.title) == expected)
        #expect(try TodoQueries.active(in: f.context).map(\.title) == expected)
    }

    @Test("the category applies before every sidebar rule: Active, Today, Upcoming, All and Done")
    @MainActor
    func everySidebarRule() throws {
        let f = try Fixture()
        let tree = try f.tree
        let inScope = try [
            f.add("open", in: f.clients.id),
            f.add("overdue", in: f.work.id, due: yesterday),
            f.add("upcoming", in: f.clients.id, due: nextWeek),
            f.add("done", in: f.work.id, done: true),
        ]
        let outOfScope = try [
            f.add("open elsewhere", in: f.home.id),
            f.add("overdue elsewhere", in: nil, due: yesterday),
            f.add("upcoming elsewhere", in: f.home.id, due: nextWeek),
            f.add("done elsewhere", in: nil, done: true),
        ]
        let selection = CategorySelection.category(f.work.id)
        func shown(_ rule: (TodoItem) -> Bool) -> [String] {
            (inScope + outOfScope).filter { TodoFilter.isInCategory($0, selection, tree: tree) && rule($0) }.map(\.title)
        }

        #expect(shown(TodoFilter.isActive) == ["open", "overdue", "upcoming"])
        #expect(shown { TodoFilter.isDueTodayOrOverdue($0, now: now, calendar: calendar) } == ["overdue"])
        #expect(shown { TodoFilter.isUpcoming($0, now: now, calendar: calendar) } == ["upcoming"])
        #expect(shown { _ in true } == ["open", "overdue", "upcoming", "done"])
        #expect(shown(\.isDone) == ["done"])

        #expect(try TodoQueries.dueTodayOrOverdueCount(in: f.context, selection: selection, now: now, calendar: calendar) == 1)
        #expect(try TodoQueries.dueTodayOrOverdueCount(in: f.context, now: now, calendar: calendar) == 1)
    }
}

@Suite("Category due counts")
struct CategoryDueCountTests {
    @Test("counts roll up to the parent, Unassigned is separate, done and deleted items are skipped")
    @MainActor
    func counts() throws {
        let f = try Fixture()
        let items = try [
            f.add("work overdue", in: f.work.id, due: yesterday),
            f.add("clients overdue", in: f.clients.id, due: yesterday),
            f.add("clients today", in: f.clients.id, due: now),
            f.add("clients upcoming", in: f.clients.id, due: nextWeek),
            f.add("clients undated", in: f.clients.id),
            f.add("clients done", in: f.clients.id, due: yesterday, done: true),
            f.add("clients deleted", in: f.clients.id, due: yesterday, deleted: true),
            f.add("unassigned overdue", in: nil, due: yesterday),
            f.add("orphan overdue", in: UUID(), due: yesterday),
            f.add("deleted category overdue", in: f.gone.id, due: yesterday),
        ]

        let counts = TodoFilter.dueCounts(items: items, tree: try f.tree, now: now, calendar: calendar)

        #expect(counts[.category(f.work.id)] == 3)
        #expect(counts[.category(f.clients.id)] == 2)
        #expect(counts[.category(f.home.id)] == 0)
        #expect(counts[.unassigned] == 3)
        #expect(counts.byCategory[f.gone.id] == nil)
    }

    @Test("each count matches the Today list of that category")
    @MainActor
    func matchesTodayList() throws {
        let f = try Fixture()
        try f.add("a", in: f.work.id, due: yesterday)
        try f.add("b", in: f.clients.id, due: now)
        try f.add("c", in: f.home.id, due: nextWeek)
        try f.add("d", in: nil, due: yesterday)
        let items = try f.context.fetch(FetchDescriptor<TodoItem>())
        let counts = TodoFilter.dueCounts(items: items, tree: try f.tree, now: now, calendar: calendar)

        for selection in [CategorySelection.unassigned, .category(f.work.id), .category(f.clients.id), .category(f.home.id)] {
            let listed = try TodoQueries.dueTodayOrOverdueCount(in: f.context, selection: selection, now: now, calendar: calendar)
            #expect(counts[selection] == listed)
        }
    }
}
