import Foundation

// Features/Profile/Domain/Repositories/WhoopServiceProtocol.swift

/// Contract for Whoop OAuth and recovery data.
/// Concrete implementation: `WhoopService` in Profile/Data/DataSources/.
/// Note: `readinessAccentColor` is intentionally omitted — Color is a Presentation concern.
/// Add it as a SwiftUI extension on `WhoopServiceProtocol` in the Presentation layer.
@MainActor
protocol WhoopServiceProtocol: AnyObject {
    var isConnected: Bool { get }
    var memberDisplayName: String? { get }
    var latestRecoveryScore: Double? { get }
    var latestRecoveryRestingHR: Int? { get }
    var latestRecoveryHRV: Int? { get }
    var latestMaxHeartRateFromProfile: Int? { get }
    /// Latest sleep performance percentage (0–100) from WHOOP, when scored and not a nap.
    var latestSleepPerformancePercent: Double? { get }
    /// Total time in bed for the latest sleep in hours, when scored and not a nap.
    var latestSleepHours: Double? { get }
    /// Respiratory rate in breaths/min from the latest scored sleep.
    var latestRespiratoryRate: Double? { get }
    var isBusy: Bool { get }
    var lastError: String? { get }
    var isConfigured: Bool { get }
    var lastSuccessfulRefreshAt: Date? { get }
    var syncHeartBaselinesFromWhoop: Bool { get set }
    var readinessTrainingHint: String { get }

    func connect() async throws
    func disconnect() async
    func refreshLinkedData() async throws
    func refreshLinkedDataIfStale(maximumAge: TimeInterval) async
    func applyHeartBaselinesFromLatestWhoopData()
    /// Triggers an immediate data refresh. Called by the Supabase webhook relay when WHOOP
    /// pushes a recovery/sleep/workout update — the 24h poll is the fallback when webhooks fail.
    func handleWebhookSignal() async

    func fetchRecentWorkouts(since: Date, until: Date) async throws -> [WhoopWorkoutDTO]
}
