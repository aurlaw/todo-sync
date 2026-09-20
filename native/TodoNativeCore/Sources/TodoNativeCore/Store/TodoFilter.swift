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

    /// Midnight at the start of the day after `now`: the boundary between Today and Upcoming.
    public static func startOfTomorrow(after now: Date, calendar: Calendar) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(24 * 60 * 60)
        return calendar.startOfDay(for: tomorrow)
    }
}
