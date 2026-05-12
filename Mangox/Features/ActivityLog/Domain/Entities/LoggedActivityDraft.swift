// Features/ActivityLog/Domain/Entities/LoggedActivityDraft.swift
import Foundation

/// Mutable value type used to create or update a `LoggedActivity`.
struct LoggedActivityDraft: Sendable {
    var id: UUID
    var source: LoggedActivitySource
    var externalID: String?
    var type: LoggedActivityType
    var customLabel: String?
    var startDate: Date
    var durationSeconds: Int
    var intensity: LoggedActivityIntensity?
    var rpe: Int?
    var notes: String
    var metrics: LoggedActivityMetrics

    static func manual() -> LoggedActivityDraft {
        LoggedActivityDraft(
            id: UUID(),
            source: .manual,
            externalID: nil,
            type: .run,
            customLabel: nil,
            startDate: Date(),
            durationSeconds: 1800,
            intensity: nil,
            rpe: nil,
            notes: "",
            metrics: .empty
        )
    }
}
