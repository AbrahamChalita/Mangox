// Features/Workout/Domain/Repositories/WorkoutRepository.swift
import Foundation

/// Domain contract for reading and persisting workouts.
/// Concrete implementation: uses SwiftData ModelContext in Data layer.
@MainActor
protocol WorkoutRepository: AnyObject {
    /// Fetches completed, valid workouts sorted by start date descending.
    func fetchCompleted(limit: Int?) async -> [Workout]

    /// Fetches all workouts in a date range.
    func fetch(from start: Date, to end: Date) async -> [Workout]

    /// Persists any in-flight changes to a workout.
    func save(_ workout: Workout) async throws

    /// Permanently removes a workout and its associated samples.
    func delete(_ workout: Workout) async throws
}
