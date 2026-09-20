import Foundation
import SwiftData

public enum AppGroup {
    /// Shared by the app, the Share extension and (N7b) the widgets extension.
    public static let identifier = "group.com.aurlaw.todonative"
}

public enum TodoContainerError: Error, Equatable, Sendable {
    /// The App Group container could not be resolved: the capability is missing from the target, or
    /// the identifier is wrong. Deliberately fatal: falling back to a private store would split the data.
    case appGroupUnavailable(String)
    /// An extension asked for the shared store before the main app has created or migrated it.
    case storeNotReady
}

public enum TodoContainer {
    private static var schema: Schema { Schema([TodoItem.self]) }

    /// The single source of truth for the SwiftData schema. Both the app and tests build
    /// their `ModelContainer` through this so they never drift.
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Self.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// A file-backed container at an explicit location.
    public static func make(storeURL: URL) throws -> ModelContainer {
        let schema = Self.schema
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Where SwiftData put the store before the App Group move (its default configuration's URL,
    /// inside the app's own container).
    public static func legacyStoreURL() -> URL {
        ModelConfiguration(schema: schema).url
    }

    /// The store location inside the App Group container.
    public static func sharedStoreURL(
        appGroup: String = AppGroup.identifier,
        groupContainerURL: (String) -> URL? = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    ) throws -> URL {
        guard let group = groupContainerURL(appGroup) else {
            throw TodoContainerError.appGroupUnavailable(appGroup)
        }
        // Same file name SwiftData used before, so a moved store keeps its name.
        return group
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
            .appending(path: "default.store")
    }

    /// The store every process shares.
    ///
    /// The main app passes `migrateLegacyStore: true` (the default): it moves an existing on-device
    /// store into the group container first, and creates the store if this is a fresh install.
    /// Extensions pass `false`: they must never create the store, or one launching before the app had
    /// migrated would create an empty store and hide the real data. They get `storeNotReady` instead.
    public static func makeShared(
        appGroup: String = AppGroup.identifier,
        migrateLegacyStore: Bool = true,
        legacyStoreURL: URL = TodoContainer.legacyStoreURL(),
        groupContainerURL: (String) -> URL? = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    ) throws -> ModelContainer {
        let storeURL = try sharedStoreURL(appGroup: appGroup, groupContainerURL: groupContainerURL)
        if migrateLegacyStore {
            try StoreMigrator.migrateLegacyStore(from: legacyStoreURL, to: storeURL)
        } else if !FileManager.default.fileExists(atPath: storeURL.path(percentEncoded: false)) {
            throw TodoContainerError.storeNotReady
        }
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try make(storeURL: storeURL)
    }
}
