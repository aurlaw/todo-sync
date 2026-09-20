import Foundation

/// One-time move of the on-device store into the App Group container, so the app, the Share
/// extension and (in N7b) the widgets all open the same file.
///
/// The store is moved, never deleted and re-pulled: a delete would silently lose any row still
/// `dirty` (an edit not yet pushed), and moving keeps the sync cursor valid.
public enum StoreMigrator {
    public enum Outcome: Equatable, Sendable {
        /// Nothing to move: a fresh install, or the store is already in the group container.
        case notNeeded
        case moved
        /// Both a group store and a legacy store exist. The group store wins; the legacy files are
        /// left exactly where they are (nothing here ever deletes).
        case legacyLeftInPlace
    }

    /// SQLite writes the store as three files that only make sense together.
    private static let sidecarSuffixes = ["-wal", "-shm"]

    /// Call before any `ModelContainer` opens either location.
    ///
    /// The main file moves last and doubles as the completion marker: if the move is interrupted, the
    /// group store still does not exist, so the next launch resumes instead of skipping.
    @discardableResult
    public static func migrateLegacyStore(
        from legacyURL: URL,
        to newURL: URL,
        fileManager: FileManager = .default
    ) throws -> Outcome {
        let legacyExists = fileManager.fileExists(atPath: legacyURL.path(percentEncoded: false))
        if fileManager.fileExists(atPath: newURL.path(percentEncoded: false)) {
            return legacyExists ? .legacyLeftInPlace : .notNeeded
        }
        guard legacyExists else { return .notNeeded }

        try fileManager.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        for suffix in sidecarSuffixes {
            let source = sibling(of: legacyURL, suffix: suffix)
            if fileManager.fileExists(atPath: source.path(percentEncoded: false)) {
                try fileManager.moveItem(at: source, to: sibling(of: newURL, suffix: suffix))
            }
        }
        try fileManager.moveItem(at: legacyURL, to: newURL)
        return .moved
    }

    private static func sibling(of url: URL, suffix: String) -> URL {
        URL(filePath: url.path(percentEncoded: false) + suffix)
    }
}
