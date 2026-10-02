import Foundation

/// Which category the lists are showing. Unassigned is virtual: it has no `TodoCategory` row.
public enum CategorySelection: Equatable, Hashable, Sendable {
    case unassigned
    case category(UUID)

    public var categoryID: UUID? {
        switch self {
        case .unassigned: nil
        case .category(let id): id
        }
    }

    public init(_ categoryID: UUID?) {
        self = categoryID.map(Self.category) ?? .unassigned
    }
}

/// The one display rule for categories, built from every `TodoCategory` row (deleted ones included;
/// they are dropped here). Last-write-wins merges can leave rows pointing at a parent that is
/// missing, deleted, or itself nested; both devices resolve those identically here, so the tree
/// never needs a repair step.
public struct CategoryTree {
    /// Live categories shown at the top level, in sibling order.
    public let topLevel: [TodoCategory]
    private let live: [UUID: TodoCategory]
    private let childrenByParent: [UUID: [TodoCategory]]

    public init(_ categories: [TodoCategory]) {
        var live: [UUID: TodoCategory] = [:]
        for category in categories where !category.isSoftDeleted {
            live[category.id] = category
        }

        var topLevel: [TodoCategory] = []
        var children: [UUID: [TodoCategory]] = [:]
        for category in live.values {
            // A subcategory only if its parent is live and is itself not nested. Anything else is
            // top-level: a missing or deleted parent, a parent that has a parent, and so both
            // halves of a two-device cycle.
            if let parentId = category.parentId, let parent = live[parentId], parent.parentId == nil {
                children[parentId, default: []].append(category)
            } else {
                topLevel.append(category)
            }
        }

        self.live = live
        self.topLevel = topLevel.sorted(by: TodoCategory.manualOrder)
        self.childrenByParent = children.mapValues { $0.sorted(by: TodoCategory.manualOrder) }
    }

    /// The live subcategories shown under `id`, in sibling order. Empty unless `id` is top-level.
    public func children(of id: UUID) -> [TodoCategory] {
        childrenByParent[id] ?? []
    }

    /// The live category with this id; nil for no id, an unknown id, or a deleted category.
    public func resolve(_ id: UUID?) -> TodoCategory? {
        id.flatMap { live[$0] }
    }

    /// Whether `category` shows nested under another one.
    public func isSubcategory(_ category: TodoCategory) -> Bool {
        parent(of: category) != nil
    }

    /// The category `category` shows under, or nil if it shows at the top level.
    public func parent(of category: TodoCategory) -> TodoCategory? {
        guard let parentId = category.parentId, let parent = live[parentId], parent.parentId == nil,
              live[category.id] != nil
        else { return nil }
        return parent
    }

    /// The sibling group shown under `parentId` (nil is the top level).
    public func siblings(under parentId: UUID?) -> [TodoCategory] {
        parentId.map(children(of:)) ?? topLevel
    }

    /// The sibling group `category` is shown in, itself included.
    public func siblings(of category: TodoCategory) -> [TodoCategory] {
        siblings(under: parent(of: category)?.id)
    }

    /// The categories `category` may be filed under (pass nil for a new one): live, top-level, not
    /// itself. A top-level row still pointing at a dead or nested parent is left out, because a
    /// category filed under it would not count as a subcategory by the display rule.
    public func parentCandidates(for category: TodoCategory?) -> [TodoCategory] {
        topLevel.filter { $0.parentId == nil && $0.id != category?.id }
    }

    /// What selecting `id` shows: the category itself, plus its subcategories if it is top-level.
    /// Empty for an id that does not resolve.
    public func scope(of id: UUID) -> Set<UUID> {
        guard live[id] != nil else { return [] }
        return Set(children(of: id).map(\.id)).union([id])
    }

    /// Whether `item` shows under `selection`. An item whose category does not resolve belongs to
    /// Unassigned.
    public func contains(_ item: TodoItem, in selection: CategorySelection) -> Bool {
        let resolved = resolve(item.categoryId)
        switch selection {
        case .unassigned:
            return resolved == nil
        case .category(let id):
            guard let resolved else { return false }
            return scope(of: id).contains(resolved.id)
        }
    }

    /// Every live category in picker order: each top-level one followed by its subcategories.
    public var flattened: [(category: TodoCategory, isSubcategory: Bool)] {
        topLevel.flatMap { parent in
            [(parent, false)] + children(of: parent.id).map { ($0, true) }
        }
    }
}

/// How many live, not-done items are due today or overdue, per category. A top-level category's
/// count includes its subcategories', so a busy subcategory never goes quiet in the picker.
public struct CategoryDueCounts: Equatable, Sendable {
    public var unassigned = 0
    public var byCategory: [UUID: Int] = [:]

    public subscript(selection: CategorySelection) -> Int {
        switch selection {
        case .unassigned: unassigned
        case .category(let id): byCategory[id] ?? 0
        }
    }
}
