import Foundation
import SwiftData

/// Defines the coaching AI contract consumed by Presentation and Domain layers.
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
    var streamDraftText: String { get }
    var streamStatusText: String? { get }
    var streamIsThinking: Bool { get }
    var streamUsesOnDeviceAppearance: Bool { get }
    var currentSessionID: UUID? { get }
    var todayMessageCount: Int { get }

    func hasReachedFreeLimit(isPro: Bool) -> Bool

    func sendMessage(
        _ text: String,
        isPro: Bool,
        modelContext: ModelContext,
        delivery: CoachChatDelivery
    ) async

    @discardableResult
    func generatePlan(
        inputs: PlanInputs,
        isPro: Bool,
        modelContext: ModelContext,
        idempotencyKey: String
    ) async throws -> PlanGenerationResult

    func runConfirmedPlanGeneration(
        draft: PlanGenerationDraft,
        isPro: Bool,
        modelContext: ModelContext
    ) async throws

    func loadPersistedMessages(modelContext: ModelContext) async
    func createNewSession(modelContext: ModelContext)
    func switchToSession(_ sessionID: UUID, modelContext: ModelContext)
    func deleteSession(_ sessionID: UUID, modelContext: ModelContext)
    func fetchSessions(modelContext: ModelContext) -> [ChatSession]
    func clearMessages(modelContext: ModelContext)
    func submitFeedback(for messageID: UUID, score: Int)
    func regenerateLastMessage(isPro: Bool, modelContext: ModelContext) async

    var contextWindowSize: Int { get }
    var currentContextCount: Int { get }
}
