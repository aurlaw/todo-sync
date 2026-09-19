import Foundation

public enum Frequency: String, Codable, Sendable {
    case daily
    case weekly
    case monthly
}

public struct RecurrenceRule: Codable, Sendable, Equatable {
    public var frequency: Frequency
    public var interval: Int
    /// Weekly only. 1 = Sunday...7 = Saturday, matching `Calendar.Component.weekday`.
    public var daysOfWeek: Set<Int>?

    public init(frequency: Frequency, interval: Int = 1, daysOfWeek: Set<Int>? = nil) {
        precondition(interval >= 1, "interval must be >= 1")
        self.frequency = frequency
        self.interval = interval
        self.daysOfWeek = frequency == .weekly ? daysOfWeek : nil
    }

    enum CodingKeys: String, CodingKey {
        case frequency, interval, daysOfWeek
    }

    /// A Set encodes in unstable order; the wire string must be deterministic, so days are sorted.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(interval, forKey: .interval)
        try container.encodeIfPresent(daysOfWeek?.sorted(), forKey: .daysOfWeek)
    }
}
