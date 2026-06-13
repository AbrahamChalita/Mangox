import Foundation

/// Precomputed on-device coach tool payloads for a chat session (built once, reused per turn).
struct CoachOnDeviceToolDigestBundle: Sendable {
    let recentWorkouts: String
    let riderExtended: String
    let ftpHistory: String
    let whoopRecovery: String
    let activePlan: String
    let decouplingTrend: String
    let powerCurveSummary: String
    let criticalPower: String
    let planForwardDailyTSS: [Double]
}
