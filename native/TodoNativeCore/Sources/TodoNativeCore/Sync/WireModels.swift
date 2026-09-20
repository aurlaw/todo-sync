import Foundation

/// The Worker's `TodoDto` (worker/src/types.ts), camelCase. Ids and dates stay `String`s here;
/// `TodoWireDto+TodoItem.swift` converts them. `recurrence` is a JSON string, not an object.
public struct TodoWireDto: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var notes: String?
    public var isDone: Bool
    public var dueAt: String?
    public var recurrence: String?
    public var createdAt: String
    public var updatedAt: String
    public var isDeleted: Bool
    public var serverSeq: Int64?
    /// Optional on the wire: rows the Worker never had an order for, or from a Worker that predates
    /// N8, omit it. A nil never resets a local order (see `apply(to:)`).
    public var sortOrder: Double? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, notes, isDone, dueAt, recurrence, createdAt, updatedAt, isDeleted, serverSeq, sortOrder
    }

    /// The Worker rejects a row as "invalid" if `notes`/`dueAt`/`recurrence` are omitted rather
    /// than `null`, and synthesized Codable omits nil optionals — so encode them explicitly.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(isDone, forKey: .isDone)
        try container.encode(dueAt, forKey: .dueAt)
        try container.encode(recurrence, forKey: .recurrence)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encode(serverSeq, forKey: .serverSeq)
        try container.encode(sortOrder, forKey: .sortOrder)
    }
}

public struct PushRequest: Codable, Sendable, Equatable {
    public var items: [TodoWireDto]

    public init(items: [TodoWireDto]) {
        self.items = items
    }
}

public struct PushResponse: Codable, Sendable, Equatable {
    public struct Applied: Codable, Sendable, Equatable {
        public var id: String
        public var serverSeq: Int64
    }

    /// `id` is a plain String: the Worker reports the literal "unknown" for a malformed item.
    public struct Rejected: Codable, Sendable, Equatable {
        public var id: String
        public var reason: String
    }

    public var applied: [Applied]
    public var rejected: [Rejected]
}

public struct ChangesResponse: Codable, Sendable, Equatable {
    public var items: [TodoWireDto]
    public var cursor: Int64
}
