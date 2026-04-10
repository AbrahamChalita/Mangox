import Foundation
import SwiftData

@MainActor
final class TrainingPlanPersistenceRepository: TrainingPlanPersistenceRepositoryProtocol {
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

    func startPlan(_ plan: TrainingPlan, startDate: Date) throws {
        let progress = TrainingPlanProgress(
            planID: plan.id,
            startDate: Calendar.current.startOfDay(for: startDate),
            ftp: PowerZone.ftp,
            aiPlanTitle: plan.eventName
        )
        modelContext.insert(progress)
        try modelContext.save()
    }

    func save(progress: TrainingPlanProgress?) throws {
        guard progress != nil else { return }
        try modelContext.save()
    }

    func resetPlan(progress: TrainingPlanProgress?) throws {
        guard let progress else { return }
        modelContext.delete(progress)
        try modelContext.save()
    }

    func deleteAIPlan(progress: TrainingPlanProgress?, aiPlan: AIGeneratedPlan?) throws {
        if let progress {
            modelContext.delete(progress)
        }
        if let aiPlan {
            modelContext.delete(aiPlan)
        }
        try modelContext.save()
    }

    func markCompleted(_ dayID: String, progress: TrainingPlanProgress?) throws {
        progress?.markCompleted(dayID)
        try modelContext.save()
    }

    func markSkipped(_ dayID: String, progress: TrainingPlanProgress?) throws {
        progress?.markSkipped(dayID)
        try modelContext.save()
    }

    func unmark(_ dayID: String, progress: TrainingPlanProgress?) throws {
        progress?.unmark(dayID)
        try modelContext.save()
    }

    func resetAdaptiveLoadMultiplier(for progress: TrainingPlanProgress?) throws {
        guard let progress else { return }
        progress.adaptiveLoadMultiplier = 1.0
        try modelContext.save()
    }
}
