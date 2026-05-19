// Features/Fitness/Domain/UseCases/HealthReadinessAnalytics.swift
import Foundation

/// Interprets morning-style health signals against the rider's own recent baseline.
/// Output is intentionally conservative: it is training context, not a medical status.
enum HealthReadinessAnalytics {
    struct Sample: Sendable {
        let date: Date
        let value: Double
    }

    enum SignalKind: String, Codable, Sendable {
        case hrvSDNN
        case restingHeartRate
        case respiratoryRate
        case sleepMinutes
        case wristTemperatureCelsius
    }

    enum SignalDirection: String, Codable, Sendable {
        case higherIsBetter
        case lowerIsBetter
        case closeToBaseline
    }

    enum SignalStatus: String, Codable, Sendable {
        case favorable
        case normal
        case watch
        case insufficientData
    }

    struct SignalSummary: Codable, Sendable {
        let kind: SignalKind
        let latestValue: Double
        let baselineMean: Double
        let baselineStandardDeviation: Double
        let zScore: Double
        let status: SignalStatus
    }

    struct Snapshot: Codable, Sendable {
        let generatedAt: Date
        let status: SignalStatus
        let score: Int
        let summaries: [SignalSummary]

        var plainLanguageSummary: String {
            switch status {
            case .favorable:
                return "Readiness signals are mostly favorable versus your recent baseline."
            case .normal:
                return "Readiness signals look close to your recent baseline."
            case .watch:
                return "Readiness signals are outside your usual range; keep intensity flexible."
            case .insufficientData:
                return "Not enough readiness data yet to compare against your baseline."
            }
        }
    }

    static let minimumBaselineSamples = 7

    static func summarize(
        kind: SignalKind,
        samples: [Sample],
        direction: SignalDirection,
        calendar: Calendar = .current
    ) -> SignalSummary? {
        let clean = samples
            .filter { $0.value.isFinite && $0.value > 0 }
            .sorted { $0.date < $1.date }
        guard clean.count >= minimumBaselineSamples + 1, let latest = clean.last else { return nil }

        let latestDay = calendar.startOfDay(for: latest.date)
        let baseline = clean.filter { calendar.startOfDay(for: $0.date) < latestDay }.suffix(28)
        guard baseline.count >= minimumBaselineSamples else { return nil }

        let values = baseline.map(\.value)
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return nil }

        let variance = values.reduce(0.0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(values.count)
        let sd = max(sqrt(variance), mean * 0.03)
        let z = (latest.value - mean) / sd

        return SignalSummary(
            kind: kind,
            latestValue: latest.value,
            baselineMean: mean,
            baselineStandardDeviation: sd,
            zScore: z,
            status: status(for: z, direction: direction)
        )
    }

    static func snapshot(
        summaries: [SignalSummary],
        generatedAt: Date = .now
    ) -> Snapshot {
        guard !summaries.isEmpty else {
            return Snapshot(
                generatedAt: generatedAt,
                status: .insufficientData,
                score: 50,
                summaries: []
            )
        }

        var score = 70.0
        for summary in summaries {
            switch summary.status {
            case .favorable:
                score += 6
            case .normal:
                break
            case .watch:
                score -= 14
            case .insufficientData:
                break
            }
        }
        let clamped = min(95, max(20, Int(score.rounded())))
        let watchCount = summaries.filter { $0.status == .watch }.count
        let favorableCount = summaries.filter { $0.status == .favorable }.count

        let overall: SignalStatus
        if watchCount >= 2 {
            overall = .watch
        } else if watchCount == 0 && favorableCount >= 2 {
            overall = .favorable
        } else {
            overall = .normal
        }

        return Snapshot(
            generatedAt: generatedAt,
            status: overall,
            score: clamped,
            summaries: summaries
        )
    }

    private static func status(
        for zScore: Double,
        direction: SignalDirection
    ) -> SignalStatus {
        switch direction {
        case .higherIsBetter:
            if zScore <= -1.25 { return .watch }
            if zScore >= 1.0 { return .favorable }
            return .normal
        case .lowerIsBetter:
            if zScore >= 1.25 { return .watch }
            if zScore <= -1.0 { return .favorable }
            return .normal
        case .closeToBaseline:
            return abs(zScore) >= 1.5 ? .watch : .normal
        }
    }
}
