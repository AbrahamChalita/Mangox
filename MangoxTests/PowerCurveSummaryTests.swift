import Testing
@testable import Mangox

struct PowerCurveSummaryTests {
    @Test func format_includesFTPMultiple() {
        let points = [
            PowerCurveAnalytics.Point(durationSeconds: 300, watts: 320),
            PowerCurveAnalytics.Point(durationSeconds: 1200, watts: 280),
        ]

        let text = PowerCurveSummary.format(points: points, ftp: 250, rangeDays: 90)

        #expect(text.contains("5m"))
        #expect(text.contains("320W"))
        #expect(text.contains("1.28× FTP"))
    }

    @Test func format_emptyPoints_returnsNoDataMessage() {
        let text = PowerCurveSummary.format(points: [], ftp: 250)

        #expect(text.contains("No power curve data"))
    }
}
