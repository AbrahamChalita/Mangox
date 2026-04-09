// Features/Coach/Domain/Repositories/CoachRepository.swift
import Foundation

/// Pure domain contract for the coaching feature.
/// Depends only on Foundation — no SwiftData, SwiftUI, or third-party SDKs.
/// Infrastructure-coupled operations (ModelContext, streaming) live in AIServiceProtocol (Data layer).
@MainActor
protocol CoachRepository: AnyObject {
    var messages: [ChatMessage] { get }
    var isLoading: Bool { get }
    var error: String? { get }
    var generatingPlan: Bool { get }
    var streamDraftText: String { get }
    var streamIsThinking: Bool { get }
    var streamUsesOnDeviceAppearance: Bool { get }
    var todayMessageCount: Int { get }
    var contextWindowSize: Int { get }
    var currentContextCount: Int { get }

    func hasReachedFreeLimit(isPro: Bool) -> Bool
    func submitFeedback(for messageID: UUID, score: Int)
}
