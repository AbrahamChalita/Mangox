import Foundation

/// Contract for PMC (Performance Management Chart) computation.
/// Concrete implementation: `FitnessTracker` in Fitness/Data/.
@MainActor
protocol FitnessTrackerProtocol: AnyObject {
    var history: [FitnessDayEntry] { get }
    var weeklyHistory: [WeekSummary] { get }
    var today: FitnessDayEntry? { get }
    var currentCTL: Double { get }
    var currentATL: Double { get }
    var currentTSB: Double { get }
    var currentFormState: FormState { get }
    var weeklyTSSGoal: Double { get }
    var currentWeekTSS: Double { get }
    var currentWeekProgress: Double { get }

    func compute(from workouts: [Workout]) async
}
