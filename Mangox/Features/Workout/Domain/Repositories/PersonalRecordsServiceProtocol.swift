import Foundation

/// Contract for Mean Maximal Power computation and personal record tracking.
/// Concrete implementation: `PersonalRecords` in Fitness/Data/DataSources/.
@MainActor
protocol PersonalRecordsServiceProtocol: AnyObject {
    // MARK: - State
    var allTimePRs: [PREntry] { get }
    var isLoaded: Bool { get }

    // MARK: - Methods
    func load(from workouts: [Workout]) async
    func computeMMP(for samples: [WorkoutSampleData], workoutID: UUID) -> WorkoutMMP?
    func newPRs(for mmp: WorkoutMMP) -> [NewPRFlag]
    func allTimePRResult(for duration: MMPDuration) -> PREntry?
}
