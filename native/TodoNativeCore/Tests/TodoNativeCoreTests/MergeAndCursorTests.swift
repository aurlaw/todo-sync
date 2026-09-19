import Foundation
import Testing
@testable import TodoNativeCore

@Suite("MergeRules")
struct MergeRulesTests {
    private let older = Iso8601.format(at(0))
    private let newer = Iso8601.format(at(10))

    @Test("no local row inserts")
    func insert() {
        #expect(MergeRules.decide(localUpdatedAt: nil, localDirty: false, incomingUpdatedAt: newer) == .insert)
        #expect(MergeRules.decide(localUpdatedAt: nil, localDirty: true, incomingUpdatedAt: newer) == .insert)
    }

    @Test("a newer incoming row applies, dirty or not")
    func newerApplies() {
        #expect(MergeRules.decide(localUpdatedAt: older, localDirty: false, incomingUpdatedAt: newer) == .apply)
        #expect(MergeRules.decide(localUpdatedAt: older, localDirty: true, incomingUpdatedAt: newer) == .apply)
    }

    @Test("an older incoming row is ignored when local is clean, and loses to a dirty local row")
    func olderIgnored() {
        #expect(MergeRules.decide(localUpdatedAt: newer, localDirty: false, incomingUpdatedAt: older) == .ignore)
        #expect(MergeRules.decide(localUpdatedAt: newer, localDirty: true, incomingUpdatedAt: older) == .keepLocal)
    }

    @Test("equal timestamps apply so a stale-rejected dirty row resolves instead of sticking")
    func equalApplies() {
        #expect(MergeRules.decide(localUpdatedAt: newer, localDirty: true, incomingUpdatedAt: newer) == .apply)
        #expect(MergeRules.decide(localUpdatedAt: newer, localDirty: false, incomingUpdatedAt: newer) == .apply)
    }
}

@Suite("SyncCursorStore")
struct SyncCursorStoreTests {
    private let one = URL(string: "https://one.test")!
    private let two = URL(string: "https://two.test")!

    @Test("returns 0 until something is stored")
    func startsAtZero() {
        #expect(makeCursorStore().cursor(for: one) == 0)
    }

    @Test("round-trips for the same URL and resets to 0 for a different one")
    func perURL() {
        let store = makeCursorStore()
        store.set(42, for: one)
        #expect(store.cursor(for: one) == 42)
        #expect(store.cursor(for: two) == 0)
    }

    @Test("reset clears the cursor")
    func reset() {
        let store = makeCursorStore()
        store.set(42, for: one)
        store.reset()
        #expect(store.cursor(for: one) == 0)
    }
}
