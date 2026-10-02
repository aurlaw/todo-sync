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
    /// A lowercase UUID, or nil for Unassigned. Always sent (see `encode(to:)`).
    public var categoryId: String? = nil
    /// Whether the `categoryId` key was there at all. A row from a Worker that predates N9a has no
    /// key, and that must not move a local item to Unassigned (see `apply(to:)`). Not on the wire.
    public var hasCategoryId: Bool = true

    enum CodingKeys: String, CodingKey {
        case id, title, notes, isDone, dueAt, recurrence, createdAt, updatedAt, isDeleted, serverSeq, sortOrder
        case categoryId
    }

    /// The Worker rejects a row as "invalid" if `notes`/`dueAt`/`recurrence` are omitted rather
    /// than `null`, and synthesized Codable omits nil optionals — so encode them explicitly.
    /// `categoryId` is always written too: the Worker keeps its stored value when the key is
    /// missing, so only an explicit `null` can move an item to Unassigned.
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
        try container.encode(categoryId, forKey: .categoryId)
    }
}

// In an extension so the memberwise initializer survives.
extension TodoWireDto {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            notes: try container.decodeIfPresent(String.self, forKey: .notes),
            isDone: try container.decode(Bool.self, forKey: .isDone),
            dueAt: try container.decodeIfPresent(String.self, forKey: .dueAt),
            recurrence: try container.decodeIfPresent(String.self, forKey: .recurrence),
            createdAt: try container.decode(String.self, forKey: .createdAt),
            updatedAt: try container.decode(String.self, forKey: .updatedAt),
            isDeleted: try container.decode(Bool.self, forKey: .isDeleted),
            serverSeq: try container.decodeIfPresent(Int64.self, forKey: .serverSeq),
            sortOrder: try container.decodeIfPresent(Double.self, forKey: .sortOrder),
            categoryId: try container.decodeIfPresent(String.self, forKey: .categoryId),
            hasCategoryId: container.contains(.categoryId)
        )
    }
}

/// The Worker's `CategoryDto`, camelCase. Ids and dates stay `String`s here;
/// `CategoryWireDto+TodoCategory.swift` converts them. No client predates categories, so every
/// field is required on push; `serverSeq` is ignored there.
public struct CategoryWireDto: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var parentId: String?
    public var color: String?
    public var sortOrder: Double
    public var createdAt: String
    public var updatedAt: String
    public var isDeleted: Bool
    public var serverSeq: Int64?

    enum CodingKeys: String, CodingKey {
        case id, name, parentId, color, sortOrder, createdAt, updatedAt, isDeleted, serverSeq
    }

    /// `parentId` and `color` must go out as explicit `null`: the Worker rejects a missing key.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(parentId, forKey: .parentId)
        try container.encode(color, forKey: .color)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encode(serverSeq, forKey: .serverSeq)
    }
}

public struct CategoryPushRequest: Codable, Sendable, Equatable {
    public var items: [CategoryWireDto]

    public init(items: [CategoryWireDto]) {
        self.items = items
    }
}

public struct CategoryChangesResponse: Codable, Sendable, Equatable {
    public var items: [CategoryWireDto]
    public var cursor: Int64
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
