// Features/Training/Data/Repositories/TrainingPlanLookupServiceProtocol.swift
import Foundation

struct ScheduledTrainingDay {
    let planID: String
    let plan: TrainingPlan
    let day: PlanDay
    let progress: TrainingPlanProgress
}

/// Infrastructure-level plan lookup contract.
/// The implementation owns its persistence context so Presentation does not thread `ModelContext`.
@MainActor
protocol TrainingPlanLookupServiceProtocol: AnyObject {
    func resolvePlan(planID: String?) -> TrainingPlan?
    func resolveDay(planID: String?, dayID: String?) -> PlanDay?
    func nextScheduledWorkout(allProgress: [TrainingPlanProgress]) -> ScheduledTrainingDay?
}
