import Foundation

/// Contract for Strava OAuth and activity upload.
/// Concrete implementation: `StravaService` in Social/Data/.
@MainActor
protocol StravaServiceProtocol: AnyObject {
    var isConnected: Bool { get }
    var athleteDisplayName: String? { get }
    var athleteProfileImageURL: URL? { get }
    var isBusy: Bool { get }
    var lastError: String? { get }
    var isConfigured: Bool { get }

    func connect() async throws
    func disconnect()
    func updateActivity(activityID: Int, name: String?, description: String?, sportType: String?) async
    func checkForDuplicate(startDate: Date, elapsedSeconds: Int) async -> Int?
    func uploadWorkoutFile(fileURL: URL, name: String, description: String?, trainer: Bool) async throws
}
