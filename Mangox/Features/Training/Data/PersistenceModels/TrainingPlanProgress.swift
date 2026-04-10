// Features/Training/Data/PersistenceModels/TrainingPlanProgress.swift
import Foundation
import SwiftData

/// Persisted completion state for a training plan.
@Model
final class TrainingPlanProgress {
    @Attribute(.unique) var planID: String
    var startDate: Date
    var completedDayIDs: [String] = []
    var skippedDayIDs: [String] = []
    var ftpAtStart: Int = 0
    var currentFTP: Int = 0
    var notes: [String: String] = [:]
    /// Optional display title for progress rows (Classicissima uses `CachedPlan` event name when empty).
    var aiPlanTitle: String = ""
    /// Scales guided ERG targets (1.0 = plan as written). Updated when plan-linked rides complete.
    var adaptiveLoadMultiplier: Double = 1.0

    init(planID: String, startDate: Date, ftp: Int, aiPlanTitle: String = "") {
        self.planID = planID
        self.startDate = startDate
        self.ftpAtStart = ftp
        self.currentFTP = ftp
        self.aiPlanTitle = aiPlanTitle
    }

    func isCompleted(_ dayID: String) -> Bool {
        completedDayIDs.contains(dayID)
    }

    func isSkipped(_ dayID: String) -> Bool {
        skippedDayIDs.contains(dayID)
    }

    func status(for dayID: String) -> PlanDayStatus {
        if completedDayIDs.contains(dayID) { return .completed }
        if skippedDayIDs.contains(dayID) { return .skipped }
        return .upcoming
    }

    func markCompleted(_ dayID: String) {
        if !completedDayIDs.contains(dayID) {
            completedDayIDs.append(dayID)
        }
        skippedDayIDs.removeAll { $0 == dayID }
    }

    func markSkipped(_ dayID: String) {
        if !skippedDayIDs.contains(dayID) {
            skippedDayIDs.append(dayID)
        }
        completedDayIDs.removeAll { $0 == dayID }
    }

    func unmark(_ dayID: String) {
        completedDayIDs.removeAll { $0 == dayID }
        skippedDayIDs.removeAll { $0 == dayID }
    }

    func calendarDate(for day: PlanDay) -> Date {
        let dayOffset = (day.weekNumber - 1) * 7 + (day.dayOfWeek - 1)
        return Calendar.current.date(byAdding: .day, value: dayOffset, to: startDate) ?? startDate
    }

    var completedCount: Int { completedDayIDs.count }
    var skippedCount: Int { skippedDayIDs.count }
}
