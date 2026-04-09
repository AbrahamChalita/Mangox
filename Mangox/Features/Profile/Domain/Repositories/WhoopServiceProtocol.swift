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
    var isBusy: Bool { get }
    var lastError: String? { get }
    var isConfigured: Bool { get }
    var syncHeartBaselinesFromWhoop: Bool { get set }
    var readinessTrainingHint: String { get }

    func connect() async throws
    func disconnect() async
    func refreshLinkedData() async throws
    func refreshLinkedDataIfStale(maximumAge: TimeInterval) async
    func applyHeartBaselinesFromLatestWhoopData()
}
