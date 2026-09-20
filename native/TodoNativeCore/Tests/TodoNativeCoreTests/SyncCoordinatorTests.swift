import Foundation
import Testing
@testable import TodoNativeCore

actor FakeRunner: SyncRunning {
    private(set) var syncCalls = 0
    private(set) var resetCalls = 0
    private var result: Result<SyncOutcome, any Error> = .success(SyncOutcome())

    func setResult(_ newResult: Result<SyncOutcome, any Error>) { result = newResult }

    func sync() async throws -> SyncOutcome {
        syncCalls += 1
        return try result.get()
    }

    func resetCursor() async { resetCalls += 1 }
}

@Suite("SyncCoordinator")
struct SyncCoordinatorTests {
    @Test("a burst of edits collapses into one debounced sync")
    @MainActor
    func debounceCollapses() async throws {
        let runner = FakeRunner()
        let coordinator = SyncCoordinator(engine: runner, debounce: .milliseconds(50))

        for _ in 0..<5 { coordinator.scheduleSync() }
        try await Task.sleep(for: .milliseconds(300))

        #expect(await runner.syncCalls == 1)
    }

    @Test("nothing runs before the debounce elapses")
    @MainActor
    func debounceDelays() async throws {
        let runner = FakeRunner()
        let coordinator = SyncCoordinator(engine: runner, debounce: .milliseconds(200))

        coordinator.scheduleSync()
        try await Task.sleep(for: .milliseconds(50))

        #expect(await runner.syncCalls == 0)
    }

    @Test("a successful sync ends idle with a last-sync date")
    @MainActor
    func success() async {
        let runner = FakeRunner()
        let coordinator = SyncCoordinator(engine: runner)

        await coordinator.syncNow()

        guard case .idle(let lastSync) = coordinator.status else { Issue.record("\(coordinator.status)"); return }
        #expect(lastSync != nil)
    }

    @Test("notConfigured and other errors map to their statuses")
    @MainActor
    func errors() async {
        let runner = FakeRunner()
        let coordinator = SyncCoordinator(engine: runner)

        await runner.setResult(.failure(SyncError.notConfigured))
        await coordinator.syncNow()
        #expect(coordinator.status == .notConfigured)

        await runner.setResult(.failure(SyncError.unauthorized))
        await coordinator.syncNow()
        #expect(coordinator.status == .failed("Token rejected by the server"))
    }

    @Test("a coalesced result leaves the status to the run already in flight")
    @MainActor
    func coalescedKeepsSyncing() async {
        let runner = FakeRunner()
        let coordinator = SyncCoordinator(engine: runner)
        await runner.setResult(.success(SyncOutcome(coalesced: true)))

        await coordinator.syncNow()

        #expect(coordinator.status == .syncing)
    }

    @Test("resetAndSync resets the cursor, then syncs")
    @MainActor
    func reset() async {
        let runner = FakeRunner()
        let coordinator = SyncCoordinator(engine: runner)

        await coordinator.resetAndSync()

        #expect(await runner.resetCalls == 1)
        #expect(await runner.syncCalls == 1)
    }
}

@Suite("SyncCoordinator afterSync")
struct SyncCoordinatorAfterSyncTests {
    @Test("runs after a completed sync, and a true result schedules a push")
    @MainActor
    func schedulesWhenChanged() async throws {
        let runner = FakeRunner()
        var calls = 0
        let coordinator = SyncCoordinator(engine: runner, debounce: .milliseconds(20), afterSync: {
            calls += 1
            return calls == 1
        })

        await coordinator.syncNow()
        try await Task.sleep(for: .milliseconds(300))

        // The first cycle changed rows, so one more ran; the second changed nothing, so it stops.
        #expect(await runner.syncCalls == 2)
        #expect(calls == 2)
    }

    @Test("a false result does not schedule anything")
    @MainActor
    func quietWhenUnchanged() async throws {
        let runner = FakeRunner()
        let coordinator = SyncCoordinator(engine: runner, debounce: .milliseconds(20), afterSync: { false })

        await coordinator.syncNow()
        try await Task.sleep(for: .milliseconds(200))

        #expect(await runner.syncCalls == 1)
    }

    @Test("does not run when the sync failed, and a throwing hook is swallowed")
    @MainActor
    func skippedOnFailure() async throws {
        let runner = FakeRunner()
        var calls = 0
        let coordinator = SyncCoordinator(engine: runner, afterSync: { calls += 1; return false })

        await runner.setResult(.failure(SyncError.notConfigured))
        await coordinator.syncNow()
        #expect(calls == 0)

        struct Boom: Error {}
        let throwing = SyncCoordinator(engine: FakeRunner(), afterSync: { throw Boom() })
        await throwing.syncNow()
        guard case .idle = throwing.status else { Issue.record("\(throwing.status)"); return }
    }
}
