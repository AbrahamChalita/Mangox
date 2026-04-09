import Foundation
import SwiftUI

/// Contract for Whoop OAuth and recovery data.
/// Concrete implementation: `WhoopService` in Profile/Data/.
@MainActor
protocol WhoopServiceProtocol: AnyObject {
    var isConnected: Bool { get }
    var memberDisplayName: String? { get }
    var latestRecoveryScore: Double? { get }
    var latestRecoveryRestingHR: Int? { get }
    var latestRecoveryHRV: Int? { get }
    var isBusy: Bool { get }
    var lastError: String? { get }
    var isConfigured: Bool { get }
    var syncHeartBaselinesFromWhoop: Bool { get set }
    var readinessAccentColor: Color { get }
    var readinessTrainingHint: String { get }

    func connect() async throws
    func disconnect() async
    func refreshLinkedData() async throws
    func refreshLinkedDataIfStale(maximumAge: TimeInterval) async
    func applyHeartBaselinesFromLatestWhoopData()
}
