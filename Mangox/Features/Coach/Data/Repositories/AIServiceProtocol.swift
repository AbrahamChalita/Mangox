// Features/Coach/Data/Repositories/AIServiceProtocol.swift
import Foundation

/// Infrastructure-level AI service contract. Lives in Data because it owns persistence and streaming.
/// Domain-level coach contract: see `CoachRepository` in Coach/Domain/Repositories/.
/// Concrete implementation: `AIService` in Coach/Data/Repositories/.
@MainActor
protocol AIServiceProtocol: AnyObject {
    var messages: [ChatMessage] { get }
    var isLoading: Bool { get }
    var error: String? { get }
    var generatingPlan: Bool { get }
    var planProgress: PlanGenerationProgress? { get }
    var lastCreditsRemaining: Int? { get }
    var planConfirmationDraft: PlanGenerationDraft? { get set }
    var planSaveCelebration: PlanSaveCelebration? { get set }
    var workoutConfirmationDraft: WorkoutGenerationDraft? { get set }
    var workoutSaveCelebration: WorkoutSaveCelebration? { get set }
    var streamDraftText: String { get }
    var streamStatusText: String? { get }
    var streamIsThinking: Bool { get }
    var currentSessionID: UUID? { get }
    var todayMessageCount: Int { get }

    func coachFactSheetText() -> String
    func hasReachedFreeLimit(isPro: Bool) -> Bool
    func loadCoachEmptyStartersContent() async -> CoachEmptyStartersContent
    func contextualQuickPrompts() -> [QuickPrompt]

    func sendMessage(
        _ text: String,
        isPro: Bool
    ) async

    @discardableResult
    func generatePlan(
        inputs: PlanInputs,
        isPro: Bool,
        idempotencyKey: String
    ) async throws -> PlanGenerationResult

    func runConfirmedPlanGeneration(
        draft: PlanGenerationDraft,
        isPro: Bool
    ) async throws
    func saveConfirmedWorkoutDraft(_ draft: WorkoutGenerationDraft) throws
    func regenerateFallbackPlanWeek(
        weekNumber: Int,
        celebration: PlanSaveCelebration,
        isPro: Bool
    ) async throws

    func loadPersistedMessages() async
    func createNewSession()
    func switchToSession(_ sessionID: UUID)
    func deleteSession(_ sessionID: UUID)
    func fetchSessions() -> [ChatSession]
    func clearMessages()
    func submitFeedback(for messageID: UUID, score: Int)
    func regenerateLastMessage(isPro: Bool) async

    var contextWindowSize: Int { get }
    var currentContextCount: Int { get }
}
