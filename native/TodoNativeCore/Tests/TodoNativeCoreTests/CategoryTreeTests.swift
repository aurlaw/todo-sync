import Foundation
import Testing
@testable import TodoNativeCore

/// A category that exists only in memory: `CategoryTree` is pure, so no store is needed.
func category(
    _ name: String,
    id: UUID = UUID(),
    parent: UUID? = nil,
    order: Double = 0,
    deleted: Bool = false
) -> TodoCategory {
    TodoCategory(
        id: id, name: name, parentId: parent, sortOrder: order,
        createdAt: at(0), updatedAt: at(0), isSoftDeleted: deleted, dirty: false
    )
}

private func item(in categoryId: UUID?) -> TodoItem {
    TodoItem(title: "t", createdAt: at(0), updatedAt: at(0), categoryId: categoryId)
}

@Suite("CategoryTree")
struct CategoryTreeTests {
    @Test("a category under a live top-level parent is a subcategory")
    func subcategory() {
        let work = category("Work")
        let clients = category("Clients", parent: work.id)
        let tree = CategoryTree([clients, work])

        #expect(tree.topLevel.map(\.name) == ["Work"])
        #expect(tree.children(of: work.id).map(\.name) == ["Clients"])
        #expect(tree.isSubcategory(clients))
        #expect(!tree.isSubcategory(work))
        #expect(tree.parent(of: clients)?.id == work.id)
        #expect(tree.flattened.map(\.category.name) == ["Work", "Clients"])
        #expect(tree.flattened.map(\.isSubcategory) == [false, true])
    }

    @Test("an orphan whose parent was never seen is top-level")
    func missingParent() {
        let orphan = category("Orphan", parent: UUID())
        let tree = CategoryTree([orphan])
        #expect(tree.topLevel.map(\.name) == ["Orphan"])
        #expect(!tree.isSubcategory(orphan))
    }

    @Test("a category whose parent is deleted is top-level, and the deleted parent is gone")
    func deletedParent() {
        let work = category("Work", deleted: true)
        let clients = category("Clients", parent: work.id)
        let tree = CategoryTree([work, clients])

        #expect(tree.topLevel.map(\.name) == ["Clients"])
        #expect(tree.resolve(work.id) == nil)
        #expect(tree.children(of: work.id).isEmpty)
    }

    @Test("a subcategory of a subcategory is top-level")
    func subOfSub() {
        let work = category("Work", order: 0)
        let clients = category("Clients", parent: work.id)
        let acme = category("Acme", parent: clients.id, order: 1)
        let tree = CategoryTree([work, clients, acme])

        #expect(tree.topLevel.map(\.name) == ["Work", "Acme"])
        #expect(tree.children(of: work.id).map(\.name) == ["Clients"])
        #expect(tree.children(of: clients.id).isEmpty)
    }

    @Test("a two-device cycle shows both categories at the top level")
    func cycle() {
        let (aID, bID) = (UUID(), UUID())
        let a = category("A", id: aID, parent: bID, order: 0)
        let b = category("B", id: bID, parent: aID, order: 1)

        // The same answer whichever order the rows arrive in.
        for rows in [[a, b], [b, a]] {
            let tree = CategoryTree(rows)
            #expect(tree.topLevel.map(\.name) == ["A", "B"])
            #expect(tree.children(of: aID).isEmpty)
            #expect(tree.children(of: bID).isEmpty)
        }
    }

    @Test("siblings sort by sortOrder, then name, then id")
    func ordering() {
        let ids = [UUID(), UUID()].sorted { $0.uuidString < $1.uuidString }
        let tree = CategoryTree([
            category("Zed", order: 1),
            category("Same", id: ids[1], order: 2),
            category("Same", id: ids[0], order: 2),
            category("Beta", order: 2),
            category("Alpha", order: 0),
        ])
        #expect(tree.topLevel.map(\.name) == ["Alpha", "Zed", "Beta", "Same", "Same"])
        #expect(tree.topLevel.suffix(2).map(\.id) == ids)
    }

    @Test("scope is the category plus its subcategories for a parent, and just itself for a subcategory")
    func scope() {
        let work = category("Work")
        let clients = category("Clients", parent: work.id)
        let internalWork = category("Internal", parent: work.id)
        let home = category("Home")
        let tree = CategoryTree([work, clients, internalWork, home])

        #expect(tree.scope(of: work.id) == [work.id, clients.id, internalWork.id])
        #expect(tree.scope(of: clients.id) == [clients.id])
        #expect(tree.scope(of: home.id) == [home.id])
        #expect(tree.scope(of: UUID()).isEmpty)
    }

    @Test("an item whose category does not resolve belongs to Unassigned")
    func unresolvedIsUnassigned() {
        let work = category("Work")
        let gone = category("Gone", deleted: true)
        let tree = CategoryTree([work, gone])

        for categoryId in [nil, UUID(), gone.id] {
            let row = item(in: categoryId)
            #expect(tree.contains(row, in: .unassigned))
            #expect(!tree.contains(row, in: .category(work.id)))
        }
        #expect(!tree.contains(item(in: work.id), in: .unassigned))
        #expect(tree.contains(item(in: work.id), in: .category(work.id)))
    }

    @Test("parent candidates are live top-level categories other than the one being edited")
    func parentCandidates() {
        let work = category("Work", order: 0)
        let clients = category("Clients", parent: work.id)
        let home = category("Home", order: 1)
        let orphan = category("Orphan", parent: UUID(), order: 2)
        let tree = CategoryTree([work, clients, home, orphan])

        #expect(tree.parentCandidates(for: nil).map(\.name) == ["Work", "Home"])
        #expect(tree.parentCandidates(for: work).map(\.name) == ["Home"])
    }
}
