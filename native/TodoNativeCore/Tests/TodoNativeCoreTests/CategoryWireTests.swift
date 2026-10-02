import Foundation
import Testing
@testable import TodoNativeCore

/// Swift replica of `isValidCategoryDto` in worker/src/categoryPush.ts.
private func workerAcceptsCategory(_ json: [String: Any]) -> Bool {
    func isNumber(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) != CFBooleanGetTypeID()
    }
    func isNullOr(_ value: Any?, _ check: (Any) -> Bool) -> Bool {
        guard let value else { return false }
        return value is NSNull || check(value)
    }
    return isLowercaseUUID(json["id"])
        && !((json["name"] as? String)?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        && isNullOr(json["parentId"]) { isLowercaseUUID($0) }
        && isNullOr(json["color"]) { ($0 as? String)?.wholeMatch(of: /#[0-9a-f]{6}/) != nil }
        && isNumber(json["sortOrder"])
        && json["createdAt"] is String
        && json["updatedAt"] is String
        && json["isDeleted"] is Bool
}

@Suite("Todo categoryId on the wire")
struct TodoCategoryWireTests {
    private let json = """
        {"id":"3f2b8c1e-9a4d-4e7b-8c55-1d2e3f4a5b6c","title":"t","notes":null,"isDone":false,"dueAt":null,
         "recurrence":null,"createdAt":"2026-09-13T15:04:05.0000000+00:00",
         "updatedAt":"2026-09-13T15:04:05.0000000+00:00","isDeleted":false,"serverSeq":1,"sortOrder":0%@}
        """

    private func decode(_ categoryField: String) throws -> TodoWireDto {
        try JSONDecoder().decode(TodoWireDto.self, from: Data(json.replacingOccurrences(of: "%@", with: categoryField).utf8))
    }

    @Test("categoryId is always encoded: a lowercase id when set, an explicit null for Unassigned")
    func alwaysEncoded() throws {
        let categoryID = UUID(uuidString: "C0FFEE00-9A4D-4E7B-8C55-1D2E3F4A5B6C")!
        let filed = TodoItem(title: "x", createdAt: at(0), updatedAt: at(0), categoryId: categoryID)
        let unassigned = TodoItem(title: "y", createdAt: at(0), updatedAt: at(0))

        let filedJSON = try jsonObject(TodoWireDto(filed))
        #expect(filedJSON["categoryId"] as? String == "c0ffee00-9a4d-4e7b-8c55-1d2e3f4a5b6c")
        #expect(workerAcceptsPushItem(filedJSON))

        let unassignedJSON = try jsonObject(TodoWireDto(unassigned))
        #expect(unassignedJSON.keys.contains("categoryId"))
        #expect(unassignedJSON["categoryId"] is NSNull)
        #expect(workerAcceptsPushItem(unassignedJSON))
    }

    @Test("a row with no categoryId key leaves the local category alone on apply")
    func missingKeyKeepsLocal() throws {
        let dto = try decode("")
        #expect(dto.hasCategoryId == false)
        #expect(dto.categoryId == nil)
        #expect(try dto.makeItem().categoryId == nil)

        let localCategory = UUID()
        let local = try dto.makeItem()
        local.categoryId = localCategory
        try dto.apply(to: local)
        #expect(local.categoryId == localCategory)
    }

    @Test("an explicit null moves the local item to Unassigned, and an id files it")
    func presentKeyApplies() throws {
        let nullDto = try decode(#","categoryId":null"#)
        #expect(nullDto.hasCategoryId)
        let local = try nullDto.makeItem()
        local.categoryId = UUID()
        try nullDto.apply(to: local)
        #expect(local.categoryId == nil)

        let filedDto = try decode(#","categoryId":"c0ffee00-9a4d-4e7b-8c55-1d2e3f4a5b6c""#)
        let expected = UUID(uuidString: "c0ffee00-9a4d-4e7b-8c55-1d2e3f4a5b6c")
        #expect(try filedDto.makeItem().categoryId == expected)
        try filedDto.apply(to: local)
        #expect(local.categoryId == expected)
    }

    @Test("a malformed categoryId fails the row before anything is applied")
    func malformed() throws {
        let dto = try decode(#","categoryId":"work""#)
        #expect(throws: WireError.invalidID("work")) { try dto.makeItem() }

        let local = TodoItem(title: "keep", createdAt: at(0), updatedAt: at(0))
        #expect(throws: WireError.invalidID("work")) { try dto.apply(to: local) }
        #expect(local.title == "keep")
    }
}

@Suite("CategoryWireDto")
struct CategoryWireDtoTests {
    @Test("encodes exactly its nine keys, with explicit nulls and lowercase ids")
    func encodesExactKeys() throws {
        let top = TodoCategory(
            id: UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001")!,
            name: "Work", sortOrder: 1.5, createdAt: at(0), updatedAt: at(1)
        )
        let json = try jsonObject(CategoryWireDto(top))

        #expect(Set(json.keys) == [
            "id", "name", "parentId", "color", "sortOrder", "createdAt", "updatedAt", "isDeleted", "serverSeq",
        ])
        #expect(json["id"] as? String == "aaaaaaaa-0000-4000-8000-000000000001")
        #expect(json["parentId"] is NSNull)
        #expect(json["color"] is NSNull)
        #expect(json["serverSeq"] is NSNull)
        #expect(json["sortOrder"] as? Double == 1.5)
        #expect(json["isDeleted"] as? Bool == false)
        #expect(workerAcceptsCategory(json))
        try expectSameInstant(json["updatedAt"] as? String, Iso8601.format(at(1)))
    }

    @Test("a subcategory sends its parent id lowercase and its colour as stored")
    func subcategory() throws {
        let sub = TodoCategory(
            name: "Clients",
            parentId: UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001")!,
            color: "#1a2b3c", createdAt: at(0), updatedAt: at(0), isSoftDeleted: true
        )
        let json = try jsonObject(CategoryWireDto(sub))

        #expect(json["parentId"] as? String == "aaaaaaaa-0000-4000-8000-000000000001")
        #expect(json["color"] as? String == "#1a2b3c")
        #expect(json["isDeleted"] as? Bool == true)
        #expect(isLowercaseUUID(json["id"]))
        #expect(workerAcceptsCategory(json))
    }

    @Test("decodes a /categories/changes payload and maps it to clean categories")
    func decodesChanges() throws {
        let response = try JSONDecoder().decode(CategoryChangesResponse.self, from: fixtureData("category-changes-response"))
        #expect(response.cursor == 6)
        #expect(response.items.count == 2)

        let work = try response.items[0].makeCategory()
        #expect(work.id == UUID(uuidString: "a0000000-0000-4000-8000-000000000001"))
        #expect(work.name == "Work")
        #expect(work.parentId == nil)
        #expect(work.color == "#1a2b3c")
        #expect(work.sortOrder == 0)
        #expect(work.isSoftDeleted == false)
        #expect(work.dirty == false)
        #expect(work.serverSeq == 4)

        let clients = try response.items[1].makeCategory()
        #expect(clients.parentId == work.id)
        #expect(clients.color == nil)
        #expect(clients.sortOrder == 2.5)
        #expect(clients.isSoftDeleted)
        #expect(clients.serverSeq == 6)
    }

    @Test("a pulled row maps to a category and back without changing anything the Worker checks")
    func roundTrip() throws {
        let response = try JSONDecoder().decode(CategoryChangesResponse.self, from: fixtureData("category-changes-response"))
        for original in response.items {
            let back = CategoryWireDto(try original.makeCategory())
            #expect(back.id == original.id)
            #expect(back.name == original.name)
            #expect(back.parentId == original.parentId)
            #expect(back.color == original.color)
            #expect(back.sortOrder == original.sortOrder)
            #expect(back.isDeleted == original.isDeleted)
            #expect(back.serverSeq == original.serverSeq)
            try expectSameInstant(back.createdAt, original.createdAt)
            try expectSameInstant(back.updatedAt, original.updatedAt)
            #expect(workerAcceptsCategory(try jsonObject(back)))
        }
    }

    @Test("apply overwrites every field and marks the category clean")
    func apply() throws {
        let local = TodoCategory(name: "Old", color: "#000000", createdAt: at(0), updatedAt: at(0), dirty: true)
        let parent = UUID()
        let dto = categoryWire(id: local.id, name: "New", parentId: parent, color: nil, sortOrder: 3,
                               updatedAt: at(9), isDeleted: true, serverSeq: 12)
        try dto.apply(to: local)

        #expect(local.name == "New")
        #expect(local.parentId == parent)
        #expect(local.color == nil)
        #expect(local.sortOrder == 3)
        #expect(local.isSoftDeleted)
        #expect(local.dirty == false)
        #expect(local.serverSeq == 12)
        #expect(abs(local.updatedAt.timeIntervalSince(at(9))) < 1e-6)
    }

    @Test("a bad id, parent id or date fails the row before anything is applied")
    func malformed() throws {
        var dto = categoryWire(updatedAt: at(1))
        dto.parentId = "nope"
        #expect(throws: WireError.invalidID("nope")) { try dto.makeCategory() }

        let local = TodoCategory(name: "keep", createdAt: at(0), updatedAt: at(0))
        #expect(throws: WireError.invalidID("nope")) { try dto.apply(to: local) }
        #expect(local.name == "keep")

        dto.parentId = nil
        dto.updatedAt = "yesterday"
        #expect(throws: WireError.invalidDate(field: "updatedAt", value: "yesterday")) { try dto.makeCategory() }
        dto.id = "also nope"
        #expect(throws: WireError.invalidID("also nope")) { try dto.makeCategory() }
    }
}
