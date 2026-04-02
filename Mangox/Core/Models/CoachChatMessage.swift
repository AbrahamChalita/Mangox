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
    var followUpQuestion: String?
    var thinkingStepsJSON: Data?
    var category: String?
    var tagsJSON: Data?
    var referencesJSON: Data?
    var session: ChatSession?

    init(
        id: UUID,
        roleRaw: String,
        content: String,
        timestamp: Date,
        suggestedActionsJSON: Data?,
        followUpQuestion: String?,
        thinkingStepsJSON: Data?,
        category: String?,
        tagsJSON: Data?,
        referencesJSON: Data?
    ) {
        self.id = id
        self.roleRaw = roleRaw
        self.content = content
        self.timestamp = timestamp
        self.suggestedActionsJSON = suggestedActionsJSON
        self.followUpQuestion = followUpQuestion
        self.thinkingStepsJSON = thinkingStepsJSON
        self.category = category
        self.tagsJSON = tagsJSON
        self.referencesJSON = referencesJSON
    }

    func toChatMessage() -> ChatMessage {
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
        return ChatMessage(
            id: id,
            role: role,
            content: content,
            timestamp: timestamp,
            suggestedActions: actions,
            followUpQuestion: followUpQuestion,
            thinkingSteps: steps,
            shouldAnimate: false,
            category: category,
            tags: tags,
            references: references
        )
    }

    static func from(_ message: ChatMessage) -> CoachChatMessage {
        let actionsData = try? JSONEncoder().encode(message.suggestedActions)
        let stepsData = try? JSONEncoder().encode(message.thinkingSteps)
        let tagsData = try? JSONEncoder().encode(message.tags)
        let refsData = try? JSONEncoder().encode(message.references)
        return CoachChatMessage(
            id: message.id,
            roleRaw: message.role.rawValue,
            content: message.content,
            timestamp: message.timestamp,
            suggestedActionsJSON: actionsData,
            followUpQuestion: message.followUpQuestion,
            thinkingStepsJSON: stepsData,
            category: message.category,
            tagsJSON: tagsData,
            referencesJSON: refsData
        )
    }
}
