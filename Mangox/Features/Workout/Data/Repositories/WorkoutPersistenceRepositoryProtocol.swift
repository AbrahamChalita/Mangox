import Foundation
import SwiftData

struct ImportedWorkoutSamplePayload {
    let timestamp: Date
    let elapsedSeconds: Int
    let power: Int
    let cadence: Double
    let speed: Double
    let heartRate: Int
}

struct ImportedWorkoutPayload {
    let fileName: String
    let format: WorkoutImportFormat
    let startDate: Date
    let durationSeconds: Int
    let distanceMeters: Double
    let avgPower: Double
    let maxPower: Int
    let avgHR: Double
    let maxHR: Int
    let samples: [ImportedWorkoutSamplePayload]
}

/// Data-layer contract for Workout-related SwiftData mutations.
/// This seam keeps direct `ModelContext` writes out of Presentation/ViewModel code.
@MainActor
protocol WorkoutPersistenceRepositoryProtocol: AnyObject {
    /// Persists a derived custom workout template from a completed workout.
    /// - Returns: The saved template id when successful; otherwise `nil`.
    func saveWorkoutAsCustomTemplate(from workout: Workout) throws -> UUID?

    /// Persists a custom workout template directly from generated content.
    func saveCustomWorkoutTemplate(name: String, intervals: [IntervalSegment]) throws -> UUID

    /// Deletes the workout and performs any required related mutations (for example unmarking plan-day progress).
    func deleteWorkout(_ workout: Workout) throws

    /// Inserts a completed outdoor workout + all its lap splits and saves. Posts the aggregate-change notification.
    func saveOutdoorRide(workout: Workout, splits: [LapSplit]) throws

    /// Inserts a completed imported workout and saves. Posts the aggregate-change notification.
    @discardableResult
    func saveImportedWorkout(_ payload: ImportedWorkoutPayload) throws -> Workout

    /// Fetches a `CustomWorkoutTemplate` by id and converts it to a `PlanDay`. Returns nil if not found.
    /// Used by `IndoorViewModel.prepareWorkoutSession` to load custom workout templates without a direct
    /// ModelContext fetch in the Presentation layer.
    func fetchCustomWorkoutTemplate(id: UUID) throws -> PlanDay?

    /// Fetches the sorted workout samples for a background-context read, returning plain `WorkoutSampleData` values.
    /// Called by `WorkoutViewModel.prepareSummaryData` to eliminate `ModelContext(modelContainer)` construction
    /// from the ViewModel.
    func fetchSortedSamples(forWorkoutID id: PersistentIdentifier) async -> [WorkoutSampleData]
}
