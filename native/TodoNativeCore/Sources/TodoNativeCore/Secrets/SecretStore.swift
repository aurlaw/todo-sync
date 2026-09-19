import Foundation

public enum SecretKey: String, Sendable {
    case apiToken
    case workerBaseURL
}

public protocol SecretStore: Sendable {
    func get(_ key: SecretKey) throws -> String?
    func set(_ key: SecretKey, value: String) throws
    func delete(_ key: SecretKey) throws
}
