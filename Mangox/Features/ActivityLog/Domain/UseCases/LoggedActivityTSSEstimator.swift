// Features/ActivityLog/Domain/UseCases/LoggedActivityTSSEstimator.swift
import Foundation

/// Pure, dependency-free TSS estimator for non-cycling logged activities.
/// Cycling rides are already excluded from `LoggedActivity` by the Strava/Whoop
/// importers, so output of this estimator is always safe to *add* to power-based
/// `Workout.tss` for daily/weekly aggregates without double counting.
///
/// Heuristic chain (industry-standard, in priority order):
/// 1. HR-based hrTSS (TrainingPeaks/Joe Friel) when avg HR + max HR are available.
/// 2. Whoop strain → TSS (strain × 7 ≈ 100 TSS at strain 14).
/// 3. Strava relative effort / suffer score (≈ 1:1 with TSS).
/// 4. RPE (Foster session-RPE → IF² × hours × 100).
/// 5. Intensity enum → mapped IF.
/// 6. Duration-only fallback at IF 0.65 (0.70 for strength).
///
/// All inputs are `Sendable`, so this can run off the main actor.
enum LoggedActivityTSSEstimator {

    /// Lightweight HR profile snapshot. Captured up-front (typically from
    /// `HeartRateZone` on the main thread) so the estimator stays pure.
    struct Profile: Sendable, Hashable {
        let maxHR: Int?
        let restingHR: Int?

        static let none = Profile(maxHR: nil, restingHR: nil)

        /// Reads the live user profile from `HeartRateZone` (UserDefaults-backed).
        static func current() -> Profile {
            let max = HeartRateZone.maxHR
            let resting = HeartRateZone.hasRestingHR ? HeartRateZone.restingHR : nil
            return Profile(maxHR: max > 0 ? max : nil, restingHR: resting)
        }
    }

    /// Best-effort TSS estimate. Returns 0 if duration is non-positive.
    static func estimate(_ activity: LoggedActivity, profile: Profile) -> Double {
        let hours = Double(activity.durationSeconds) / 3600.0
        guard hours > 0 else { return 0 }

        if let avg = activity.metrics.avgHeartRate, avg > 0,
           let maxHR = profile.maxHR, maxHR > 0 {
            let lthr = lactateThresholdHR(maxHR: maxHR, restingHR: profile.restingHR)
            let intensityFactor = clampIF(Double(avg) / Double(max(lthr, 1)))
            return hours * intensityFactor * intensityFactor * 100
        }

        if let strain = activity.metrics.strain, strain > 0 {
            return strain * 7.0
        }

        if let re = activity.metrics.relativeEffort, re > 0 {
            return Double(re)
        }

        if let rpe = activity.rpe, rpe > 0 {
            let intensityFactor = clampIF(Double(rpe) / 10.0)
            return hours * intensityFactor * intensityFactor * 100
        }

        if let intensity = activity.intensity {
            let intensityFactor: Double
            switch intensity {
            case .easy: intensityFactor = 0.65
            case .moderate: intensityFactor = 0.78
            case .hard: intensityFactor = 0.92
            case .max: intensityFactor = 1.05
            }
            return hours * intensityFactor * intensityFactor * 100
        }

        let intensityFactor = activity.type.isStrength ? 0.70 : 0.65
        return hours * intensityFactor * intensityFactor * 100
    }

    /// Karvonen-style LTHR when resting HR is set (mid-zone 4 ≈ 85% HRR + resting),
    /// otherwise the conventional 89% of max HR.
    private static func lactateThresholdHR(maxHR: Int, restingHR: Int?) -> Int {
        if let resting = restingHR, resting > 0, resting < maxHR {
            let hrr = Double(maxHR - resting)
            return Int((hrr * 0.85).rounded()) + resting
        }
        return Int((Double(maxHR) * 0.89).rounded())
    }

    private static func clampIF(_ value: Double) -> Double {
        min(max(value, 0.4), 1.15)
    }
}

extension LoggedActivity {
    /// Estimated TSS using the live user HR profile. For off-main work, capture a
    /// `LoggedActivityTSSEstimator.Profile` once and call `estimate(_:profile:)` directly.
    var estimatedTSS: Double {
        LoggedActivityTSSEstimator.estimate(self, profile: .current())
    }
}
