import Foundation
import SwiftData

/// One-time cleanup for removed built-in plans that no longer exist in app code.
enum TrainingPlanProgressCleanupMigration {
    private static let doneKey = "mangox.training_plan_progress_cleanup_v1"
    private static let removedPlanIDs: Set<String> = ["wedding-weight-loss-2026"]

    @MainActor
    static func runIfNeeded() {
        runIfNeeded(modelContext: PersistenceContainer.shared.mainContext)
    }

    @MainActor
    static func runIfNeeded(modelContext: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }

        let descriptor = FetchDescriptor<TrainingPlanProgress>()
        let allProgress = (try? modelContext.fetch(descriptor)) ?? []
        let staleRows = allProgress.filter { removedPlanIDs.contains($0.planID) }

        if staleRows.isEmpty {
            UserDefaults.standard.set(true, forKey: doneKey)
            return
        }

        for row in staleRows {
            modelContext.delete(row)
        }
        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: doneKey)
    }
}
