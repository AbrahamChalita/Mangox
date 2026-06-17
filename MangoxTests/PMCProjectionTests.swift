// MangoxTests/PMCProjectionTests.swift
import XCTest
@testable import Mangox

final class PMCProjectionTests: XCTestCase {

    func testZeroLoad_DecaysTowardZero() {
        let result = PMCProjection.project(
            currentCTL: 45,
            currentATL: 30,
            dailyTSS: Array(repeating: 0.0, count: 90)
        )

        XCTAssertEqual(result.count, 90)
        // CTL uses a 42-day EMA, so decay is deliberately slower than ATL.
        let last = result.last!
        XCTAssertLessThan(last.ctl, 5.0)
        XCTAssertLessThan(last.atl, 2.0)
        XCTAssertGreaterThan(last.tsb, -5.0) // form recovers
    }

    func testConstantWeeklyLoad_ReachesApproximateEquilibrium() {
        // ~400 TSS/week → daily ~57
        let projection = PMCProjection.projectConstantWeeklyLoad(
            currentCTL: 40,
            currentATL: 35,
            weeklyTSS: 400,
            numberOfWeeks: 8
        )

        let last = projection.last!
        let daily = 400.0 / 7.0
        XCTAssertEqual(last.ctl, expectedEMA(start: 40, target: daily, alpha: 2.0 / 43.0, days: 56), accuracy: 0.001)
        XCTAssertEqual(last.atl, expectedEMA(start: 35, target: daily, alpha: 2.0 / 8.0, days: 56), accuracy: 0.001)
        XCTAssertGreaterThan(last.ctl, 54)
        XCTAssertLessThan(last.ctl, 58)
        XCTAssertGreaterThan(last.atl, 56)
        XCTAssertLessThan(last.atl, 58)
    }

    func testProjectionUsesSameAlphaFormulaAsFitnessTracker() {
        // Explicitly pass the alphas that FitnessTracker uses internally
        let ctlDays = 42
        let atlDays = 7
        let ctlAlpha = 2.0 / Double(ctlDays + 1)
        let atlAlpha = 2.0 / Double(atlDays + 1)

        let withExplicit = PMCProjection.project(
            currentCTL: 50,
            currentATL: 40,
            dailyTSS: [60, 55, 70],
            ctlAlpha: ctlAlpha,
            atlAlpha: atlAlpha
        )

        let withDefaults = PMCProjection.project(
            currentCTL: 50,
            currentATL: 40,
            dailyTSS: [60, 55, 70]
        )

        XCTAssertEqual(withExplicit, withDefaults)
    }

    func testSummaryString_IsStableAndInformative() {
        let proj = PMCProjection.project(
            currentCTL: 42,
            currentATL: 28,
            dailyTSS: [50, 55, 45]
        )
        let summary = PMCProjection.summary(from: proj)
        XCTAssertTrue(summary.contains("After 3 days"))
        XCTAssertTrue(summary.contains("CTL"))
        XCTAssertTrue(summary.contains("TSB"))
    }

    func testNegativeTSS_IsClampedToZero() {
        let result = PMCProjection.project(
            currentCTL: 30,
            currentATL: 20,
            dailyTSS: [-100, -50, 0]
        )
        XCTAssertGreaterThanOrEqual(result[0].appliedTSS, 0)
        XCTAssertGreaterThanOrEqual(result[1].appliedTSS, 0)
    }

    private func expectedEMA(start: Double, target: Double, alpha: Double, days: Int) -> Double {
        var value = start
        for _ in 0..<days {
            value = value + alpha * (target - value)
        }
        return value
    }
}
