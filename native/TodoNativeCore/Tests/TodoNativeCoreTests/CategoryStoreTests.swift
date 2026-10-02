import Foundation
import SwiftData
import Testing
@testable import TodoNativeCore

@MainActor
private final class Rig {
    let context: ModelContext
    private let clock = AdjustableClock()
    private(set) var mutations = 0

    init() throws {
        context = ModelContext(try TodoContainer.make(inMemory: true))
    }

    var store: TodoStore {
        TodoStore(context: context, clock: clock, onMutation: { [unowned self] in mutations += 1 })
    }

    func advance(to seconds: TimeInterval) { clock.date = at(seconds) }

    /// Marks every row clean, so the next write shows exactly which rows it touched.
    func settle() throws {
        for category in try context.fetch(FetchDescriptor<TodoCategory>()) { category.dirty = false }
        for item in try context.fetch(FetchDescriptor<TodoItem>()) { item.dirty = false }
        try context.save()
        mutations = 0
    }

    var tree: CategoryTree {
        get throws { try store.categoryTree() }
    }

    func topLevel() throws -> [String] { try tree.topLevel.map(\.name) }
    func children(of category: TodoCategory) throws -> [String] { try tree.children(of: category.id).map(\.name) }
}

@Suite("Category store: create and rename")
struct CategoryCreateTests {
    @Test("create trims the name, appends to the end of its siblings, and writes a dirty stamped row")
    @MainActor
    func create() throws {
        let rig = try Rig()
        rig.advance(to: 5)
        let work = try rig.store.createCategory(name: "  Work \n", color: "#AABBCC")
        let home = try rig.store.createCategory(name: "Home")
        let clients = try rig.store.createCategory(name: "Clients", parentId: work.id)
        let internalWork = try rig.store.createCategory(name: "Internal", parentId: work.id)

        #expect(work.name == "Work")
        #expect(work.color == "#aabbcc")
        #expect(work.dirty && work.updatedAt == at(5) && work.createdAt == at(5))
        #expect([work.sortOrder, home.sortOrder] == [0, 1])
        #expect([clients.sortOrder, internalWork.sortOrder] == [0, 1])
        #expect(clients.parentId == work.id)
        #expect(try rig.topLevel() == ["Work", "Home"])
        #expect(try rig.children(of: work) == ["Clients", "Internal"])
        #expect(rig.mutations == 4)
    }

    @Test("an empty name, a bad colour, and a parent that is not a live top-level category are refused")
    @MainActor
    func createRejections() throws {
        let rig = try Rig()
        let work = try rig.store.createCategory(name: "Work")
        let clients = try rig.store.createCategory(name: "Clients", parentId: work.id)
        let gone = try rig.store.createCategory(name: "Gone")
        try rig.store.deleteCategory(gone)
        try rig.settle()

        #expect(throws: CategoryError.emptyName) { try rig.store.createCategory(name: "  \n ") }
        #expect(throws: CategoryError.invalidColor("blue")) { try rig.store.createCategory(name: "X", color: "blue") }
        #expect(throws: CategoryError.invalidParent) { try rig.store.createCategory(name: "X", parentId: clients.id) }
        #expect(throws: CategoryError.invalidParent) { try rig.store.createCategory(name: "X", parentId: gone.id) }
        #expect(throws: CategoryError.invalidParent) { try rig.store.createCategory(name: "X", parentId: UUID()) }

        #expect(try rig.context.fetchCount(FetchDescriptor<TodoCategory>()) == 3)
        #expect(rig.mutations == 0)
    }

    @Test("names are unique among live siblings ignoring case, but may repeat under different parents")
    @MainActor
    func siblingNames() throws {
        let rig = try Rig()
        let work = try rig.store.createCategory(name: "Work")
        let home = try rig.store.createCategory(name: "Home")
        try rig.store.createCategory(name: "Clients", parentId: work.id)

        #expect(throws: CategoryError.duplicateName("work")) { try rig.store.createCategory(name: " work ") }
        #expect(throws: CategoryError.duplicateName("CLIENTS")) {
            try rig.store.createCategory(name: "CLIENTS", parentId: work.id)
        }
        // The same name under another parent, and at the top level, is a different sibling group.
        try rig.store.createCategory(name: "Clients", parentId: home.id)
        try rig.store.createCategory(name: "Clients")

        // A deleted sibling no longer blocks its name.
        try rig.store.deleteCategory(home)
        try rig.store.createCategory(name: "Home")
        #expect(try rig.topLevel().filter { $0 == "Home" }.count == 1)
    }

    @Test("rename trims, checks siblings, and lets a category keep or re-case its own name")
    @MainActor
    func rename() throws {
        let rig = try Rig()
        let work = try rig.store.createCategory(name: "Work")
        try rig.store.createCategory(name: "Home")
        try rig.settle()

        #expect(throws: CategoryError.duplicateName("home")) { try rig.store.renameCategory(work, to: "home") }
        #expect(throws: CategoryError.emptyName) { try rig.store.renameCategory(work, to: " ") }
        #expect(work.name == "Work" && !work.dirty)

        rig.advance(to: 9)
        try rig.store.renameCategory(work, to: "  WORK ")
        #expect(work.name == "WORK")
        #expect(work.dirty && work.updatedAt == at(9))
        #expect(rig.mutations == 1)

        // An unchanged name is not a write.
        try rig.settle()
        try rig.store.renameCategory(work, to: "WORK")
        #expect(!work.dirty && rig.mutations == 0)
    }

    @Test("the colour is stored lowercase, can be cleared, and a bad value changes nothing")
    @MainActor
    func color() throws {
        let rig = try Rig()
        let work = try rig.store.createCategory(name: "Work")
        try rig.settle()

        rig.advance(to: 3)
        try rig.store.setCategoryColor(work, "#0A84FF")
        #expect(work.color == "#0a84ff")
        #expect(work.dirty && work.updatedAt == at(3))

        #expect(throws: CategoryError.invalidColor("#12")) { try rig.store.setCategoryColor(work, "#12") }
        #expect(work.color == "#0a84ff")

        try rig.store.setCategoryColor(work, nil)
        #expect(work.color == nil)
    }
}

@Suite("Category store: parent")
struct CategoryParentTests {
    @Test("moving under a parent, and back to the top level, lands at the end of the new siblings")
    @MainActor
    func move() throws {
        let rig = try Rig()
        let work = try rig.store.createCategory(name: "Work")
        let home = try rig.store.createCategory(name: "Home")
        let errands = try rig.store.createCategory(name: "Errands")
        try rig.store.createCategory(name: "Clients", parentId: work.id)
        try rig.settle()

        rig.advance(to: 4)
        try rig.store.setCategoryParent(errands, to: work.id)
        #expect(try rig.topLevel() == ["Work", "Home"])
        #expect(try rig.children(of: work) == ["Clients", "Errands"])
        #expect(errands.dirty && errands.updatedAt == at(4))
        #expect(!work.dirty && !home.dirty)

        try rig.store.setCategoryParent(errands, to: nil)
        #expect(try rig.topLevel() == ["Work", "Home", "Errands"])
        #expect(errands.parentId == nil)
    }

    @Test("refused: a category with subcategories, a target that is a subcategory, and itself")
    @MainActor
    func rejections() throws {
        let rig = try Rig()
        let work = try rig.store.createCategory(name: "Work")
        let home = try rig.store.createCategory(name: "Home")
        let clients = try rig.store.createCategory(name: "Clients", parentId: work.id)
        let errands = try rig.store.createCategory(name: "Errands")
        try rig.settle()

        #expect(throws: CategoryError.hasSubcategories) { try rig.store.setCategoryParent(work, to: home.id) }
        #expect(throws: CategoryError.invalidParent) { try rig.store.setCategoryParent(errands, to: clients.id) }
        #expect(throws: CategoryError.parentIsSelf) { try rig.store.setCategoryParent(errands, to: errands.id) }
        #expect(throws: CategoryError.invalidParent) { try rig.store.setCategoryParent(errands, to: UUID()) }

        #expect(try rig.topLevel() == ["Work", "Home", "Errands"])
        #expect(try rig.children(of: work) == ["Clients"])
        #expect(rig.mutations == 0)
        #expect(try rig.context.fetch(FetchDescriptor<TodoCategory>()).allSatisfy { !$0.dirty })
    }

    @Test("the sibling-name rule is re-checked in the new parent")
    @MainActor
    func nameClashInNewParent() throws {
        let rig = try Rig()
        let work = try rig.store.createCategory(name: "Work")
        try rig.store.createCategory(name: "Clients", parentId: work.id)
        let topClients = try rig.store.createCategory(name: "clients")

        #expect(throws: CategoryError.duplicateName("clients")) { try rig.store.setCategoryParent(topClients, to: work.id) }
        #expect(topClients.parentId == nil)
    }

    @Test("one editor save applies name, parent and colour together, or nothing at all")
    @MainActor
    func updateIsAtomic() throws {
        let rig = try Rig()
        let work = try rig.store.createCategory(name: "Work")
        let errands = try rig.store.createCategory(name: "Errands")
        try rig.settle()

        #expect(throws: CategoryError.invalidColor("nope")) {
            try rig.store.updateCategory(errands, name: "Chores", parentId: work.id, color: "nope")
        }
        #expect(errands.name == "Errands" && errands.parentId == nil && !errands.dirty)

        rig.advance(to: 6)
        try rig.store.updateCategory(errands, name: "Chores", parentId: work.id, color: "#112233")
        #expect(errands.name == "Chores" && errands.parentId == work.id && errands.color == "#112233")
        #expect(errands.updatedAt == at(6))
        #expect(rig.mutations == 1)
    }

    @Test("editing a category shown at the top level only because its parent is gone settles its parentId")
    @MainActor
    func settlesOrphan() throws {
        let rig = try Rig()
        let orphan = category("Orphan", parent: UUID())
        rig.context.insert(orphan)
        try rig.context.save()

        try rig.store.renameCategory(orphan, to: "Found")
        #expect(orphan.parentId == nil)
        #expect(orphan.dirty)
    }
}

@Suite("Category store: ordering")
struct CategoryOrderingTests {
    @MainActor
    private func seeded() throws -> (rig: Rig, work: TodoCategory) {
        let rig = try Rig()
        let work = try rig.store.createCategory(name: "Work")
        try rig.store.createCategory(name: "Home")
        try rig.store.createCategory(name: "Errands")
        try rig.store.createCategory(name: "Clients", parentId: work.id)
        try rig.store.createCategory(name: "Internal", parentId: work.id)
        try rig.store.createCategory(name: "Admin", parentId: work.id)
        try rig.settle()
        return (rig, work)
    }

    @Test("a move reorders one sibling group, dirties only the moved row, and leaves other groups alone")
    @MainActor
    func moveWithinGroup() throws {
        let (rig, work) = try seeded()
        rig.advance(to: 7)

        try rig.store.moveCategory(fromOffsets: [2], toOffset: 0, in: try rig.tree.topLevel)
        #expect(try rig.topLevel() == ["Errands", "Work", "Home"])
        #expect(try rig.children(of: work) == ["Clients", "Internal", "Admin"])

        let all = try rig.context.fetch(FetchDescriptor<TodoCategory>())
        #expect(all.filter(\.dirty).map(\.name) == ["Errands"])
        #expect(all.first { $0.name == "Errands" }?.updatedAt == at(7))
        #expect(rig.mutations == 1)

        try rig.store.moveCategory(fromOffsets: [0], toOffset: 3, in: try rig.tree.children(of: work.id))
        #expect(try rig.children(of: work) == ["Internal", "Admin", "Clients"])
        #expect(try rig.topLevel() == ["Errands", "Work", "Home"])
    }

    @Test("placing between two siblings takes the midpoint")
    @MainActor
    func moveBetween() throws {
        let (rig, work) = try seeded()
        let subs = try rig.tree.children(of: work.id)

        try rig.store.moveCategory(subs[2], between: subs[0], and: subs[1])
        #expect(subs[2].sortOrder == 0.5)
        #expect(try rig.children(of: work) == ["Clients", "Admin", "Internal"])
    }

    @Test("renormalize respaces one sibling group at integer steps, touching only rows that change")
    @MainActor
    func renormalize() throws {
        let (rig, work) = try seeded()
        let subs = try rig.tree.children(of: work.id)
        try rig.store.moveCategory(subs[2], between: subs[0], and: subs[1])
        let topBefore = try rig.tree.topLevel.map(\.sortOrder)
        try rig.settle()
        rig.advance(to: 8)

        try rig.store.renormalizeCategories(parentId: work.id)

        let after = try rig.tree.children(of: work.id)
        #expect(after.map(\.name) == ["Clients", "Admin", "Internal"])
        #expect(after.map(\.sortOrder) == [0, 1, 2])
        #expect(after.map(\.dirty) == [false, true, true])
        #expect(try rig.tree.topLevel.map(\.sortOrder) == topBefore)
        #expect(try rig.tree.topLevel.allSatisfy { !$0.dirty })
    }

    @Test("a gap too small to split respaces the group first, and the move still lands in place")
    @MainActor
    func tinyGap() throws {
        let rig = try Rig()
        for (name, order) in [("a", 0.0), ("b", 1e-7), ("c", 5.0)] {
            rig.context.insert(category(name, order: order))
        }
        try rig.context.save()
        let top = try rig.tree.topLevel

        try rig.store.moveCategory(top[2], between: top[0], and: top[1])
        #expect(try rig.topLevel() == ["a", "c", "b"])
        let orders = try rig.tree.topLevel.map(\.sortOrder)
        #expect(orders[1] - orders[0] > TodoStore.minimumGap && orders[2] - orders[1] > TodoStore.minimumGap)
    }
}

@Suite("Category store: delete")
struct CategoryDeleteTests {
    @Test("deleting a leaf moves its items to Unassigned in one stamped batch")
    @MainActor
    func deleteLeaf() throws {
        let rig = try Rig()
        let work = try rig.store.createCategory(name: "Work")
        let home = try rig.store.createCategory(name: "Home")
        let first = try rig.store.create(title: "one", categoryId: work.id)
        let second = try rig.store.create(title: "two", categoryId: work.id)
        let other = try rig.store.create(title: "elsewhere", categoryId: home.id)
        let removed = try rig.store.create(title: "already deleted", categoryId: work.id)
        try rig.store.softDelete(removed)
        try rig.settle()

        #expect(try rig.store.deletionImpact(of: work) == (0, 2))
        rig.advance(to: 12)
        try rig.store.deleteCategory(work)

        #expect(work.isSoftDeleted && work.dirty && work.updatedAt == at(12))
        for item in [first, second] {
            #expect(item.categoryId == nil)
            #expect(item.dirty && item.updatedAt == at(12))
        }
        #expect(other.categoryId == home.id && !other.dirty)
        #expect(removed.categoryId == work.id && !removed.dirty)
        #expect(!home.dirty)
        #expect(try rig.topLevel() == ["Home"])
        #expect(rig.mutations == 1)
    }

    @Test("deleting a parent promotes its subcategories into its slot, in order, and leaves their items alone")
    @MainActor
    func deleteParent() throws {
        let rig = try Rig()
        let home = try rig.store.createCategory(name: "Home")
        let work = try rig.store.createCategory(name: "Work")
        let errands = try rig.store.createCategory(name: "Errands")
        let clients = try rig.store.createCategory(name: "Clients", parentId: work.id, color: "#112233")
        let internalWork = try rig.store.createCategory(name: "Internal", parentId: work.id)
        let own = try rig.store.create(title: "work's own", categoryId: work.id)
        let subItem = try rig.store.create(title: "in clients", categoryId: clients.id)
        try rig.settle()

        #expect(try rig.store.deletionImpact(of: work) == (2, 1))
        rig.advance(to: 20)
        try rig.store.deleteCategory(work)

        #expect(try rig.topLevel() == ["Home", "Clients", "Internal", "Errands"])
        for sub in [clients, internalWork] {
            #expect(sub.parentId == nil)
            #expect(sub.dirty && sub.updatedAt == at(20))
            #expect(sub.sortOrder > home.sortOrder && sub.sortOrder < errands.sortOrder)
        }
        #expect(clients.color == "#112233")
        #expect(own.categoryId == nil && own.dirty)
        #expect(subItem.categoryId == clients.id && !subItem.dirty)
        #expect(!home.dirty && !errands.dirty)
        #expect(rig.mutations == 1)
    }

    @Test("promotion works when the parent was first, last, or the only top-level category")
    @MainActor
    func deleteParentAtEdges() throws {
        for position in ["first", "last", "only"] {
            let rig = try Rig()
            if position == "last" { try rig.store.createCategory(name: "Other") }
            let work = try rig.store.createCategory(name: "Work")
            if position == "first" { try rig.store.createCategory(name: "Other") }
            try rig.store.createCategory(name: "A", parentId: work.id)
            try rig.store.createCategory(name: "B", parentId: work.id)

            try rig.store.deleteCategory(work)

            let expected = ["first": ["A", "B", "Other"], "last": ["Other", "A", "B"], "only": ["A", "B"]][position]
            #expect(try rig.topLevel() == expected, "\(position)")
            let orders = try rig.tree.topLevel.map(\.sortOrder)
            #expect(zip(orders, orders.dropFirst()).allSatisfy { $1 - $0 > TodoStore.minimumGap }, "\(position)")
        }
    }

    @Test("a slot too narrow for the promoted subcategories respaces the top level")
    @MainActor
    func deleteParentTinyGap() throws {
        let rig = try Rig()
        let workID = UUID()
        for row in [
            category("Home", order: 0), category("Work", id: workID, order: 1e-7), category("Errands", order: 2e-7),
            category("A", parent: workID, order: 0), category("B", parent: workID, order: 1),
        ] {
            rig.context.insert(row)
        }
        try rig.context.save()
        let work = try #require(try rig.tree.resolve(workID))

        try rig.store.deleteCategory(work)

        #expect(try rig.topLevel() == ["Home", "A", "B", "Errands"])
        #expect(try rig.tree.topLevel.map(\.sortOrder) == [0, 1, 2, 3])
    }
}

@Suite("Category store: items")
struct CategoryItemTests {
    @Test("create files an item under a category, and capture always files into Unassigned")
    @MainActor
    func create() throws {
        let rig = try Rig()
        let work = try rig.store.createCategory(name: "Work")

        #expect(try rig.store.create(title: "filed", categoryId: work.id).categoryId == work.id)
        #expect(try rig.store.create(title: "plain").categoryId == nil)
        #expect(try TodoCapture.save(CaptureDraft(title: "captured"), using: rig.store).categoryId == nil)
    }

    @Test("moving an item stamps it; moving it to where it already is does nothing")
    @MainActor
    func setCategory() throws {
        let rig = try Rig()
        let work = try rig.store.createCategory(name: "Work")
        let item = try rig.store.create(title: "x")
        try rig.settle()

        rig.advance(to: 2)
        try rig.store.setCategory(item, to: work.id)
        #expect(item.categoryId == work.id && item.dirty && item.updatedAt == at(2))
        #expect(rig.mutations == 1)

        try rig.settle()
        try rig.store.setCategory(item, to: work.id)
        #expect(!item.dirty && rig.mutations == 0)

        rig.advance(to: 3)
        try rig.store.setCategory(item, to: nil)
        #expect(item.categoryId == nil && item.dirty && item.updatedAt == at(3))
    }

    @Test("the editor's update changes the category in the same write, and the plain update leaves it alone")
    @MainActor
    func update() throws {
        let rig = try Rig()
        let work = try rig.store.createCategory(name: "Work")
        let item = try rig.store.create(title: "x")
        try rig.settle()

        try rig.store.update(item, title: "y", notes: nil, dueAt: nil, recurrence: nil, categoryId: work.id)
        #expect(item.title == "y" && item.categoryId == work.id)
        #expect(rig.mutations == 1)

        try rig.store.update(item, title: "z", notes: nil, dueAt: nil, recurrence: nil)
        #expect(item.title == "z" && item.categoryId == work.id)
    }
}
