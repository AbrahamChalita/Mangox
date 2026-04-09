// Features/Coach/Presentation/View/AITrainingPlanView.swift
import SwiftUI
import SwiftData

/// Resolves an `AIGeneratedPlan` by ID from SwiftData and presents it as a `TrainingPlanView`.
/// Used as the navigation destination for `AppRoute.aiPlan(planID:)`.
struct AITrainingPlanView: View {
    let planID: String
    @Binding var navigationPath: NavigationPath

    @Query private var aiPlans: [AIGeneratedPlan]

    init(planID: String, navigationPath: Binding<NavigationPath>) {
        self.planID = planID
        _navigationPath = navigationPath
        let pid = planID
        var d = FetchDescriptor<AIGeneratedPlan>(
            predicate: #Predicate<AIGeneratedPlan> { $0.id == pid }
        )
        d.fetchLimit = 1
        _aiPlans = Query(d)
    }

    private var resolvedPlan: TrainingPlan? {
        aiPlans.first?.plan
    }

    var body: some View {
        if let plan = resolvedPlan {
            TrainingPlanView(navigationPath: $navigationPath, plan: plan)
        } else {
            ContentUnavailableView(
                "Plan not found",
                systemImage: "exclamationmark.triangle",
                description: Text("This plan may have been deleted.")
            )
        }
    }
}
