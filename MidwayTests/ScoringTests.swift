import XCTest
@testable import Midway

final class ScoringTests: XCTestCase {

    private func participant(name: String,
                             lat: Double, lon: Double,
                             mode: TransportMode = .transit,
                             maxMinutes: Int = 30,
                             budget: BudgetRange = .medium,
                             interests: [String] = []) -> PlanningParticipant {
        PlanningParticipant(
            id: UUID(), name: name,
            transportMode: mode, maxTravelMinutes: maxMinutes,
            budget: budget, interests: interests,
            coordinate: Coordinate(latitude: lat, longitude: lon)
        )
    }

    // MARK: - Fairness

    func testEqualTravelTimesScoreNearPerfect() {
        let a = participant(name: "A", lat: 37.76, lon: -122.41)
        let b = participant(name: "B", lat: 37.78, lon: -122.43)
        let travel: [UUID: Double] = [a.id: 15, b.id: 15]

        let score = MeetupScoring.fairness(travelMinutes: travel, participants: [a, b])
        XCTAssertEqual(score, 1.0, accuracy: 0.001)
    }

    func testWideSpreadScoresLow() {
        let a = participant(name: "A", lat: 37.76, lon: -122.41)
        let b = participant(name: "B", lat: 37.78, lon: -122.43, maxMinutes: 20)
        // A walks 5 minutes, B travels 50 — clearly unfair and over B's limit.
        let travel: [UUID: Double] = [a.id: 5, b.id: 50]

        let score = MeetupScoring.fairness(travelMinutes: travel, participants: [a, b])
        XCTAssertLessThan(score, 0.3)
    }

    func testExceedingPersonalLimitIsPenalizedEvenWhenBalanced() {
        let a = participant(name: "A", lat: 37.76, lon: -122.41, maxMinutes: 20)
        let b = participant(name: "B", lat: 37.78, lon: -122.43, maxMinutes: 20)
        let balanced: [UUID: Double] = [a.id: 40, b.id: 40]
        let withinLimits: [UUID: Double] = [a.id: 15, b.id: 15]

        let overScore = MeetupScoring.fairness(travelMinutes: balanced, participants: [a, b])
        let okScore = MeetupScoring.fairness(travelMinutes: withinLimits, participants: [a, b])
        XCTAssertLessThan(overScore, okScore)
    }

    // MARK: - Interest match

    func testInterestMatchFindsOverlap() {
        let a = participant(name: "A", lat: 0, lon: 0, interests: ["Live music", "Coffee"])
        let venue = Venue(name: "Blue Note Coffee", category: "Cafe",
                          areaName: "Mission", coordinate: Coordinate(latitude: 0, longitude: 0))

        let score = MeetupScoring.interestMatch(venue: venue, participants: [a])
        XCTAssertGreaterThan(score, 0.5)
    }

    func testNoInterestsScoresNeutral() {
        let a = participant(name: "A", lat: 0, lon: 0, interests: [])
        let venue = Venue(name: "Somewhere", category: "Bar",
                          areaName: "", coordinate: Coordinate(latitude: 0, longitude: 0))

        XCTAssertEqual(MeetupScoring.interestMatch(venue: venue, participants: [a]), 0.5)
    }

    // MARK: - Budget

    func testBudgetUsesTightestParticipant() {
        let frugal = participant(name: "A", lat: 0, lon: 0, budget: .low)
        let spender = participant(name: "B", lat: 0, lon: 0, budget: .high)
        let priceyVenue = Venue(name: "Fancy", category: "Restaurant", areaName: "",
                                coordinate: Coordinate(latitude: 0, longitude: 0),
                                priceLevel: .high)

        let score = MeetupScoring.budgetFit(venue: priceyVenue,
                                            participants: [frugal, spender],
                                            cap: nil)
        XCTAssertLessThan(score, 0.5)
    }

    func testUnknownPriceIsNeutral() {
        let a = participant(name: "A", lat: 0, lon: 0, budget: .low)
        let venue = Venue(name: "Unknown", category: "Cafe", areaName: "",
                          coordinate: Coordinate(latitude: 0, longitude: 0))

        XCTAssertEqual(MeetupScoring.budgetFit(venue: venue, participants: [a], cap: nil), 0.7)
    }

    // MARK: - Midpoint

    func testWeightedMidpointPullsTowardSlowerTraveler() {
        let walker = participant(name: "W", lat: 37.70, lon: -122.40, mode: .walking)
        let driver = participant(name: "D", lat: 37.80, lon: -122.40, mode: .driving)

        let midpoint = MeetupScoring.weightedMidpoint(of: [walker, driver])
        XCTAssertNotNil(midpoint)
        // Slower (walking) participant should pull the center below 37.75.
        XCTAssertLessThan(midpoint!.latitude, 37.75)
        XCTAssertGreaterThan(midpoint!.latitude, 37.70)
    }

    func testApproximateCoordinateRoundsToKilometerScale() {
        let exact = Coordinate(latitude: 37.76123, longitude: -122.41987)
        let approx = exact.approximate
        XCTAssertEqual(approx.latitude, 37.76, accuracy: 0.0001)
        XCTAssertEqual(approx.longitude, -122.42, accuracy: 0.0001)
        XCTAssertLessThan(exact.distance(to: approx), 1500)
    }

    // MARK: - Time windows

    func testTonightSuggestsSevenPM() {
        let window = TimeWindow(kind: .tonight)
        let time = window.suggestedTime()
        let hour = Calendar.current.component(.hour, from: time)
        XCTAssertEqual(hour, 19)
    }

    func testNowLeavesTravelBuffer() {
        let reference = Date()
        let time = TimeWindow.now.suggestedTime(from: reference)
        XCTAssertEqual(time.timeIntervalSince(reference), 45 * 60, accuracy: 1)
    }
}
