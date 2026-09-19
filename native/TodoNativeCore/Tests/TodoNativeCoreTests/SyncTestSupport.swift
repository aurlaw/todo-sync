import Foundation
import SwiftData
import Testing
@testable import TodoNativeCore

struct FixedTestClock: Clock {
    let date: Date
    func now() -> Date { date }
}

let epoch = Date(timeIntervalSince1970: 1_800_000_000)

func at(_ seconds: TimeInterval) -> Date { epoch.addingTimeInterval(seconds) }

final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [SecretKey: String] = [:]

    init(baseURL: String? = "https://worker.test", token: String? = "test-token") {
        values[.workerBaseURL] = baseURL
        values[.apiToken] = token
    }

    func get(_ key: SecretKey) throws -> String? { lock.withLock { values[key] } }
    func set(_ key: SecretKey, value: String) throws { lock.withLock { values[key] = value } }
    func delete(_ key: SecretKey) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
}

func wire(
    id: UUID = UUID(),
    title: String = "remote",
    updatedAt: Date,
    isDone: Bool = false,
    isDeleted: Bool = false,
    serverSeq: Int64 = 1
) -> TodoWireDto {
    TodoWireDto(
        id: id.uuidString.lowercased(),
        title: title,
        notes: nil,
        isDone: isDone,
        dueAt: nil,
        recurrence: nil,
        createdAt: Iso8601.format(updatedAt),
        updatedAt: Iso8601.format(updatedAt),
        isDeleted: isDeleted,
        serverSeq: serverSeq
    )
}

actor FakeSyncClient: SyncClient {
    private var base = URL(string: "https://worker.test")!
    private var baseError: SyncError?
    private var rejectStale: Set<String> = []
    private var rejectInvalid: Set<String> = []
    private var pages: [ChangesResponse] = []
    private var onPush: (@Sendable ([TodoWireDto]) async -> Void)?
    private var nextSeq: Int64 = 100

    private(set) var pushedChunks: [[TodoWireDto]] = []
    private(set) var changeRequests: [Int64] = []

    func setBase(_ url: URL) { base = url }
    func setBaseError(_ error: SyncError?) { baseError = error }
    func setRejectStale(_ ids: Set<String>) { rejectStale = ids }
    func setRejectInvalid(_ ids: Set<String>) { rejectInvalid = ids }
    func setPages(_ newPages: [ChangesResponse]) { pages = newPages }
    func setOnPush(_ hook: (@Sendable ([TodoWireDto]) async -> Void)?) { onPush = hook }

    func baseURL() async throws -> URL {
        if let baseError { throw baseError }
        return base
    }

    func push(_ items: [TodoWireDto]) async throws -> PushResponse {
        pushedChunks.append(items)
        await onPush?(items)

        var applied: [PushResponse.Applied] = []
        var rejected: [PushResponse.Rejected] = []
        for item in items {
            if rejectStale.contains(item.id) {
                rejected.append(.init(id: item.id, reason: "stale"))
            } else if rejectInvalid.contains(item.id) {
                rejected.append(.init(id: item.id, reason: "invalid"))
            } else {
                nextSeq += 1
                applied.append(.init(id: item.id, serverSeq: nextSeq))
            }
        }
        return PushResponse(applied: applied, rejected: rejected)
    }

    func changes(since: Int64, limit: Int) async throws -> ChangesResponse {
        changeRequests.append(since)
        if pages.isEmpty { return ChangesResponse(items: [], cursor: since) }
        return pages.removeFirst()
    }
}

actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

func makeCursorStore() -> SyncCursorStore {
    SyncCursorStore(defaults: UserDefaults(suiteName: "todonative.tests.\(UUID().uuidString)")!)
}

/// A URLProtocol that answers from a closure and records requests. State is static, so suites
/// using it must be `.serialized`.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var recorded: [(request: URLRequest, body: Data?)] = []

    static func reset() {
        handler = nil
        recorded = []
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body: Data?
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            body = data
        } else {
            body = request.httpBody
        }
        Self.recorded.append((request, body))

        do {
            let (status, data) = try Self.handler?(request) ?? (500, Data())
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
