import Foundation
import SwiftData

/// A single chat conversation session that groups multiple messages together.
@Model
final class ChatSession {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var title: String
    @Relationship(deleteRule: .cascade, inverse: \CoachChatMessage.session)
    var messages: [CoachChatMessage] = []

    init(id: UUID = UUID(), title: String = "New Conversation", createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Generates a short title from the first user message in the session.
    func updateTitle(from messages: [CoachChatMessage]) {
        if let firstUser = messages.first(where: { $0.roleRaw == "user" }) {
            let words = firstUser.content.split(separator: " ").prefix(5).joined(separator: " ")
            self.title = words.count < firstUser.content.count ? words + "…" : firstUser.content
        }
        self.updatedAt = .now
    }
}
