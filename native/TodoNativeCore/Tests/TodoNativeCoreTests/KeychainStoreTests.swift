import Foundation
import Testing
@testable import TodoNativeCore

@Suite("KeychainStore", .serialized)
struct KeychainStoreTests {
    private func makeStore() -> KeychainStore {
        KeychainStore(service: "com.aurlaw.todonative.tests.\(UUID().uuidString)")
    }

    @Test("get returns nil for a key that was never set")
    func getMissingReturnsNil() throws {
        let store = makeStore()
        #expect(try store.get(.apiToken) == nil)
    }

    @Test("set then get round-trips the value")
    func setThenGet() throws {
        let store = makeStore()
        defer { try? store.delete(.apiToken) }

        try store.set(.apiToken, value: "value-\(UUID().uuidString)")
        let stored = try store.get(.apiToken)
        #expect(stored?.hasPrefix("value-") == true)
    }

    @Test("set twice overwrites (exercises the update path)")
    func setTwiceOverwrites() throws {
        let store = makeStore()
        defer { try? store.delete(.workerBaseURL) }

        try store.set(.workerBaseURL, value: "first")
        try store.set(.workerBaseURL, value: "second")
        #expect(try store.get(.workerBaseURL) == "second")
    }

    @Test("delete removes the value, and deleting a missing key is not an error")
    func deleteRemoves() throws {
        let store = makeStore()

        try store.set(.apiToken, value: "temp")
        try store.delete(.apiToken)
        #expect(try store.get(.apiToken) == nil)

        try store.delete(.apiToken)
    }

    @Test("keys are independent")
    func keysAreIndependent() throws {
        let store = makeStore()
        defer {
            try? store.delete(.apiToken)
            try? store.delete(.workerBaseURL)
        }

        try store.set(.apiToken, value: "a")
        try store.set(.workerBaseURL, value: "b")
        #expect(try store.get(.apiToken) == "a")
        #expect(try store.get(.workerBaseURL) == "b")
    }
}
