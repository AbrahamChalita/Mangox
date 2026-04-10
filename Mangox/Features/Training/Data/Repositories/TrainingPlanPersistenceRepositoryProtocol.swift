import Foundation

@MainActor
protocol TrainingPlanPersistenceRepositoryProtocol: AnyObject {
    func startPlan(_ plan: TrainingPlan, startDate: Date) throws
    func save(progress: TrainingPlanProgress?) throws
    func resetPlan(progress: TrainingPlanProgress?) throws
    func deleteAIPlan(progress: TrainingPlanProgress?, aiPlan: AIGeneratedPlan?) throws
    func markCompleted(_ dayID: String, progress: TrainingPlanProgress?) throws
    func markSkipped(_ dayID: String, progress: TrainingPlanProgress?) throws
    func unmark(_ dayID: String, progress: TrainingPlanProgress?) throws
    func resetAdaptiveLoadMultiplier(for progress: TrainingPlanProgress?) throws
}
