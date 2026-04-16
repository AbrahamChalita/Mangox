// Features/Fitness/Domain/Entities/WorkoutMetricsSnapshot.swift
import Foundation

/// A plain, Sendable snapshot of a Workout's data needed for PMC, power-curve,
/// and plan-compliance calculations. Replaces direct `@Model Workout` references in
/// FitnessViewModel, keeping the Domain and Presentation layers free of SwiftData.
///
/// - Note: `init(from:)` accepts a live `@Model Workout` object intentionally —
///   it is called in the View layer where `@Query` provides SwiftData results.
///   `FitnessViewModel` itself never sees `Workout` directly.
struct WorkoutMetricsSnapshot: Sendable {
    let startDate: Date
    let tss: Double
    let sampleCount: Int
    let maxPower: Int
    /// Power values in elapsed-second order — pre-sorted from `workout.samples`.
    let sortedPowers: [Int]

    /// PMC, plan-week TSS, and metadata only — avoids sorting power samples (O(rides) instead of O(samples)).
    init(pmcFieldsFrom workout: Workout) {
        self.startDate = workout.startDate
        self.tss = workout.tss
        self.sampleCount = workout.sampleCount
        self.maxPower = Int(workout.maxPower)
        self.sortedPowers = []
    }

    /// Full snapshot including sorted power stream — only use for power-curve work (cap how many you build).
    init(from workout: Workout) {
        self.startDate = workout.startDate
        self.tss = workout.tss
        self.sampleCount = workout.sampleCount
        self.maxPower = Int(workout.maxPower)
        let sorted = workout.samples.sorted { $0.elapsedSeconds < $1.elapsedSeconds }
        self.sortedPowers = sorted.map { $0.power }
    }

    /// Up to `limit` recent rides in the window that qualify for the power curve (each pays a sample sort).
    static func powerCurveCandidates(
        from workouts: [Workout],
        rangeDays: Int,
        limit: Int = 80
    ) -> [WorkoutMetricsSnapshot] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let cutoff = cal.date(byAdding: .day, value: -rangeDays, to: today) ?? .distantPast
        var result: [WorkoutMetricsSnapshot] = []
        result.reserveCapacity(min(limit, workouts.count))
        for workout in workouts {
            guard result.count < limit else { break }
            guard workout.startDate >= cutoff else { continue }
            guard workout.sampleCount >= 5, workout.maxPower > 0 else { continue }
            let snap = WorkoutMetricsSnapshot(from: workout)
            guard snap.sortedPowers.count >= 5 else { continue }
            result.append(snap)
        }
        return result
    }
}
