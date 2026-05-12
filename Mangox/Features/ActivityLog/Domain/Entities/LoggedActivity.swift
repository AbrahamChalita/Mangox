// Features/ActivityLog/Domain/Entities/LoggedActivity.swift
import Foundation

struct LoggedActivity: Identifiable, Sendable, Hashable {
    let id: UUID
    let source: LoggedActivitySource
    /// Whoop activity UUID or Strava activity id string. `nil` for manual entries.
    let externalID: String?
    let type: LoggedActivityType
    /// Non-nil only when type == .other.
    let customLabel: String?
    let startDate: Date
    let durationSeconds: Int
    let intensity: LoggedActivityIntensity?
    let rpe: Int?
    let notes: String
    let metrics: LoggedActivityMetrics
    let createdAt: Date
    let updatedAt: Date

    var displayName: String {
        if type == .other, let label = customLabel, !label.isEmpty { return label }
        return type.displayName
    }

    var durationFormatted: String {
        let h = durationSeconds / 3600
        let m = (durationSeconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
