import Foundation
import SwiftData

/// Single persisted coach thread (replaces in-memory-only `AIService.messages` on launch).
@Model
final class CoachChatMessage {
    var id: UUID
    var roleRaw: String
    var content: String
    var timestamp: Date
    var suggestedActionsJSON: Data?
    /// When set, coach UI shows multiple "Coach asks" cards (`CoachFollowUpBlock` array JSON).
    var followUpBlocksJSON: Data?
    var followUpQuestion: String?
    var thinkingStepsJSON: Data?
    var category: String?
    var tagsJSON: Data?
    var referencesJSON: Data?
    /// Nil for rows saved before this field existed (treated as false).
    var usedWebSearch: Bool?
    var feedbackScore: Int?
    var session: ChatSession?

    init(
        id: UUID,
        roleRaw: String,
        content: String,
        timestamp: Date,
        suggestedActionsJSON: Data?,
        followUpBlocksJSON: Data? = nil,
        followUpQuestion: String?,
        thinkingStepsJSON: Data?,
        category: String?,
        tagsJSON: Data?,
        referencesJSON: Data?,
        usedWebSearch: Bool? = nil,
        feedbackScore: Int? = nil
    ) {
        self.id = id
        self.roleRaw = roleRaw
        self.content = content
        self.timestamp = timestamp
        self.suggestedActionsJSON = suggestedActionsJSON
        self.followUpBlocksJSON = followUpBlocksJSON
        self.followUpQuestion = followUpQuestion
        self.thinkingStepsJSON = thinkingStepsJSON
        self.category = category
        self.tagsJSON = tagsJSON
        self.referencesJSON = referencesJSON
        self.usedWebSearch = usedWebSearch
        self.feedbackScore = feedbackScore
    }

    func toChatMessage() -> ChatMessage {
        let blocks: [CoachFollowUpBlock] = {
            guard let data = followUpBlocksJSON else { return [] }
            return (try? JSONDecoder().decode([CoachFollowUpBlock].self, from: data)) ?? []
        }()
        let actions: [SuggestedAction] = {
            guard let data = suggestedActionsJSON else { return [] }
            return (try? JSONDecoder().decode([SuggestedAction].self, from: data)) ?? []
        }()
        let steps: [String] = {
            guard let data = thinkingStepsJSON else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }()
        let tags: [String] = {
            guard let data = tagsJSON else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }()
        let references: [ChatReference] = {
            guard let data = referencesJSON else { return [] }
            return (try? JSONDecoder().decode([ChatReference].self, from: data)) ?? []
        }()
        let role = MessageRole(rawValue: roleRaw) ?? .assistant
        // Match AIService: only persisted `usedWebSearch`, not URL heuristics (avoids false "live web" on reload).
        let showWebBadge = usedWebSearch == true
        return ChatMessage(
            id: id,
            role: role,
            content: content,
            timestamp: timestamp,
            suggestedActions: actions,
            followUpQuestion: followUpQuestion,
            followUpBlocks: blocks,
            thinkingSteps: steps,
            category: category,
            tags: tags,
            references: references,
            usedWebSearch: showWebBadge,
            feedbackScore: feedbackScore,
            confidence: 1.0
        )
    }

    static func from(_ message: ChatMessage) -> CoachChatMessage {
        let actionsData = try? JSONEncoder().encode(message.suggestedActions)
        let blocksData = message.followUpBlocks.isEmpty ? nil : (try? JSONEncoder().encode(message.followUpBlocks))
        let stepsData = try? JSONEncoder().encode(message.thinkingSteps)
        let tagsData = try? JSONEncoder().encode(message.tags)
        let refsData = try? JSONEncoder().encode(message.references)
        return CoachChatMessage(
            id: message.id,
            roleRaw: message.role.rawValue,
            content: message.content,
            timestamp: message.timestamp,
            suggestedActionsJSON: actionsData,
            followUpBlocksJSON: blocksData,
            followUpQuestion: message.followUpQuestion,
            thinkingStepsJSON: stepsData,
            category: message.category,
            tagsJSON: tagsData,
            referencesJSON: refsData,
            usedWebSearch: message.usedWebSearch
        )
    }
}
