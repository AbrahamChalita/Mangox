import Foundation
import Supabase
import SwiftData

/// Pushes coach `ChatSession` rows and their `CoachChatMessage` children.
struct ChatSyncDomain: SupabaseSyncDomain {
    let name = "chat"

    private static let cursorKey = "mangox.sync.chat.cursor"

    @MainActor
    func push(userId: UUID, client: SupabaseClient, context: ModelContext) async throws {
        let cursor = UserDefaults.standard.object(forKey: Self.cursorKey) as? Date ?? .distantPast

        let descriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate { $0.updatedAt > cursor },
            sortBy: [SortDescriptor(\.updatedAt, order: .forward)]
        )
        let sessions = try context.fetch(descriptor)
        guard !sessions.isEmpty else { return }

        var newCursor = cursor

        for session in sessions {
            let sessionRow = SessionRow(session: session, userId: userId)
            try await client
                .from("chat_sessions")
                .upsert(sessionRow, onConflict: "id")
                .execute()

            if !session.messages.isEmpty {
                let messageRows = session.messages
                    .sorted { $0.timestamp < $1.timestamp }
                    .map { MessageRow(message: $0, sessionId: session.id, userId: userId) }
                try await client
                    .from("chat_messages")
                    .upsert(messageRows, onConflict: "id")
                    .execute()
            }

            if session.updatedAt > newCursor { newCursor = session.updatedAt }
        }

        UserDefaults.standard.set(newCursor, forKey: Self.cursorKey)
    }
}

// MARK: - Rows

private struct SessionRow: Codable, Sendable {
    let id: String
    let user_id: String
    let title: String?
    let created_at: Date
    let updated_at: Date

    init(session: ChatSession, userId: UUID) {
        self.id = session.id.uuidString
        self.user_id = userId.uuidString
        self.title = session.title.isEmpty ? nil : session.title
        self.created_at = session.createdAt
        self.updated_at = session.updatedAt
    }
}

private struct MessageRow: Codable, Sendable {
    let id: String
    let session_id: String
    let user_id: String
    let role: String
    let content: String
    let category: String?
    let tags: [String]
    let suggested_actions: AnyJSON?
    let follow_up_blocks: AnyJSON?
    let follow_up_question: String?
    let thinking_steps: AnyJSON?
    let references_payload: AnyJSON?
    let used_web_search: Bool
    let feedback_score: Int?
    let timestamp: Date

    init(message: CoachChatMessage, sessionId: UUID, userId: UUID) {
        self.id = message.id.uuidString
        self.session_id = sessionId.uuidString
        self.user_id = userId.uuidString
        self.role = message.roleRaw
        self.content = message.content
        self.category = message.category
        self.tags = Self.decodeStringArray(message.tagsJSON)
        self.suggested_actions = Self.decodeJSON(message.suggestedActionsJSON)
        self.follow_up_blocks = Self.decodeJSON(message.followUpBlocksJSON)
        self.follow_up_question = message.followUpQuestion
        self.thinking_steps = Self.decodeJSON(message.thinkingStepsJSON)
        self.references_payload = Self.decodeJSON(message.referencesJSON)
        self.used_web_search = message.usedWebSearch ?? false
        self.feedback_score = message.feedbackScore
        self.timestamp = message.timestamp
    }

    private static func decodeJSON(_ data: Data?) -> AnyJSON? {
        guard let data, !data.isEmpty,
              let any = try? JSONDecoder().decode(AnyJSON.self, from: data) else {
            return nil
        }
        return any
    }

    private static func decodeStringArray(_ data: Data?) -> [String] {
        guard let data, !data.isEmpty,
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return arr
    }
}
