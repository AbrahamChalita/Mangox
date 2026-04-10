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

    init(from workout: Workout) {
        self.startDate = workout.startDate
        self.tss = workout.tss
        self.sampleCount = workout.sampleCount
        self.maxPower = Int(workout.maxPower)
        let sorted = workout.samples.sorted { $0.elapsedSeconds < $1.elapsedSeconds }
        self.sortedPowers = sorted.map { $0.power }
    }
}
