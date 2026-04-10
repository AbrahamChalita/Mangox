// Features/Training/Presentation/ViewModel/TrainingViewModel.swift
import Foundation
import SwiftUI

private extension WhoopServiceProtocol {
    var trainingReadinessAccentColor: Color {
        guard let recovery = latestRecoveryScore else {
            return AppColor.whoop.opacity(0.85)
        }
        if recovery >= 67 { return AppColor.success }
        if recovery >= 34 { return AppColor.yellow }
        return AppColor.orange
    }
}

@MainActor
@Observable
final class TrainingViewModel {
    private let whoopService: WhoopServiceProtocol
    private let purchasesService: PurchasesServiceProtocol
    private let persistenceRepository: TrainingPlanPersistenceRepositoryProtocol

    // MARK: - View state
    var weekCompliance: PlanWeekCompliance.Snapshot? = nil
    var isLoading: Bool = false
    var selectedWeek: Int = 1
    var showStartPlanSheet = false
    var showResetConfirmation = false
    var showDeleteConfirmation = false
    var showICSExportShare = false
    var icsExportURL: URL?
    var planStartDate = Date()

    enum TrainingNavigationAction: Equatable {
        case paywall
        case connectionForPlan(planID: String, dayID: String)
        case ftpSetup
    }

    var pendingNavigation: TrainingNavigationAction?

    init(
        whoopService: WhoopServiceProtocol,
        purchasesService: PurchasesServiceProtocol,
        persistenceRepository: TrainingPlanPersistenceRepositoryProtocol
    ) {
        self.whoopService = whoopService
        self.purchasesService = purchasesService
        self.persistenceRepository = persistenceRepository
    }

    var showsWhoopBanner: Bool { whoopService.isConnected && whoopService.isConfigured }
    var shouldShowUpgradeCTA: Bool { !purchasesService.isPro }
    var whoopRecoveryScore: Double? { whoopService.latestRecoveryScore }
    var whoopReadinessHint: String { whoopService.readinessTrainingHint }
    var whoopReadinessAccentColor: Color { whoopService.trainingReadinessAccentColor }

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

    func startPlan(plan: TrainingPlan) {
        try? persistenceRepository.startPlan(plan, startDate: planStartDate)
        selectedWeek = 1
    }

    func resetPlan(progress: TrainingPlanProgress?) {
        try? persistenceRepository.resetPlan(progress: progress)
    }

    func exportPlanICS(plan: TrainingPlan, progress: TrainingPlanProgress) {
        let body = PlanICSExport.buildICS(plan: plan, progress: progress)
        icsExportURL = try? PlanICSExport.writeTempICSFile(planName: plan.name, icsBody: body)
        showICSExportShare = icsExportURL != nil
    }

    func deleteAIPlan(
        progress: TrainingPlanProgress?,
        aiPlan: AIGeneratedPlan?
    ) {
        try? persistenceRepository.deleteAIPlan(progress: progress, aiPlan: aiPlan)
    }

    func autoSelectCurrentWeek(progress: TrainingPlanProgress?, totalWeeks: Int) {
        guard let progress else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let planStart = calendar.startOfDay(for: progress.startDate)
        let daysSinceStart = calendar.dateComponents([.day], from: planStart, to: today).day ?? 0

        if daysSinceStart < 0 {
            selectedWeek = 1
        } else {
            let week = (daysSinceStart / 7) + 1
            selectedWeek = min(max(week, 1), totalWeeks)
        }
    }

    func clearPendingNavigation() {
        pendingNavigation = nil
    }

    func refreshWhoopIfNeeded() async {
        await whoopService.refreshLinkedDataIfStale(maximumAge: 4 * 60 * 60)
    }

    func requestPaywall() {
        pendingNavigation = .paywall
    }

    func requestPlanWorkout(planID: String, dayID: String) {
        pendingNavigation = .connectionForPlan(planID: planID, dayID: dayID)
    }

    func requestFTPSetup() {
        pendingNavigation = .ftpSetup
    }

    func markCompleted(_ dayID: String, progress: TrainingPlanProgress?) {
        try? persistenceRepository.markCompleted(dayID, progress: progress)
    }

    func markSkipped(_ dayID: String, progress: TrainingPlanProgress?) {
        try? persistenceRepository.markSkipped(dayID, progress: progress)
    }

    func unmark(_ dayID: String, progress: TrainingPlanProgress?) {
        try? persistenceRepository.unmark(dayID, progress: progress)
    }

    func resetAdaptiveLoadMultiplier(progress: TrainingPlanProgress?) {
        try? persistenceRepository.resetAdaptiveLoadMultiplier(for: progress)
    }
}
