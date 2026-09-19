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
            serverSeq: item.serverSeq
        )
    }

    /// Builds a clean (`dirty == false`) item. An undecodable `recurrence` string becomes nil
    /// rather than failing the whole row.
    public func makeItem() throws -> TodoItem {
        guard let uuid = UUID(uuidString: id) else { throw WireError.invalidID(id) }
        guard let created = Iso8601.parse(createdAt) else {
            throw WireError.invalidDate(field: "createdAt", value: createdAt)
        }
        guard let updated = Iso8601.parse(updatedAt) else {
            throw WireError.invalidDate(field: "updatedAt", value: updatedAt)
        }
        var due: Date?
        if let dueAt {
            guard let parsed = Iso8601.parse(dueAt) else {
                throw WireError.invalidDate(field: "dueAt", value: dueAt)
            }
            due = parsed
        }

        return TodoItem(
            id: uuid,
            title: title,
            notes: notes,
            isDone: isDone,
            dueAt: due,
            recurrence: recurrence.flatMap(Self.decodeRecurrence),
            createdAt: created,
            updatedAt: updated,
            isSoftDeleted: isDeleted,
            dirty: false,
            serverSeq: serverSeq
        )
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
