// Features/Training/Domain/UseCases/PlanWorkoutCompletion.swift
import Foundation
import SwiftData

/// Shared plan-day completion path for indoor and outdoor plan-linked rides.
enum PlanWorkoutCompletion {
    @MainActor
    static func completePlanLinkedRide(
        workout: Workout,
        planID: String,
        dayID: String,
        planDay: PlanDay?,
        modelContext: ModelContext,
        trainingPlanPersistenceRepository: TrainingPlanPersistenceRepositoryProtocol,
        source: String
    ) {
        workout.planID = planID
        workout.planDayID = dayID

        let progressDescriptor = FetchDescriptor<TrainingPlanProgress>(
            predicate: #Predicate<TrainingPlanProgress> { $0.planID == planID }
        )
        guard let progress = (try? modelContext.fetch(progressDescriptor))?.first else { return }

        do {
            try trainingPlanPersistenceRepository.markCompleted(dayID, progress: progress)
            PrecisionCoachInstrumentation.planDayCompleted(
                planID: planID,
                dayID: dayID,
                source: source
            )
        } catch {
            return
        }

        guard let linkedDay = planDay else { return }

        let plan = PlanLibrary.resolvePlan(planID: planID, modelContext: modelContext)
        let signals = AdaptiveTrainingAdjuster.signals(
            modelContext: modelContext,
            plan: plan,
            progress: progress
        )
        AdaptiveTrainingAdjuster.adjustAfterCompletedPlanWorkout(
            workout: workout,
            planDay: linkedDay,
            progress: progress,
            signals: signals
        )

        do {
            try trainingPlanPersistenceRepository.save(progress: progress)
            try modelContext.save()
        } catch {
            // Best-effort; ride is already saved.
        }
    }
}
