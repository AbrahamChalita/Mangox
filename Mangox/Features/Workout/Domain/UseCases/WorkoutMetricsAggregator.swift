// Features/Workout/Domain/UseCases/WorkoutMetricsAggregator.swift
import Foundation

/// Normalized power, IF, and TSS from 1 Hz (or denser) power samples — same model as live recording.
enum WorkoutMetricsAggregator {

    /// Rolling 30 s window NP per Coggan; requires at least 30 samples for meaningful NP.
    static func normalizedPowerIntensityAndTSS(
        powerSamples: [Int],
        durationSeconds: Int,
        ftp: Double
    ) -> (np: Double, intensityFactor: Double, tss: Double) {
        guard ftp > 0, !powerSamples.isEmpty, durationSeconds > 0 else {
            return (0, 0, 0)
        }

        // O(1) per sample: fixed-size array as circular buffer + running sum
        // avoids the O(n) removeFirst() and the full reduce() on every iteration.
        var ring = [Int](repeating: 0, count: 30)
        var ringHead = 0
        var ringFull = false
        var runningSum = 0
        var sum4th: Double = 0
        var count4th = 0

        for p in powerSamples {
            if ringFull { runningSum -= ring[ringHead] }
            ring[ringHead] = p
            runningSum += p
            ringHead = (ringHead + 1) % 30
            if !ringFull && ringHead == 0 { ringFull = true }
            guard ringFull else { continue }
            let avg = Double(runningSum) / 30.0
            let a2 = avg * avg
            sum4th += a2 * a2          // pow(avg, 4) without libm overhead
            count4th += 1
        }

        guard count4th > 0 else {
            let avg = Double(powerSamples.reduce(0, +)) / Double(powerSamples.count)
            let ifac = avg / ftp
            let tss = (Double(durationSeconds) * avg * ifac) / (ftp * 3600) * 100
            return (avg, ifac, tss)
        }

        // pow(x, 0.25) == sqrt(sqrt(x)) — avoids general-purpose exponentiation
        let np = sqrt(sqrt(sum4th / Double(count4th)))
        let ifac = np / ftp
        let tss = (Double(durationSeconds) * np * ifac) / (ftp * 3600) * 100
        return (np, ifac, tss)
    }
}
