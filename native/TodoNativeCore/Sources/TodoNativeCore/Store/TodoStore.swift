import Foundation
import SwiftData

/// A synced row with a fractional sort key: what the manual-ordering helpers work on, so items and
/// categories share one implementation.
protocol ManuallyOrdered: AnyObject {
    var id: UUID { get }
    var sortOrder: Double { get set }
    var updatedAt: Date { get set }
    var dirty: Bool { get set }
}

extension TodoItem: ManuallyOrdered {}
extension TodoCategory: ManuallyOrdered {}

/// Why a category write was refused. The descriptions are shown in the category editor.
public enum CategoryError: Error, Equatable, Sendable, CustomStringConvertible {
    case emptyName
    /// Another live category in the same sibling group already has this name (case-insensitive).
    case duplicateName(String)
    /// The parent is not a live top-level category.
    case invalidParent
    /// Only one level of nesting: a category that has subcategories cannot become one.
    case hasSubcategories
    case parentIsSelf
    case invalidColor(String)

    public var description: String {
        switch self {
        case .emptyName: "Enter a name."
        case .duplicateName(let name): "There is already a category named \u{201C}\(name)\u{201D} here."
        case .invalidParent: "The parent must be a top-level category."
        case .hasSubcategories: "A category that has subcategories can't be moved under another one."
        case .parentIsSelf: "A category can't be its own parent."
        case .invalidColor(let value): "\(value) is not a #rrggbb color."
        }
    }
}

/// The only path for mutating a `TodoItem` or a `TodoCategory`. Every write here sets
/// `updatedAt`/`dirty` and persists immediately — views must never touch those fields or the
/// `ModelContext` directly, since SwiftData has no repository layer to enforce it otherwise.
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
        recurrence: RecurrenceRule? = nil,
        categoryId: UUID? = nil
    ) throws -> TodoItem {
        let now = clock.now()
        // New items go to the end of the list, below every live item (in any category: the order is global).
        let sortOrder = try liveItems().last.map { $0.sortOrder + 1 } ?? 0
        let item = TodoItem(
            title: title,
            notes: notes,
            dueAt: dueAt,
            recurrence: recurrence,
            createdAt: now,
            updatedAt: now,
            dirty: true,
            sortOrder: sortOrder,
            categoryId: categoryId
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

    /// `update` that also files the item under `categoryId` (nil is Unassigned), in the same write.
    public func update(
        _ item: TodoItem,
        title: String,
        notes: String?,
        dueAt: Date?,
        recurrence: RecurrenceRule?,
        categoryId: UUID?
    ) throws {
        item.categoryId = categoryId
        try update(item, title: title, notes: notes, dueAt: dueAt, recurrence: recurrence)
    }

    /// Moves an item to another category; nil is Unassigned.
    public func setCategory(_ item: TodoItem, to categoryId: UUID?) throws {
        guard item.categoryId != categoryId else { return }
        item.categoryId = categoryId
        try touch(item)
    }

    public func complete(_ item: TodoItem, isDone: Bool = true) throws {
        item.isDone = isDone
        try touch(item)
    }

    /// A live (not soft-deleted) item by id, for callers that only hold an id, such as a widget's intent.
    public func item(id: UUID) throws -> TodoItem? {
        try context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == id && !$0.isSoftDeleted })).first
    }

    /// `complete(_:isDone:)` by id. Returns `false`, changing nothing, when there is no live item with that id.
    @discardableResult
    public func complete(id: UUID, isDone: Bool = true) throws -> Bool {
        guard let found = try item(id: id) else { return false }
        try complete(found, isDone: isDone)
        return true
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
        try reorder(fromOffsets: source, toOffset: destination, in: ordered, group: liveItems)
    }

    /// `group` is the whole ordered list the keys belong to, respaced if two neighbours get too close.
    private func reorder<Row: ManuallyOrdered>(
        fromOffsets source: IndexSet,
        toOffset destination: Int,
        in ordered: [Row],
        group: () throws -> [Row]
    ) throws {
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
            try place(item, previous: previous, next: next, now: now, group: group)
            previous = item
        }
        try commit()
    }

    /// Places `item` between two neighbours (`nil` means the head or tail of the list).
    public func move(_ item: TodoItem, between previous: TodoItem?, and next: TodoItem?) throws {
        try place(item, previous: previous, next: next, now: clock.now(), group: liveItems)
        try commit()
    }

    /// Above everything, including items the current filter hides.
    public func moveToTop(_ item: TodoItem) throws {
        guard let first = try liveItems().first, first.id != item.id else { return }
        try place(item, previous: nil, next: first, now: clock.now(), group: liveItems)
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

    // MARK: Categories

    /// The category tree as stored right now.
    public func categoryTree() throws -> CategoryTree {
        CategoryTree(try context.fetch(FetchDescriptor<TodoCategory>()))
    }

    /// Appends a category to the end of its sibling group. Throws `CategoryError` for an empty
    /// name, a name a sibling already has, a parent that is not a live top-level category, or a
    /// colour that is not `#rrggbb`.
    @discardableResult
    public func createCategory(name: String, parentId: UUID? = nil, color: String? = nil) throws -> TodoCategory {
        let tree = try categoryTree()
        if let parentId { try validateParent(parentId, in: tree) }
        let siblings = tree.siblings(under: parentId)
        let name = try validatedName(name, among: siblings)
        let color = try validatedColor(color)

        let now = clock.now()
        let category = TodoCategory(
            name: name,
            parentId: parentId,
            color: color,
            sortOrder: siblings.last.map { $0.sortOrder + 1 } ?? 0,
            createdAt: now,
            updatedAt: now,
            dirty: true
        )
        context.insert(category)
        try commit()
        return category
    }

    /// The editor's save: name, parent and colour in one write. Everything is validated before
    /// anything changes, so a refused edit leaves the category untouched. `parentId` nil means top
    /// level; a category that changes parent goes to the end of its new siblings.
    public func updateCategory(_ category: TodoCategory, name: String, parentId: UUID?, color: String?) throws {
        let tree = try categoryTree()
        let moving = parentId != tree.parent(of: category)?.id
        if moving, let parentId {
            guard parentId != category.id else { throw CategoryError.parentIsSelf }
            guard tree.children(of: category.id).isEmpty else { throw CategoryError.hasSubcategories }
            try validateParent(parentId, in: tree)
        }
        let siblings = tree.siblings(under: parentId).filter { $0.id != category.id }
        let name = try validatedName(name, among: siblings)
        let color = try validatedColor(color)

        var changed = false
        if moving {
            category.sortOrder = siblings.last.map { $0.sortOrder + 1 } ?? 0
            changed = true
        }
        // Also settles a row shown at the top level only because its stored parent is dead or nested.
        if category.parentId != parentId {
            category.parentId = parentId
            changed = true
        }
        if category.name != name {
            category.name = name
            changed = true
        }
        if category.color != color {
            category.color = color
            changed = true
        }
        if changed { try touch(category) }
    }

    public func renameCategory(_ category: TodoCategory, to name: String) throws {
        try updateCategory(category, name: name, parentId: try shownParentID(of: category), color: category.color)
    }

    /// `color` is `#rrggbb` in either case, stored lowercase; nil removes the custom colour.
    public func setCategoryColor(_ category: TodoCategory, _ color: String?) throws {
        try updateCategory(category, name: category.name, parentId: try shownParentID(of: category), color: color)
    }

    /// Files `category` under another top-level category, or at the top level for nil.
    public func setCategoryParent(_ category: TodoCategory, to parentId: UUID?) throws {
        try updateCategory(category, name: category.name, parentId: parentId, color: category.color)
    }

    /// Applies a SwiftUI `.onMove` to `ordered`, one sibling group exactly as displayed.
    public func moveCategory(fromOffsets source: IndexSet, toOffset destination: Int, in ordered: [TodoCategory]) throws {
        try reorder(fromOffsets: source, toOffset: destination, in: ordered, group: { ordered })
    }

    /// Places `category` between two of its siblings (`nil` means the head or tail of the group).
    public func moveCategory(_ category: TodoCategory, between previous: TodoCategory?, and next: TodoCategory?) throws {
        try place(category, previous: previous, next: next, now: clock.now(), group: {
            try categoryTree().siblings(of: previous ?? next ?? category)
        })
        try commit()
    }

    /// Respaces one sibling group (nil is the top level) at integer steps in its current order.
    public func renormalizeCategories(parentId: UUID?) throws {
        if renormalizeInMemory(try categoryTree().siblings(under: parentId), now: clock.now()) { try commit() }
    }

    /// What deleting `category` would do, for the confirmation: how many subcategories become
    /// top-level and how many of its own items (not its subcategories') move to Unassigned.
    public func deletionImpact(of category: TodoCategory) throws -> (subcategories: Int, items: Int) {
        let id = category.id
        return (
            try categoryTree().children(of: id).count,
            try liveItems().filter { $0.categoryId == id }.count
        )
    }

    /// Soft-deletes `category` in one batch. Its own items move to Unassigned. If it is a parent,
    /// its subcategories become top-level and take its slot in the top-level order, keeping their
    /// order among themselves; their items stay with them.
    public func deleteCategory(_ category: TodoCategory) throws {
        let now = clock.now()
        let tree = try categoryTree()
        let id = category.id
        let promoted = tree.children(of: id)

        category.isSoftDeleted = true
        stamp(category, at: now)

        for item in try liveItems() where item.categoryId == id {
            item.categoryId = nil
            stamp(item, at: now)
        }

        // Only a top-level category has subcategories, so it is in `topLevel` whenever this runs.
        if !promoted.isEmpty, let index = tree.topLevel.firstIndex(where: { $0.id == id }) {
            let previous = index > 0 ? tree.topLevel[index - 1].sortOrder : nil
            let next = index + 1 < tree.topLevel.count ? tree.topLevel[index + 1].sortOrder : nil
            // Evenly spaced strictly between the old neighbours; an open end steps by 1.
            let count = Double(promoted.count)
            let low = previous ?? next.map { $0 - count - 1 } ?? category.sortOrder - 1
            let high = next ?? low + count + 1
            let step = (high - low) / (count + 1)
            for (offset, child) in promoted.enumerated() {
                child.parentId = nil
                child.sortOrder = low + step * Double(offset + 1)
                stamp(child, at: now)
            }
            if step < Self.minimumGap {
                var resulting = tree.topLevel
                resulting.replaceSubrange(index...index, with: promoted)
                renormalizeInMemory(resulting, now: now)
            }
        }
        try commit()
    }

    private func shownParentID(of category: TodoCategory) throws -> UUID? {
        try categoryTree().parent(of: category)?.id
    }

    private func validateParent(_ parentId: UUID, in tree: CategoryTree) throws {
        guard let parent = tree.resolve(parentId), parent.parentId == nil else { throw CategoryError.invalidParent }
    }

    /// The trimmed name, unique among `siblings` ignoring case.
    private func validatedName(_ name: String, among siblings: [TodoCategory]) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CategoryError.emptyName }
        let clash = siblings.contains {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(trimmed) == .orderedSame
        }
        if clash { throw CategoryError.duplicateName(trimmed) }
        return trimmed
    }

    private func validatedColor(_ color: String?) throws -> String? {
        guard let color else { return nil }
        guard let normalized = CategoryColor.normalized(color) else { throw CategoryError.invalidColor(color) }
        return normalized
    }

    private func liveItems() throws -> [TodoItem] {
        try context.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { !$0.isSoftDeleted }))
            .sorted(by: TodoItem.manualOrder)
    }

    private func place<Row: ManuallyOrdered>(
        _ item: Row,
        previous: Row?,
        next: Row?,
        now: Date,
        group: () throws -> [Row]
    ) throws {
        if let previous, let next, next.sortOrder - previous.sortOrder < Self.minimumGap {
            renormalizeInMemory(try group(), now: now)
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
        renormalizeInMemory(try liveItems(), now: now)
    }

    /// Respaces `ordered` at integer steps, touching only the rows whose key changes.
    @discardableResult
    private func renormalizeInMemory<Row: ManuallyOrdered>(_ ordered: [Row], now: Date) -> Bool {
        var changed = false
        for (index, item) in ordered.enumerated() where item.sortOrder != Double(index) {
            item.sortOrder = Double(index)
            stamp(item, at: now)
            changed = true
        }
        return changed
    }

    // Every row a batch changes must move `updatedAt` too: the Worker's `updated_at >` guard rejects
    // an unchanged timestamp as stale, and the sync engine's compare-and-clear keys off it.
    private func stamp<Row: ManuallyOrdered>(_ item: Row, at now: Date) {
        item.updatedAt = now
        item.dirty = true
    }

    private func commit() throws {
        try context.save()
        onMutation?()
    }

    private func touch<Row: ManuallyOrdered>(_ item: Row) throws {
        stamp(item, at: clock.now())
        try commit()
    }
}
