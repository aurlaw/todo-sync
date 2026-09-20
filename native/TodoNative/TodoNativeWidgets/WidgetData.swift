import SwiftData
import SwiftUI
import TodoNativeCore
import WidgetKit

/// Everything both widgets draw: the top of the Active list and the due-today count, as value copies.
struct TodoEntry: TimelineEntry {
    /// Rows the biggest layout can show; the small ones just show fewer.
    static let maxRows = 8

    let date: Date
    let items: [TodoSnapshot]
    let dueCount: Int
    /// Set when the shared store cannot be opened (the app has not run since the App Group was added).
    let problem: String?

    static let sample = TodoEntry(
        date: .now,
        items: [
            TodoSnapshot(id: UUID(), title: "Call the dentist", dueAt: .now.addingTimeInterval(-3_600), isOverdue: true),
            TodoSnapshot(id: UUID(), title: "Buy milk", dueAt: .now.addingTimeInterval(3_600), isOverdue: false),
            TodoSnapshot(id: UUID(), title: "Renew passport", dueAt: nil, isOverdue: false),
        ],
        dueCount: 2,
        problem: nil
    )
}

/// One provider for both widgets. It only reads the App Group store; it never syncs (no Keychain or Worker
/// access here), so a widget shows what is on this device as of the app's last sync or local edit.
struct TodoTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (TodoEntry) -> Void) {
        completion(context.isPreview ? .sample : load(at: .now).first ?? .sample)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoEntry>) -> Void) {
        let now = Date.now
        // Refresh hourly so due badges roll over; edits and syncs reload the timeline sooner.
        let nextHour = Calendar.current.dateInterval(of: .hour, for: now)?.end ?? now.addingTimeInterval(3_600)
        completion(Timeline(entries: load(at: now), policy: .after(nextHour)))
    }

    /// The entry for `now`, plus one for the start of tomorrow so the due-today count rolls over at midnight
    /// even if no reload happens.
    private func load(at now: Date) -> [TodoEntry] {
        do {
            let container = try TodoContainer.makeShared(migrateLegacyStore: false)
            let context = ModelContext(container)
            let calendar = Calendar.current
            let tomorrow = TodoFilter.startOfTomorrow(after: now, calendar: calendar)
            return try [now, tomorrow].map { date in
                TodoEntry(
                    date: date,
                    items: try TodoQueries.active(in: context, now: date, limit: TodoEntry.maxRows),
                    dueCount: try TodoQueries.dueTodayOrOverdueCount(in: context, now: date, calendar: calendar),
                    problem: nil
                )
            }
        } catch TodoContainerError.storeNotReady {
            return [TodoEntry(date: now, items: [], dueCount: 0, problem: "Open TodoNative once to finish setup.")]
        } catch {
            return [TodoEntry(date: now, items: [], dueCount: 0, problem: "Couldn't read your todos.")]
        }
    }
}
