import Foundation
import SwiftData

public struct SyncOutcome: Equatable, Sendable {
    /// True when another sync was already running; that run will pick this request up.
    public var coalesced = false
    public var pushed = 0
    public var rejectedStale = 0
    public var rejectedInvalid = 0
    public var pulled = 0
    public var applied = 0

    mutating func add(_ other: SyncOutcome) {
        pushed += other.pushed
        rejectedStale += other.rejectedStale
        rejectedInvalid += other.rejectedInvalid
        pulled += other.pulled
        applied += other.applied
    }
}

/// One sync cycle: push dirty rows, then pull changes since the cursor and merge them
/// (last-write-wins). Runs on its own `ModelContext`; the UI's context sees its saves.
public actor SyncEngine: ModelActor {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor

    private let client: any SyncClient
    private let cursors: SyncCursorStore
    private let pushChunkSize: Int
    private let pullPageSize: Int
    private let onChangesApplied: @Sendable () async -> Void

    private var isRunning = false
    private var rerunRequested = false

    /// `push.ts` makes two D1 queries per item and Workers cap subrequests per invocation, so
    /// pushes go out in small chunks.
    public static let defaultPushChunkSize = 20
    public static let defaultPullPageSize = 500

    public init(
        modelContainer: ModelContainer,
        client: any SyncClient,
        cursors: SyncCursorStore = SyncCursorStore(),
        pushChunkSize: Int = SyncEngine.defaultPushChunkSize,
        pullPageSize: Int = SyncEngine.defaultPullPageSize,
        onChangesApplied: @escaping @Sendable () async -> Void = {}
    ) {
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.client = client
        self.cursors = cursors
        self.pushChunkSize = pushChunkSize
        self.pullPageSize = pullPageSize
        self.onChangesApplied = onChangesApplied
    }

    /// A call made while a sync is running returns immediately (`coalesced`) and leaves one
    /// trailing rerun queued, so an edit made mid-sync is still pushed by that same run.
    public func sync() async throws -> SyncOutcome {
        if isRunning {
            rerunRequested = true
            return SyncOutcome(coalesced: true)
        }
        isRunning = true
        defer {
            isRunning = false
            rerunRequested = false
        }

        var total = SyncOutcome()
        repeat {
            rerunRequested = false
            total.add(try await runCycle())
        } while rerunRequested
        return total
    }

    public func resetCursor() {
        cursors.reset()
    }

    private func runCycle() async throws -> SyncOutcome {
        let baseURL = try await client.baseURL()
        var outcome = SyncOutcome()
        try await pushDirty(into: &outcome)
        try await pull(baseURL: baseURL, into: &outcome)
        if outcome.applied > 0 {
            await onChangesApplied()
        }
        return outcome
    }

    // MARK: Push

    private func pushDirty(into outcome: inout SyncOutcome) async throws {
        let dirty = try modelContext.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { $0.dirty }))
        let snapshots = dirty.map { TodoWireDto($0) }
        guard !snapshots.isEmpty else { return }

        var start = 0
        while start < snapshots.count {
            let chunk = Array(snapshots[start..<min(start + pushChunkSize, snapshots.count)])
            start += pushChunkSize

            let response = try await client.push(chunk)
            try clearDirty(applied: response.applied, sent: chunk, into: &outcome)
            for rejection in response.rejected {
                if rejection.reason == "stale" {
                    outcome.rejectedStale += 1
                } else {
                    outcome.rejectedInvalid += 1
                }
            }
        }
    }

    /// Clears `dirty` only if the item still has the exact `updatedAt` that was pushed; an edit
    /// made while the push was in flight keeps its flag and goes out on the next cycle.
    private func clearDirty(
        applied: [PushResponse.Applied],
        sent: [TodoWireDto],
        into outcome: inout SyncOutcome
    ) throws {
        let sentByID = Dictionary(sent.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in applied {
            guard let dto = sentByID[entry.id], let uuid = UUID(uuidString: entry.id) else { continue }
            let matches = try modelContext.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { $0.id == uuid }))
            guard let item = matches.first, Iso8601.format(item.updatedAt) == dto.updatedAt else { continue }
            item.dirty = false
            item.serverSeq = entry.serverSeq
            outcome.pushed += 1
        }
        try modelContext.save()
    }

    // MARK: Pull

    private func pull(baseURL: URL, into outcome: inout SyncOutcome) async throws {
        var cursor = cursors.cursor(for: baseURL)
        while true {
            let page = try await client.changes(since: cursor, limit: pullPageSize)

            do {
                try apply(page.items, into: &outcome)
                try modelContext.save()
            } catch {
                modelContext.rollback()
                throw error
            }
            // Rows are saved before the cursor moves; a crash in between re-pulls an idempotent page.
            cursors.set(page.cursor, for: baseURL)
            outcome.pulled += page.items.count

            if page.items.count < pullPageSize || page.cursor <= cursor { return }
            cursor = page.cursor
        }
    }

    private func apply(_ items: [TodoWireDto], into outcome: inout SyncOutcome) throws {
        var ids: [UUID] = []
        for dto in items {
            guard let uuid = UUID(uuidString: dto.id) else { throw SyncError.invalidRow("id \(dto.id)") }
            ids.append(uuid)
        }

        let existing = try modelContext.fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { ids.contains($0.id) }))
        let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for (dto, uuid) in zip(items, ids) {
            let local = existingByID[uuid]
            let decision = MergeRules.decide(
                localUpdatedAt: local.map { Iso8601.format($0.updatedAt) },
                localDirty: local?.dirty ?? false,
                incomingUpdatedAt: dto.updatedAt
            )
            do {
                switch decision {
                case .insert:
                    modelContext.insert(try dto.makeItem())
                    outcome.applied += 1
                case .apply:
                    try dto.apply(to: local!)
                    outcome.applied += 1
                case .keepLocal, .ignore:
                    break
                }
            } catch {
                throw SyncError.invalidRow(String(describing: error))
            }
        }
    }
}
