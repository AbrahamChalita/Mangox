// Features/Home/Domain/Repositories/HomeRepository.swift
import Foundation

/// Domain contract for fetching the lightweight workout slices used by HomeView.
/// Using slices (not full Workout objects) avoids faulting in all samples on the main thread.
@MainActor
protocol HomeRepository: AnyObject {
    /// Returns metric slices for workouts within the last `days` days.
    func fetchRecentWorkoutSlices(days: Int) async -> [HomeWorkoutMetricSlice]

    /// Returns the most recent completed workouts for the recent rides list, capped at `limit`.
    func fetchRecentWorkouts(limit: Int) async -> [Workout]
}
