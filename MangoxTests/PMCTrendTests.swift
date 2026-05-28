import XCTest
@testable import Mangox

final class PMCTrendTests: XCTestCase {

    func testWindowSummary_computesDeltas() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let history: [FitnessDayEntry] = (0..<30).map { offset in
            let date = cal.date(byAdding: .day, value: offset, to: start)!
            let ctl = 40.0 + Double(offset) * 0.5
            let atl = 35.0 + Double(offset) * 0.3
            return FitnessDayEntry(
                date: date,
                ctl: ctl,
                atl: atl,
                tsb: ctl - atl,
                tss: 50
            )
        }

        let summary = PMCTrend.windowSummary(history: history, days: 14)

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.days, 14)
        XCTAssertGreaterThan(summary?.ctlDelta ?? 0, 5)
        XCTAssertGreaterThan(summary?.ctlPerWeek ?? 0, 0)
    }

    func testCompactTrendLine_includesBothWindowsWhenPossible() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let history: [FitnessDayEntry] = (0..<35).map { offset in
            let date = cal.date(byAdding: .day, value: offset, to: start)!
            let ctl = 45.0
            let atl = 30.0 + Double(offset) * 0.1
            return FitnessDayEntry(
                date: date,
                ctl: ctl,
                atl: atl,
                tsb: ctl - atl,
                tss: 40
            )
        }

        let line = PMCTrend.compactTrendLine(history: history)

        XCTAssertNotNil(line)
        XCTAssertTrue(line?.contains("14d") == true)
        XCTAssertTrue(line?.contains("28d") == true)
    }
}
