import Testing
@testable import Mangox

struct PowerCurveAnalyticsTests {
    @Test func rollingAverage_findsPlateau() {
        let p = Array(repeating: 200, count: 100)
        let best5 = PowerCurveAnalytics.bestRollingAverage(powers: p, window: 5)
        #expect(best5 == 200)
    }

    @Test func compute_picksBestAcrossStreams() {
        let flat = Array(repeating: 150, count: 120)
        var spike = Array(repeating: 100, count: 60)
        spike.append(contentsOf: Array(repeating: 400, count: 10))
        spike.append(contentsOf: Array(repeating: 100, count: 60))
        let points = PowerCurveAnalytics.compute(from: [flat, spike])
        let five = points.first { $0.durationSeconds == 5 }
        #expect(five?.watts == 400)
    }
}
