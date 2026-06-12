import XCTest
@testable import Midway

/// Suggested times must never land in the past — this regression hid in
/// CI for hours because "tonight at 7 PM" only breaks after 7 PM.
final class TimeWindowTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(weekday: Int, hour: Int) -> Date {
        // Wednesday June 10, 2026 is a known anchor; offset to the weekday.
        let anchor = DateComponents(calendar: calendar, year: 2026, month: 6,
                                    day: 10, hour: hour).date!
        let anchorWeekday = calendar.component(.weekday, from: anchor)
        return calendar.date(byAdding: .day, value: weekday - anchorWeekday, to: anchor)!
    }

    func testTonightBeforeSevenSuggestsSeven() {
        let afternoon = date(weekday: 4, hour: 15)
        let suggested = TimeWindow(kind: .tonight).suggestedTime(calendar: calendar, from: afternoon)
        XCTAssertEqual(calendar.component(.hour, from: suggested), 19)
        XCTAssertTrue(calendar.isDate(suggested, inSameDayAs: afternoon))
    }

    func testTonightAfterSevenStaysInTheFuture() {
        let evening = date(weekday: 4, hour: 21)
        let suggested = TimeWindow(kind: .tonight).suggestedTime(calendar: calendar, from: evening)
        XCTAssertGreaterThan(suggested, evening)
        XCTAssertTrue(calendar.isDate(suggested, inSameDayAs: evening))
    }

    func testWeekendFromWeekdayIsSaturdayAfternoon() {
        let wednesday = date(weekday: 4, hour: 12)
        let suggested = TimeWindow(kind: .thisWeekend).suggestedTime(calendar: calendar, from: wednesday)
        XCTAssertTrue(calendar.isDateInWeekend(suggested))
        XCTAssertEqual(calendar.component(.hour, from: suggested), 14)
        XCTAssertGreaterThan(suggested, wednesday)
    }

    func testWeekendLateSaturdayRollsToSunday() {
        let saturdayEvening = date(weekday: 7, hour: 20)
        let suggested = TimeWindow(kind: .thisWeekend).suggestedTime(calendar: calendar, from: saturdayEvening)
        XCTAssertGreaterThan(suggested, saturdayEvening)
        XCTAssertTrue(calendar.isDateInWeekend(suggested))
    }

    func testTomorrowIsAlwaysFuture() {
        let lateNight = date(weekday: 4, hour: 23)
        let suggested = TimeWindow(kind: .tomorrow).suggestedTime(calendar: calendar, from: lateNight)
        XCTAssertGreaterThan(suggested, lateNight)
    }
}
