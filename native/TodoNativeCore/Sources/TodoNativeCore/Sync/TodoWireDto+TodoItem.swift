import Foundation

public enum WireError: Error, Equatable, Sendable {
    case invalidID(String)
    case invalidDate(field: String, value: String)
}

extension TodoWireDto {
    /// `dirty` is local-only and never sent. The id is lowercased because `todos.id` is a
    /// case-sensitive TEXT key and rows written by the .NET client are lowercase.
    public init(_ item: TodoItem) {
        self.init(
            id: item.id.uuidString.lowercased(),
            title: item.title,
            notes: item.notes,
            isDone: item.isDone,
            dueAt: item.dueAt.map(Iso8601.format),
            recurrence: item.recurrence.flatMap(Self.encodeRecurrence),
            createdAt: Iso8601.format(item.createdAt),
            updatedAt: Iso8601.format(item.updatedAt),
            isDeleted: item.isSoftDeleted,
            serverSeq: item.serverSeq,
            sortOrder: item.sortOrder
        )
    }

    /// Builds a clean (`dirty == false`) item. An undecodable `recurrence` string becomes nil
    /// rather than failing the whole row.
    public func makeItem() throws -> TodoItem {
        let parsed = try parse()
        return TodoItem(
            id: parsed.uuid,
            title: title,
            notes: notes,
            isDone: isDone,
            dueAt: parsed.due,
            recurrence: recurrence.flatMap(Self.decodeRecurrence),
            createdAt: parsed.created,
            updatedAt: parsed.updated,
            isSoftDeleted: isDeleted,
            dirty: false,
            serverSeq: serverSeq,
            sortOrder: sortOrder ?? 0
        )
    }

    /// Overwrites `item` with this row and marks it clean. Throws before touching `item` if the
    /// row is malformed, so a bad row never leaves a half-applied item behind.
    public func apply(to item: TodoItem) throws {
        let parsed = try parse()
        item.title = title
        item.notes = notes
        item.isDone = isDone
        item.dueAt = parsed.due
        item.recurrence = recurrence.flatMap(Self.decodeRecurrence)
        item.createdAt = parsed.created
        item.updatedAt = parsed.updated
        item.isSoftDeleted = isDeleted
        item.dirty = false
        item.serverSeq = serverSeq
        // A row with no order (old Worker, never-ordered) must not reset the local one.
        if let sortOrder { item.sortOrder = sortOrder }
    }

    private func parse() throws -> (uuid: UUID, created: Date, updated: Date, due: Date?) {
        guard let uuid = UUID(uuidString: id) else { throw WireError.invalidID(id) }
        guard let created = Iso8601.parse(createdAt) else {
            throw WireError.invalidDate(field: "createdAt", value: createdAt)
        }
        guard let updated = Iso8601.parse(updatedAt) else {
            throw WireError.invalidDate(field: "updatedAt", value: updatedAt)
        }
        var due: Date?
        if let dueAt {
            guard let parsedDue = Iso8601.parse(dueAt) else {
                throw WireError.invalidDate(field: "dueAt", value: dueAt)
            }
            due = parsedDue
        }
        return (uuid, created, updated, due)
    }

    private static func encodeRecurrence(_ rule: RecurrenceRule) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(rule)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func decodeRecurrence(_ json: String) -> RecurrenceRule? {
        try? JSONDecoder().decode(RecurrenceRule.self, from: Data(json.utf8))
    }
}
