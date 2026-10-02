import Foundation
import SwiftData

/// A value copy of what a widget row shows. Widget timeline entries carry these, never `@Model` objects,
/// which are tied to the context that fetched them.
public struct TodoSnapshot: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let dueAt: Date?
    public let isOverdue: Bool

    public init(id: UUID, title: String, dueAt: Date?, isOverdue: Bool) {
        self.id = id
        self.title = title
        self.dueAt = dueAt
        self.isOverdue = isOverdue
    }

    public init(_ item: TodoItem, now: Date) {
        self.init(
            id: item.id,
            title: item.title,
            dueAt: item.dueAt,
            isOverdue: !item.isDone && (item.dueAt.map { $0 < now } ?? false)
        )
    }
}

/// Read-only queries for surfaces outside the main list (the widgets). Takes the caller's context; on the
/// widget side that is a context on the App Group store.
public enum TodoQueries {
    /// The category tree as stored in `context`.
    public static func categoryTree(in context: ModelContext) throws -> CategoryTree {
        CategoryTree(try context.fetch(FetchDescriptor<TodoCategory>()))
    }

    /// The Active list of one category in the app's manual order (`TodoItem.manualOrder`), optionally cut
    /// to the first `limit` rows.
    public static func active(
        in context: ModelContext,
        selection: CategorySelection = .unassigned,
        now: Date = .now,
        limit: Int? = nil
    ) throws -> [TodoSnapshot] {
        let tree = try categoryTree(in: context)
        let items = try context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { !$0.isSoftDeleted }))
            .filter { TodoFilter.isInCategory($0, selection, tree: tree) }
            .filter(TodoFilter.isActive)
            .sorted(by: TodoItem.manualOrder)
        let shown = limit.map { Array(items.prefix($0)) } ?? items
        return shown.map { TodoSnapshot($0, now: now) }
    }

    /// How many open items of one category are due today or overdue: the same rule as the Today list.
    public static func dueTodayOrOverdueCount(
        in context: ModelContext,
        selection: CategorySelection = .unassigned,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> Int {
        let tree = try categoryTree(in: context)
        return try context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { !$0.isSoftDeleted }))
            .filter { TodoFilter.isInCategory($0, selection, tree: tree) }
            .filter { TodoFilter.isDueTodayOrOverdue($0, now: now, calendar: calendar) }
            .count
    }
}
