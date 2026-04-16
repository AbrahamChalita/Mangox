import XCTest

@testable import Mangox

final class OnDeviceModelFallbackCopyTests: XCTestCase {

    func testInstagramStoryCaptionRespectsMaxLength() {
        let w = Workout(startDate: Date())
        w.status = .completed
        w.duration = 7200
        w.avgPower = 210
        w.normalizedPower = 225
        w.intensityFactor = 0.91
        w.tss = 120
        let longRoute = "Alpine Loop " + String(repeating: "X", count: 400)
        let caption = OnDeviceModelFallbackCopy.instagramStoryCaption(
            workout: w,
            dominantZoneName: "Sweet Spot",
            routeName: longRoute,
            ftpWatts: 250,
            powerZoneLine: "Z1 5%, Z2 15%, Z3 55%, Z4 25%"
        )
        XCTAssertLessThanOrEqual(caption.count, 280)
        XCTAssertTrue(caption.contains("#cycling"))
    }

    func testRideSummaryInsightNonEmpty() {
        let w = Workout(startDate: Date())
        w.status = .completed
        w.duration = 2700
        w.avgPower = 180
        w.tss = 55
        w.intensityFactor = 0.72
        let insight = OnDeviceModelFallbackCopy.rideSummaryInsight(
            workout: w,
            powerZoneLine: "Z2 70%, Z3 30%",
            planLine: nil,
            ftpWatts: 250,
            riderCallName: nil
        )
        XCTAssertFalse(insight.headline.isEmpty)
        XCTAssertGreaterThanOrEqual(insight.bullets.count, 2)
        XCTAssertNotNil(insight.narrative)
    }
}
