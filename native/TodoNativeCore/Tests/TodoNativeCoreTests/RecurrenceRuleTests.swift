import Foundation
import Testing
@testable import TodoNativeCore

@Suite("RecurrenceRule")
struct RecurrenceRuleTests {
    @Test("daysOfWeek is dropped for non-weekly frequencies")
    func daysOfWeekOnlyAppliesToWeekly() {
        let daily = RecurrenceRule(frequency: .daily, interval: 1, daysOfWeek: [2, 4])
        #expect(daily.daysOfWeek == nil)

        let weekly = RecurrenceRule(frequency: .weekly, interval: 1, daysOfWeek: [2, 4])
        #expect(weekly.daysOfWeek == [2, 4])
    }

    @Test("round-trips through JSON")
    func codableRoundTrip() throws {
        let rule = RecurrenceRule(frequency: .weekly, interval: 2, daysOfWeek: [1, 7])
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: data)
        #expect(decoded == rule)
    }
}
