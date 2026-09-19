import Foundation

/// Persists the `/changes` cursor together with the base URL it belongs to. A cursor is only
/// meaningful for the Worker that issued it, so asking for a different URL yields 0.
// UserDefaults is documented thread-safe but not annotated Sendable.
public struct SyncCursorStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let urlKey = "todonative.sync.cursorBaseURL"
    private let valueKey = "todonative.sync.cursorValue"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func cursor(for baseURL: URL) -> Int64 {
        guard defaults.string(forKey: urlKey) == baseURL.absoluteString else { return 0 }
        return Int64(defaults.integer(forKey: valueKey))
    }

    public func set(_ cursor: Int64, for baseURL: URL) {
        defaults.set(baseURL.absoluteString, forKey: urlKey)
        defaults.set(Int(cursor), forKey: valueKey)
    }

    public func reset() {
        defaults.removeObject(forKey: urlKey)
        defaults.removeObject(forKey: valueKey)
    }
}
