import Foundation
import SwiftData
import SwiftUI
import CryptoKit
import os.log

// MARK: - Chat Models

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    let suggestedActions: [SuggestedAction]
    let followUpQuestion: String?
    let thinkingSteps: [String]
    var shouldAnimate: Bool
    let category: String?
    let tags: [String]
    let references: [ChatReference]

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(
            id: UUID(), role: .user, content: text, timestamp: .now,
            suggestedActions: [], followUpQuestion: nil, thinkingSteps: [],
            shouldAnimate: false, category: nil, tags: [], references: []
        )
    }
}

enum MessageRole: String, Equatable {
    case user, assistant
}

struct SuggestedAction: Codable, Identifiable, Equatable {
    var id: String { label }
    let label: String
    let type: String
}

// MARK: - API Request / Response Models

struct ChatRequest: Encodable {
    let message: String
    let history: [HistoryTurn]?
    /// Plaintext context — only set when no encryption key is available (dev/fallback).
    let user_context: UserContext?
    /// AES-256-GCM encrypted context: base64(nonce[12] ‖ ciphertext ‖ tag[16]).
    /// When present, `user_context` is nil.
    let user_context_encrypted: String?
    let is_pro: Bool
}

struct HistoryTurn: Encodable {
    let role: String
    let content: String
}

struct ChatAPIResponse: Decodable {
    let category: String
    let content: String
    let suggestedActions: [SuggestedAction]
    let followUpQuestion: String?
    let confidence: Double
    let thinkingSteps: [String]
    let tags: [String]
    let references: [ChatReference]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        category = (try? c.decodeIfPresent(String.self, forKey: .category)) ?? "training_advice"
        content = try c.decode(String.self, forKey: .content)
        suggestedActions = (try? c.decodeIfPresent([SuggestedAction].self, forKey: .suggestedActions)) ?? []
        followUpQuestion = try? c.decodeIfPresent(String.self, forKey: .followUpQuestion)
        confidence = (try? c.decodeIfPresent(Double.self, forKey: .confidence)) ?? 1.0
        thinkingSteps = (try? c.decodeIfPresent([String].self, forKey: .thinkingSteps)) ?? []
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        references = (try? c.decodeIfPresent([ChatReference].self, forKey: .references)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case category, content, suggestedActions, followUpQuestion, confidence, thinkingSteps, tags, references
    }
}

struct ChatReference: Codable, Equatable {
    let title: String
    let url: String?
    let snippet: String?
}

struct UserContext: Encodable {
    let ftp: Int
    let maxHR: Int
    let restingHR: Int
    let recentWorkoutsCount: Int
    let activePlanName: String?
    let activePlanProgress: String?
    let ftpHistory: String?
    let lastRide: LastRideContext?
}

struct LastRideContext: Encodable {
    let date: String
    let durationMinutes: Int
    let distanceKm: Double
    let avgPower: Double
    let maxPower: Int
    let avgHR: Double
    let avgSpeed: Double
    let elevationGain: Double
    let normalizedPower: Double
    let tss: Double
    let intensityFactor: Double
    let summary: String
}

struct PlanGenerationRequest: Encodable {
    let inputs: PlanInputs
}

struct PlanInputs: Encodable {
    let event_name: String
    let event_date: String
    let ftp: Int
    let weekly_hours: Int?
    let experience: String?
}

struct PlanGenerationResponse: Decodable {
    let plan: TrainingPlan
    let credits_used: Int?
    let credits_remaining: Int?
}

// MARK: - AIService

@Observable @MainActor
final class AIService {

    // MARK: Public State

    var messages: [ChatMessage] = []
    var isLoading: Bool = false
    var error: String? = nil
    var generatingPlan: Bool = false
    var lastCreditsRemaining: Int? = nil

    /// The currently active chat session. Nil means no session selected.
    var currentSessionID: UUID?

    /// IDs of messages whose typewriter animation has already played.
    /// Prevents re-animation when dismissing/reopening the chat sheet.
    private var animatedMessageIDs: Set<UUID> = []

    /// Returns true only the FIRST time — after that the ID is remembered.
    func shouldAnimateMessage(_ id: UUID) -> Bool {
        !animatedMessageIDs.contains(id)
    }

    func markAnimated(_ id: UUID) {
        animatedMessageIDs.insert(id)
    }

    // MARK: Constants

    static let freeDailyLimit = 5

    private let logger = Logger(subsystem: "com.abchalita.Mangox", category: "AIService")

    // MARK: Private — daily usage tracking (UserDefaults, no @Observable needed)

    private let udDateKey = "ai_chat_count_date"
    private let udCountKey = "ai_chat_count_today"

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()

    private var todayDateString: String {
        Self.dateFormatter.string(from: .now)
    }

    var todayMessageCount: Int {
        guard UserDefaults.standard.string(forKey: udDateKey) == todayDateString else { return 0 }
        return UserDefaults.standard.integer(forKey: udCountKey)
    }

    func hasReachedFreeLimit(isPro: Bool) -> Bool {
        return false // paywall disabled for testing
    }

    private func incrementDailyCount() {
        let today = todayDateString
        if UserDefaults.standard.string(forKey: udDateKey) != today {
            UserDefaults.standard.set(today, forKey: udDateKey)
            UserDefaults.standard.set(1, forKey: udCountKey)
        } else {
            let current = UserDefaults.standard.integer(forKey: udCountKey)
            UserDefaults.standard.set(current + 1, forKey: udCountKey)
        }
    }

    // MARK: Networking

    private var baseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "MangoxAPIBaseURL") as? String
            ?? "https://mangox-backend-production.up.railway.app"
    }

    private var userID: String {
        if let existing = UserDefaults.standard.string(forKey: "user_device_id") {
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: "user_device_id")
        return new
    }

    /// AES-256-GCM key from build-time `UserDataKey` Info.plist var.
    /// Nil when not configured (dev builds without the key set).
    private var encryptionKey: SymmetricKey? {
        guard let b64 = Bundle.main.object(forInfoDictionaryKey: "UserDataKey") as? String,
              !b64.isEmpty,
              let keyData = Data(base64Encoded: b64),
              keyData.count == 32 else { return nil }
        return SymmetricKey(data: keyData)
    }

    /// Encrypts `context` as AES-256-GCM and returns base64(nonce ‖ ciphertext ‖ tag).
    /// Returns nil if the key is not configured or encryption fails.
    private func encryptUserContext(_ context: UserContext) -> String? {
        guard let key = encryptionKey,
              let json = try? JSONEncoder().encode(context) else { return nil }
        guard let sealed = try? AES.GCM.seal(json, using: key),
              let combined = sealed.combined else { return nil }
        return combined.base64EncodedString()
    }

    // MARK: - Send Chat Message

    func sendMessage(_ text: String, isPro: Bool, modelContext: ModelContext) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        incrementDailyCount()

        // Auto-create a session if none exists
        if currentSessionID == nil {
            createNewSession(modelContext: modelContext)
        }

        let userMsg = ChatMessage.user(trimmed)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            messages.append(userMsg)
        }
        persistCoachMessage(userMsg, modelContext: modelContext)

        // Update session title from first user message
        updateSessionTitleIfNeeded(modelContext: modelContext)

        isLoading = true
        error = nil

        let history = buildHistory()
        let context = buildUserContext(modelContext: modelContext)
        let encryptedContext = encryptUserContext(context)
        let request = ChatRequest(
            message: trimmed,
            history: history,
            user_context: encryptedContext == nil ? context : nil,
            user_context_encrypted: encryptedContext,
            is_pro: isPro
        )

        do {
            let response: ChatAPIResponse = try await post(path: "/api/chat", body: request)
            isLoading = false

            let aiMsg = ChatMessage(
                id: UUID(),
                role: .assistant,
                content: response.content,
                timestamp: .now,
                suggestedActions: response.suggestedActions,
                followUpQuestion: response.followUpQuestion,
                thinkingSteps: response.thinkingSteps,
                shouldAnimate: true,
                category: response.category,
                tags: response.tags,
                references: response.references
            )
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                messages.append(aiMsg)
            }
            persistCoachMessage(aiMsg, modelContext: modelContext)
        } catch {
            logger.error("sendMessage failed: \(error)")
            isLoading = false
            let errMsg = ChatMessage(
                id: UUID(),
                role: .assistant,
                content: "I couldn't connect to the coaching server. Please check your connection and try again.",
                timestamp: .now,
                suggestedActions: [SuggestedAction(label: "Try again", type: "retry")],
                followUpQuestion: nil,
                thinkingSteps: [],
                shouldAnimate: false,
                category: "error",
                tags: [],
                references: []
            )
            withAnimation(.spring(response: 0.4)) {
                messages.append(errMsg)
            }
            persistCoachMessage(errMsg, modelContext: modelContext)
            self.error = error.localizedDescription
        }
    }

    // MARK: - Generate Plan

    func generatePlan(inputs: PlanInputs) async throws -> TrainingPlan {
        generatingPlan = true
        defer { generatingPlan = false }

        let request = PlanGenerationRequest(inputs: inputs)
        let response: PlanGenerationResponse = try await post(path: "/api/generate-plan", body: request)
        lastCreditsRemaining = response.credits_remaining
        return response.plan
    }

    // MARK: - Context Building

    func buildUserContext(modelContext: ModelContext) -> UserContext {
        let ftp = PowerZone.ftp
        let maxHR = HeartRateZone.maxHR
        let restingHR = HeartRateZone.restingHR

        // Recent workouts — last 30 days
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        let workoutDescriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.startDate >= thirtyDaysAgo }
        )
        let recentCount = (try? modelContext.fetchCount(workoutDescriptor)) ?? 0

        // Active plan
        let progressDescriptor = FetchDescriptor<TrainingPlanProgress>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let progresses = (try? modelContext.fetch(progressDescriptor)) ?? []
        let activeProgress = progresses.first

        var planName: String? = nil
        var planProgressStr: String? = nil
        if let p = activeProgress, p.planID == CachedPlan.shared.id {
            planName = CachedPlan.shared.name
            let totalDays = CachedPlan.shared.allDays
                .filter { $0.dayType == .workout || $0.dayType == .ftpTest }
                .count
            planProgressStr = "\(p.completedCount) of \(totalDays) workouts done"
        }

        // FTP history — last 3 test results
        let ftpHistory = FTPTestHistory.load()
            .sorted { $0.date > $1.date }
            .prefix(3)
            .map { "\(Int($0.estimatedFTP))W" }
            .joined(separator: " → ")

        // Last completed ride — most recent completed workout
        let lastRideDescriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.statusRaw == "completed" },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let lastRides = (try? modelContext.fetch(lastRideDescriptor)) ?? []
        let lastRide = lastRides.first

        var lastRideContext: LastRideContext?
        if let ride = lastRide {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let dateStr = formatter.localizedString(for: ride.startDate, relativeTo: .now)
            let summaryParts: [String] = [
                "\(Int(ride.duration / 60))min",
                String(format: "%.1fkm", ride.distance / 1000),
                "\(Int(ride.avgPower))W avg",
                "NP \(Int(ride.normalizedPower))W",
                "TSS \(Int(ride.tss))"
            ]

            lastRideContext = LastRideContext(
                date: dateStr,
                durationMinutes: Int(ride.duration / 60),
                distanceKm: ride.distance / 1000,
                avgPower: ride.avgPower,
                maxPower: ride.maxPower,
                avgHR: ride.avgHR,
                avgSpeed: ride.avgSpeed,
                elevationGain: ride.elevationGain,
                normalizedPower: ride.normalizedPower,
                tss: ride.tss,
                intensityFactor: ride.intensityFactor,
                summary: summaryParts.joined(separator: " · ")
            )
        }

        return UserContext(
            ftp: ftp,
            maxHR: maxHR,
            restingHR: restingHR,
            recentWorkoutsCount: recentCount,
            activePlanName: planName,
            activePlanProgress: planProgressStr,
            ftpHistory: ftpHistory.isEmpty ? nil : ftpHistory,
            lastRide: lastRideContext
        )
    }

    /// Restores the coach thread from SwiftData (in-memory `messages` was always empty after relaunch).
    func loadPersistedMessages(modelContext: ModelContext) {
        guard messages.isEmpty else {
            logger.debug("loadPersistedMessages skipped — \(self.messages.count) messages already in memory")
            return
        }

        // Try to load the most recent session first
        if let sessionID = currentSessionID {
            loadSession(sessionID, modelContext: modelContext)
            return
        }

        // Fall back to loading the most recent session
        let sessionDescriptor = FetchDescriptor<ChatSession>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let sessions = try? modelContext.fetch(sessionDescriptor), let latest = sessions.first {
            currentSessionID = latest.id
            loadSession(latest.id, modelContext: modelContext)
            return
        }

        // No sessions exist — start fresh
        logger.debug("No sessions found, starting fresh")
    }

    private func loadSession(_ sessionID: UUID, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<CoachChatMessage>(
            predicate: #Predicate<CoachChatMessage> { $0.session?.id == sessionID },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        do {
            let rows = try modelContext.fetch(descriptor)
            logger.debug("Loaded \(rows.count) persisted messages from session \(sessionID)")
            guard messages.isEmpty else { return }
            let loaded = rows.map { $0.toChatMessage() }
            messages = loaded
            for msg in loaded {
                animatedMessageIDs.insert(msg.id)
            }
        } catch {
            logger.error("Failed to load persisted messages: \(error)")
        }
    }

    /// Creates a new chat session and sets it as the active session.
    func createNewSession(modelContext: ModelContext) {
        let session = ChatSession()
        modelContext.insert(session)
        do {
            try modelContext.save()
            currentSessionID = session.id
            messages.removeAll()
            animatedMessageIDs.removeAll()
            logger.debug("Created new session \(session.id)")
        } catch {
            logger.error("Failed to create new session: \(error)")
        }
    }

    /// Switches to an existing session by ID.
    func switchToSession(_ sessionID: UUID, modelContext: ModelContext) {
        currentSessionID = sessionID
        animatedMessageIDs.removeAll()
        loadSession(sessionID, modelContext: modelContext)
    }

    /// Deletes a session by ID. If it's the current session, clears messages too.
    func deleteSession(_ sessionID: UUID, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate<ChatSession> { $0.id == sessionID }
        )
        if let sessions = try? modelContext.fetch(descriptor), let session = sessions.first {
            modelContext.delete(session)
            do {
                try modelContext.save()
                if currentSessionID == sessionID {
                    messages.removeAll()
                    animatedMessageIDs.removeAll()
                    currentSessionID = nil
                }
                logger.debug("Deleted session \(sessionID)")
            } catch {
                logger.error("Failed to delete session: \(error)")
            }
        }
    }

    /// Fetches all sessions sorted by most recently updated.
    func fetchSessions(modelContext: ModelContext) -> [ChatSession] {
        let descriptor = FetchDescriptor<ChatSession>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Updates the session title from the first user message if still default.
    private func updateSessionTitleIfNeeded(modelContext: ModelContext) {
        guard let sessionID = currentSessionID else { return }
        let descriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate<ChatSession> { $0.id == sessionID }
        )
        if let sessions = try? modelContext.fetch(descriptor), let session = sessions.first {
            if session.title == "New Conversation" {
                session.updateTitle(from: session.messages)
                do {
                    try modelContext.save()
                } catch {
                    logger.error("Failed to update session title: \(error)")
                }
            } else {
                session.updatedAt = .now
                do {
                    try modelContext.save()
                } catch {
                    logger.error("Failed to update session timestamp: \(error)")
                }
            }
        }
    }

    func clearMessages(modelContext: ModelContext) {
        createNewSession(modelContext: modelContext)
    }

    private func persistCoachMessage(_ message: ChatMessage, modelContext: ModelContext) {
        let persisted = CoachChatMessage.from(message)
        if let sessionID = currentSessionID {
            let descriptor = FetchDescriptor<ChatSession>(
                predicate: #Predicate<ChatSession> { $0.id == sessionID }
            )
            if let sessions = try? modelContext.fetch(descriptor), let session = sessions.first {
                session.messages.append(persisted)
            }
        }
        modelContext.insert(persisted)
        do {
            try modelContext.save()
        } catch {
            logger.error("persistCoachMessage save failed: \(error)")
        }
    }

    // MARK: - Helpers

    private func buildHistory() -> [HistoryTurn] {
        // Last 6 turns (12 messages) — exclude the very last user message (sent separately)
        messages
            .suffix(12)
            .map { HistoryTurn(role: $0.role.rawValue, content: $0.content) }
    }

    private func post<Req: Encodable, Res: Decodable>(path: String, body: Req) async throws -> Res {
        guard let url = URL(string: baseURL + path) else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(userID, forHTTPHeaderField: "X-User-ID")
        req.timeoutInterval = 90
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)

        if let httpResponse = response as? HTTPURLResponse {
            logger.debug("\(path) → HTTP \(httpResponse.statusCode)")
            if httpResponse.statusCode >= 400 {
                if let body = String(data: data, encoding: .utf8) {
                    logger.error("Error body: \(body.prefix(500), privacy: .private)")
                }
                throw URLError(.badServerResponse)
            }
        }

        do {
            return try JSONDecoder().decode(Res.self, from: data)
        } catch {
            logger.error("Decode error for \(path): \(error)")
            if let body = String(data: data, encoding: .utf8) {
                logger.error("Raw response: \(body.prefix(500), privacy: .private)")
            }
            throw error
        }
    }
}
