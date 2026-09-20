import Foundation
import SwiftData

@Model
public final class TodoItem {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var notes: String?
    public var isDone: Bool
    public var dueAt: Date?
    public var recurrence: RecurrenceRule?
    public var createdAt: Date
    public var updatedAt: Date
    public var isSoftDeleted: Bool
    public var dirty: Bool
    public var serverSeq: Int64?
    /// Manual list order, ascending. Fractional keys: a move sets one row to the midpoint of its new
    /// neighbours. The declaration-site default is what lets SwiftData add the column to an existing store.
    public var sortOrder: Double = 0

    /// Only `TodoStore` should call this directly — it does not set `updatedAt`/`dirty`,
    /// which is `TodoStore`'s job on every mutation. See `TodoStore` for the enforced writes.
    public init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        isDone: Bool = false,
        dueAt: Date? = nil,
        recurrence: RecurrenceRule? = nil,
        createdAt: Date,
        updatedAt: Date,
        isSoftDeleted: Bool = false,
        dirty: Bool = true,
        serverSeq: Int64? = nil,
        sortOrder: Double = 0
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isDone = isDone
        self.dueAt = dueAt
        self.recurrence = recurrence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isSoftDeleted = isSoftDeleted
        self.dirty = dirty
        self.serverSeq = serverSeq
        self.sortOrder = sortOrder
    }
}

extension TodoItem {
    /// The one list ordering: `sortOrder` ascending, then newest first, then id so it is total.
    /// Rows that have never been ordered (all 0) therefore read newest-first.
    public static func manualOrder(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
