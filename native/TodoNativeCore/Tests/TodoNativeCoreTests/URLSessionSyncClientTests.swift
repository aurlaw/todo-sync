import Foundation
import Testing
@testable import TodoNativeCore

@Suite("URLSessionSyncClient", .serialized)
struct URLSessionSyncClientTests {
    private let emptyChanges = Data(#"{"items":[],"cursor":0}"#.utf8)
    private let emptyPush = Data(#"{"applied":[],"rejected":[]}"#.utf8)

    private func makeClient(_ secrets: MemorySecretStore = MemorySecretStore()) -> URLSessionSyncClient {
        StubURLProtocol.reset()
        return URLSessionSyncClient(session: StubURLProtocol.makeSession(), secrets: secrets)
    }

    @Test("sends the bearer token and builds the changes URL with since and limit")
    func changesRequestShape() async throws {
        let client = makeClient()
        StubURLProtocol.handler = { _ in (200, self.emptyChanges) }

        _ = try await client.changes(since: 42, limit: 500)

        let request = try #require(StubURLProtocol.recorded.first?.request)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        let components = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)
        #expect(components?.path == "/changes")
        #expect(components?.queryItems?.first { $0.name == "since" }?.value == "42")
        #expect(components?.queryItems?.first { $0.name == "limit" }?.value == "500")
    }

    @Test("handles a base URL with a trailing slash and with a path prefix")
    func baseURLForms() async throws {
        for (base, expectedPath) in [
            ("https://worker.test/", "/push"),
            ("https://worker.test", "/push"),
            ("https://worker.test/api/", "/api/push"),
            ("https://worker.test/api", "/api/push"),
        ] {
            let client = makeClient(MemorySecretStore(baseURL: base))
            StubURLProtocol.handler = { _ in (200, self.emptyPush) }
            _ = try await client.push([])
            #expect(StubURLProtocol.recorded.first?.request.url?.path == expectedPath, "\(base)")
        }
    }

    @Test("push sends a JSON body with explicit nulls")
    func pushBody() async throws {
        let client = makeClient()
        StubURLProtocol.handler = { _ in (200, self.emptyPush) }

        let dto = wire(updatedAt: at(0))
        _ = try await client.push([dto])

        let recorded = try #require(StubURLProtocol.recorded.first)
        #expect(recorded.request.httpMethod == "POST")
        #expect(recorded.request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(recorded.body)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let items = try #require(object["items"] as? [[String: Any]])
        #expect(items.count == 1)
        #expect(items[0]["notes"] is NSNull)
        #expect(items[0]["dueAt"] is NSNull)
        #expect(items[0]["recurrence"] is NSNull)
        #expect(workerAcceptsPushItem(items[0]))
    }

    @Test("decodes real-shaped responses")
    func decodesResponses() async throws {
        let client = makeClient()
        StubURLProtocol.handler = { request in
            let path = request.url?.path
            return (200, path == "/push" ? try fixtureData("push-response") : try fixtureData("changes-response"))
        }

        let push = try await client.push([])
        #expect(push.rejected.last?.id == "unknown")
        let changes = try await client.changes(since: 0, limit: 500)
        #expect(changes.items.count == 3)
    }

    @Test("maps 401 to unauthorized, 5xx to http, and a bad body to decoding")
    func errorMapping() async throws {
        let client = makeClient()

        StubURLProtocol.handler = { _ in (401, Data()) }
        await #expect(throws: SyncError.unauthorized) { try await client.changes(since: 0, limit: 1) }

        StubURLProtocol.handler = { _ in (503, Data()) }
        await #expect(throws: SyncError.http(503)) { try await client.changes(since: 0, limit: 1) }

        StubURLProtocol.handler = { _ in (200, Data("nope".utf8)) }
        do {
            _ = try await client.changes(since: 0, limit: 1)
            Issue.record("expected a decoding error")
        } catch let error as SyncError {
            guard case .decoding = error else { Issue.record("wrong error: \(error)"); return }
        }
    }

    @Test("a missing token or URL is notConfigured and makes no request")
    func notConfigured() async throws {
        for secrets in [
            MemorySecretStore(baseURL: "https://worker.test", token: nil),
            MemorySecretStore(baseURL: "https://worker.test", token: "   "),
            MemorySecretStore(baseURL: nil, token: "test-token"),
            MemorySecretStore(baseURL: "", token: "test-token"),
        ] {
            let client = makeClient(secrets)
            StubURLProtocol.handler = { _ in (200, self.emptyChanges) }
            await #expect(throws: SyncError.notConfigured) { try await client.changes(since: 0, limit: 1) }
            await #expect(throws: SyncError.notConfigured) { try await client.push([]) }
            #expect(StubURLProtocol.recorded.isEmpty)
        }
    }

    @Test("a non-http URL is invalid")
    func invalidURL() async {
        let client = makeClient(MemorySecretStore(baseURL: "ftp://worker.test"))
        await #expect(throws: SyncError.invalidURL("ftp://worker.test")) { try await client.baseURL() }
    }

    @Test("the token and URL are re-read on every call")
    func rereadsSecrets() async throws {
        let secrets = MemorySecretStore(baseURL: "https://one.test", token: "first")
        let client = makeClient(secrets)
        StubURLProtocol.handler = { _ in (200, self.emptyChanges) }

        _ = try await client.changes(since: 0, limit: 1)
        try secrets.set(.apiToken, value: "second")
        try secrets.set(.workerBaseURL, value: "https://two.test")
        _ = try await client.changes(since: 0, limit: 1)

        let requests = StubURLProtocol.recorded.map(\.request)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer first")
        #expect(requests[0].url?.host() == "one.test")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer second")
        #expect(requests[1].url?.host() == "two.test")
    }
}
