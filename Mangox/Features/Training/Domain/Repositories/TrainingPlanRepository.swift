// Features/Training/Domain/Repositories/TrainingPlanRepository.swift
import Foundation

/// Domain contract for training plan progress persistence.
/// Concrete implementation: uses SwiftData ModelContext in Data layer.
@MainActor
protocol TrainingPlanRepository: AnyObject {
    /// Returns the most recently started active plan progress, or nil when none exists.
    func fetchActivePlanProgress() async -> TrainingPlanProgress?

    /// Saves mutations to a plan progress record.
    func save(_ progress: TrainingPlanProgress) async throws

    /// Marks a specific plan day as completed.
    func markCompleted(dayID: String, in progress: TrainingPlanProgress) async throws

    /// Clears completion state for a plan day (e.g. when a linked workout is deleted).
    func markIncomplete(dayID: String, in progress: TrainingPlanProgress) async throws
}
