import Foundation
import Testing
@testable import TodoNativeCore

func fixtureData(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

/// Swift replica of `isValidTodoDto` in worker/src/push.ts — a row failing this is rejected "invalid".
func workerAcceptsPushItem(_ json: [String: Any]) -> Bool {
    func isNullOrString(_ key: String) -> Bool {
        guard let value = json[key] else { return false }
        return value is NSNull || value is String
    }
    return json["id"] is String
        && json["title"] is String
        && isNullOrString("notes")
        && json["isDone"] is Bool
        && isNullOrString("dueAt")
        && isNullOrString("recurrence")
        && json["createdAt"] is String
        && json["updatedAt"] is String
        && json["isDeleted"] is Bool
        && isMissingNullOrNumber("sortOrder")

    func isMissingNullOrNumber(_ key: String) -> Bool {
        guard let value = json[key] else { return true }
        if value is NSNull { return true }
        // `NSNumber(0) is Bool` is true in Swift, so tell a JSON boolean from a number by CF type.
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) != CFBooleanGetTypeID()
    }
}

func jsonObject(_ dto: TodoWireDto) throws -> [String: Any] {
    let data = try JSONEncoder().encode(dto)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Suite("Wire models")
struct WireModelsTests {
    @Test("decodes a /changes response")
    func decodesChanges() throws {
        let response = try JSONDecoder().decode(ChangesResponse.self, from: fixtureData("changes-response"))
        #expect(response.cursor == 3)
        #expect(response.items.count == 3)
        #expect(response.items[0].title == "Buy milk")
        #expect(response.items[0].notes == nil)
        #expect(response.items[1].isDeleted)
        #expect(response.items[2].recurrence == #"{"daysOfWeek":[2,4],"frequency":"weekly","interval":1}"#)
    }

    @Test("an empty /changes response keeps the cursor")
    func decodesEmptyChanges() throws {
        let response = try JSONDecoder().decode(ChangesResponse.self, from: fixtureData("changes-empty"))
        #expect(response.items.isEmpty)
        #expect(response.cursor == 42)
    }

    @Test("decodes a /push response, including the literal \"unknown\" rejected id")
    func decodesPushResponse() throws {
        let response = try JSONDecoder().decode(PushResponse.self, from: fixtureData("push-response"))
        #expect(response.applied == [.init(id: "3f2b8c1e-9a4d-4e7b-8c55-1d2e3f4a5b6c", serverSeq: 7)])
        #expect(response.rejected.map(\.reason) == ["stale", "invalid"])
        #expect(response.rejected.last?.id == "unknown")
    }

    @Test("encodes exactly the eleven camelCase keys, with explicit nulls and no dirty")
    func encodesExactKeysWithNulls() throws {
        let item = TodoItem(
            title: "Buy milk",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            sortOrder: -2.5
        )
        let json = try jsonObject(TodoWireDto(item))

        #expect(Set(json.keys) == [
            "id", "title", "notes", "isDone", "dueAt", "recurrence",
            "createdAt", "updatedAt", "isDeleted", "serverSeq", "sortOrder",
        ])
        #expect(json["notes"] is NSNull)
        #expect(json["dueAt"] is NSNull)
        #expect(json["recurrence"] is NSNull)
        #expect(json["serverSeq"] is NSNull)
        #expect(json["sortOrder"] as? Double == -2.5)
        #expect(workerAcceptsPushItem(json))
    }

    @Test("a row without sortOrder decodes to nil, maps to 0, and never resets a local order on apply")
    func missingSortOrder() throws {
        let response = try JSONDecoder().decode(ChangesResponse.self, from: fixtureData("changes-response"))
        let dto = try #require(response.items.first)
        #expect(dto.sortOrder == nil)
        #expect(try dto.makeItem().sortOrder == 0)

        let local = try dto.makeItem()
        local.sortOrder = 4
        try dto.apply(to: local)
        #expect(local.sortOrder == 4)
    }

    @Test("an incoming sortOrder, including 0, replaces the local one")
    func incomingSortOrderApplies() throws {
        var dto = wire(updatedAt: at(1))
        let local = try dto.makeItem()
        local.sortOrder = 4

        dto.sortOrder = 9
        try dto.apply(to: local)
        #expect(local.sortOrder == 9)

        dto.sortOrder = 0
        try dto.apply(to: local)
        #expect(local.sortOrder == 0)
    }

    @Test("every fixture row survives the Worker's validity check after a round trip")
    func fixtureRowsPassWorkerValidation() throws {
        let response = try JSONDecoder().decode(ChangesResponse.self, from: fixtureData("changes-response"))
        for dto in response.items {
            let item = try dto.makeItem()
            #expect(workerAcceptsPushItem(try jsonObject(TodoWireDto(item))))
        }
    }

    @Test("ids go out lowercase even though UUID.uuidString is uppercase")
    func idsAreLowercase() {
        let item = TodoItem(
            id: UUID(uuidString: "3F2B8C1E-9A4D-4E7B-8C55-1D2E3F4A5B6C")!,
            title: "x",
            createdAt: .now,
            updatedAt: .now
        )
        #expect(TodoWireDto(item).id == "3f2b8c1e-9a4d-4e7b-8c55-1d2e3f4a5b6c")
    }

    @Test("a pulled row maps to a clean item and back without changing its id or fields")
    func mappingRoundTrip() throws {
        let response = try JSONDecoder().decode(ChangesResponse.self, from: fixtureData("changes-response"))
        for original in response.items {
            let item = try original.makeItem()
            #expect(item.dirty == false)
            #expect(item.serverSeq == original.serverSeq)

            let back = TodoWireDto(item)
            #expect(back.id == original.id)
            #expect(back.title == original.title)
            #expect(back.notes == original.notes)
            #expect(back.isDone == original.isDone)
            #expect(back.isDeleted == original.isDeleted)
            #expect(back.recurrence == original.recurrence)
            #expect(back.serverSeq == original.serverSeq)
            try expectSameInstant(back.createdAt, original.createdAt)
            try expectSameInstant(back.updatedAt, original.updatedAt)
            try expectSameInstant(back.dueAt, original.dueAt)
        }
    }

    @Test("makeItem throws on a bad id or date")
    func makeItemThrows() {
        var dto = TodoWireDto(id: "nope", title: "x", notes: nil, isDone: false, dueAt: nil, recurrence: nil,
                              createdAt: "2026-09-13T15:04:05.0000000+00:00",
                              updatedAt: "2026-09-13T15:04:05.0000000+00:00", isDeleted: false, serverSeq: nil)
        #expect(throws: WireError.invalidID("nope")) { try dto.makeItem() }

        dto.id = "3f2b8c1e-9a4d-4e7b-8c55-1d2e3f4a5b6c"
        dto.updatedAt = "yesterday"
        #expect(throws: WireError.invalidDate(field: "updatedAt", value: "yesterday")) { try dto.makeItem() }
    }
}

@Suite("Recurrence on the wire")
struct RecurrenceWireTests {
    private func dto(recurrence: RecurrenceRule?) -> TodoWireDto {
        TodoWireDto(TodoItem(title: "x", recurrence: recurrence, createdAt: .now, updatedAt: .now))
    }

    @Test("encodes to a deterministic JSON string with sorted days")
    func encodesSorted() {
        let rule = RecurrenceRule(frequency: .weekly, interval: 2, daysOfWeek: [7, 1, 4])
        #expect(dto(recurrence: rule).recurrence == #"{"daysOfWeek":[1,4,7],"frequency":"weekly","interval":2}"#)
        #expect(dto(recurrence: RecurrenceRule(frequency: .daily)).recurrence == #"{"frequency":"daily","interval":1}"#)
    }

    @Test("decodes back to the same rule")
    func decodes() throws {
        let rule = RecurrenceRule(frequency: .weekly, interval: 2, daysOfWeek: [1, 7])
        let item = try dto(recurrence: rule).makeItem()
        #expect(item.recurrence == rule)
    }

    @Test("an undecodable recurrence string becomes nil instead of failing the row")
    func garbageBecomesNil() throws {
        var wire = dto(recurrence: nil)
        wire.recurrence = #"{"Frequency":1,"Interval":1,"DaysOfWeek":null}"#
        #expect(try wire.makeItem().recurrence == nil)
        wire.recurrence = "not json"
        #expect(try wire.makeItem().recurrence == nil)
    }
}

func expectSameInstant(_ lhs: String?, _ rhs: String?, sourceLocation: SourceLocation = #_sourceLocation) throws {
    guard let lhs, let rhs else {
        #expect(lhs == rhs, sourceLocation: sourceLocation)
        return
    }
    let left = try #require(Iso8601.parse(lhs), sourceLocation: sourceLocation)
    let right = try #require(Iso8601.parse(rhs), sourceLocation: sourceLocation)
    #expect(abs(left.timeIntervalSince(right)) < 2e-7, "\(lhs) vs \(rhs)", sourceLocation: sourceLocation)
    #expect(
        lhs.wholeMatch(of: /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}\+00:00/) != nil,
        "\(lhs) is not in the .NET \"O\" shape",
        sourceLocation: sourceLocation
    )
}
