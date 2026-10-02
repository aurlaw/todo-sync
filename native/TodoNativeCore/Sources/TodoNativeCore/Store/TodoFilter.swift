import Foundation

/// The membership rules for the Active and Today/Upcoming lists, in one place so the app's sidebar and the
/// widgets (a separate process) cannot drift apart. Every rule assumes a live item: callers exclude
/// soft-deleted rows (the app's `@Query` and `TodoQueries` both do).
public enum TodoFilter {
    /// Every item not yet completed, dated or not.
    public static func isActive(_ item: TodoItem) -> Bool {
        !item.isDone
    }

    /// Not done and due before tomorrow starts, so overdue items are included.
    public static func isDueTodayOrOverdue(_ item: TodoItem, now: Date, calendar: Calendar) -> Bool {
        guard !item.isDone, let dueAt = item.dueAt else { return false }
        return dueAt < startOfTomorrow(after: now, calendar: calendar)
    }

    /// Not done and due tomorrow or later.
    public static func isUpcoming(_ item: TodoItem, now: Date, calendar: Calendar) -> Bool {
        guard !item.isDone, let dueAt = item.dueAt else { return false }
        return dueAt >= startOfTomorrow(after: now, calendar: calendar)
    }

    /// Whether `item` shows under the active category. Applied before the sidebar rules above, for
    /// every sidebar list and for the widgets.
    public static func isInCategory(_ item: TodoItem, _ selection: CategorySelection, tree: CategoryTree) -> Bool {
        tree.contains(item, in: selection)
    }

    /// Due-today-or-overdue counts for the category picker, using the same rule as the Today list.
    /// Soft-deleted items are skipped here, so `items` may be any set of rows.
    public static func dueCounts(
        items: [TodoItem],
        tree: CategoryTree,
        now: Date,
        calendar: Calendar
    ) -> CategoryDueCounts {
        var counts = CategoryDueCounts()
        for item in items where !item.isSoftDeleted && isDueTodayOrOverdue(item, now: now, calendar: calendar) {
            guard let category = tree.resolve(item.categoryId) else {
                counts.unassigned += 1
                continue
            }
            counts.byCategory[category.id, default: 0] += 1
            if let parent = tree.parent(of: category) {
                counts.byCategory[parent.id, default: 0] += 1
            }
        }
        return counts
    }

    /// Midnight at the start of the day after `now`: the boundary between Today and Upcoming.
    public static func startOfTomorrow(after now: Date, calendar: Calendar) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(24 * 60 * 60)
        return calendar.startOfDay(for: tomorrow)
    }
}
