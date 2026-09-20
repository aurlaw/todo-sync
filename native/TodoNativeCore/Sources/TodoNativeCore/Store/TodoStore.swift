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
        // New items go to the top of the list so a captured item is visible.
        let sortOrder = try liveItems().first.map { $0.sortOrder - 1 } ?? 0
        let item = TodoItem(
            title: title,
            notes: notes,
            dueAt: dueAt,
            recurrence: recurrence,
            createdAt: now,
            updatedAt: now,
            dirty: true,
            sortOrder: sortOrder
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

    // MARK: Manual ordering

    /// Below this gap between neighbours a midpoint is no longer safely distinct, so the whole list
    /// is respaced first.
    static let minimumGap = 1e-6

    /// Applies a SwiftUI `.onMove` to `ordered`, the list exactly as displayed (a filtered view of
    /// the manual order). Neighbours are taken from that displayed list, so hidden items (for
    /// example done ones under Active) never matter. Only the moved rows are dirtied.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int, in ordered: [TodoItem]) throws {
        let moving = source.sorted().filter { ordered.indices.contains($0) }.map { ordered[$0] }
        guard !moving.isEmpty else { return }

        let movingIDs = Set(moving.map(\.id))
        let remaining = ordered.filter { !movingIDs.contains($0.id) }
        let insertAt = destination - source.filter { $0 < destination }.count
        guard (0...remaining.count).contains(insertAt) else { return }

        var resulting = remaining
        resulting.insert(contentsOf: moving, at: insertAt)
        if resulting.map(\.id) == ordered.map(\.id) { return }

        let now = clock.now()
        var previous = insertAt > 0 ? remaining[insertAt - 1] : nil
        let next = insertAt < remaining.count ? remaining[insertAt] : nil
        for item in moving {
            try place(item, previous: previous, next: next, now: now)
            previous = item
        }
        try commit()
    }

    /// Places `item` between two neighbours (`nil` means the head or tail of the list).
    public func move(_ item: TodoItem, between previous: TodoItem?, and next: TodoItem?) throws {
        try place(item, previous: previous, next: next, now: clock.now())
        try commit()
    }

    /// Above everything, including items the current filter hides.
    public func moveToTop(_ item: TodoItem) throws {
        guard let first = try liveItems().first, first.id != item.id else { return }
        try place(item, previous: nil, next: first, now: clock.now())
        try commit()
    }

    /// Respaces every live item at integer steps in its current order. The only operation that
    /// dirties many rows; rows whose value does not change are left alone.
    public func renormalize() throws {
        if try renormalizeInMemory(now: clock.now()) { try commit() }
    }

    /// One-time fill for items that predate manual ordering: newest first, matching where new
    /// items land. Runs only when every live item is still 0, so a device that already pulled real
    /// keys skips it, and two devices that race produce the same numbering. Returns whether it changed anything.
    @discardableResult
    public func backfillSortOrderIfNeeded() throws -> Bool {
        let live = try liveItems()
        guard live.count >= 2, live.allSatisfy({ $0.sortOrder == 0 }) else { return false }
        guard try renormalizeInMemory(now: clock.now()) else { return false }
        try commit()
        return true
    }

    private func liveItems() throws -> [TodoItem] {
        try context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { !$0.isSoftDeleted }))
            .sorted(by: TodoItem.manualOrder)
    }

    private func place(_ item: TodoItem, previous: TodoItem?, next: TodoItem?, now: Date) throws {
        if let previous, let next, next.sortOrder - previous.sortOrder < Self.minimumGap {
            try renormalizeInMemory(now: now)
        }
        let key: Double
        if let previous, let next {
            key = (previous.sortOrder + next.sortOrder) / 2
        } else if let next {
            key = next.sortOrder - 1
        } else if let previous {
            key = previous.sortOrder + 1
        } else {
            return
        }
        guard item.sortOrder != key else { return }
        item.sortOrder = key
        stamp(item, at: now)
    }

    @discardableResult
    private func renormalizeInMemory(now: Date) throws -> Bool {
        var changed = false
        for (index, item) in try liveItems().enumerated() where item.sortOrder != Double(index) {
            item.sortOrder = Double(index)
            stamp(item, at: now)
            changed = true
        }
        return changed
    }

    // Every row a batch changes must move `updatedAt` too: the Worker's `updated_at >` guard rejects
    // an unchanged timestamp as stale, and the sync engine's compare-and-clear keys off it.
    private func stamp(_ item: TodoItem, at now: Date) {
        item.updatedAt = now
        item.dirty = true
    }

    private func commit() throws {
        try context.save()
        onMutation?()
    }

    private func touch(_ item: TodoItem) throws {
        stamp(item, at: clock.now())
        try commit()
    }
}
