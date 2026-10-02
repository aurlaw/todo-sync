import Foundation
import SwiftData

/// A user-defined category. One level of nesting: `parentId` names a top-level category. Whether a
/// row actually shows as a subcategory is decided by `CategoryTree`, never by `parentId` alone.
/// The virtual Unassigned category (`TodoItem.categoryId == nil`) has no row.
@Model
public final class TodoCategory {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var parentId: UUID?
    /// The light-mode colour as lowercase `#rrggbb`, or nil for the app accent. The dark-mode
    /// variant is derived (`CategoryColor.darkVariant`), never stored.
    public var color: String?
    /// Fractional key among siblings, the same scheme as `TodoItem.sortOrder`.
    public var sortOrder: Double = 0
    public var createdAt: Date
    public var updatedAt: Date
    /// Not `isDeleted`: `@Model` reserves that name and silently resets it on save.
    public var isSoftDeleted: Bool = false
    public var dirty: Bool = false
    public var serverSeq: Int64?

    /// Only `TodoStore` should call this directly; it does not set `updatedAt`/`dirty`.
    public init(
        id: UUID = UUID(),
        name: String,
        parentId: UUID? = nil,
        color: String? = nil,
        sortOrder: Double = 0,
        createdAt: Date,
        updatedAt: Date,
        isSoftDeleted: Bool = false,
        dirty: Bool = true,
        serverSeq: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.color = color
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isSoftDeleted = isSoftDeleted
        self.dirty = dirty
        self.serverSeq = serverSeq
    }
}

extension TodoCategory {
    /// Sibling order: `sortOrder` ascending, then name, then id so it is total and both devices agree.
    public static func manualOrder(_ lhs: TodoCategory, _ rhs: TodoCategory) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
