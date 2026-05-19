import Foundation
import Testing
@testable import Mangox

@MainActor
struct HealthReadinessAnalyticsTests {
    @Test func hrvDropAgainstBaseline_isWatchStatus() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        var samples: [HealthReadinessAnalytics.Sample] = []
        for offset in 0..<14 {
            samples.append(.init(
                date: calendar.date(byAdding: .day, value: offset, to: start)!,
                value: 60
            ))
        }
        samples.append(.init(
            date: calendar.date(byAdding: .day, value: 14, to: start)!,
            value: 45
        ))

        let summary = HealthReadinessAnalytics.summarize(
            kind: .hrvSDNN,
            samples: samples,
            direction: .higherIsBetter,
            calendar: calendar
        )

        #expect(summary?.status == .watch)
        #expect((summary?.zScore ?? 0) < 0)
    }

    @Test func snapshotWithTwoFavorableSignals_isFavorable() {
        let summaries = [
            HealthReadinessAnalytics.SignalSummary(
                kind: .hrvSDNN,
                latestValue: 70,
                baselineMean: 60,
                baselineStandardDeviation: 5,
                zScore: 2,
                status: .favorable
            ),
            HealthReadinessAnalytics.SignalSummary(
                kind: .restingHeartRate,
                latestValue: 48,
                baselineMean: 52,
                baselineStandardDeviation: 2,
                zScore: -2,
                status: .favorable
            ),
        ]

        let snapshot = HealthReadinessAnalytics.snapshot(summaries: summaries)

        #expect(snapshot.status == .favorable)
        #expect(snapshot.score > 70)
    }
}
