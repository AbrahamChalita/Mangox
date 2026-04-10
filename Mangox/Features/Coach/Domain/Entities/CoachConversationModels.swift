// Features/Coach/Domain/Entities/CoachConversationModels.swift
import Foundation

struct ChatMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    let suggestedActions: [SuggestedAction]
    let followUpQuestion: String?
    /// When non-empty, UI shows one reply card per block; flat `followUpQuestion` / `suggestedActions` are unused for the panel.
    let followUpBlocks: [CoachFollowUpBlock]
    let thinkingSteps: [String]
    let category: String?
    let tags: [String]
    let references: [ChatReference]
    /// True when the coach used live web sources (API flag or link-backed references).
    let usedWebSearch: Bool
    var feedbackScore: Int?
    var confidence: Double

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(
            id: UUID(),
            role: .user,
            content: text,
            timestamp: .now,
            suggestedActions: [],
            followUpQuestion: nil,
            followUpBlocks: [],
            thinkingSteps: [],
            category: nil,
            tags: [],
            references: [],
            usedWebSearch: false,
            feedbackScore: nil,
            confidence: 1.0
        )
    }
}

enum MessageRole: String, Equatable, Sendable {
    case user
    case assistant
}

struct SuggestedAction: Codable, Identifiable, Equatable, Sendable {
    var id: String { "\(type)|\(label)" }
    let label: String
    let type: String
}

/// One "Coach asks" card + its chips (from `followUpBlocks` on the coach API).
struct CoachFollowUpBlock: Codable, Equatable, Sendable {
    let question: String
    let suggestedActions: [SuggestedAction]

    enum CodingKeys: String, CodingKey {
        case question
        case suggestedActions
        case suggested_actions
    }

    init(question: String, suggestedActions: [SuggestedAction]) {
        self.question = question
        self.suggestedActions = suggestedActions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        question = try c.decode(String.self, forKey: .question)
        suggestedActions =
            (try? c.decodeIfPresent([SuggestedAction].self, forKey: .suggestedActions))
            ?? (try? c.decodeIfPresent([SuggestedAction].self, forKey: .suggested_actions))
            ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(question, forKey: .question)
        try c.encode(suggestedActions, forKey: .suggestedActions)
    }
}

struct ChatReference: Codable, Equatable, Sendable {
    let title: String
    let url: String?
    let snippet: String?
}
