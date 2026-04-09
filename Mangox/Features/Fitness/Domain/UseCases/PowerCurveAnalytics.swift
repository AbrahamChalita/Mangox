// Features/Fitness/Domain/UseCases/PowerCurveAnalytics.swift
import Foundation

/// Best average power for fixed durations (max over all rides), classic “power curve” buckets.
enum PowerCurveAnalytics {
    /// Standard durations in seconds (5s … 1h).
    static let standardDurations: [Int] = [5, 15, 30, 60, 120, 300, 480, 1200, 3600]

    struct Point: Identifiable, Sendable {
        var id: Int { durationSeconds }
        let durationSeconds: Int
        let watts: Int
    }

    /// Builds a curve from per-second power streams (one array per workout).
    static func compute(from powerStreams: [[Int]]) -> [Point] {
        guard !powerStreams.isEmpty else { return [] }

        var bestByDuration: [Int: Int] = [:]
        for window in standardDurations {
            var best = 0
            for stream in powerStreams where stream.count >= window {
                best = max(best, bestRollingAverage(powers: stream, window: window))
            }
            if best > 0 {
                bestByDuration[window] = best
            }
        }

        return standardDurations.compactMap { d in
            guard let w = bestByDuration[d], w > 0 else { return nil }
            return Point(durationSeconds: d, watts: w)
        }
    }

    static func bestRollingAverage(powers: [Int], window: Int) -> Int {
        guard window > 0, !powers.isEmpty else { return 0 }
        guard powers.count >= window else {
            let sum = powers.reduce(0, +)
            return sum / max(1, powers.count)
        }
        var sum = powers.prefix(window).reduce(0, +)
        var best = sum
        for i in window..<powers.count {
            sum += powers[i] - powers[i - window]
            best = max(best, sum)
        }
        return (best + window / 2) / window
    }
}
