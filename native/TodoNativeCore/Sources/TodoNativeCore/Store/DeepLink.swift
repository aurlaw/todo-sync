import Foundation

/// A `todonative://` link, used by widgets and controls to open the app somewhere specific.
public enum DeepLink: Equatable, Sendable {
    case today
    case new
    case item(UUID)

    public static let scheme = "todonative"

    /// `nil` for a different scheme, an unknown destination, a malformed id, or extra path components.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host()?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch (host, parts.count) {
        case ("today", 0):
            self = .today
        case ("new", 0):
            self = .new
        case ("item", 1):
            guard let id = UUID(uuidString: parts[0]) else { return nil }
            self = .item(id)
        default:
            return nil
        }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .today:
            components.host = "today"
        case .new:
            components.host = "new"
        case .item(let id):
            components.host = "item"
            components.path = "/" + id.uuidString.lowercased()
        }
        // Built only from constants and a UUID, so this cannot be nil.
        return components.url!
    }
}
