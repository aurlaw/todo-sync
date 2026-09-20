import AppIntents
import SwiftData
import TodoNativeCore

/// Runs when a checkbox in `ActiveListWidget` is tapped. Interactive widgets need an `AppIntent`; this one runs
/// in the widget process, completes the item through `TodoStore` (so it is stamped and marked dirty like any other
/// write, and picks up recurrence handling when that exists), then reloads the widgets. The main app pushes the
/// change the next time it becomes active.
struct CompleteTodoIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Todo"
    /// The widget uses this directly; there is no reason to offer it in Shortcuts.
    static let isDiscoverable = false

    @Parameter(title: "Todo ID")
    var todoID: String

    init() {}

    init(todoID: UUID) {
        self.todoID = todoID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // A malformed id, or an item deleted since the widget last drew, is a silent no-op.
        guard let id = UUID(uuidString: todoID) else { return .result() }
        let container = try TodoContainer.makeShared(migrateLegacyStore: false)
        let store = TodoStore(context: container.mainContext, onMutation: { WidgetReloader.reloadAll() })
        try store.complete(id: id)
        return .result()
    }
}
