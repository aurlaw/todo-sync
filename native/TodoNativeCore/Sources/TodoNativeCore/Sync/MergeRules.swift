import Foundation

public enum MergeDecision: Equatable, Sendable {
    case insert
    case apply
    case keepLocal
    case ignore
}

/// Last-write-wins on `updatedAt`, compared as plain strings exactly as the Worker's upsert
/// does (`Iso8601` guarantees one shape). Equal timestamps apply: the Worker rejects an equal
/// push as "stale", so a dirty row whose write already reached the server must resolve here
/// or it would be re-pushed forever.
public enum MergeRules {
    public static func decide(
        localUpdatedAt: String?,
        localDirty: Bool,
        incomingUpdatedAt: String
    ) -> MergeDecision {
        guard let localUpdatedAt else { return .insert }
        if localDirty && localUpdatedAt > incomingUpdatedAt { return .keepLocal }
        return incomingUpdatedAt >= localUpdatedAt ? .apply : .ignore
    }
}
