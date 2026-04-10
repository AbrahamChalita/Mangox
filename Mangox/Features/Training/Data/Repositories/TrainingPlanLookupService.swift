// Features/Training/Data/Repositories/TrainingPlanLookupService.swift
import Foundation
import SwiftData

@MainActor
final class TrainingPlanLookupService: TrainingPlanLookupServiceProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    convenience init(modelContainer: ModelContainer) {
        self.init(modelContext: ModelContext(modelContainer))
    }

    convenience init() {
        self.init(modelContext: PersistenceContainer.shared.mainContext)
    }

    func resolvePlan(planID: String?) -> TrainingPlan? {
        PlanLibrary.resolvePlan(planID: planID, modelContext: modelContext)
    }

    func resolveDay(planID: String?, dayID: String?) -> PlanDay? {
        PlanLibrary.resolveDay(planID: planID, dayID: dayID, modelContext: modelContext)
    }

    func nextScheduledWorkout(allProgress: [TrainingPlanProgress]) -> ScheduledTrainingDay? {
        guard let next = PlanLibrary.nextScheduledWorkout(
            allProgress: allProgress,
            modelContext: modelContext
        ) else { return nil }

        return ScheduledTrainingDay(
            planID: next.planID,
            plan: next.plan,
            day: next.day,
            progress: next.progress
        )
    }
}
