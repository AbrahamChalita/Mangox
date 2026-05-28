// Features/Fitness/Domain/UseCases/TrainingMath/PMCTrend.swift
import Foundation

/// Derived PMC trends over fixed lookback windows (14 / 28 days) for coach context.
nonisolated enum PMCTrend {

    struct WindowSummary: Sendable, Equatable {
        let days: Int
        let ctlDelta: Double
        let atlDelta: Double
        let tsbDelta: Double
        /// Approximate CTL change per week over the window.
        let ctlPerWeek: Double

        var plainLanguageSummary: String {
            String(
                format: "%dd: CTL %+.1f (%.1f/wk), ATL %+.1f, TSB %+.1f",
                days,
                ctlDelta,
                ctlPerWeek,
                atlDelta,
                tsbDelta
            )
        }
    }

    /// Computes delta from `days` ago to the latest entry in ascending history.
    nonisolated static func windowSummary(
        history: [FitnessDayEntry],
        days: Int
    ) -> WindowSummary? {
        guard days > 0, history.count >= 2, let latest = history.last else { return nil }

        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -days, to: latest.date) else { return nil }

        guard let start = history.first(where: { $0.date >= cutoff }) ?? history.first else {
            return nil
        }

        let ctlDelta = latest.ctl - start.ctl
        let atlDelta = latest.atl - start.atl
        let tsbDelta = latest.tsb - start.tsb
        let weeks = max(1, Double(days) / 7.0)
        let ctlPerWeek = ctlDelta / weeks

        return WindowSummary(
            days: days,
            ctlDelta: ctlDelta,
            atlDelta: atlDelta,
            tsbDelta: tsbDelta,
            ctlPerWeek: ctlPerWeek
        )
    }

    nonisolated static func compactTrendLine(history: [FitnessDayEntry]) -> String? {
        let w14 = windowSummary(history: history, days: 14)
        let w28 = windowSummary(history: history, days: 28)
        switch (w14, w28) {
        case let (a?, b?):
            return "PMC trend — 14d: \(a.plainLanguageSummary); 28d: \(b.plainLanguageSummary)"
        case let (a?, nil):
            return "PMC trend — 14d: \(a.plainLanguageSummary)"
        case let (nil, b?):
            return "PMC trend — 28d: \(b.plainLanguageSummary)"
        default:
            return nil
        }
    }
}
