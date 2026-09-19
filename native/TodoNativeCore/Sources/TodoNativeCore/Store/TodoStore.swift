import Foundation
import SwiftData

/// The only path for mutating a `TodoItem`. Every write here sets `updatedAt`/`dirty`
/// and persists immediately — views must never touch those fields or the `ModelContext`
/// directly, since SwiftData has no repository layer to enforce it otherwise.
@MainActor
public struct TodoStore {
    private let context: ModelContext
    private let clock: Clock
    private let onMutation: (@MainActor () -> Void)?

    /// `onMutation` runs after every successful save; the app uses it to schedule a sync.
    public init(context: ModelContext, clock: Clock = SystemClock(), onMutation: (@MainActor () -> Void)? = nil) {
        self.context = context
        self.clock = clock
        self.onMutation = onMutation
    }

    @discardableResult
    public func create(
        title: String,
        notes: String? = nil,
        dueAt: Date? = nil,
        recurrence: RecurrenceRule? = nil
    ) throws -> TodoItem {
        let now = clock.now()
        let item = TodoItem(
            title: title,
            notes: notes,
            dueAt: dueAt,
            recurrence: recurrence,
            createdAt: now,
            updatedAt: now,
            dirty: true
        )
        context.insert(item)
        try context.save()
        onMutation?()
        return item
    }

    public func update(
        _ item: TodoItem,
        title: String,
        notes: String?,
        dueAt: Date?,
        recurrence: RecurrenceRule?
    ) throws {
        item.title = title
        item.notes = notes
        item.dueAt = dueAt
        item.recurrence = recurrence
        try touch(item)
    }

    public func complete(_ item: TodoItem, isDone: Bool = true) throws {
        item.isDone = isDone
        try touch(item)
    }

    /// Soft delete only — hard deletes happen nowhere in this app.
    public func softDelete(_ item: TodoItem) throws {
        item.isSoftDeleted = true
        try touch(item)
    }

    private func touch(_ item: TodoItem) throws {
        item.updatedAt = clock.now()
        item.dirty = true
        try context.save()
        onMutation?()
    }
}
