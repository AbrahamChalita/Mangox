import Foundation

/// Contract for reading and writing health data.
/// Concrete implementation: `HealthKitManager` in Fitness/Data/.
@MainActor
protocol HealthKitServiceProtocol: AnyObject {
    var isAuthorized: Bool { get }
    var restingHeartRate: Int? { get }
    var maxHeartRate: Int? { get }
    var dateOfBirth: DateComponents? { get }
    var vo2Max: Double? { get }
    var lastError: String? { get }
    var workoutSyncToHealthLastError: String? { get }
    var syncWorkoutsToAppleHealth: Bool { get set }
    var effectiveMaxHR: Int { get }
    var currentAge: Int? { get }

    func requestAuthorization() async

    // MARK: - Workout Sync
    func saveCyclingWorkoutToHealthIfEnabled(_ workout: Workout) async
}
