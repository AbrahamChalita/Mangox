// Features/Training/Presentation/ViewModel/TrainingViewModel.swift
import Foundation

@MainActor
@Observable
final class TrainingViewModel {
    // MARK: - View state
    var weekCompliance: PlanWeekCompliance.Snapshot? = nil
    var trainingGoals: MangoxTrainingGoals.Type = MangoxTrainingGoals.self
    var isLoading: Bool = false

    func refreshCompliance(
        progress: TrainingPlanProgress?,
        plan: TrainingPlan?,
        recentWorkouts: [Workout]
    ) {
        weekCompliance = PlanWeekCompliance.snapshot(
            progress: progress,
            plan: plan,
            recentWorkouts: recentWorkouts
        )
    }
}
