import Foundation
import SwiftData
import Testing
@testable import TodoNativeCore

/// Stand-in for the sync engine's actor shape: a ModelActor with one long-lived context.
actor ProbeActor: ModelActor {
    nonisolated let modelContainer: ModelContainer
    nonisolated let modelExecutor: any ModelExecutor

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
    }

    func title(of id: UUID) throws -> String? {
        let descriptor = FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first?.title
    }

    func rename(_ id: UUID, to title: String) throws {
        let descriptor = FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == id })
        try modelContext.fetch(descriptor).first?.title = title
        try modelContext.save()
    }
}

@Suite("Cross-context visibility (file-backed store)")
struct ContextVisibilityTests {
    private func makeContainer() throws -> ModelContainer {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "todonative-visibility-\(UUID().uuidString).store")
        let schema = Schema([TodoItem.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
    }

    @Test("main-context saves are visible to the actor, including after it has cached the row")
    @MainActor
    func mainToActor() async throws {
        let container = try makeContainer()
        let main = ModelContext(container)
        let store = TodoStore(context: main)
        let probe = ProbeActor(modelContainer: container)

        let item = try store.create(title: "one")
        #expect(try await probe.title(of: item.id) == "one")

        try store.update(item, title: "two", notes: nil, dueAt: nil, recurrence: nil)
        #expect(try await probe.title(of: item.id) == "two")
    }

    @Test("actor saves are visible to a main-context fetch and to an already-loaded instance")
    @MainActor
    func actorToMain() async throws {
        let container = try makeContainer()
        let main = ModelContext(container)
        let store = TodoStore(context: main)
        let probe = ProbeActor(modelContainer: container)

        let item = try store.create(title: "one")
        let id = item.id
        try await probe.rename(id, to: "renamed")

        let fresh = try main.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == id }))
        #expect(fresh.first?.title == "renamed")
        #expect(item.title == "renamed")
    }
}
