import Foundation
import Testing
@testable import TodoNativeCore

@Suite("Iso8601")
struct Iso8601Tests {
    @Test("formats a whole-second instant in the .NET \"O\" shape")
    func formatsKnownInstant() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(Iso8601.format(date) == "2027-01-15T08:00:00.0000000+00:00")
    }

    @Test("always emits 7 fractional digits and +00:00, never Z")
    func shapeIsAlwaysUniform() {
        let dates = [
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 1_800_000_000.5),
            Date(timeIntervalSince1970: 1_800_000_000.000_001),
            Date(timeIntervalSince1970: 1_900_000_000.999_999_9),
        ]
        for date in dates {
            let text = Iso8601.format(date)
            #expect(text.wholeMatch(of: /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}\+00:00/) != nil, "\(text)")
        }
    }

    @Test("parses Z, +00:00, 3- and 7-digit fractions, and no fraction")
    func parsesSupportedForms() throws {
        let whole = try #require(Iso8601.parse("2026-09-13T15:04:05Z"))
        let z3 = try #require(Iso8601.parse("2026-09-13T15:04:05.500Z"))
        let plus7 = try #require(Iso8601.parse("2026-09-13T15:04:05.5000000+00:00"))

        #expect(z3.timeIntervalSince(whole) == 0.5)
        #expect(plus7 == z3)
        #expect(Iso8601.format(whole) == "2026-09-13T15:04:05.0000000+00:00")
    }

    @Test("converts non-UTC offsets to the same instant")
    func parsesOffsets() throws {
        let utc = try #require(Iso8601.parse("2026-09-13T15:04:05.5Z"))
        let east = try #require(Iso8601.parse("2026-09-13T20:34:05.5+05:30"))
        let west = try #require(Iso8601.parse("2026-09-13T11:04:05.5-04:00"))
        #expect(east == utc)
        #expect(west == utc)
    }

    @Test("rejects malformed and out-of-range strings")
    func rejectsGarbage() {
        let bad = [
            "", "not a date", "2026-09-13", "2026-09-13T15:04:05", "2026-13-01T00:00:00Z",
            "2026-02-30T00:00:00Z", "2026-09-13T25:00:00Z", "2026-09-13T15:04:05.12345678Z",
            "2026-09-13 15:04:05Z",
        ]
        for text in bad {
            #expect(Iso8601.parse(text) == nil, "\(text)")
        }
    }

    @Test("round trip stays within one tick (100 ns)")
    func roundTripWithinOneTick() throws {
        let legacy = [
            "2026-09-13T15:04:05.1234567+00:00",
            "2026-09-14T09:30:00.5000000+00:00",
            "2026-12-31T23:59:59.9999999+00:00",
        ]
        for text in legacy {
            let date = try #require(Iso8601.parse(text))
            let again = try #require(Iso8601.parse(Iso8601.format(date)))
            #expect(abs(again.timeIntervalSince(date)) < 2e-7, "\(text)")
        }
    }

    @Test("string order equals date order, including across second and year boundaries")
    func stringOrderMatchesDateOrder() {
        let start = Date(timeIntervalSince1970: 1_798_761_599.9)
        let dates = (0..<40).map { start.addingTimeInterval(Double($0) * 0.137) }
        let strings = dates.map(Iso8601.format)
        #expect(strings == strings.sorted())
        #expect(Set(strings).count == strings.count)
    }

    @Test("carries into the next second instead of emitting 10000000 ticks")
    func ticksCarry() {
        let date = Date(timeIntervalSince1970: 1_800_000_000.999_999_97)
        let text = Iso8601.format(date)
        #expect(!text.contains(".10000000"))
        #expect(text.hasPrefix("2027-01-15T08:00:0"))
    }
}
