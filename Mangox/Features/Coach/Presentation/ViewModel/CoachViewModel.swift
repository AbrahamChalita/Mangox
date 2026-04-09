// Features/Coach/Presentation/ViewModel/CoachViewModel.swift
import Foundation

@MainActor
@Observable
final class CoachViewModel {
    // MARK: - Dependencies
    private let coach: CoachRepository

    // MARK: - View state
    var messages: [ChatMessage] { coach.messages }
    var isLoading: Bool { coach.isLoading }
    var error: String? { coach.error }
    var generatingPlan: Bool { coach.generatingPlan }
    var streamDraftText: String { coach.streamDraftText }
    var streamIsThinking: Bool { coach.streamIsThinking }
    var streamUsesOnDeviceAppearance: Bool { coach.streamUsesOnDeviceAppearance }
    var todayMessageCount: Int { coach.todayMessageCount }
    var contextWindowSize: Int { coach.contextWindowSize }
    var currentContextCount: Int { coach.currentContextCount }
    var hasReachedLimit: Bool = false

    init(coach: CoachRepository) {
        self.coach = coach
    }

    func refreshLimitState(isPro: Bool) {
        hasReachedLimit = coach.hasReachedFreeLimit(isPro: isPro)
    }

    func submitFeedback(for messageID: UUID, score: Int) {
        coach.submitFeedback(for: messageID, score: score)
    }
}

// MARK: - Preview mock
#if DEBUG
@MainActor
final class MockCoachRepository: CoachRepository {
    var messages: [ChatMessage] = []
    var isLoading = false
    var error: String? = nil
    var generatingPlan = false
    var streamDraftText = ""
    var streamIsThinking = false
    var streamUsesOnDeviceAppearance = false
    var todayMessageCount = 0
    var contextWindowSize = 16
    var currentContextCount = 0
    func hasReachedFreeLimit(isPro: Bool) -> Bool { false }
    func submitFeedback(for messageID: UUID, score: Int) {}
}
#endif
