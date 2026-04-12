// Features/Coach/Presentation/ViewModel/CoachViewModel.swift
import Foundation

@MainActor
@Observable
final class CoachViewModel {
    // MARK: - Dependencies
    private let coach: AIServiceProtocol
    private let purchasesService: PurchasesServiceProtocol

    // MARK: - View state
    var messages: [ChatMessage] { coach.messages }
    var isLoading: Bool { coach.isLoading }
    var error: String? { coach.error }
    var generatingPlan: Bool { coach.generatingPlan }
    var planProgress: PlanGenerationProgress? { coach.planProgress }
    var planConfirmationDraft: PlanGenerationDraft? { coach.planConfirmationDraft }
    var planSaveCelebration: PlanSaveCelebration? { coach.planSaveCelebration }
    var workoutConfirmationDraft: WorkoutGenerationDraft? { coach.workoutConfirmationDraft }
    var workoutSaveCelebration: WorkoutSaveCelebration? { coach.workoutSaveCelebration }
    var streamDraftText: String { coach.streamDraftText }
    var streamStatusText: String? { coach.streamStatusText }
    var streamIsThinking: Bool { coach.streamIsThinking }
    var todayMessageCount: Int { coach.todayMessageCount }
    var contextWindowSize: Int { coach.contextWindowSize }
    var currentContextCount: Int { coach.currentContextCount }
    var currentSessionID: UUID? { coach.currentSessionID }
    var hasReachedLimit: Bool = false
    var starterContent: CoachEmptyStartersContent?

    // MARK: - Purchase state
    var isPro: Bool { purchasesService.isPro }

    private var didRequestPersistedLoad = false

    init(coach: AIServiceProtocol, purchasesService: PurchasesServiceProtocol) {
        self.coach = coach
        self.purchasesService = purchasesService
    }

    func refreshLimitState(isPro: Bool) {
        hasReachedLimit = coach.hasReachedFreeLimit(isPro: isPro)
    }

    func hasReachedFreeLimit(isPro: Bool) -> Bool {
        coach.hasReachedFreeLimit(isPro: isPro)
    }

    func remainingFreeMessages(isPro: Bool) -> Int {
        guard !isPro else { return Int.max }
        return max(0, AIService.freeDailyLimit - todayMessageCount)
    }

    var bypassesDailyLimit: Bool {
        AIService.bypassesDailyCoachMessageLimit
    }

    func loadPersistedMessagesIfNeeded() async {
        guard !didRequestPersistedLoad else { return }
        didRequestPersistedLoad = true
        await Task.yield()
        await coach.loadPersistedMessages()
    }

    func refreshStarterContentIfNeeded() async {
        guard messages.isEmpty else {
            starterContent = nil
            return
        }
        starterContent = await coach.loadCoachEmptyStartersContent()
    }

    func contextualQuickPrompts() -> [QuickPrompt] {
        coach.contextualQuickPrompts()
    }

    func normalizePlanEventDate(_ raw: String) -> String? {
        AIService.normalizeEventDateForPlan(raw)
    }

    func planGenerationSummaryLine(for inputs: PlanInputs) -> String {
        AIService.planSummaryLine(for: inputs)
    }

    func userFacingPlanGenerationError(_ error: Error) -> String {
        AIService.userFacingPlanGenerationError(error)
    }

    func sendMessage(
        _ text: String,
        isPro: Bool
    ) async {
        await coach.sendMessage(text, isPro: isPro)
    }

    func createNewSession() {
        starterContent = nil
        coach.createNewSession()
    }

    func switchToSession(_ sessionID: UUID) {
        starterContent = nil
        coach.switchToSession(sessionID)
    }

    func deleteSession(_ sessionID: UUID) {
        coach.deleteSession(sessionID)
    }

    func submitFeedback(for messageID: UUID, score: Int) {
        coach.submitFeedback(for: messageID, score: score)
    }

    func clearPlanConfirmationDraft() {
        coach.planConfirmationDraft = nil
    }

    func clearPlanSaveCelebration() {
        coach.planSaveCelebration = nil
    }

    func clearWorkoutConfirmationDraft() {
        coach.workoutConfirmationDraft = nil
    }

    func clearWorkoutSaveCelebration() {
        coach.workoutSaveCelebration = nil
    }

    func saveConfirmedWorkoutDraft(_ draft: WorkoutGenerationDraft) throws {
        try coach.saveConfirmedWorkoutDraft(draft)
    }

    func stagePlanRegeneration(from aiPlan: AIGeneratedPlanDraft) -> Bool {
        guard let data = aiPlan.regenerationInputsJSON,
              let inputs = try? JSONDecoder().decode(PlanInputs.self, from: data) else {
            return false
        }

        coach.planConfirmationDraft = PlanGenerationDraft(
            inputs: inputs,
            summaryLine: aiPlan.userPrompt
        )
        return true
    }

    func runConfirmedPlanGeneration(
        draft: PlanGenerationDraft,
        isPro: Bool
    ) async throws {
        try await coach.runConfirmedPlanGeneration(
            draft: draft,
            isPro: isPro
        )
    }

    func regenerateFallbackPlanWeek(
        _ weekNumber: Int,
        celebration: PlanSaveCelebration,
        isPro: Bool
    ) async throws {
        try await coach.regenerateFallbackPlanWeek(
            weekNumber: weekNumber,
            celebration: celebration,
            isPro: isPro
        )
    }
}
