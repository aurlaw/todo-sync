import Foundation
import SwiftData
import Testing
@testable import TodoNativeCore

/// A scratch directory standing in for both the legacy app container and the App Group container.
private struct Scratch {
    let root = FileManager.default.temporaryDirectory.appending(path: "todonative-appgroup-\(UUID().uuidString)", directoryHint: .isDirectory)
    var legacyURL: URL { root.appending(path: "legacy/default.store") }
    var groupURL: URL { root.appending(path: "group", directoryHint: .isDirectory) }
    var newURL: URL { groupURL.appending(path: "Library/Application Support/default.store") }

    init() throws {
        try FileManager.default.createDirectory(at: root.appending(path: "legacy"), withIntermediateDirectories: true)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    func exists(_ url: URL, suffix: String = "") -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false) + suffix)
    }

    func writePlaceholder(_ url: URL, suffix: String = "", contents: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: URL(filePath: url.path(percentEncoded: false) + suffix))
    }

    /// Writes a real store with one dirty and one clean row, then releases the container.
    @MainActor
    func writeRealStore(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let container = try TodoContainer.make(storeURL: url)
        let context = ModelContext(container)
        context.insert(TodoItem(title: "unsynced edit", createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1), dirty: true))
        context.insert(TodoItem(title: "synced", createdAt: Date(timeIntervalSince1970: 2), updatedAt: Date(timeIntervalSince1970: 2), dirty: false, serverSeq: 7))
        try context.save()
    }

    func locator() -> (String) -> URL? {
        let group = groupURL
        return { _ in group }
    }
}

@Suite("StoreMigrator")
struct StoreMigratorTests {
    @Test("rows survive the move, including the ones still dirty")
    @MainActor
    func rowsSurviveTheMove() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        do { try scratch.writeRealStore(at: scratch.legacyURL) }

        let outcome = try StoreMigrator.migrateLegacyStore(from: scratch.legacyURL, to: scratch.newURL)

        #expect(outcome == .moved)
        #expect(!scratch.exists(scratch.legacyURL))
        let items = try ModelContext(TodoContainer.make(storeURL: scratch.newURL)).fetch(FetchDescriptor<TodoItem>())
        #expect(items.count == 2)
        let unsynced = try #require(items.first { $0.title == "unsynced edit" })
        #expect(unsynced.dirty)
        let synced = try #require(items.first { $0.title == "synced" })
        #expect(!synced.dirty)
        #expect(synced.serverSeq == 7)
    }

    @Test("the -wal and -shm files travel with the store")
    func sidecarsMove() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.writePlaceholder(scratch.legacyURL, contents: "main")
        try scratch.writePlaceholder(scratch.legacyURL, suffix: "-wal", contents: "wal")
        try scratch.writePlaceholder(scratch.legacyURL, suffix: "-shm", contents: "shm")

        #expect(try StoreMigrator.migrateLegacyStore(from: scratch.legacyURL, to: scratch.newURL) == .moved)

        for suffix in ["", "-wal", "-shm"] {
            #expect(!scratch.exists(scratch.legacyURL, suffix: suffix))
            #expect(scratch.exists(scratch.newURL, suffix: suffix))
        }
        #expect(try String(contentsOf: scratch.newURL, encoding: .utf8) == "main")
        #expect(try String(contentsOf: URL(filePath: scratch.newURL.path(percentEncoded: false) + "-wal"), encoding: .utf8) == "wal")
    }

    @Test("a second run is a no-op")
    func secondRunIsNoOp() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.writePlaceholder(scratch.legacyURL, contents: "main")

        try StoreMigrator.migrateLegacyStore(from: scratch.legacyURL, to: scratch.newURL)
        #expect(try StoreMigrator.migrateLegacyStore(from: scratch.legacyURL, to: scratch.newURL) == .notNeeded)
        #expect(try String(contentsOf: scratch.newURL, encoding: .utf8) == "main")
    }

    @Test("no legacy store (fresh install) does nothing and creates nothing")
    func freshInstall() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }

        #expect(try StoreMigrator.migrateLegacyStore(from: scratch.legacyURL, to: scratch.newURL) == .notNeeded)
        #expect(!scratch.exists(scratch.newURL))
    }

    @Test("both stores present: the group store wins and the legacy files are left untouched")
    func bothPresent() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.writePlaceholder(scratch.legacyURL, contents: "legacy")
        try scratch.writePlaceholder(scratch.legacyURL, suffix: "-wal", contents: "legacy-wal")
        try scratch.writePlaceholder(scratch.newURL, contents: "group")

        #expect(try StoreMigrator.migrateLegacyStore(from: scratch.legacyURL, to: scratch.newURL) == .legacyLeftInPlace)

        #expect(try String(contentsOf: scratch.legacyURL, encoding: .utf8) == "legacy")
        #expect(scratch.exists(scratch.legacyURL, suffix: "-wal"))
        #expect(try String(contentsOf: scratch.newURL, encoding: .utf8) == "group")
    }

    @Test("an interrupted move resumes: sidecars already moved, main file still in the legacy location")
    func resumesAfterInterruption() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.writePlaceholder(scratch.legacyURL, contents: "main")
        try scratch.writePlaceholder(scratch.newURL, suffix: "-wal", contents: "wal")

        #expect(try StoreMigrator.migrateLegacyStore(from: scratch.legacyURL, to: scratch.newURL) == .moved)

        #expect(try String(contentsOf: scratch.newURL, encoding: .utf8) == "main")
        #expect(try String(contentsOf: URL(filePath: scratch.newURL.path(percentEncoded: false) + "-wal"), encoding: .utf8) == "wal")
    }
}

@Suite("TodoContainer.makeShared")
struct SharedContainerTests {
    @Test("the legacy location is SwiftData's default store name")
    func legacyName() {
        #expect(TodoContainer.legacyStoreURL().lastPathComponent == "default.store")
    }

    @Test("throws when the App Group container cannot be resolved, rather than using a private store")
    func groupUnavailable() throws {
        #expect(throws: TodoContainerError.appGroupUnavailable("group.example")) {
            try TodoContainer.makeShared(appGroup: "group.example", groupContainerURL: { _ in nil })
        }
    }

    @Test("an extension gets storeNotReady while the group store does not exist, and creates nothing")
    func extensionBeforeApp() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }

        #expect(throws: TodoContainerError.storeNotReady) {
            try TodoContainer.makeShared(migrateLegacyStore: false, legacyStoreURL: scratch.legacyURL, groupContainerURL: scratch.locator())
        }
        #expect(!scratch.exists(scratch.newURL))
    }

    @Test("the app migrates the legacy store and opens it; an extension then sees the same rows")
    @MainActor
    func appThenExtension() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        do { try scratch.writeRealStore(at: scratch.legacyURL) }

        let app = try TodoContainer.makeShared(legacyStoreURL: scratch.legacyURL, groupContainerURL: scratch.locator())
        #expect(try ModelContext(app).fetch(FetchDescriptor<TodoItem>()).count == 2)
        #expect(!scratch.exists(scratch.legacyURL))

        let ext = try TodoContainer.makeShared(migrateLegacyStore: false, legacyStoreURL: scratch.legacyURL, groupContainerURL: scratch.locator())
        #expect(try ModelContext(ext).fetch(FetchDescriptor<TodoItem>()).count == 2)
    }

    @Test("a fresh install creates the group store, after which an extension can open it")
    @MainActor
    func freshInstallCreatesStore() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }

        let app = try TodoContainer.makeShared(legacyStoreURL: scratch.legacyURL, groupContainerURL: scratch.locator())
        #expect(try ModelContext(app).fetch(FetchDescriptor<TodoItem>()).isEmpty)
        #expect(scratch.exists(scratch.newURL))

        _ = try TodoContainer.makeShared(migrateLegacyStore: false, legacyStoreURL: scratch.legacyURL, groupContainerURL: scratch.locator())
    }
}
