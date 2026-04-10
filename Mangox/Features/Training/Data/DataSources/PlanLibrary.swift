// Features/Training/Data/DataSources/PlanLibrary.swift
import Foundation
import SwiftData

// MARK: - Plan resolution

enum PlanLibrary {
    /// Resolves an AI-generated `TrainingPlan` by ID when a `ModelContext` is provided.
    static func resolvePlan(planID: String?, modelContext: ModelContext? = nil) -> TrainingPlan? {
        guard let planID else { return nil }
        if let ctx = modelContext {
            let descriptor = FetchDescriptor<AIGeneratedPlan>(
                predicate: #Predicate { $0.id == planID }
            )
            if let aiPlan = try? ctx.fetch(descriptor).first {
                return aiPlan.plan
            }
        }
        return nil
    }

    static func resolveDay(planID: String?, dayID: String?, modelContext: ModelContext? = nil) -> PlanDay? {
        guard let dayID, let plan = resolvePlan(planID: planID, modelContext: modelContext) else { return nil }
        return plan.day(id: dayID)
    }

    /// Next incomplete workout or FTP test day, preferring the most recently started plan.
    /// Chooses by **mapped calendar date** so a missed day in week 1 does not block "next" once the user is in a later week.
    static func nextScheduledWorkout(
        allProgress: [TrainingPlanProgress],
        modelContext: ModelContext
    ) -> (planID: String, plan: TrainingPlan, day: PlanDay, progress: TrainingPlanProgress)? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sorted = allProgress.sorted { $0.startDate > $1.startDate }
        for p in sorted {
            guard let plan = resolvePlan(planID: p.planID, modelContext: modelContext) else { continue }
            let candidates = plan.allDays.filter { d in
                !p.isCompleted(d.id) && !p.isSkipped(d.id)
                    && (d.dayType == .workout || d.dayType == .ftpTest)
            }
            let futureOrToday = candidates.filter {
                calendar.startOfDay(for: p.calendarDate(for: $0)) >= today
            }
            if let day = futureOrToday.min(by: { p.calendarDate(for: $0) < p.calendarDate(for: $1) }) {
                return (p.planID, plan, day, p)
            }
            if let day = candidates.min(by: { p.calendarDate(for: $0) < p.calendarDate(for: $1) }) {
                return (p.planID, plan, day, p)
            }
        }
        return nil
    }
}
