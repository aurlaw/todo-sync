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

    private var categoryPages: [CategoryChangesResponse] = []

    private(set) var pushedChunks: [[TodoWireDto]] = []
    private(set) var changeRequests: [Int64] = []
    private(set) var pushedCategoryChunks: [[CategoryWireDto]] = []
    private(set) var categoryChangeRequests: [Int64] = []
    /// Every call in the order it was made, by method name.
    private(set) var calls: [String] = []

    func setBase(_ url: URL) { base = url }
    func setBaseError(_ error: SyncError?) { baseError = error }
    func setRejectStale(_ ids: Set<String>) { rejectStale = ids }
    func setRejectInvalid(_ ids: Set<String>) { rejectInvalid = ids }
    func setPages(_ newPages: [ChangesResponse]) { pages = newPages }
    func setCategoryPages(_ newPages: [CategoryChangesResponse]) { categoryPages = newPages }
    func setOnPush(_ hook: (@Sendable ([TodoWireDto]) async -> Void)?) { onPush = hook }

    func baseURL() async throws -> URL {
        if let baseError { throw baseError }
        return base
    }

    func push(_ items: [TodoWireDto]) async throws -> PushResponse {
        calls.append("push")
        pushedChunks.append(items)
        await onPush?(items)
        return respond(to: items.map(\.id))
    }

    func changes(since: Int64, limit: Int) async throws -> ChangesResponse {
        calls.append("changes")
        changeRequests.append(since)
        if pages.isEmpty { return ChangesResponse(items: [], cursor: since) }
        return pages.removeFirst()
    }

    func pushCategories(_ items: [CategoryWireDto]) async throws -> PushResponse {
        calls.append("pushCategories")
        pushedCategoryChunks.append(items)
        return respond(to: items.map(\.id))
    }

    func categoryChanges(since: Int64, limit: Int) async throws -> CategoryChangesResponse {
        calls.append("categoryChanges")
        categoryChangeRequests.append(since)
        if categoryPages.isEmpty { return CategoryChangesResponse(items: [], cursor: since) }
        return categoryPages.removeFirst()
    }

    private func respond(to ids: [String]) -> PushResponse {
        var applied: [PushResponse.Applied] = []
        var rejected: [PushResponse.Rejected] = []
        for id in ids {
            if rejectStale.contains(id) {
                rejected.append(.init(id: id, reason: "stale"))
            } else if rejectInvalid.contains(id) {
                rejected.append(.init(id: id, reason: "invalid"))
            } else {
                nextSeq += 1
                applied.append(.init(id: id, serverSeq: nextSeq))
            }
        }
        return PushResponse(applied: applied, rejected: rejected)
    }
}

func categoryWire(
    id: UUID = UUID(),
    name: String = "remote",
    parentId: UUID? = nil,
    color: String? = nil,
    sortOrder: Double = 0,
    updatedAt: Date,
    isDeleted: Bool = false,
    serverSeq: Int64 = 1
) -> CategoryWireDto {
    CategoryWireDto(
        id: id.uuidString.lowercased(),
        name: name,
        parentId: parentId?.uuidString.lowercased(),
        color: color,
        sortOrder: sortOrder,
        createdAt: Iso8601.format(updatedAt),
        updatedAt: Iso8601.format(updatedAt),
        isDeleted: isDeleted,
        serverSeq: serverSeq
    )
}

/// A clock a test can advance, so "which rows did this write touch" shows as "which rows have the
/// new `updatedAt`".
final class AdjustableClock: Clock, @unchecked Sendable {
    var date: Date
    init(_ date: Date = at(0)) { self.date = date }
    func now() -> Date { date }
}

/// A stand-in for the Worker that actually stores rows: last-write-wins upserts, one sequence
/// counter shared by todos and categories, and `/changes` paging. Two engines given the same
/// instance behave like two devices syncing through one server.
actor InMemoryWorker: SyncClient {
    private var seq: Int64 = 0
    private var todos: [String: TodoWireDto] = [:]
    private var categories: [String: CategoryWireDto] = [:]

    func baseURL() async throws -> URL { URL(string: "https://worker.test")! }

    func push(_ items: [TodoWireDto]) async throws -> PushResponse {
        var response = PushResponse(applied: [], rejected: [])
        for var item in items {
            seq += 1
            if let stored = todos[item.id], item.updatedAt <= stored.updatedAt {
                response.rejected.append(.init(id: item.id, reason: "stale"))
                continue
            }
            item.serverSeq = seq
            todos[item.id] = item
            response.applied.append(.init(id: item.id, serverSeq: seq))
        }
        return response
    }

    func changes(since: Int64, limit: Int) async throws -> ChangesResponse {
        let rows = todos.values.filter { ($0.serverSeq ?? 0) > since }
            .sorted { ($0.serverSeq ?? 0) < ($1.serverSeq ?? 0) }
            .prefix(limit)
        return ChangesResponse(items: Array(rows), cursor: rows.last?.serverSeq ?? since)
    }

    func pushCategories(_ items: [CategoryWireDto]) async throws -> PushResponse {
        var response = PushResponse(applied: [], rejected: [])
        for var item in items {
            seq += 1
            if let stored = categories[item.id], item.updatedAt <= stored.updatedAt {
                response.rejected.append(.init(id: item.id, reason: "stale"))
                continue
            }
            item.serverSeq = seq
            categories[item.id] = item
            response.applied.append(.init(id: item.id, serverSeq: seq))
        }
        return response
    }

    func categoryChanges(since: Int64, limit: Int) async throws -> CategoryChangesResponse {
        let rows = categories.values.filter { ($0.serverSeq ?? 0) > since }
            .sorted { ($0.serverSeq ?? 0) < ($1.serverSeq ?? 0) }
            .prefix(limit)
        return CategoryChangesResponse(items: Array(rows), cursor: rows.last?.serverSeq ?? since)
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
