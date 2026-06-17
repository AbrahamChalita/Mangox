import XCTest
@testable import Mangox

final class TrainingLoadMathTests: XCTestCase {
    func testUsesSameEmaConstantsAsFitnessTrackerAndProjection() {
        XCTAssertEqual(TrainingLoadMath.ctlAlpha, 2.0 / 43.0, accuracy: 0.000001)
        XCTAssertEqual(TrainingLoadMath.atlAlpha, 2.0 / 8.0, accuracy: 0.000001)
    }

    func testCombinesInternalStravaWhoopAndLoggedLoadsByDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 17))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let points = TrainingLoadMath.buildPoints(
            inputs: [
                TrainingLoadInput(startDate: yesterday, tss: 90),
                TrainingLoadInput(startDate: yesterday.addingTimeInterval(3600), tss: 20),
                TrainingLoadInput(startDate: today, tss: 40),
            ],
            rangeDays: 2,
            now: today,
            calendar: calendar,
            warmBackDays: 0
        )

        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[1].ctl, 110 * TrainingLoadMath.ctlAlpha, accuracy: 0.000001)
        XCTAssertEqual(points[1].atl, 110 * TrainingLoadMath.atlAlpha, accuracy: 0.000001)
        XCTAssertLessThan(points.last?.tsb ?? 0, 0)
    }

    func testPositiveRecoveryCanCoexistWithFatiguedTrainingLoadForm() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 17))!

        let inputs: [TrainingLoadInput] = (0..<6).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return TrainingLoadInput(startDate: date, tss: 95)
        }

        let latest = TrainingLoadMath.buildPoints(
            inputs: inputs,
            rangeDays: 7,
            now: today,
            calendar: calendar,
            warmBackDays: 0
        ).last

        let whoopRecovery = 70
        XCTAssertGreaterThanOrEqual(whoopRecovery, 67)
        XCTAssertLessThan(latest?.tsb ?? 0, -10)
    }
}
