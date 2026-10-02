import Foundation

extension CategoryWireDto {
    /// `dirty` is local-only and never sent. Ids are lowercased: the Worker rejects a category
    /// `id` or `parentId` that is not a lowercase UUID, and `UUID.uuidString` is uppercase.
    public init(_ category: TodoCategory) {
        self.init(
            id: category.id.uuidString.lowercased(),
            name: category.name,
            parentId: category.parentId?.uuidString.lowercased(),
            color: category.color,
            sortOrder: category.sortOrder,
            createdAt: Iso8601.format(category.createdAt),
            updatedAt: Iso8601.format(category.updatedAt),
            isDeleted: category.isSoftDeleted,
            serverSeq: category.serverSeq
        )
    }

    /// Builds a clean (`dirty == false`) category.
    public func makeCategory() throws -> TodoCategory {
        let parsed = try parse()
        return TodoCategory(
            id: parsed.uuid,
            name: name,
            parentId: parsed.parent,
            color: color,
            sortOrder: sortOrder,
            createdAt: parsed.created,
            updatedAt: parsed.updated,
            isSoftDeleted: isDeleted,
            dirty: false,
            serverSeq: serverSeq
        )
    }

    /// Overwrites `category` with this row and marks it clean. Throws before touching `category`
    /// if the row is malformed.
    public func apply(to category: TodoCategory) throws {
        let parsed = try parse()
        category.name = name
        category.parentId = parsed.parent
        category.color = color
        category.sortOrder = sortOrder
        category.createdAt = parsed.created
        category.updatedAt = parsed.updated
        category.isSoftDeleted = isDeleted
        category.dirty = false
        category.serverSeq = serverSeq
    }

    private func parse() throws -> (uuid: UUID, parent: UUID?, created: Date, updated: Date) {
        guard let uuid = UUID(uuidString: id) else { throw WireError.invalidID(id) }
        var parent: UUID?
        if let parentId {
            guard let parsedParent = UUID(uuidString: parentId) else { throw WireError.invalidID(parentId) }
            parent = parsedParent
        }
        guard let created = Iso8601.parse(createdAt) else {
            throw WireError.invalidDate(field: "createdAt", value: createdAt)
        }
        guard let updated = Iso8601.parse(updatedAt) else {
            throw WireError.invalidDate(field: "updatedAt", value: updatedAt)
        }
        return (uuid, parent, created, updated)
    }
}
