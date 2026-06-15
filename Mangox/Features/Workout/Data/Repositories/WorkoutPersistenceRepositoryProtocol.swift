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

/// Payload for cycling rides imported from Strava or WHOOP into the calendar lane.
struct ExternalWorkoutPayload {
    let source: ExternalWorkoutSource
    let externalID: String
    let title: String?
    let format: WorkoutImportFormat
    let startDate: Date
    let durationSeconds: Int
    let distanceMeters: Double
    let elevationGainMeters: Double
    let avgPower: Double
    let maxPower: Int
    let avgHR: Double
    let maxHR: Int
    let avgCadence: Double
    let normalizedPower: Double
    let intensityFactor: Double
    let tss: Double
    let samples: [ImportedWorkoutSamplePayload]
}

/// Data-layer contract for Workout-related SwiftData mutations.
/// This seam keeps direct `ModelContext` writes out of Presentation/ViewModel code.
@MainActor
protocol WorkoutPersistenceRepositoryProtocol: AnyObject {
    /// Called after local workout/template mutations that should be pushed to Supabase.
    func setOnLocalChange(_ block: @escaping () -> Void)
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

    /// Inserts a Strava/WHOOP cycling ride. Skips callers that already deduped by external id or overlap.
    @discardableResult
    func saveExternalWorkout(_ payload: ExternalWorkoutPayload) throws -> Workout

    /// Most recent imported external ride for cursor-based sync windows.
    func mostRecentExternalWorkoutDate(source: ExternalWorkoutSource) throws -> Date?

    /// Returns a workout already linked to the given external source id, if any.
    func fetchExternalWorkout(source: ExternalWorkoutSource, externalID: String) throws -> Workout?

    /// Returns a completed workout overlapping the given start time (±window) and duration (±120s).
    func fetchOverlappingWorkout(
        startDate: Date,
        durationSeconds: Int,
        windowSeconds: Int
    ) throws -> Workout?

    /// Plan day ids that already have a completed linked ride for the given plan.
    func occupiedPlanDayIDs(planID: String) throws -> Set<String>

    /// Fetches a `CustomWorkoutTemplate` by id and converts it to a `PlanDay`. Returns nil if not found.
    /// Used by `IndoorViewModel.prepareWorkoutSession` to load custom workout templates without a direct
    /// ModelContext fetch in the Presentation layer.
    func fetchCustomWorkoutTemplate(id: UUID) throws -> PlanDay?

    /// Fetches the sorted workout samples for a background-context read, returning plain `WorkoutSampleData` values.
    /// Called by `WorkoutViewModel.prepareSummaryData` to eliminate `ModelContext(modelContainer)` construction
    /// from the ViewModel.
    func fetchSortedSamples(forWorkoutID id: PersistentIdentifier) async -> [WorkoutSampleData]
}
