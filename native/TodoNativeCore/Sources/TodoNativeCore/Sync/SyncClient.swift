import Foundation

public enum SyncError: Error, Equatable, Sendable, CustomStringConvertible {
    case notConfigured
    case invalidURL(String)
    case secretStore(String)
    case unauthorized
    case http(Int)
    case transport(String)
    case decoding(String)
    /// A row pulled from the Worker could not be mapped (bad id or date).
    case invalidRow(String)

    public var description: String {
        switch self {
        case .notConfigured: "Not configured"
        case .invalidURL(let value): "Invalid Worker URL: \(value)"
        case .secretStore(let message): "Could not read settings: \(message)"
        case .unauthorized: "Token rejected by the server"
        case .http(let status): "Server error (HTTP \(status))"
        case .transport(let message): "Network error: \(message)"
        case .decoding(let message): "Unexpected server response: \(message)"
        case .invalidRow(let message): "Bad row from server: \(message)"
        }
    }
}

public protocol SyncClient: Sendable {
    /// The configured Worker base URL. Throws `.notConfigured` when none is saved. The engine keys
    /// its sync cursor by this so pointing the app at a different Worker restarts from zero.
    func baseURL() async throws -> URL
    func push(_ items: [TodoWireDto]) async throws -> PushResponse
    func changes(since: Int64, limit: Int) async throws -> ChangesResponse
}
