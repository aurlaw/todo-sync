import Foundation
import Observation

public enum SyncStatus: Equatable, Sendable {
    case idle(lastSync: Date?)
    case syncing
    case notConfigured
    case failed(String)
}

/// What the coordinator needs from an engine; `SyncEngine` conforms, tests substitute a fake.
public protocol SyncRunning: Sendable {
    func sync() async throws -> SyncOutcome
    func resetCursor() async
}

extension SyncEngine: SyncRunning {}

/// UI-facing side of sync: owns the observable status, the launch/foreground/edit triggers,
/// and the 2-second debounce after local edits. The engine itself coalesces overlapping runs.
@MainActor
@Observable
public final class SyncCoordinator {
    public private(set) var status: SyncStatus = .idle(lastSync: nil)

    @ObservationIgnored private let engine: any SyncRunning
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var lastSync: Date?
    @ObservationIgnored private let afterSync: (@MainActor () throws -> Bool)?

    /// `afterSync` runs after every completed cycle, once local data is caught up with the server;
    /// return `true` if it changed local rows and they need pushing. The app uses it for the
    /// one-time sort-order backfill.
    public init(
        engine: any SyncRunning,
        debounce: Duration = .seconds(2),
        afterSync: (@MainActor () throws -> Bool)? = nil
    ) {
        self.engine = engine
        self.debounce = debounce
        self.afterSync = afterSync
    }

    /// Called after every local edit; a burst of edits collapses into one sync.
    public func scheduleSync() {
        debounceTask?.cancel()
        let delay = debounce
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.performSync()
        }
    }

    public func syncNow() async {
        debounceTask?.cancel()
        await performSync()
    }

    /// Launch and `scenePhase == .active`.
    public func handleActive() {
        Task { await syncNow() }
    }

    public func resetAndSync() async {
        await engine.resetCursor()
        await syncNow()
    }

    private func performSync() async {
        status = .syncing
        do {
            let outcome = try await engine.sync()
            // A coalesced call leaves the status to the run that is already in flight.
            if outcome.coalesced { return }
            lastSync = .now
            status = .idle(lastSync: lastSync)
            if (try? afterSync?()) == true { scheduleSync() }
        } catch is CancellationError {
            status = .idle(lastSync: lastSync)
        } catch SyncError.notConfigured {
            status = .notConfigured
        } catch {
            status = .failed(String(describing: error))
        }
    }
}
