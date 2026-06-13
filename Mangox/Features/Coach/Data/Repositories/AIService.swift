import CryptoKit
import Foundation
import FoundationModels
import SwiftData
import SwiftUI
import os.log

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
    /// Device local calendar date `yyyy-MM-dd` so the coach anchors schedules correctly.
    let client_local_date: String
    /// IANA zone id (e.g. `America/Los_Angeles`).
    let client_time_zone: String
    /// When true, backend prepends plan-intake booster and forces full tier + user context.
    let force_plan_intake: Bool?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(history, forKey: .history)
        try container.encodeIfPresent(user_context, forKey: .user_context)
        try container.encodeIfPresent(user_context_encrypted, forKey: .user_context_encrypted)
        try container.encode(is_pro, forKey: .is_pro)
        try container.encode(client_local_date, forKey: .client_local_date)
        try container.encode(client_time_zone, forKey: .client_time_zone)
        if force_plan_intake == true {
            try container.encode(true, forKey: .force_plan_intake)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case message, history, user_context, user_context_encrypted
        case is_pro, client_local_date, client_time_zone, force_plan_intake
    }
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
    let followUpBlocks: [CoachFollowUpBlock]
    let confidence: Double
    let thinkingSteps: [String]
    let tags: [String]
    let references: [ChatReference]
    let toolCalls: [ToolCall]
    let usedWebSearch: Bool

    init(
        category: String,
        content: String,
        suggestedActions: [SuggestedAction],
        followUpQuestion: String?,
        followUpBlocks: [CoachFollowUpBlock] = [],
        confidence: Double,
        thinkingSteps: [String],
        tags: [String],
        references: [ChatReference],
        toolCalls: [ToolCall],
        usedWebSearch: Bool = false
    ) {
        self.category = category
        self.content = content
        self.suggestedActions = suggestedActions
        self.followUpQuestion = followUpQuestion
        self.followUpBlocks = followUpBlocks
        self.confidence = confidence
        self.thinkingSteps = thinkingSteps
        self.tags = tags
        self.references = references
        self.toolCalls = toolCalls
        self.usedWebSearch = usedWebSearch
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        category = (try? c.decodeIfPresent(String.self, forKey: .category)) ?? "training_advice"
        content = try c.decode(String.self, forKey: .content)
        suggestedActions =
            (try? c.decodeIfPresent([SuggestedAction].self, forKey: .suggestedActions))
            ?? (try? c.decodeIfPresent([SuggestedAction].self, forKey: .suggested_actions))
            ?? []
        followUpQuestion =
            (try? c.decodeIfPresent(String.self, forKey: .followUpQuestion))
            ?? (try? c.decodeIfPresent(String.self, forKey: .follow_up_question))
        followUpBlocks =
            (try? c.decodeIfPresent([CoachFollowUpBlock].self, forKey: .followUpBlocks))
            ?? (try? c.decodeIfPresent([CoachFollowUpBlock].self, forKey: .follow_up_blocks))
            ?? []
        confidence = (try? c.decodeIfPresent(Double.self, forKey: .confidence)) ?? 1.0
        thinkingSteps = (try? c.decodeIfPresent([String].self, forKey: .thinkingSteps)) ?? []
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        references = (try? c.decodeIfPresent([ChatReference].self, forKey: .references)) ?? []
        toolCalls = (try? c.decodeIfPresent([ToolCall].self, forKey: .toolCalls)) ?? []
        usedWebSearch = (try? c.decodeIfPresent(Bool.self, forKey: .usedWebSearch)) ?? false
    }

    enum CodingKeys: String, CodingKey {
        case category, content, suggestedActions, followUpQuestion, followUpBlocks, confidence,
            thinkingSteps, tags, references, toolCalls
        case suggested_actions, follow_up_question, follow_up_blocks
        case usedWebSearch = "used_web_search"
    }
}

struct UserContext: Encodable {
    let ftp: Int
    let maxHR: Int
    let restingHR: Int
    let recentWorkoutsCount: Int
    let activePlanName: String?
    let activePlanProgress: String?
    /// `builtin` (template) or `ai` when an active plan is resolved.
    let activePlanSource: String?
    /// Sum of TSS from valid completed rides in the current calendar week.
    let weekActualTss: Int
    /// Guided ERG scale as percent (100 = plan as written).
    let adaptiveErgPercent: Int
    let ftpHistory: String?
    let lastRide: LastRideContext?
    /// Reserved; always `nil` (goal/season UI removed).
    let seasonGoalSummary: String?
    /// Short hint about optional vs mandatory plan days when the active week includes flexible sessions.
    let planKeyDaySemanticsHint: String?
    /// Compact multi-line digest of the most recent completed rides for broader training context.
    let recentRideDigest: String?
    /// Latest ride Pw:HR aerobic drift summary when enough power and HR data exists.
    let lastRideAerobicDecoupling: String?
    /// Rider body weight in kg when set. Used to compute W/kg context.
    let riderWeightKg: Double?
    /// Rider age in years when birth year is set.
    let riderAge: Int?
    /// True when a WHOOP account is connected in-app (OAuth).
    let whoopLinked: Bool
    /// Latest WHOOP recovery score (0–100) when available.
    let whoopRecoveryPercent: Double?
    /// Resting HR from latest WHOOP recovery payload, when present.
    let whoopRestingHR: Int?
    /// HRV (RMSSD, ms) rounded from WHOOP when present.
    let whoopHrvMs: Int?
    /// Max HR from WHOOP body-measurement endpoint when present (not workout peak).
    let whoopMaxHeartRate: Int?
    /// Current chronic training load when PMC history is loaded.
    let currentCtl: Double?
    /// Current acute training load when PMC history is loaded.
    let currentAtl: Double?
    /// Current training stress balance when PMC history is loaded.
    let currentTsb: Double?
    /// 14/28-day PMC delta summary when enough history exists.
    let pmcTrendSummary: String?
    /// Multi-ride aerobic decoupling trend when enough steady rides exist.
    let aerobicDecouplingTrend: String?
    /// Compact best-power curve summary from recent rides.
    let powerCurveSummary: String?
    /// Two-parameter critical power fit when enough curve points exist.
    let criticalPowerSummary: String?
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
    /// Human-readable line for the coach; omits misleading 0W/NP when no power meter.
    let summary: String
    let powerDataAvailable: Bool
    let aerobicDecouplingPercent: Double?
    let aerobicDecouplingStatus: String?
}

struct PlanGenerationRequest: Encodable {
    let inputs: PlanInputs
    let is_pro: Bool
    let user_context_encrypted: String?
    let client_local_date: String
    let client_time_zone: String
}

struct PlanGenerationResponse: Decodable {
    let plan: TrainingPlan
    let credits_used: Int?
    let credits_remaining: Int?
    let request_id: String?
    let validation_warnings: [String]?
    let generation_metrics: PlanGenerationMetrics?
}

struct WorkoutGenerationRequest: Encodable {
    let inputs: WorkoutGenerationInputs
    let is_pro: Bool
    let user_context_encrypted: String?
    let client_local_date: String
    let client_time_zone: String
}

struct WorkoutGenerationResponse: Decodable {
    let workout: GeneratedWorkout
    let request_id: String?
    let validation_warnings: [String]?
}

struct ToolCall: Codable, Identifiable, Equatable, Sendable {
    var id: String { "\(name)-\(state)-\(detail ?? "")" }
    let name: String
    let state: String
    let detail: String?
}

/// JSON in `ToolCall.detail` when `name == "generate_plan"` (matches `/api/generate-plan` inputs).
private struct GeneratePlanToolDetail: Decodable {
    let event_name: String
    let event_date: String?
    let weekly_hours: Int?
    let experience: String?
    let route_option: String?
    let target_distance_km: Double?
    let target_elevation_m: Double?
    let event_location: String?
    let event_notes: String?

    enum CodingKeys: String, CodingKey {
        case event_name, event_date, weekly_hours, experience
        case route_option, target_distance_km, target_elevation_m, event_location, event_notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        event_name = try c.decode(String.self, forKey: .event_name)
        event_date = try c.decodeIfPresent(String.self, forKey: .event_date)
        weekly_hours = Self.decodeFlexibleInt(c, forKey: .weekly_hours)
        experience = try c.decodeIfPresent(String.self, forKey: .experience)
        route_option = try c.decodeIfPresent(String.self, forKey: .route_option)
        target_distance_km = Self.decodeFlexibleDouble(c, forKey: .target_distance_km)
        target_elevation_m = Self.decodeFlexibleDouble(c, forKey: .target_elevation_m)
        event_location = try c.decodeIfPresent(String.self, forKey: .event_location)
        event_notes = try c.decodeIfPresent(String.self, forKey: .event_notes)
    }

    private static func decodeFlexibleDouble(
        _ c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return Double(i) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let d = Double(t) { return d }
            let filtered = t.filter { $0.isNumber || $0 == "." || $0 == "," }
            let normalized = filtered.replacingOccurrences(of: ",", with: ".")
            if let d = Double(normalized) { return d }
        }
        return nil
    }

    private static func decodeFlexibleInt(
        _ c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int? {
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(d.rounded()) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key),
            let v = Int(s.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            return v
        }
        return nil
    }
}

private struct GenerateWorkoutToolDetail: Decodable {
    let goal: String
    let duration_minutes: Int?
    let experience: String?
    let preferred_intensity: String?
    let environment: String?
    let planned_date: String?
    let plan_context: String?
}

/// Normalizes model-supplied dates to `yyyy-MM-dd` for `/api/generate-plan` and UI.
private enum PlanEventDateNormalization {
    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func normalizedYYYYMMDD(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let cal = Calendar.current

        if let d = ymd.date(from: trimmed) {
            return ymd.string(from: cal.startOfDay(for: d))
        }

        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [
            .withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime,
        ]
        if let d = isoFull.date(from: trimmed) {
            return ymd.string(from: cal.startOfDay(for: d))
        }

        let isoDay = ISO8601DateFormatter()
        isoDay.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        if let d = isoDay.date(from: trimmed) {
            return ymd.string(from: cal.startOfDay(for: d))
        }

        let medium = DateFormatter()
        medium.locale = .current
        medium.timeZone = TimeZone.current
        medium.dateStyle = .medium
        medium.timeStyle = .none
        if let d = medium.date(from: trimmed) {
            return ymd.string(from: cal.startOfDay(for: d))
        }

        let long = DateFormatter()
        long.locale = .current
        long.timeZone = TimeZone.current
        long.dateStyle = .long
        long.timeStyle = .none
        if let d = long.date(from: trimmed) {
            return ymd.string(from: cal.startOfDay(for: d))
        }

        let us = DateFormatter()
        us.locale = Locale(identifier: "en_US_POSIX")
        us.timeZone = TimeZone.current
        for pattern in ["MM/dd/yyyy", "M/d/yyyy", "MM-dd-yyyy"] {
            us.dateFormat = pattern
            if let d = us.date(from: trimmed) {
                return ymd.string(from: cal.startOfDay(for: d))
            }
        }

        let eu = DateFormatter()
        eu.locale = Locale(identifier: "en_GB")
        eu.timeZone = TimeZone.current
        for pattern in ["dd/MM/yyyy", "d/M/yyyy", "dd-MM-yyyy"] {
            eu.dateFormat = pattern
            if let d = eu.date(from: trimmed) {
                return ymd.string(from: cal.startOfDay(for: d))
            }
        }

        if let d = extractDateWithDataDetector(from: trimmed) {
            return ymd.string(from: cal.startOfDay(for: d))
        }

        return nil
    }

    private static func extractDateWithDataDetector(from string: String) -> Date? {
        guard
            let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.date.rawValue)
        else { return nil }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        var found: Date?
        detector.enumerateMatches(in: string, options: [], range: range) { match, _, _ in
            guard let match, let d = match.date else { return }
            if found == nil { found = d }
        }
        return found
    }
}

enum ChatRuntimeEvent: Sendable {
    case status(String)
    case textDelta(String)
    case reasoningDelta(String)
    case toolCalls([ToolCall])
    case completed(ChatAPIResponse)
    case failed(String)
}

struct ChatWireEvent: Decodable, Sendable {
    let type: String
    let delta: String?
    let status: String?
    let message: ChatAPIResponse?
    let error: String?
}

// MARK: - AIService

@Observable @MainActor
final class AIService: AIServiceProtocol, CoachRepository {

    private let workoutPersistence: WorkoutPersistenceRepositoryProtocol

    /// Injected from `DIContainer` so coach context and recovery heuristics can use WHOOP when linked.
    var whoopDataSource: (any WhoopServiceProtocol)?
    var persistenceContext: ModelContext { PersistenceContainer.shared.mainContext }

    init(workoutPersistence: WorkoutPersistenceRepositoryProtocol = WorkoutPersistenceRepository()) {
        self.workoutPersistence = workoutPersistence
    }

    // MARK: Public State

    var messages: [ChatMessage] = []
    var isLoading: Bool = false
    var error: String? = nil
    var generatingPlan: Bool = false
    var planProgress: PlanGenerationProgress?
    var lastCreditsRemaining: Int? = nil

    /// User must confirm before we call the plan API (set from chat `generate_plan` tool or Regenerate).
    var planConfirmationDraft: PlanGenerationDraft?
    /// After a successful save, celebration UI + optional navigation to the plan.
    var planSaveCelebration: PlanSaveCelebration?
    /// Full single-workout draft awaiting save.
    var workoutConfirmationDraft: WorkoutGenerationDraft?
    /// Last saved generated workout, used for start-workout CTA.
    var workoutSaveCelebration: WorkoutSaveCelebration?

    /// Shown while the backend streams the coach reply (`/api/chat/stream` extracts `content` text).
    /// Refreshes on a short debounce so the UI does not repaint every token.
    var streamDraftText: String = ""
    /// Short status from SSE / reasoning phases (shown in the pending bubble subtitle).
    var streamStatusText: String?
    /// True while the model is emitting a `<think>` block with no visible content yet.
    var streamIsThinking: Bool = false
    /// Set when the backend reports a web-search status before the first content delta.
    var streamIsSearchingWeb: Bool = false
    /// Chrome for the in-flight pending bubble (on-device, PCC, cloud, …).
    var streamDelivery: CoachStreamDelivery = .cloud
    /// Tags streamed from partial FM replies before the final message commits.
    var streamPartialTags: [String] = []
    /// Shown while falling back between delivery tiers ("Trying Private Cloud…").
    var streamRouteStatus: String? = nil

    private var streamRawBuffer: String = ""
    private var streamUsesTokenDeltas = false
    private var streamDisplayThrottleTask: Task<Void, Never>?
    private var activeChatTurnTask: Task<Void, Never>?
    private var activeChatTurnGeneration: UInt64 = 0
    /// Stays true after plan builder entry until session change or plan confirm clears it.
    private var planIntakeModeActive = false

    /// The currently active chat session. Nil means no session selected.
    var currentSessionID: UUID?

    /// Reused multi-turn narrow coach session; reset on createNewSession/switchToSession.
    private var narrowCoachLanguageSession: LanguageModelSession?
    private var narrowCoachSessionOwnerID: UUID?

    /// Reused PCC coach session (iOS 27 Dynamic Profiles); reset on createNewSession/switchToSession.
    private var pccCoachLanguageSession: LanguageModelSession?
    private var pccCoachSessionOwnerID: UUID?
    /// Raw `CoachAgentMode` storage (iOS 27+); avoids availability on stored property type.
    private var pccCoachSessionModeRaw: String?

    /// Reused third-party `LanguageModel` coach session; reset on createNewSession/switchToSession.
    private var thirdPartyCoachLanguageSession: LanguageModelSession?
    private var thirdPartyCoachSessionOwnerID: UUID?
    /// When true, the next turn skips on-device narrow and PCC (cloud-only retry).
    private var skipLocalCoachForNextTurn = false
    /// Delivery tier that failed before the last error bubble (for retry UI).
    var lastFailedDeliveryPath: CoachDeliveryPath?
    private var activeTurnIsWebSearch = false

    // MARK: - Coach context cache (one aggregate build per invalidation)

    var coachContextCacheToken = UUID()
    var cachedUserContextEntry: UserContext?
    var cachedFactSheetFull: String?
    var cachedFactSheetCompact: String?
    var cachedStarterAvailability: CoachStarterPromptAvailability?
    var cachedOnDeviceToolDigests: CoachOnDeviceToolDigestBundle?
    var cachedOnDeviceToolDigestsOwnerID: UUID?

    func invalidateCoachContextCache() {
        coachContextCacheToken = UUID()
        cachedUserContextEntry = nil
        cachedFactSheetFull = nil
        cachedFactSheetCompact = nil
        cachedStarterAvailability = nil
        cachedOnDeviceToolDigests = nil
        cachedOnDeviceToolDigestsOwnerID = nil
    }

    func cachedUserContext(modelContext: ModelContext) -> UserContext {
        if let cachedUserContextEntry { return cachedUserContextEntry }
        let ctx = buildUserContext(modelContext: modelContext)
        cachedUserContextEntry = ctx
        return ctx
    }

    /// Rule-based empty-state starters (no on-device AI); safe to show immediately.
    func instantCoachEmptyStartersContent() -> CoachEmptyStartersContent {
        CoachEmptyStartersContent(
            prompts: contextualQuickPrompts(modelContext: persistenceContext),
            topicTags: []
        )
    }

    func onDeviceToolDigests(modelContext: ModelContext) -> CoachOnDeviceToolDigestBundle {
        if cachedOnDeviceToolDigestsOwnerID == currentSessionID,
            let cachedOnDeviceToolDigests
        {
            return cachedOnDeviceToolDigests
        }
        let bundle = buildOnDeviceToolDigestBundle(modelContext: modelContext)
        cachedOnDeviceToolDigests = bundle
        cachedOnDeviceToolDigestsOwnerID = currentSessionID
        return bundle
    }

    func preparedOnDeviceToolDigests(modelContext: ModelContext) async
        -> CoachOnDeviceToolDigestBundle
    {
        if cachedOnDeviceToolDigestsOwnerID == currentSessionID,
            let cachedOnDeviceToolDigests
        {
            return cachedOnDeviceToolDigests
        }
        await Task.yield()
        return onDeviceToolDigests(modelContext: modelContext)
    }

    // MARK: Constants

    /// Daily cap for **Mangox Cloud** turns only (web search until PCC ships, legacy fallback).
    /// On-device stats, Private Cloud Compute, and third-party LanguageModel turns are not counted.
    static let freeDailyLimit = 5

    /// When `Info.plist` `MangoxCoachStaffTier` is `admin` or `superuser` (via build setting `MANGOX_COACH_STAFF_TIER`), the free-tier daily coach cap is skipped. Leave empty for App Store builds.
    static var bypassesDailyCoachMessageLimit: Bool {
        let raw =
            (Bundle.main.object(forInfoDictionaryKey: "MangoxCoachStaffTier") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let norm = raw.replacingOccurrences(of: "_", with: "").replacingOccurrences(
            of: "-", with: "")
        return norm == "admin" || norm == "superuser"
    }

    func sendMessage(
        _ text: String,
        isPro: Bool,
        forcePlanIntake: Bool = false,
        image: CoachUserImageAttachment? = nil
    ) async {
        await sendMessage(
            text,
            isPro: isPro,
            forcePlanIntake: forcePlanIntake,
            image: image,
            modelContext: persistenceContext
        )
    }

    @discardableResult
    func generatePlan(
        inputs: PlanInputs,
        isPro: Bool,
        idempotencyKey: String
    ) async throws -> PlanGenerationResult {
        try await generatePlan(
            inputs: inputs,
            isPro: isPro,
            modelContext: persistenceContext,
            idempotencyKey: idempotencyKey
        )
    }

    func runConfirmedPlanGeneration(
        draft: PlanGenerationDraft,
        isPro: Bool
    ) async throws {
        try await runConfirmedPlanGeneration(
            draft: draft,
            isPro: isPro,
            modelContext: persistenceContext
        )
    }

    func saveConfirmedWorkoutDraft(_ draft: WorkoutGenerationDraft) throws {
        try saveConfirmedWorkoutDraft(draft, modelContext: persistenceContext)
    }

    func regenerateFallbackPlanWeek(
        weekNumber: Int,
        celebration: PlanSaveCelebration,
        isPro: Bool
    ) async throws {
        try await regenerateFallbackPlanWeek(
            weekNumber: weekNumber,
            celebration: celebration,
            isPro: isPro,
            modelContext: persistenceContext
        )
    }

    func loadPersistedMessages() async {
        await loadPersistedMessages(modelContext: persistenceContext)
    }

    func createNewSession() {
        createNewSession(modelContext: persistenceContext)
    }

    func switchToSession(_ sessionID: UUID) {
        switchToSession(sessionID, modelContext: persistenceContext)
    }

    func deleteSession(_ sessionID: UUID) {
        deleteSessions([sessionID], modelContext: persistenceContext)
    }

    func deleteSessions(_ sessionIDs: Set<UUID>) {
        deleteSessions(sessionIDs, modelContext: persistenceContext)
    }

    func fetchSessions() -> [ChatSession] {
        fetchSessions(modelContext: persistenceContext)
    }

    func clearMessages() {
        clearMessages(modelContext: persistenceContext)
    }

    func dismissError() {
        error = nil
    }

    func regenerateLastMessage(isPro: Bool) async {
        await regenerateLastMessage(isPro: isPro, modelContext: persistenceContext)
    }

    func regenerateLastMessagePreferringCloud(isPro: Bool) async {
        await regenerateLastMessagePreferringCloud(
            isPro: isPro,
            modelContext: persistenceContext
        )
    }

    /// In-chat quick-reply chips (model `suggestedActions`). Trim, cap, drop empties.
    private static func sanitizedSuggestedActions(_ raw: [SuggestedAction]) -> [SuggestedAction] {
        raw
            .map {
                let trimmed = SuggestedAction(
                    label: $0.label.trimmingCharacters(in: .whitespacesAndNewlines),
                    type: $0.type.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                return SuggestedAction(
                    label: CoachChipPresentation.displayTitle(for: trimmed),
                    type: trimmed.type
                )
            }
            .filter { !$0.label.isEmpty }
            .prefix(4)
            .map { $0 }
    }

    /// Up to three follow-up cards; drops empty questions or empty chip lists.
    private static func sanitizedFollowUpBlocks(_ raw: [CoachFollowUpBlock]) -> [CoachFollowUpBlock]
    {
        Array(
            raw
                .prefix(3)
                .map {
                    CoachFollowUpBlock(
                        question: $0.question.trimmingCharacters(in: .whitespacesAndNewlines),
                        suggestedActions: sanitizedSuggestedActions($0.suggestedActions)
                    )
                }
                .filter { !$0.question.isEmpty }
        )
    }

    private static func cappedThinkingSteps(_ raw: [String]) -> [String] {
        raw
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { String($0.prefix(1200)) }
    }

    /// Short question line only — never the full clarification paragraph (avoids duplicating the main bubble).
    private static func firstQuestionSentence(in content: String, maxLength: Int = 160) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let qMark = trimmed.firstIndex(of: "?") else { return nil }
        let head = trimmed[..<qMark]
        let start: String.Index
        if let lineBreak = head.lastIndex(of: "\n") {
            start = trimmed.index(after: lineBreak)
        } else if let period = head.lastIndex(of: ".") {
            start = trimmed.index(after: period)
        } else {
            start = trimmed.startIndex
        }
        let end = trimmed.index(after: qMark)
        let sentence = String(trimmed[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard sentence.count >= 8 else { return nil }
        if sentence.count > maxLength { return nil }
        return sentence
    }

    private static func isFollowUpRedundantWithBody(followUp: String, body: String) -> Bool {
        let f = followUp.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if f.isEmpty { return true }
        if b.hasPrefix(f) { return true }
        if f.count >= 48, b.contains(f) { return true }
        let prefixLen = min(100, b.count)
        if prefixLen > 0, f.hasPrefix(b.prefix(prefixLen)) { return true }
        return false
    }

    /// True when we should attach plan-intake chips without echoing the whole `content` as `followUpQuestion`.
    private static func shouldOfferClarificationRecovery(category: String, content: String) -> Bool {
        let cat = category.lowercased()
        if cat == "clarification" || cat.contains("clarif") { return true }
        let lower = content.lowercased()
        if lower.contains("training plan"), lower.contains("detail") || lower.contains("need") {
            return true
        }
        return false
    }

    /// Optional short question; chips carry the real “what next” affordances.
    private static func tightClarificationQuestion(category: String, content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cat = category.lowercased()
        let categoryMatches = cat == "clarification" || cat.contains("clarif")
        let looseMatch =
            !categoryMatches && trimmed.count >= 40
            && (trimmed.lowercased().contains("detail") || trimmed.lowercased().contains("plan"))
        guard categoryMatches || looseMatch else { return nil }
        return firstQuestionSentence(in: trimmed, maxLength: 160)
    }

    /// Concrete next-step chips when the API omits structured follow-ups (e.g. Gemma JSON parse failure).
    /// Labels are sent verbatim as user messages — must be real answers, not UI section headers.
    private static func planIntakeClarificationChips() -> [SuggestedAction] {
        [
            SuggestedAction(label: "Gran Fondo or century ride", type: "ask_followup"),
            SuggestedAction(label: "L'Étape or sportive event", type: "ask_followup"),
            SuggestedAction(label: "About 8 hours per week", type: "ask_followup"),
            SuggestedAction(label: "Guide me step by step", type: "ask_followup"),
        ]
    }

    private static func isPlanUpsellFollowUp(_ text: String) -> Bool {
        let lower = text.lowercased()
        let markers = [
            "training plan", "build a plan", "generate a plan", "generate a training",
            "prepare for this event", "plan for this", "help you train for",
        ]
        return markers.contains(where: { lower.contains($0) })
    }

    /// Web research turns should not surface the full plan-intake card unless the user is already in that flow.
    private static func sanitizeFollowUpForWebResearch(
        followUp: String?,
        actions: [SuggestedAction],
        planIntakeActive: Bool
    ) -> (followUp: String?, actions: [SuggestedAction]) {
        guard !planIntakeActive else { return (followUp, actions) }
        guard let followUp, isPlanUpsellFollowUp(followUp) else { return (followUp, actions) }
        var trimmedActions = actions
        if trimmedActions.isEmpty {
            trimmedActions = [
                SuggestedAction(label: "Build a plan for this event", type: "ask_followup"),
                SuggestedAction(label: "Thanks, that's enough", type: "ask_followup"),
            ]
        }
        return (nil, trimmedActions)
    }

    /// Client-side plan builder entry points should set `force_plan_intake` on the cloud request.
    static func shouldForcePlanIntake(for text: String) -> Bool {
        let lower = text.lowercased()
        let markers = [
            "build a structured training plan",
            "build a training plan",
            "create a training plan",
            "generate my plan",
            "help me build a plan",
            "start plan builder",
        ]
        if markers.contains(where: { lower.contains($0) }) { return true }
        if lower.hasPrefix("here are my answers:") { return true }
        return false
    }

    private static func isPlanIntakeContinuation(_ text: String) -> Bool {
        shouldForcePlanIntake(for: text)
    }

    private static func looksLikePlanIntakeAssistantTurn(
        blocks: [CoachFollowUpBlock],
        followUp: String?,
        content: String,
        toolCalls: [ToolCall]
    ) -> Bool {
        if toolCalls.contains(where: { $0.name == "generate_plan" && $0.state == "pending" }) {
            return false
        }
        if !blocks.isEmpty { return true }
        let q = (followUp ?? "").lowercased()
        let planQuestionMarkers = [
            "event", "goal", "race", "date", "hour", "week", "experience", "plan",
            "route", "training for", "volume", "level",
        ]
        if planQuestionMarkers.contains(where: { q.contains($0) }) { return true }
        let lower = content.lowercased()
        if lower.contains("build your plan")
            || lower.contains("plan intake")
            || lower.contains("collect the key details")
            || lower.contains("training plan")
        {
            return true
        }
        return false
    }

    private func syncPlanIntakeMode(
        userText: String,
        forcePlanIntake: Bool,
        response: ChatAPIResponse?,
        blocks: [CoachFollowUpBlock],
        panelFollowUp: String?,
        usedWebSearch: Bool = false
    ) {
        if usedWebSearch && !forcePlanIntake && !Self.isPlanIntakeContinuation(userText) {
            return
        }
        if forcePlanIntake || Self.isPlanIntakeContinuation(userText) {
            planIntakeModeActive = true
            return
        }
        guard let response else { return }
        if Self.looksLikePlanIntakeAssistantTurn(
            blocks: blocks,
            followUp: panelFollowUp,
            content: response.content,
            toolCalls: response.toolCalls
        ) {
            planIntakeModeActive = true
        }
    }

    private func clearPlanIntakeMode() {
        planIntakeModeActive = false
    }

    private static func looksLikeSingleWorkoutRequest(_ text: String) -> Bool {
        let lower = text.lowercased()
        let workoutHints = [
            "build me a workout", "generate a workout", "give me a workout",
            "session for today", "session for tonight", "recovery ride", "threshold workout",
            "vo2 workout", "sweet spot workout", "tempo workout", "endurance ride",
        ]
        if workoutHints.contains(where: { lower.contains($0) }) { return true }
        return lower.contains(" workout") && !lower.contains("training plan")
    }

    /// Matches server `used_web_search` only. References alone can be model-invented URLs;
    /// inferring "live search" from `references` caused false "Answer used live web sources" badges.
    private static func resolvedUsedWebSearch(_ response: ChatAPIResponse) -> Bool {
        response.usedWebSearch
    }

    private static var isPCCLiveWebSearchAvailable: Bool {
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
            return MangoxPrivateCloudComputeModelFactory.isLiveWebSearchAvailable
        }
        return false
    }

    /// Normalizes user-entered race day for `/api/generate-plan` (yyyy-MM-dd and common variants).
    static func normalizeEventDateForPlan(_ raw: String) -> String? {
        PlanEventDateNormalization.normalizedYYYYMMDD(from: raw)
    }

    /// Short headline for the plan confirmation banner and saved `userPrompt`.
    static func planSummaryLine(for inputs: PlanInputs) -> String {
        var parts = [inputs.event_name, inputs.event_date]
        if let r = inputs.route_option?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty
        {
            parts.append(r)
        }
        return parts.joined(separator: " · ")
    }

    static func workoutSummaryLine(for inputs: WorkoutGenerationInputs) -> String {
        inputs.summaryLine
    }

    private static func nonEmptyTrimmed(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else {
            return nil
        }
        return t
    }

    private let logger = Logger(subsystem: "com.abchalita.Mangox", category: "AIService")

    // MARK: Coach chat flow logging

    /// `UserDefaults` key. When `true`, logs routing for each coach send (on-device vs cloud, delivery mode).
    /// In **DEBUG** builds, flow logging defaults to **on** unless this key is explicitly set to `false`.
    static let coachChatFlowLogDefaultsKey = "MangoxCoachChatFlowLog"

    private static var coachChatFlowLoggingEnabled: Bool {
        let ud = UserDefaults.standard
        #if DEBUG
        if ud.object(forKey: coachChatFlowLogDefaultsKey) == nil { return true }
        #endif
        return ud.bool(forKey: coachChatFlowLogDefaultsKey)
    }

    private func logCoachFlow(_ message: String) {
        guard Self.coachChatFlowLoggingEnabled else { return }
        logger.info("\(message, privacy: .public)")
    }

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

    var todayMessageCount: Int { todayCloudMessageCount }

    private var todayCloudMessageCount: Int {
        guard UserDefaults.standard.string(forKey: udDateKey) == todayDateString else { return 0 }
        return UserDefaults.standard.integer(forKey: udCountKey)
    }

    func hasReachedFreeLimit(isPro: Bool) -> Bool {
        if isPro { return false }
        if Self.bypassesDailyCoachMessageLimit { return false }
        return todayCloudMessageCount >= Self.freeDailyLimit
    }

    /// Free tier: on-device narrow stats and Private Cloud turns do not count against the cloud cap.
    func canSendCoachMessage(
        _ text: String,
        isPro: Bool,
        forcePlanIntake: Bool = false,
        hasImage: Bool = false
    ) -> Bool {
        if isPro || Self.bypassesDailyCoachMessageLimit { return true }
        if todayCloudMessageCount < Self.freeDailyLimit { return true }
        if forcePlanIntake || planIntakeModeActive { return false }
        if hasImage { return qualifiesForUnbilledPCCCoach(text, forcePlanIntake: forcePlanIntake) }
        if qualifiesForUnbilledOnDeviceNarrow(text) { return true }
        if qualifiesForUnbilledPCCCoach(text, forcePlanIntake: forcePlanIntake) { return true }
        return false
    }

    private func qualifiesForUnbilledPCCCoach(_ text: String, forcePlanIntake: Bool) -> Bool {
        if skipLocalCoachForNextTurn { return false }
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return false }
        guard MangoxFoundationModelsSupport.isPrivateCloudComputeCoachAvailable else { return false }
        guard MangoxFoundationModelsSupport.privateCloudComputeSupportsCurrentLocale() else { return false }
        if OnDeviceCoachEngine.heuristicPrefersPCCWebSearch(for: text),
            !Self.isPCCLiveWebSearchAvailable
        {
            return false
        }
        if forcePlanIntake || planIntakeModeActive { return true }
        if OnDeviceCoachEngine.heuristicPrefersPCCCoach(for: text) { return true }
        if !OnDeviceCoachEngine.heuristicCloudRoute(for: text) { return true }
        return false
    }

    private func qualifiesForUnbilledOnDeviceNarrow(_ text: String) -> Bool {
        if skipLocalCoachForNextTurn { return false }
        if OnDeviceCoachEngine.heuristicCloudRoute(for: text) { return false }
        if OnDeviceCoachEngine.passesOnDeviceNarrowHeuristics(for: text) { return true }
        if OnDeviceCoachEngine.heuristicLocalPreferred(for: text), text.count <= 220 { return true }
        return false
    }

    private func incrementDailyCount() {
        if Self.bypassesDailyCoachMessageLimit { return }
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

    /// REST base for `/api/generate-plan` etc. Matches Mangox Cloud provider URL from Settings; falls back to Info.plist or production when using OpenAI-compatible chat only.
    private var apiBaseURL: String {
        let cfg = ChatProviderResolver().resolve()
        if !cfg.baseURL.isEmpty {
            return MangoxBackendBaseURLFormatting.normalizedRoot(cfg.baseURL)
        }
        let raw =
            Bundle.main.object(forInfoDictionaryKey: "MangoxAPIBaseURL") as? String
            ?? MangoxBackendDefaults.productionBaseURL
        return MangoxBackendBaseURLFormatting.normalizedRoot(raw)
    }

    private var userID: String {
        if let existing = UserDefaults.standard.string(forKey: "user_device_id") {
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: "user_device_id")
        return new
    }

    /// AES-256-GCM key from build-time `UserDataKey` Info.plist var (populated via USER_DATA_KEY in xcconfig).
    /// When present, all rich user context (FTP, recent workouts, plans, etc.) sent to the Mangox cloud coach
    /// is encrypted before leaving the device. When nil we fall back to plaintext (only acceptable in DEBUG).
    private var encryptionKey: SymmetricKey? {
        guard let b64 = Bundle.main.object(forInfoDictionaryKey: "UserDataKey") as? String,
            !b64.isEmpty,
            let keyData = Data(base64Encoded: b64),
            keyData.count == 32
        else { return nil }
        return SymmetricKey(data: keyData)
    }

    /// Publicly observable: does this build have a valid encryption key for coach context?
    /// Exposed so Settings/Diagnostics can surface the state and so we can enforce policy.
    var hasValidCoachEncryptionKey: Bool {
        encryptionKey != nil
    }

    /// Encrypts `context` as AES-256-GCM and returns base64(nonce ‖ ciphertext ‖ tag).
    /// Returns nil if the key is not configured or encryption fails.
    private func encryptUserContext(_ context: UserContext) -> String? {
        guard let key = encryptionKey,
            let json = try? JSONEncoder().encode(context)
        else { return nil }
        guard let sealed = try? AES.GCM.seal(json, using: key),
            let combined = sealed.combined
        else { return nil }
        return combined.base64EncodedString()
    }

    // MARK: - Streaming display (debounced)

    private static let streamDisplayThrottleMs: Int = 50

    private func scheduleStreamDraftDisplayFlush() {
        streamDisplayThrottleTask?.cancel()
        streamDisplayThrottleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Self.streamDisplayThrottleMs))
            guard !Task.isCancelled else { return }
            applyStreamDraftToUI()
        }
    }

    private func applyStreamDraftToUI() {
        let snap = CoachThinkingTagParser.snapshot(streamBuffer: streamRawBuffer)
        streamDraftText = snap.visible
        streamIsThinking =
            snap.visible.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (snap.openDraft != nil || streamStatusText != nil)
    }

    private func flushStreamDraftToUI() {
        streamDisplayThrottleTask?.cancel()
        streamDisplayThrottleTask = nil
        applyStreamDraftToUI()
    }

    private func applyFMStreamPartial(
        body: String,
        partialTags: [String]?,
        partialCategory: String?,
        planIntake: Bool,
        usedWebSearch: Bool
    ) {
        streamRawBuffer = body
        streamUsesTokenDeltas = false
        streamPartialTags = CoachReplyMetadataSupport.resolvedTags(
            modelTags: partialTags ?? [],
            modelCategory: partialCategory,
            body: body,
            usedWebSearch: usedWebSearch,
            planIntake: planIntake
        )
        streamStatusText = nil
        streamIsThinking = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        scheduleStreamDraftDisplayFlush()
    }

    private func resetStreamingState(clearLoading: Bool) {
        streamDraftText = ""
        streamRawBuffer = ""
        streamDisplayThrottleTask?.cancel()
        streamDisplayThrottleTask = nil
        streamStatusText = nil
        streamIsThinking = false
        streamIsSearchingWeb = false
        streamDelivery = .cloud
        streamPartialTags = []
        streamRouteStatus = nil
        streamUsesTokenDeltas = false
        if clearLoading {
            isLoading = false
        }
    }

    /// Flush the last streamed frame, commit, clear pending UI, then haptic/VO.
    private func finishCoachReply(_ message: ChatMessage, modelContext: ModelContext) {
        flushStreamDraftToUI()
        commitAssistantMessage(message, modelContext: modelContext, notify: false)
        resetStreamingState(clearLoading: true)
        notifyAssistantMessageArrived(message)
        recordBillableCoachTurnIfNeeded(for: message)
        let path = CoachDeliveryPath.fromMessageCategory(message.category)
        PrecisionCoachInstrumentation.coachReplyDelivered(
            path: path.instrumentationLabel,
            category: message.category,
            charCount: message.content.count
        )
        lastFailedDeliveryPath = nil
    }

    private func recordBillableCoachTurnIfNeeded(for message: ChatMessage) {
        guard message.role == .assistant else { return }
        guard message.category != "error" else { return }
        let path = CoachDeliveryPath.fromMessageCategory(message.category)
        guard path == .mangoxCloudBackend else { return }
        incrementDailyCount()
    }

    private func logRoutingFallback(from: CoachDeliveryPath, to: CoachDeliveryPath, reason: String) {
        logCoachFlow("coachFlow fallback \(from.rawValue)→\(to.rawValue) reason=\(reason)")
        PrecisionCoachInstrumentation.coachRoutingFallback(
            from: from.instrumentationLabel,
            to: to.instrumentationLabel,
            reason: reason
        )
    }

    /// Flips loading + pending bubble immediately so chip/starter taps feel instant (before async work).
    @discardableResult
    func prepareOutgoingMessage(
        _ text: String,
        isPro: Bool,
        forcePlanIntake: Bool = false,
        hasImage: Bool = false
    ) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || hasImage else { return false }
        guard canSendCoachMessage(trimmed, isPro: isPro, forcePlanIntake: forcePlanIntake, hasImage: hasImage)
        else {
            return false
        }
        guard !isLoading else { return false }
        isLoading = true
        error = nil
        resetStreamingState(clearLoading: false)
        streamDelivery = .onDevice
        return true
    }

    private func cancelActiveChatTurnIfNeeded() {
        activeChatTurnTask?.cancel()
        activeChatTurnTask = nil
        activeChatTurnGeneration &+= 1
        resetStreamingState(clearLoading: true)
    }

    func cancelActiveChatTurn() {
        cancelActiveChatTurnIfNeeded()
    }

    // MARK: - Mangox Cloud coach turn (no new user row)

    private func runMangoxCloudCoachTurn(
        userText: String,
        isPro: Bool,
        forcePlanIntake: Bool,
        modelContext: ModelContext,
        deliveryCategoryOverride: String? = nil
    ) async {
        let history = buildHistory()
        let context = cachedUserContext(modelContext: modelContext)
        let encryptedContext = encryptUserContext(context)

        // Strong release guard: never send rich training context (FTP, recent workouts, plans, etc.)
        // in plaintext to the cloud coach from a production build.
        #if !DEBUG
        if encryptedContext == nil {
            logger.critical("USER_DATA_KEY missing or invalid in RELEASE build — refusing to send unencrypted UserContext to cloud coach.")
            appendAssistantErrorBubble(
                "Coach cloud security is not configured for this build. Falling back to on-device only.",
                category: "error",
                modelContext: modelContext
            )
            self.error = "Coach context encryption key not configured"
            resetStreamingState(clearLoading: true)
            return
        }
        #endif

        let request = ChatRequest(
            message: userText,
            history: history,
            user_context: encryptedContext == nil ? context : nil,
            user_context_encrypted: encryptedContext,
            is_pro: isPro,
            client_local_date: Self.dateFormatter.string(from: .now),
            client_time_zone: TimeZone.current.identifier,
            force_plan_intake: forcePlanIntake ? true : nil
        )

        let provider = ChatProviderResolver().resolve()
        let adapter = ChatProviderFactory.makeAdapter(for: provider.kind)

        logCoachFlow(
            "coachFlow cloud runMangoxCloudCoachTurn begin provider=\(provider.kind.rawValue) historyTurns=\(history.count) userChars=\(userText.count)"
        )

        streamDelivery = .cloud
        streamUsesTokenDeltas = true
        streamRouteStatus = nil

        do {
            var finalResponse: ChatAPIResponse?
            var streamFailure: String?

            for try await event in adapter.streamChat(
                request: request, configuration: provider, userID: userID)
            {
                switch event {
                case .status(let s):
                    streamStatusText = s
                    streamIsSearchingWeb = s.localizedCaseInsensitiveContains("search")
                case .textDelta(let delta):
                    streamRawBuffer += delta
                    streamStatusText = nil
                    streamRouteStatus = nil
                    streamIsThinking = false
                    streamIsSearchingWeb = false
                    streamUsesTokenDeltas = true
                    scheduleStreamDraftDisplayFlush()
                case .reasoningDelta:
                    streamIsThinking = true
                    if streamDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        streamStatusText = "Thinking…"
                    }
                case .toolCalls:
                    break
                case .completed(let message):
                    finalResponse = message
                case .failed(let err):
                    streamFailure = err
                }
            }

            if let streamFailure {
                resetStreamingState(clearLoading: true)
                appendAssistantErrorBubble(
                    streamFailure,
                    category: "error",
                    modelContext: modelContext,
                    failedPath: .mangoxCloudBackend,
                    retryActions: Self.coachErrorRetryActions
                )
                self.error = streamFailure
                logCoachFlow("coachFlow cloud end streamFailure assistantErrorBubble")
                return
            }

            guard let response = finalResponse else {
                resetStreamingState(clearLoading: true)
                appendAssistantErrorBubble(
                    "The coach didn't return a complete reply. Please try again.",
                    category: "error",
                    modelContext: modelContext,
                    failedPath: .mangoxCloudBackend,
                    retryActions: Self.coachErrorRetryActions
                )
                self.error = "Empty response"
                logCoachFlow("coachFlow cloud end emptyFinalResponse")
                return
            }

            var (cleanContent, parsedThinkingBlocks) = CoachThinkingTagParser.finalizedContent(
                response.content)

            let usedWebSearch = Self.resolvedUsedWebSearch(response)
            if usedWebSearch, CoachReplyMetadataSupport.isWebSearchDeferralOnly(cleanContent) {
                cleanContent = """
                    I couldn't pull a complete answer from live web sources for that query. \
                    Try rephrasing with a specific site or event name, or open the links below if any were found.
                    """
            }

            let blocks = Self.sanitizedFollowUpBlocks(response.followUpBlocks)
            var panelActions: [SuggestedAction]
            var panelFollowUp: String?
            if blocks.isEmpty {
                panelActions = Self.sanitizedSuggestedActions(response.suggestedActions)
                let rawFollow = response.followUpQuestion
                if let raw = rawFollow,
                    Self.isFollowUpRedundantWithBody(followUp: raw, body: cleanContent)
                {
                    panelFollowUp = nil
                } else {
                    panelFollowUp = rawFollow
                }
            } else {
                panelActions = []
                panelFollowUp = nil
            }

            let isWebResearchTurn =
                usedWebSearch || deliveryCategoryOverride == "pcc_web_search"
            if blocks.isEmpty,
                !isWebResearchTurn,
                Self.nonEmptyTrimmed(panelFollowUp) == nil,
                panelActions.isEmpty,
                Self.shouldOfferClarificationRecovery(category: response.category, content: cleanContent)
            {
                panelActions = Self.planIntakeClarificationChips()
                if let q = Self.tightClarificationQuestion(
                    category: response.category, content: cleanContent),
                    !Self.isFollowUpRedundantWithBody(followUp: q, body: cleanContent)
                {
                    panelFollowUp = q
                }
            }

            if isWebResearchTurn {
                let sanitized = Self.sanitizeFollowUpForWebResearch(
                    followUp: panelFollowUp,
                    actions: panelActions,
                    planIntakeActive: forcePlanIntake || planIntakeModeActive
                )
                panelFollowUp = sanitized.followUp
                panelActions = sanitized.actions
            }

            // Use server-supplied thinkingSteps when present.
            // Otherwise capture <redacted_thinking> blocks parsed from content.
            let thinkingSource =
                response.thinkingSteps.isEmpty ? parsedThinkingBlocks : response.thinkingSteps

            let aiMsg = ChatMessage(
                id: UUID(),
                role: .assistant,
                content: cleanContent,
                timestamp: .now,
                suggestedActions: panelActions,
                followUpQuestion: panelFollowUp,
                followUpBlocks: blocks,
                thinkingSteps: Self.cappedThinkingSteps(thinkingSource),
                category: deliveryCategoryOverride ?? response.category,
                tags: response.tags,
                references: response.references,
                usedWebSearch: usedWebSearch,
                feedbackScore: nil,
                confidence: response.confidence,
                imageJPEG: nil
            )
            finishCoachReply(aiMsg, modelContext: modelContext)

            syncPlanIntakeMode(
                userText: userText,
                forcePlanIntake: forcePlanIntake,
                response: response,
                blocks: blocks,
                panelFollowUp: panelFollowUp,
                usedWebSearch: usedWebSearch
            )

            logCoachFlow(
                "coachFlow cloud success category=\(response.category) suggestedActions=\(panelActions.count) followUpBlocks=\(blocks.count)"
            )

            await executePendingGeneratePlanToolIfNeeded(from: response, modelContext: modelContext)
            await executePendingGenerateWorkoutToolIfNeeded(
                from: response,
                isPro: isPro,
                modelContext: modelContext
            )
        } catch is CancellationError {
            logCoachFlow("coachFlow cloud cancelled")
            resetStreamingState(clearLoading: true)
        } catch {
            logger.error("runMangoxCloudCoachTurn failed: \(error)")
            logCoachFlow("coachFlow cloud catch transportOrDecodeError")
            resetStreamingState(clearLoading: true)
            appendAssistantErrorBubble(
                Self.cloudCoachErrorMessage(for: error, webSearch: activeTurnIsWebSearch),
                category: "error",
                modelContext: modelContext,
                failedPath: .mangoxCloudBackend,
                retryActions: Self.coachErrorRetryActions
            )
            self.error = error.localizedDescription
        }
    }

    private static let coachErrorRetryActions: [SuggestedAction] = [
        SuggestedAction(label: "Try again", type: "retry"),
        SuggestedAction(label: "Retry on cloud server", type: "escalate_cloud"),
    ]

    private static func cloudCoachErrorMessage(for error: Error, webSearch: Bool) -> String {
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            if webSearch {
                return
                    "Web search needs an internet connection. Try again when you're back online, or ask a stats question I can answer on-device."
            }
            return
                "You're offline. Connect to reach the coach server, or ask a short stats question I can answer on-device."
        }
        return "I couldn't connect to the coaching server. Check your connection and try again."
    }

    /// Persist-first commit: write to disk, then append to the in-memory array. Keeps
    /// the visible transcript in lock-step with what `loadPersistedMessages()` would
    /// rehydrate, eliminating "the message was there a second ago" disappearances.
    private func commitAssistantMessage(
        _ message: ChatMessage,
        modelContext: ModelContext,
        notify: Bool = true
    ) {
        do {
            try persistCoachMessage(message, modelContext: modelContext)
            messages.append(message)
        } catch {
            logger.error("commitAssistantMessage persist failed: \(error)")
            self.error = "Couldn't save coach reply: \(error.localizedDescription)"
            // Still surface the reply this session so the user isn't stuck in silence.
            messages.append(message)
        }
        if notify {
            notifyAssistantMessageArrived(message)
        }
    }

    private func notifyAssistantMessageArrived(_ message: ChatMessage) {
        // Skip silent ack on error bubbles — the banner above the input bar already
        // tells the user (and via VoiceOver) that something failed.
        guard message.category != "error" else { return }
        HapticManager.shared.coachReplyReceived()
        let summary = String(message.content.prefix(140))
        UIAccessibility.post(notification: .announcement, argument: "Coach replied. \(summary)")
    }

    private func appendAssistantErrorBubble(
        _ text: String,
        category: String,
        modelContext: ModelContext,
        failedPath: CoachDeliveryPath? = nil,
        retryActions: [SuggestedAction] = []
    ) {
        lastFailedDeliveryPath = failedPath
        let errMsg = ChatMessage(
            id: UUID(),
            role: .assistant,
            content: text,
            timestamp: .now,
            suggestedActions: retryActions,
            followUpQuestion: nil,
            followUpBlocks: [],
            thinkingSteps: [],
            category: category,
            tags: failedPath.map { [$0.rawValue] } ?? [],
            references: [],
            usedWebSearch: false,
            feedbackScore: nil,
            confidence: 0,
            imageJPEG: nil
        )
        commitAssistantMessage(errMsg, modelContext: modelContext)
    }

    private func bumpSessionUpdatedAt(modelContext: ModelContext) {
        guard let sessionID = currentSessionID else { return }
        let descriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate<ChatSession> { $0.id == sessionID }
        )
        if let sessions = try? modelContext.fetch(descriptor), let session = sessions.first {
            session.updatedAt = .now
            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to bump session timestamp: \(error)")
            }
        }
    }

    private func removeCoachMessage(id: UUID, modelContext: ModelContext) {
        messages.removeAll { $0.id == id }
        let descriptor = FetchDescriptor<CoachChatMessage>(
            predicate: #Predicate<CoachChatMessage> { $0.id == id }
        )
        if let rows = try? modelContext.fetch(descriptor) {
            for row in rows {
                modelContext.delete(row)
            }
            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to delete coach message: \(error)")
            }
        }
        bumpSessionUpdatedAt(modelContext: modelContext)
    }

    // MARK: - Send Chat Message

    func sendMessage(
        _ text: String,
        isPro: Bool,
        forcePlanIntake: Bool = false,
        image: CoachUserImageAttachment? = nil,
        modelContext: ModelContext
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let planIntake = forcePlanIntake || planIntakeModeActive || Self.shouldForcePlanIntake(for: trimmed)
        let alreadyPrepared = isLoading
        let hasImage = image != nil

        if planIntake {
            planIntakeModeActive = true
        }

        guard !trimmed.isEmpty || hasImage else {
            logCoachFlow("coachFlow sendMessage abort reason=empty")
            if alreadyPrepared { resetStreamingState(clearLoading: true) }
            return
        }
        guard canSendCoachMessage(trimmed, isPro: isPro, forcePlanIntake: planIntake, hasImage: hasImage)
        else {
            logCoachFlow("coachFlow sendMessage abort reason=dailyLimit isPro=\(isPro)")
            if alreadyPrepared { resetStreamingState(clearLoading: true) }
            return
        }
        if !alreadyPrepared {
            guard !isLoading else {
                logCoachFlow("coachFlow sendMessage abort reason=alreadyLoading")
                return
            }
            isLoading = true
            error = nil
            resetStreamingState(clearLoading: false)
        }

        let sessionBefore = currentSessionID
        let deliveryLogLabel = planIntake ? "cloudPlanIntake" : "cloudOnly"

        logCoachFlow(
            "coachFlow sendMessage start delivery=\(deliveryLogLabel) isPro=\(isPro) chars=\(trimmed.count) session=\(sessionBefore?.uuidString ?? "nil")"
        )

        activeTurnIsWebSearch = OnDeviceCoachEngine.heuristicPrefersPCCWebSearch(for: trimmed)

        // Auto-create a session if none exists
        if currentSessionID == nil {
            createNewSession(modelContext: modelContext, cancelInFlightTurn: false)
            logCoachFlow(
                "coachFlow sendMessage createdSession id=\(currentSessionID?.uuidString ?? "?")"
            )
        }

        let userMsg = ChatMessage.user(trimmed, imageJPEG: image?.jpegData)
        do {
            try persistCoachMessage(userMsg, modelContext: modelContext)
            messages.append(userMsg)
        } catch {
            logger.error("sendMessage user persist failed: \(error)")
            self.error = "Couldn't save your message: \(error.localizedDescription)"
            // Still show it locally so the user sees what they typed.
            messages.append(userMsg)
        }

        // Update session title from first user message
        updateSessionTitleIfNeeded(modelContext: modelContext)

        if !alreadyPrepared {
            error = nil
            resetStreamingState(clearLoading: false)
        } else {
            error = nil
        }

        if !alreadyPrepared {
            streamDelivery = planIntake ? .planIntake : .onDevice
        }

        await Task.yield()

        activeChatTurnTask?.cancel()
        activeChatTurnGeneration &+= 1
        let turnGeneration = activeChatTurnGeneration
        let turnTask = Task {
            defer {
                if activeChatTurnGeneration == turnGeneration {
                    activeChatTurnTask = nil
                }
            }
            await Task.yield()
            if !planIntake, !skipLocalCoachForNextTurn, !hasImage,
                await tryOnDeviceNarrowTurn(
                    userText: trimmed,
                    modelContext: modelContext
                )
            {
                logCoachFlow("coachFlow sendMessage path=onDeviceNarrow")
                skipLocalCoachForNextTurn = false
                return
            }

            let webSearchTurn = activeTurnIsWebSearch && !hasImage

            // PCC cannot ground live web until Apple's webSearch extension ships — use Mangox Cloud.
            if webSearchTurn, !Self.isPCCLiveWebSearchAvailable {
                if !skipLocalCoachForNextTurn {
                    logRoutingFallback(
                        from: .privateCloudCompute,
                        to: .mangoxCloudBackend,
                        reason: "pcc_web_unavailable"
                    )
                }
                streamDelivery = .webSearch
                streamIsSearchingWeb = true
                streamStatusText = "Searching the web…"
                streamRouteStatus = nil
                streamUsesTokenDeltas = true
                logCoachFlow("coachFlow sendMessage path=mangoxCloudWebSearch")
                await runMangoxCloudCoachTurn(
                    userText: trimmed,
                    isPro: isPro,
                    forcePlanIntake: planIntake,
                    modelContext: modelContext,
                    deliveryCategoryOverride: "pcc_web_search"
                )
                skipLocalCoachForNextTurn = false
                return
            }

            if skipLocalCoachForNextTurn {
                streamRouteStatus = "Connecting to coach server…"
                streamDelivery = .cloud
                streamUsesTokenDeltas = true
                streamPartialTags = []
                logCoachFlow("coachFlow sendMessage path=mangoxCloudForcedRetry")
                await runMangoxCloudCoachTurn(
                    userText: trimmed,
                    isPro: isPro,
                    forcePlanIntake: planIntake,
                    modelContext: modelContext
                )
                skipLocalCoachForNextTurn = false
                return
            }

            if MangoxFoundationModelsSupport.isPrivateCloudComputeCoachAvailable,
                let quotaMessage = MangoxPCCSupport.coachTurnQuotaBlockMessage()
            {
                logCoachFlow("coachFlow sendMessage path=pccQuotaBlocked")
                self.error = quotaMessage
                appendAssistantErrorBubble(
                    quotaMessage,
                    category: "error",
                    modelContext: modelContext,
                    failedPath: .privateCloudCompute
                )
                resetStreamingState(clearLoading: true)
                if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
                    PrivateCloudComputeLanguageModel().quotaUsage.limitIncreaseSuggestion?.show()
                }
                skipLocalCoachForNextTurn = false
                return
            }

            streamRouteStatus = planIntake
                ? "Designing on Private Cloud…"
                : "Trying Private Cloud…"
            streamDelivery = CoachStreamDelivery.forPCCTurn(
                planIntake: planIntake,
                webSearch: webSearchTurn
            )
            streamIsSearchingWeb = webSearchTurn
            if webSearchTurn {
                streamStatusText = "Searching the web…"
            }

            if await tryPrivateCloudComputeCoachTurn(
                userText: trimmed,
                planIntake: planIntake,
                image: image,
                modelContext: modelContext
            ) {
                logCoachFlow("coachFlow sendMessage path=privateCloudCompute")
                skipLocalCoachForNextTurn = false
                return
            }

            if await tryThirdPartyLanguageModelCoachTurn(
                userText: trimmed,
                planIntake: planIntake,
                image: image,
                modelContext: modelContext
            ) {
                logCoachFlow("coachFlow sendMessage path=thirdPartyLanguageModel")
                skipLocalCoachForNextTurn = false
                return
            }

            if !planIntake, !webSearchTurn {
                logRoutingFallback(
                    from: .privateCloudCompute,
                    to: .mangoxCloudBackend,
                    reason: "pcc_and_third_party_miss"
                )
            } else if !webSearchTurn {
                logRoutingFallback(
                    from: .privateCloudCompute,
                    to: .mangoxCloudBackend,
                    reason: "pcc_miss"
                )
            }

            if hasImage {
                logCoachFlow("coachFlow sendMessage abort reason=imageRequiresLocalModel")
                appendAssistantErrorBubble(
                    "Photo questions need Private Cloud Compute or a configured fallback model in Settings → AI Coach.",
                    category: "error",
                    modelContext: modelContext
                )
                skipLocalCoachForNextTurn = false
                return
            }

            streamRouteStatus = "Connecting to coach server…"
            streamDelivery = .cloud
            streamUsesTokenDeltas = true
            streamPartialTags = []
            logCoachFlow("coachFlow sendMessage path=mangoxCloudFallback")
            await runMangoxCloudCoachTurn(
                userText: trimmed,
                isPro: isPro,
                forcePlanIntake: planIntake,
                modelContext: modelContext
            )
            skipLocalCoachForNextTurn = false
        }
        activeChatTurnTask = turnTask
    }

    // MARK: - On-device narrow routing

    private func resetNarrowCoachLanguageSession() {
        narrowCoachLanguageSession = nil
        narrowCoachSessionOwnerID = nil
    }

    private func resetPCCCoachLanguageSession() {
        pccCoachLanguageSession = nil
        pccCoachSessionOwnerID = nil
        pccCoachSessionModeRaw = nil
        thirdPartyCoachLanguageSession = nil
        thirdPartyCoachSessionOwnerID = nil
    }

    private func resetCoachLanguageSessions() {
        resetNarrowCoachLanguageSession()
        resetPCCCoachLanguageSession()
    }

    /// Releases coach chat FM/PCC sessions so plan generation can open its own session.
    private func prepareForPlanGeneration() {
        activeChatTurnTask?.cancel()
        activeChatTurnTask = nil
        resetCoachLanguageSessions()
    }

    private func coachOnDeviceTools(digests: CoachOnDeviceToolDigestBundle) -> [any Tool] {
        var tools: [any Tool] = [
            MangoxOnDeviceRecentWorkoutsTool(digest: digests.recentWorkouts),
            MangoxOnDeviceRiderExtendedTool(digest: digests.riderExtended),
            MangoxOnDeviceFTPHistoryTool(digest: digests.ftpHistory),
            MangoxOnDeviceWhoopRecoveryTool(digest: digests.whoopRecovery),
            MangoxOnDeviceActivePlanTool(digest: digests.activePlan),
            MangoxOnDeviceDecouplingTrendTool(digest: digests.decouplingTrend),
            MangoxOnDevicePowerCurveSummaryTool(digest: digests.powerCurveSummary),
            MangoxOnDeviceCriticalPowerTool(digest: digests.criticalPower),
            MangoxOnDevicePlanForwardSimTool(dailyTSSFromPlan: digests.planForwardDailyTSS),
            MangoxOnDevicePMCProjectionTool(),
        ]
        tools.append(MangoxCoachSpotlightToolFactory.makeSpotlightSearchTool())
        return tools
    }

    /// Reuses the narrow `LanguageModelSession` for the active chat session; creates on first turn.
    private func narrowCoachSession(digests: CoachOnDeviceToolDigestBundle) -> LanguageModelSession {
        if let session = narrowCoachLanguageSession,
            narrowCoachSessionOwnerID == currentSessionID
        {
            return session
        }
        let session = OnDeviceCoachEngine.makeNarrowSession(
            tools: coachOnDeviceTools(digests: digests)
        )
        narrowCoachLanguageSession = session
        narrowCoachSessionOwnerID = currentSessionID
        return session
    }

    /// Heuristic fast path, then on-device `classifyRoute` for ambiguous messages.
    private func shouldUseOnDeviceNarrowPath(
        userText: String,
        modelContext: ModelContext
    ) async -> Bool {
        guard OnDeviceCoachEngine.isOnDeviceWritingModelAvailable else { return false }
        if OnDeviceCoachEngine.heuristicCloudRoute(for: userText) { return false }
        if OnDeviceCoachEngine.passesOnDeviceNarrowHeuristics(for: userText) { return true }

        do {
            let factSheet = coachFactSheetTextCompact(modelContext: modelContext)
            let route = try await OnDeviceCoachEngine.classifyRoute(
                userMessage: userText,
                factSheet: factSheet
            )
            logCoachFlow("coachFlow classifyRoute route=\(route.rawValue)")
            switch route {
            case .localNarrowReply: return true
            case .pccCoach, .cloudCoach: return false
            }
        } catch {
            logger.debug("classifyRoute failed, falling back to cloud: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private Cloud Compute coach

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    private func pccCoachSession(
        mode: CoachAgentMode,
        digests: CoachOnDeviceToolDigestBundle
    ) -> LanguageModelSession {
        if let session = pccCoachLanguageSession,
            pccCoachSessionOwnerID == currentSessionID,
            pccCoachSessionModeRaw == mode.rawStorageKey
        {
            return session
        }
        let tools = coachOnDeviceTools(digests: digests)
        let history: [Transcript.Entry] =
            pccCoachLanguageSession.map { Array($0.transcript) } ?? []
        let session = OnDeviceCoachEngine.makePCCCoachSession(
            mode: mode,
            tools: tools,
            history: history
        )
        pccCoachLanguageSession = session
        pccCoachSessionOwnerID = currentSessionID
        pccCoachSessionModeRaw = mode.rawStorageKey
        return session
    }

    /// PCC path for plan intake and deep coaching. Returns `false` to fall back to Mangox cloud.
    private func tryPrivateCloudComputeCoachTurn(
        userText: String,
        planIntake: Bool,
        image: CoachUserImageAttachment? = nil,
        modelContext: ModelContext
    ) async -> Bool {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return false }
        guard MangoxFoundationModelsSupport.isPrivateCloudComputeCoachAvailable else { return false }
        guard PrivateCloudComputeLanguageModel().supportsLocale(Locale.current) else { return false }

        let mode = CoachAgentMode.detect(userMessage: userText, planIntake: planIntake)
        let webSearchTurn = mode.enablesPCCWebSearch
        if webSearchTurn, !Self.isPCCLiveWebSearchAvailable {
            logCoachFlow("coachFlow pcc skip webSearch -> cloud fallback")
            return false
        }
        let digests = await preparedOnDeviceToolDigests(modelContext: modelContext)
        let snapshot = await coachTrainingSnapshotForCoachTurn(
            modelContext: modelContext,
            usePrivateCloudCompute: true
        )
        let session = pccCoachSession(mode: mode, digests: digests)

        do {
            let final = try await OnDeviceCoachEngine.signpostOnDeviceNarrow {
                try await OnDeviceCoachEngine.streamPCCCoachReply(
                    userMessage: userText,
                    trainingSnapshot: snapshot,
                    planIntake: planIntake,
                    session: session,
                    image: image
                ) { partial in
                    let body = partial.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    self.streamDelivery = CoachStreamDelivery.forPCCTurn(
                        planIntake: planIntake,
                        webSearch: webSearchTurn
                    )
                    self.streamIsSearchingWeb = webSearchTurn
                    if webSearchTurn, body.isEmpty {
                        self.streamStatusText = "Searching the web…"
                    }
                    self.applyFMStreamPartial(
                        body: body,
                        partialTags: partial.tags,
                        partialCategory: partial.category,
                        planIntake: planIntake,
                        usedWebSearch: webSearchTurn
                    )
                }
            }

            guard let reply = final, !reply.body.isEmpty else {
                logCoachFlow("coachFlow pcc empty -> fallback cloud")
                return false
            }

            if webSearchTurn, CoachReplyMetadataSupport.isWebSearchDeferralOnly(reply.body) {
                logCoachFlow("coachFlow pcc webSearch deferralOnly -> fallback cloud")
                return false
            }

            let actions = reply.suggestedActions
                .map { SuggestedAction(label: $0.label, type: "follow_up") }
                .prefix(4)
                .map { $0 }
            let followUp = reply.followUp.trimmingCharacters(in: .whitespacesAndNewlines)
            let references = webSearchTurn
                ? MangoxCoachTranscriptSearchSupport.referencesFromTranscript(session)
                : []
            let usedWebSearch = webSearchTurn
                && !CoachReplyMetadataSupport.isWebSearchDeferralOnly(reply.body)
                && (!references.isEmpty
                    || MangoxCoachTranscriptSearchSupport.transcriptIndicatesWebSearch(session))
            let deliveryCategory =
                planIntake ? "plan_intake" : (webSearchTurn ? "pcc_web_search" : "pcc_coach")
            let tags = CoachReplyMetadataSupport.resolvedTags(
                modelTags: reply.tags,
                modelCategory: reply.category,
                body: reply.body,
                usedWebSearch: usedWebSearch,
                planIntake: planIntake
            )
            let aiMsg = ChatMessage(
                id: UUID(),
                role: .assistant,
                content: reply.body,
                timestamp: .now,
                suggestedActions: Self.sanitizedSuggestedActions(actions),
                followUpQuestion: followUp.isEmpty ? nil : followUp,
                followUpBlocks: [],
                thinkingSteps: CoachReplyMetadataSupport.thinkingSteps(from: reply.reasoning),
                category: deliveryCategory,
                tags: tags,
                references: references,
                usedWebSearch: usedWebSearch,
                feedbackScore: nil,
                confidence: 1.0,
                imageJPEG: nil
            )
            finishCoachReply(aiMsg, modelContext: modelContext)
            syncPlanIntakeMode(
                userText: userText,
                forcePlanIntake: planIntake,
                response: nil,
                blocks: [],
                panelFollowUp: followUp.isEmpty ? nil : followUp,
                usedWebSearch: usedWebSearch
            )
            stagePlanConfirmationFromLocalIntakeIfReady(
                planIntake: planIntake,
                body: reply.body,
                followUp: followUp,
                suggestedActions: Array(actions),
                category: deliveryCategory,
                followUpBlocksCount: 0
            )
            logCoachFlow("coachFlow pcc success chars=\(reply.body.count) mode=\(mode) webSearch=\(usedWebSearch)")
            return true
        } catch {
            logger.error("PCC coach turn failed: \(error)")
            if MangoxPCCSupport.isQuotaLimitReached(error) {
                let message = MangoxPCCSupport.userFacingMessage(for: error)
                    ?? "Private Cloud daily limit reached."
                self.error = message
                appendAssistantErrorBubble(
                    message,
                    category: "error",
                    modelContext: modelContext,
                    failedPath: .privateCloudCompute
                )
                resetStreamingState(clearLoading: true)
                MangoxPCCSupport.presentQuotaLimitIncreaseIfAvailable(from: error)
                logCoachFlow("coachFlow pcc quotaLimitReached")
                return true
            }
            if MangoxPCCSupport.isNetworkFailure(error) {
                logCoachFlow("coachFlow pcc networkFailure -> onDevice retry")
                if await tryOnDeviceCoachDegradedTurn(
                    userText: userText,
                    planIntake: planIntake,
                    image: image,
                    modelContext: modelContext
                ) {
                    return true
                }
            }
            logCoachFlow("coachFlow pcc error -> fallback cloud")
            return false
        }
    }

    /// On-device retry after PCC network failure (Apple's recommended fallback).
    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    private func tryOnDeviceCoachDegradedTurn(
        userText: String,
        planIntake: Bool,
        image: CoachUserImageAttachment?,
        modelContext: ModelContext
    ) async -> Bool {
        guard OnDeviceCoachEngine.isOnDeviceWritingModelAvailable else { return false }

        let digests = await preparedOnDeviceToolDigests(modelContext: modelContext)
        let snapshot = await coachTrainingSnapshotForCoachTurn(
            modelContext: modelContext,
            usePrivateCloudCompute: false
        )
        let session = narrowCoachSession(digests: digests)
        streamDelivery = planIntake ? .planIntake : .onDevice
        streamRouteStatus = "Using on-device Apple Intelligence…"
        streamIsSearchingWeb = false

        do {
            let final = try await OnDeviceCoachEngine.signpostOnDeviceNarrow {
                try await OnDeviceCoachEngine.streamGuidedCoachReply(
                    userMessage: userText,
                    trainingSnapshot: snapshot,
                    session: session,
                    image: image,
                    logLabel: "coach_pcc_network_fallback"
                ) { partial in
                    let body = partial.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    self.streamDelivery = planIntake ? .planIntake : .onDevice
                    self.applyFMStreamPartial(
                        body: body,
                        partialTags: partial.tags,
                        partialCategory: partial.category,
                        planIntake: planIntake,
                        usedWebSearch: false
                    )
                }
            }

            guard let reply = final, !reply.body.isEmpty else {
                logCoachFlow("coachFlow pccNetworkFallback empty -> fallback cloud")
                return false
            }

            let actions = reply.suggestedActions
                .map { SuggestedAction(label: $0.label, type: "follow_up") }
                .prefix(4)
                .map { $0 }
            let followUp = reply.followUp.trimmingCharacters(in: .whitespacesAndNewlines)
            let tags = CoachReplyMetadataSupport.resolvedTags(
                modelTags: reply.tags,
                modelCategory: reply.category,
                body: reply.body,
                usedWebSearch: false,
                planIntake: planIntake
            )
            let aiMsg = ChatMessage(
                id: UUID(),
                role: .assistant,
                content: reply.body,
                timestamp: .now,
                suggestedActions: Self.sanitizedSuggestedActions(actions),
                followUpQuestion: followUp.isEmpty ? nil : followUp,
                followUpBlocks: [],
                thinkingSteps: CoachReplyMetadataSupport.thinkingSteps(from: reply.reasoning),
                category: planIntake ? "plan_intake" : "on_device",
                tags: tags,
                references: [],
                usedWebSearch: false,
                feedbackScore: nil,
                confidence: 1.0,
                imageJPEG: nil
            )
            finishCoachReply(aiMsg, modelContext: modelContext)
            syncPlanIntakeMode(
                userText: userText,
                forcePlanIntake: planIntake,
                response: nil,
                blocks: [],
                panelFollowUp: followUp.isEmpty ? nil : followUp,
                usedWebSearch: false
            )
            stagePlanConfirmationFromLocalIntakeIfReady(
                planIntake: planIntake,
                body: reply.body,
                followUp: followUp,
                suggestedActions: Array(actions),
                category: planIntake ? "plan_intake" : "on_device",
                followUpBlocksCount: 0
            )
            logCoachFlow("coachFlow pccNetworkFallback success chars=\(reply.body.count)")
            return true
        } catch {
            logger.error("On-device fallback after PCC network failure failed: \(error)")
            logCoachFlow("coachFlow pccNetworkFallback error -> fallback cloud")
            return false
        }
    }

    /// Third-party `LanguageModel` path (Anthropic / Google SPM). Returns `false` when not configured.
    private func tryThirdPartyLanguageModelCoachTurn(
        userText: String,
        planIntake: Bool,
        image: CoachUserImageAttachment? = nil,
        modelContext: ModelContext
    ) async -> Bool {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return false }
        guard MangoxCoachLanguageModelProviderSupport.isThirdPartyFallbackConfigured else { return false }

        let digests = await preparedOnDeviceToolDigests(modelContext: modelContext)
        let snapshot = coachFactSheetText(modelContext: modelContext)
        let session = thirdPartyCoachSession(planIntake: planIntake, digests: digests)
        guard let session else {
            logCoachFlow("coachFlow thirdParty skip reason=packageOrKeyMissing")
            return false
        }

        streamDelivery = planIntake ? .planIntake : .onDevice
        streamRouteStatus = "Trying fallback model…"

        do {
            let final = try await OnDeviceCoachEngine.signpostOnDeviceNarrow {
                try await OnDeviceCoachEngine.streamGuidedCoachReply(
                    userMessage: userText,
                    trainingSnapshot: snapshot,
                    session: session,
                    image: image,
                    logLabel: "coach_third_party_stream"
                ) { partial in
                    let body = partial.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    self.streamDelivery = planIntake ? .planIntake : .onDevice
                    self.streamIsSearchingWeb = false
                    self.applyFMStreamPartial(
                        body: body,
                        partialTags: partial.tags,
                        partialCategory: partial.category,
                        planIntake: planIntake,
                        usedWebSearch: false
                    )
                }
            }

            guard let reply = final, !reply.body.isEmpty else {
                logCoachFlow("coachFlow thirdParty empty -> fallback")
                return false
            }

            let actions = reply.suggestedActions
                .map { SuggestedAction(label: $0.label, type: "follow_up") }
                .prefix(4)
                .map { $0 }
            let followUp = reply.followUp.trimmingCharacters(in: .whitespacesAndNewlines)
            let tags = CoachReplyMetadataSupport.resolvedTags(
                modelTags: reply.tags,
                modelCategory: reply.category,
                body: reply.body,
                usedWebSearch: false,
                planIntake: planIntake
            )
            let aiMsg = ChatMessage(
                id: UUID(),
                role: .assistant,
                content: reply.body,
                timestamp: .now,
                suggestedActions: Self.sanitizedSuggestedActions(actions),
                followUpQuestion: followUp.isEmpty ? nil : followUp,
                followUpBlocks: [],
                thinkingSteps: CoachReplyMetadataSupport.thinkingSteps(from: reply.reasoning),
                category: "third_party_coach",
                tags: tags,
                references: [],
                usedWebSearch: false,
                feedbackScore: nil,
                confidence: 1.0,
                imageJPEG: nil
            )
            finishCoachReply(aiMsg, modelContext: modelContext)
            syncPlanIntakeMode(
                userText: userText,
                forcePlanIntake: planIntake,
                response: nil,
                blocks: [],
                panelFollowUp: followUp.isEmpty ? nil : followUp,
                usedWebSearch: false
            )
            stagePlanConfirmationFromLocalIntakeIfReady(
                planIntake: planIntake,
                body: reply.body,
                followUp: followUp,
                suggestedActions: Array(actions),
                category: planIntake ? "plan_intake" : "third_party_coach",
                followUpBlocksCount: 0
            )
            logCoachFlow("coachFlow thirdParty success chars=\(reply.body.count)")
            return true
        } catch {
            logger.error("Third-party coach turn failed: \(error)")
            logCoachFlow("coachFlow thirdParty error -> fallback")
            return false
        }
    }

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    private func thirdPartyCoachSession(
        planIntake: Bool,
        digests: CoachOnDeviceToolDigestBundle
    ) -> LanguageModelSession? {
        if let session = thirdPartyCoachLanguageSession,
            thirdPartyCoachSessionOwnerID == currentSessionID
        {
            return session
        }
        let tools = coachOnDeviceTools(digests: digests)
        let history = pccCoachLanguageSession.map { Array($0.transcript) }
            ?? thirdPartyCoachLanguageSession.map { Array($0.transcript) }
            ?? []
        guard
            let session = MangoxCoachLanguageModelProviderSupport.makeThirdPartyCoachSession(
                planIntake: planIntake,
                tools: tools,
                history: history
            )
        else { return nil }
        thirdPartyCoachLanguageSession = session
        thirdPartyCoachSessionOwnerID = currentSessionID
        return session
    }

    /// Returns `true` when the on-device Foundation Models path produced a final assistant
    /// reply. Returns `false` to fall back to the cloud (model unavailable, locale unsupported,
    /// message looks heavy, on-device generation failed, or the reply was empty).
    private func tryOnDeviceNarrowTurn(
        userText: String,
        modelContext: ModelContext
    ) async -> Bool {
        guard await shouldUseOnDeviceNarrowPath(
            userText: userText,
            modelContext: modelContext
        ) else { return false }

        let digests = await preparedOnDeviceToolDigests(modelContext: modelContext)
        let snapshot = await coachTrainingSnapshotForOnDeviceNarrow(modelContext: modelContext)
        let session = narrowCoachSession(digests: digests)
        streamDelivery = .onDevice
        streamRouteStatus = nil

        do {
            let final = try await OnDeviceCoachEngine.signpostOnDeviceNarrow {
                try await OnDeviceCoachEngine.streamNarrowReply(
                    userMessage: userText,
                    trainingSnapshot: snapshot,
                    session: session
                ) { partial in
                    let body = partial.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    self.streamDelivery = .onDevice
                    self.streamIsSearchingWeb = false
                    self.applyFMStreamPartial(
                        body: body,
                        partialTags: partial.tags,
                        partialCategory: partial.category,
                        planIntake: false,
                        usedWebSearch: false
                    )
                }
            }

            guard let reply = final, !reply.body.isEmpty else {
                // Leave streaming state intact so the cloud fallback continues
                // displaying the thinking indicator without a flicker.
                logCoachFlow("coachFlow onDevice empty -> fallback cloud")
                return false
            }

            // Final cleanup happens here only on success; on fallback we hand the
            // streaming UI state to the cloud path untouched.
            let actions = reply.suggestedActions
                .map { SuggestedAction(label: $0.label, type: "follow_up") }
                .prefix(4)
                .map { $0 }
            let followUp = reply.followUp.trimmingCharacters(in: .whitespacesAndNewlines)
            let tags = CoachReplyMetadataSupport.resolvedTags(
                modelTags: reply.tags,
                modelCategory: reply.category,
                body: reply.body,
                usedWebSearch: false,
                planIntake: false
            )
            let aiMsg = ChatMessage(
                id: UUID(),
                role: .assistant,
                content: reply.body,
                timestamp: .now,
                suggestedActions: Self.sanitizedSuggestedActions(actions),
                followUpQuestion: followUp.isEmpty ? nil : followUp,
                followUpBlocks: [],
                thinkingSteps: CoachReplyMetadataSupport.thinkingSteps(from: reply.reasoning),
                category: "on_device",
                tags: tags,
                references: [],
                usedWebSearch: false,
                feedbackScore: nil,
                confidence: 1.0,
                imageJPEG: nil
            )
            finishCoachReply(aiMsg, modelContext: modelContext)
            logCoachFlow("coachFlow onDevice success chars=\(reply.body.count)")
            return true
        } catch {
            logger.error("on-device narrow turn failed: \(error)")
            logCoachFlow("coachFlow onDevice error -> fallback cloud")
            return false
        }
    }

    // MARK: - Generate Plan

    func generatePlan(
        inputs: PlanInputs,
        isPro: Bool,
        modelContext: ModelContext,
        idempotencyKey: String
    ) async throws -> PlanGenerationResult {
        generatingPlan = true
        planProgress = nil
        defer {
            generatingPlan = false
            planProgress = nil
        }

        prepareForPlanGeneration()

        if OnDevicePlanGenerator.canGenerateOnDevice {
            do {
                let factSheet = coachFactSheetText(modelContext: modelContext)
                let plan = try await OnDevicePlanGenerator.generate(
                    inputs: inputs,
                    factSheet: factSheet,
                    ftp: PowerZone.ftp,
                    tools: []
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.planProgress = progress
                    }
                }
                logCoachFlow("coachFlow generatePlan path=onDevice weeks=\(plan.totalWeeks)")
                return PlanGenerationResult(
                    plan: plan,
                    requestId: nil,
                    validationWarnings: [],
                    creditsRemaining: nil,
                    generationMetrics: nil
                )
            } catch {
                if MangoxPCCSupport.isQuotaLimitReached(error) {
                    throw error
                }
                logger.info(
                    "On-device plan generation failed: \(error.localizedDescription)"
                )
            }
        }

        guard MangoxCoachLanguageModelProviderSupport.planCloudFallbackEnabled else {
            throw OnDevicePlanGenerator.canGenerateOnDevice
                ? OnDevicePlanGeneratorError.cloudFallbackDisabled
                : OnDevicePlanGeneratorError.unavailable
        }

        let encrypted = encryptUserContext(cachedUserContext(modelContext: modelContext))

        #if !DEBUG
        if encrypted == nil {
            logger.critical("USER_DATA_KEY missing in RELEASE build during plan generation — cloud will receive no context.")
            // We still proceed (backend can handle missing context), but this should never happen in App Store builds.
        }
        #endif

        let request = PlanGenerationRequest(
            inputs: inputs,
            is_pro: isPro,
            user_context_encrypted: encrypted,
            client_local_date: Self.dateFormatter.string(from: .now),
            client_time_zone: TimeZone.current.identifier
        )

        // Try streaming endpoint first (progress events); fall back to regular endpoint only
        // when the stream never delivered model output (avoids duplicate generation).
        do {
            return try await generatePlanStreaming(request: request, idempotencyKey: idempotencyKey)
        } catch let streamError as PlanStreamError {
            if MangoxSSEFallbackPolicy.shouldFallbackToNonStreaming(
                receivedStreamPayload: streamError.receivedStreamPayload
            ) {
                logger.info(
                    "Streaming plan endpoint unavailable, falling back to regular: \(streamError.underlying.localizedDescription)"
                )
            } else {
                throw streamError.underlying
            }
        } catch {
            throw error
        }

        let response: PlanGenerationResponse = try await post(
            path: "/api/generate-plan",
            body: request,
            extraHTTPHeaders: ["Idempotency-Key": idempotencyKey]
        )
        lastCreditsRemaining = response.credits_remaining
        return PlanGenerationResult(
            plan: response.plan,
            requestId: response.request_id,
            validationWarnings: response.validation_warnings ?? [],
            creditsRemaining: response.credits_remaining,
            generationMetrics: response.generation_metrics
        )
    }

    private func generateWorkout(
        inputs: WorkoutGenerationInputs,
        isPro: Bool,
        modelContext: ModelContext
    ) async throws -> (workout: GeneratedWorkout, serverWarnings: [String]) {
        if OnDeviceCoachEngine.isOnDeviceWritingModelAvailable {
            let snapshot = await coachTrainingSnapshotForOnDeviceNarrow(modelContext: modelContext)
            let ftp = inputs.currentFTP ?? PowerZone.ftp
            let prompt = """
                Goal: \(inputs.goal)
                Duration: \(inputs.durationMinutes) minutes
                Experience: \(inputs.experience ?? "intermediate")
                Intensity: \(inputs.preferredIntensity ?? "moderate")
                Environment: \(inputs.environment ?? "indoor trainer")
                Planned date: \(inputs.plannedDate ?? "today")
                Plan context: \(inputs.planContext ?? "")
                """
            do {
                let draft = try await Self.generateSingleWorkoutDraft(
                    userMessage: prompt,
                    trainingSnapshot: snapshot,
                    ftp: ftp
                )
                return (draft, [])
            } catch {
                logger.info(
                    "On-device workout generation failed, falling back to cloud: \(error.localizedDescription)"
                )
            }
        }

        let encrypted = encryptUserContext(cachedUserContext(modelContext: modelContext))

        #if !DEBUG
        if encrypted == nil {
            logger.critical("USER_DATA_KEY missing in RELEASE build during workout generation — cloud will receive no context.")
        }
        #endif

        let request = WorkoutGenerationRequest(
            inputs: inputs,
            is_pro: isPro,
            user_context_encrypted: encrypted,
            client_local_date: Self.dateFormatter.string(from: .now),
            client_time_zone: TimeZone.current.identifier
        )
        let response: WorkoutGenerationResponse = try await post(
            path: "/api/generate-workout",
            body: request
        )
        return (response.workout, response.validation_warnings ?? [])
    }

    /// Streaming plan generation with SSE progress events.
    private func generatePlanStreaming(
        request: PlanGenerationRequest,
        idempotencyKey: String
    ) async throws -> PlanGenerationResult {
        guard let url = URL(string: apiBaseURL + "/api/generate-plan/stream") else {
            throw URLError(.badURL)
        }

        var urlReq = URLRequest(url: url)
        urlReq.httpMethod = "POST"
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.setValue(userID, forHTTPHeaderField: "X-User-ID")
        urlReq.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        urlReq.mangox_applyDevTunnelHeadersIfNeeded(mangoxBaseURL: apiBaseURL)
        urlReq.timeoutInterval = 300
        urlReq.httpBody = try JSONEncoder().encode(request)

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: urlReq)
        } catch {
            throw PlanStreamError(underlying: error, receivedStreamPayload: false)
        }

        if let http = response as? HTTPURLResponse {
            // If the streaming endpoint doesn't exist (404) or returns non-SSE, throw to trigger fallback
            guard http.statusCode == 200 else {
                throw PlanStreamError(
                    underlying: URLError(.badServerResponse),
                    receivedStreamPayload: false
                )
            }
            let ct = http.value(forHTTPHeaderField: "Content-Type") ?? ""
            if ct.contains("application/json") {
                // Server returned a cached idempotent response (regular JSON, not SSE)
                var data = Data()
                do {
                    for try await byte in bytes { data.append(byte) }
                } catch {
                    throw PlanStreamError(underlying: error, receivedStreamPayload: false)
                }
                let decoded = try JSONDecoder().decode(PlanGenerationResponse.self, from: data)
                lastCreditsRemaining = decoded.credits_remaining
                return PlanGenerationResult(
                    plan: decoded.plan,
                    requestId: decoded.request_id,
                    validationWarnings: decoded.validation_warnings ?? [],
                    creditsRemaining: decoded.credits_remaining,
                    generationMetrics: decoded.generation_metrics
                )
            }
        }

        // Parse SSE events
        var receivedStreamPayload = false
        do {
            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let json = String(line.dropFirst(6))
                guard let data = json.data(using: .utf8) else { continue }

                guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let type = event["type"] as? String
                else { continue }

                switch type {
                case "progress":
                    receivedStreamPayload = true
                    let phase = event["phase"] as? String ?? ""
                    let message = event["message"] as? String ?? ""
                    let current = event["current"] as? Int
                    let total = event["total"] as? Int
                    planProgress = PlanGenerationProgress(
                        phase: phase, message: message, current: current, total: total
                    )

                case "complete":
                    receivedStreamPayload = true
                    let decoded = try JSONDecoder().decode(PlanGenerationResponse.self, from: data)
                    lastCreditsRemaining = decoded.credits_remaining
                    return PlanGenerationResult(
                        plan: decoded.plan,
                        requestId: decoded.request_id,
                        validationWarnings: decoded.validation_warnings ?? [],
                        creditsRemaining: decoded.credits_remaining,
                        generationMetrics: decoded.generation_metrics
                    )

                case "error":
                    receivedStreamPayload = true
                    let errorMsg = event["error"] as? String ?? "Plan generation failed"
                    throw NSError(
                        domain: "PlanGeneration", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: errorMsg])

                default:
                    break
                }
            }
        } catch {
            throw PlanStreamError(underlying: error, receivedStreamPayload: receivedStreamPayload)
        }

        if receivedStreamPayload {
            throw PlanStreamError(
                underlying: URLError(.badServerResponse),
                receivedStreamPayload: true
            )
        }

        throw PlanStreamError(
            underlying: URLError(.badServerResponse),
            receivedStreamPayload: false
        )
    }

    private struct PlanStreamError: Error {
        let underlying: Error
        let receivedStreamPayload: Bool
    }

    /// Persists `AIGeneratedPlan`, clears the confirmation draft, and presents success.
    func runConfirmedPlanGeneration(
        draft: PlanGenerationDraft,
        isPro: Bool,
        modelContext: ModelContext
    ) async throws {
        let result = try await generatePlan(
            inputs: draft.inputs,
            isPro: isPro,
            modelContext: modelContext,
            idempotencyKey: draft.id.uuidString
        )
        let critic = PlanCritic.validate(plan: result.plan, ftp: PowerZone.ftp)
        var mergedWarnings = result.validationWarnings
        mergedWarnings.append(contentsOf: critic.warnings.map(\.message))

        PrecisionCoachInstrumentation.planGenerated(
            planID: result.plan.id,
            criticWarnings: critic.warnings.count,
            criticErrors: critic.errors.count
        )

        guard let json = try? JSONEncoder().encode(result.plan) else {
            throw URLError(.cannotCreateFile)
        }
        let inputsData = try? JSONEncoder().encode(draft.inputs)
        let stored = AIGeneratedPlan(
            id: result.plan.id,
            planJSON: json,
            userPrompt: draft.summaryLine,
            regenerationInputsJSON: inputsData
        )
        modelContext.insert(stored)
        try modelContext.save()

        planConfirmationDraft = nil
        let snap = try? JSONEncoder().encode(result.plan)
        let fb = result.generationMetrics?.fallbackWeekNumbers ?? []
        let forwardImpact = PlanForwardImpactSummary.compute(
            plan: result.plan,
            eventDateString: draft.inputs.event_date
        )
        planSaveCelebration = PlanSaveCelebration(
            planID: result.plan.id,
            planName: result.plan.name,
            warnings: mergedWarnings,
            fallbackWeekNumbers: fb,
            planSnapshotJSON: snap,
            planInputs: draft.inputs,
            forwardImpactSummary: forwardImpact
        )

        appendLocalAssistantMessage(
            "Your plan **\(result.plan.name)** is saved. You can open it from **My Plans** or tap **Open plan** on the celebration screen.",
            category: "plan_analysis",
            modelContext: modelContext
        )
    }

    func saveConfirmedWorkoutDraft(_ draft: WorkoutGenerationDraft, modelContext: ModelContext) throws {
        let templateID = try workoutPersistence.saveCustomWorkoutTemplate(
            name: draft.workout.title,
            intervals: draft.workout.day.intervals
        )
        workoutConfirmationDraft = nil
        workoutSaveCelebration = WorkoutSaveCelebration(
            templateID: templateID,
            workoutTitle: draft.workout.title,
            purpose: draft.workout.purpose
        )
        appendLocalAssistantMessage(
            """
            Your workout **\(draft.workout.title)** is saved under **My Workouts** on the Coach tab. \
            Tap **Start workout** below, or open it anytime from Coach or **Indoor → Connection**.
            """,
            category: "training_advice",
            modelContext: modelContext
        )
    }

    /// Re-runs AI for one week (after a server fallback) via `/api/regenerate-plan-week`; updates SwiftData and celebration state.
    func regenerateFallbackPlanWeek(
        weekNumber: Int,
        celebration: PlanSaveCelebration,
        isPro: Bool,
        modelContext: ModelContext
    ) async throws {
        guard let inputs = celebration.planInputs else {
            throw URLError(.cannotCreateFile)
        }
        guard let snap = celebration.planSnapshotJSON,
            let plan = TrainingPlan.decodeFromStoredJSON(snap)
        else {
            throw URLError(.cannotDecodeContentData)
        }

        struct RegeneratePlanWeekRequest: Encodable {
            let inputs: PlanInputs
            let week_number: Int
            let plan: TrainingPlan
            let is_pro: Bool
            let client_local_date: String
            let client_time_zone: String
            let user_context_encrypted: String?
        }

        struct RegeneratePlanWeekResponse: Decodable {
            let days: [PlanDay]
            let week_number: Int
        }

        if OnDevicePlanGenerator.canGenerateOnDevice {
            prepareForPlanGeneration()
            do {
                let factSheet = coachFactSheetText(modelContext: modelContext)
                let days = try await OnDevicePlanGenerator.regenerateWeek(
                    inputs: inputs,
                    plan: plan,
                    weekNumber: weekNumber,
                    factSheet: factSheet,
                    ftp: PowerZone.ftp,
                    tools: []
                )
                let updated = plan.replacingDays(forWeekNumber: weekNumber, days: days)
                guard let json = try? JSONEncoder().encode(updated) else {
                    throw URLError(.cannotCreateFile)
                }
                let planId = celebration.planID
                let descriptor = FetchDescriptor<AIGeneratedPlan>(
                    predicate: #Predicate { $0.id == planId }
                )
                if let stored = try modelContext.fetch(descriptor).first {
                    stored.planJSON = json
                    try modelContext.save()
                }
                let remaining = celebration.fallbackWeekNumbers.filter { $0 != weekNumber }
                planSaveCelebration = PlanSaveCelebration(
                    planID: celebration.planID,
                    planName: celebration.planName,
                    warnings: celebration.warnings,
                    fallbackWeekNumbers: remaining,
                    planSnapshotJSON: json,
                    planInputs: celebration.planInputs,
                    forwardImpactSummary: celebration.forwardImpactSummary
                )
                return
            } catch {
                logger.info(
                    "On-device week regeneration failed: \(error.localizedDescription)"
                )
            }
        }

        guard MangoxCoachLanguageModelProviderSupport.planCloudFallbackEnabled else {
            throw OnDevicePlanGeneratorError.cloudFallbackDisabled
        }

        let enc = encryptUserContext(cachedUserContext(modelContext: modelContext))
        let body = RegeneratePlanWeekRequest(
            inputs: inputs,
            week_number: weekNumber,
            plan: plan,
            is_pro: isPro,
            client_local_date: Self.dateFormatter.string(from: .now),
            client_time_zone: TimeZone.current.identifier,
            user_context_encrypted: enc
        )

        // Stable per (snapshot, week): duplicate in-flight requests dedupe on the server; a new snapshot after success gets a new key.
        let idemBasis = snap + Data("\(weekNumber)".utf8)
        let idemKey = SHA256.hash(data: idemBasis).map { String(format: "%02x", $0) }.joined()

        let res: RegeneratePlanWeekResponse = try await post(
            path: "/api/regenerate-plan-week",
            body: body,
            extraHTTPHeaders: ["Idempotency-Key": idemKey]
        )

        let updated = plan.replacingDays(forWeekNumber: res.week_number, days: res.days)
        guard let json = try? JSONEncoder().encode(updated) else {
            throw URLError(.cannotCreateFile)
        }

        let planId = celebration.planID
        let descriptor = FetchDescriptor<AIGeneratedPlan>(
            predicate: #Predicate<AIGeneratedPlan> { $0.id == planId }
        )
        if let rows = try? modelContext.fetch(descriptor), let row = rows.first {
            row.planJSON = json
            try modelContext.save()
        }

        let newFallback = celebration.fallbackWeekNumbers.filter { $0 != weekNumber }
        planSaveCelebration = PlanSaveCelebration(
            planID: updated.id,
            planName: updated.name,
            warnings: celebration.warnings,
            fallbackWeekNumbers: newFallback,
            planSnapshotJSON: json,
            planInputs: inputs,
            forwardImpactSummary: celebration.forwardImpactSummary
        )
    }

    /// Runs after a normal chat reply: if the model requested plan generation, stage a confirmation draft (user confirms before `/api/generate-plan`).
    private func executePendingGeneratePlanToolIfNeeded(
        from response: ChatAPIResponse, modelContext: ModelContext
    ) async {
        let pending = response.toolCalls.filter {
            $0.name == "generate_plan" && $0.state == "pending"
        }
        guard let call = pending.first,
            let raw = call.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
        else {
            return
        }

        guard let data = raw.data(using: .utf8) else {
            logger.error("generate_plan detail not UTF-8")
            return
        }

        let detail: GeneratePlanToolDetail
        do {
            detail = try JSONDecoder().decode(GeneratePlanToolDetail.self, from: data)
        } catch {
            logger.error("generate_plan detail JSON decode failed: \(error.localizedDescription)")
            appendLocalAssistantMessage(
                "I couldn't read the plan details from that reply. Try asking again with your event name and target date (YYYY-MM-DD).",
                category: "clarification",
                modelContext: modelContext
            )
            return
        }

        stagePlanConfirmationDraft(from: detail, modelContext: modelContext)
    }

    /// PCC / on-device plan intake: stage confirmation when transcript has required fields.
    private func stagePlanConfirmationFromLocalIntakeIfReady(
        planIntake: Bool,
        body: String,
        followUp: String,
        suggestedActions: [SuggestedAction],
        category: String,
        followUpBlocksCount: Int
    ) {
        guard planIntake, planConfirmationDraft == nil else { return }
        let turn = PlanIntakeLocalDraftStaging.TurnContext(
            body: body,
            followUp: followUp,
            suggestedActionLabels: suggestedActions.map(\.label),
            category: category,
            followUpBlocksCount: followUpBlocksCount
        )
        guard
            let draft = PlanIntakeLocalDraftStaging.draftIfReady(
                messages: messages,
                turn: turn,
                ftp: PowerZone.ftp
            )
        else { return }
        planConfirmationDraft = draft
        logCoachFlow("coachFlow localPlanIntake stagedConfirmation event=\(draft.inputs.event_name)")
    }

    private func stagePlanConfirmationDraft(
        from detail: GeneratePlanToolDetail,
        modelContext: ModelContext
    ) {
        let eventName = detail.event_name.trimmingCharacters(in: .whitespacesAndNewlines)
        let eventDateRaw = (detail.event_date ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eventName.isEmpty else {
            appendLocalAssistantMessage(
                "To generate your plan I need an event name and a target date.",
                category: "clarification",
                modelContext: modelContext
            )
            return
        }
        guard let eventDate = PlanEventDateNormalization.normalizedYYYYMMDD(from: eventDateRaw)
        else {
            if eventDateRaw.isEmpty {
                appendLocalAssistantMessage(
                    "To generate your plan I need a **target date** for your event (say it in your own words, or as yyyy-MM-dd).",
                    category: "clarification",
                    modelContext: modelContext
                )
            } else {
                appendLocalAssistantMessage(
                    "I couldn't parse the event date \"\(eventDateRaw)\". Please confirm the race day as **yyyy-MM-dd** (for example \(Self.dateFormatter.string(from: .now))).",
                    category: "clarification",
                    modelContext: modelContext
                )
            }
            return
        }

        let inputs = PlanInputs(
            event_name: eventName,
            event_date: eventDate,
            ftp: PowerZone.ftp,
            weekly_hours: detail.weekly_hours,
            experience: detail.experience,
            route_option: Self.nonEmptyTrimmed(detail.route_option),
            target_distance_km: detail.target_distance_km,
            target_elevation_m: detail.target_elevation_m,
            event_location: Self.nonEmptyTrimmed(detail.event_location),
            event_notes: Self.nonEmptyTrimmed(detail.event_notes)
        )
        let summary = Self.planSummaryLine(for: inputs)
        planConfirmationDraft = PlanGenerationDraft(inputs: inputs, summaryLine: summary)
        // Confirmation UI is the bottom sheet; avoid a second bubble with duplicate "confirm" copy (it overlapped the card visually).
    }

    private func executePendingGenerateWorkoutToolIfNeeded(
        from response: ChatAPIResponse,
        isPro: Bool,
        modelContext: ModelContext
    ) async {
        guard let call = response.toolCalls.first(where: {
            $0.name == "generate_workout" && $0.state == "pending"
        }),
            let raw = call.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
            let data = raw.data(using: .utf8)
        else { return }

        let detail: GenerateWorkoutToolDetail
        do {
            detail = try JSONDecoder().decode(GenerateWorkoutToolDetail.self, from: data)
        } catch {
            logger.error("generate_workout detail JSON decode failed: \(error.localizedDescription)")
            appendLocalAssistantMessage(
                "I couldn't read the workout details from that reply. Try again with the workout focus and duration.",
                category: "clarification",
                modelContext: modelContext
            )
            return
        }

        let goal = detail.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else {
            appendLocalAssistantMessage(
                "To build a workout I need the workout focus, like threshold, endurance, or recovery.",
                category: "clarification",
                modelContext: modelContext
            )
            return
        }
        guard let duration = detail.duration_minutes, duration > 0 else {
            appendLocalAssistantMessage(
                "To build a workout I need the workout duration in minutes.",
                category: "clarification",
                modelContext: modelContext
            )
            return
        }

        let inputs = WorkoutGenerationInputs(
            goal: goal,
            durationMinutes: duration,
            experience: Self.nonEmptyTrimmed(detail.experience),
            preferredIntensity: Self.nonEmptyTrimmed(detail.preferred_intensity),
            environment: Self.nonEmptyTrimmed(detail.environment) ?? "indoor",
            plannedDate: Self.nonEmptyTrimmed(detail.planned_date),
            currentFTP: PowerZone.ftp,
            planContext: Self.nonEmptyTrimmed(detail.plan_context)
        )

        do {
            let generation = try await generateWorkout(
                inputs: inputs,
                isPro: isPro,
                modelContext: modelContext
            )
            let critic = WorkoutCritic.validate(
                workout: generation.workout,
                inputs: inputs,
                ftp: PowerZone.ftp
            )
            var warnings = generation.serverWarnings
            for message in critic.warnings.map(\.message) where !warnings.contains(message) {
                warnings.append(message)
            }
            PrecisionCoachInstrumentation.workoutGenerated(
                title: generation.workout.title,
                warningCount: warnings.count
            )
            workoutConfirmationDraft = WorkoutGenerationDraft(
                inputs: inputs,
                workout: generation.workout,
                validationWarnings: warnings
            )
        } catch {
            logger.error("generate_workout endpoint failed: \(error.localizedDescription)")
            appendLocalAssistantMessage(
                "I couldn't generate that workout right now. Try again in a moment or tweak the duration and focus.",
                category: "error",
                modelContext: modelContext
            )
        }
    }

    private func appendLocalAssistantMessage(
        _ text: String,
        category: String,
        modelContext: ModelContext
    ) {
        let msg = ChatMessage(
            id: UUID(),
            role: .assistant,
            content: text,
            timestamp: .now,
            suggestedActions: [],
            followUpQuestion: nil,
            followUpBlocks: [],
            thinkingSteps: [],
            category: category,
            tags: [],
            references: [],
            usedWebSearch: false,
            feedbackScore: nil,
            confidence: 1.0,
            imageJPEG: nil
        )
        commitAssistantMessage(msg, modelContext: modelContext)
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

        let weekRange = TrainingPlanCompliance.currentWeekRange()

        var planName: String? = nil
        var planProgressStr: String? = nil
        var planSource: String? = nil
        var adaptiveErgPercent = 100
        var planSemanticsHint: String?
        if let p = activeProgress,
            let plan = PlanLibrary.resolvePlan(planID: p.planID, modelContext: modelContext)
        {
            planName = plan.name
            planSource = "ai"
            let totalDays = plan.allDays.filter {
                switch $0.dayType {
                case .workout, .ftpTest, .optionalWorkout, .commute: return true
                default: return false
                }
            }.count
            planProgressStr = "\(p.completedCount) of \(totalDays) workouts done"
            adaptiveErgPercent = Int((p.adaptiveLoadMultiplier * 100).rounded())

            var sawOptional = false
            var sawCommute = false
            for day in plan.allDays {
                let d = p.calendarDate(for: day)
                guard d >= weekRange.start, d < weekRange.end else { continue }
                if day.dayType == .optionalWorkout { sawOptional = true }
                if day.dayType == .commute { sawCommute = true }
            }
            if sawOptional || sawCommute {
                planSemanticsHint =
                    "This calendar week includes optional and/or commute days. Optional days are flexible volume; starred key days are priority quality sessions unless the day is explicitly optional. Commute days should stay easy."
            }
        }

        let weekStart = weekRange.start
        let weekEnd = weekRange.end
        let weekWorkouts = (try? modelContext.fetch(
            FetchDescriptor<Workout>(
                predicate: #Predicate<Workout> {
                    $0.startDate >= weekStart && $0.startDate < weekEnd
                }
            )
        )) ?? []
        let weekActualTss = Int(
            weekWorkouts
                .filter { $0.status == .completed && $0.isValid }
                .reduce(0.0) { $0 + $1.tss }
                .rounded()
        )

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
        let recentRideDigest = lastRides
            .filter(\.isValid)
            .prefix(5)
            .map { ride in
                var parts: [String] = [
                    "\(Int(ride.duration / 60))min",
                    String(format: "%.1fkm", ride.distance / 1000),
                ]
                if ride.avgPower > 0 {
                    parts.append("\(Int(ride.avgPower))W avg")
                    parts.append("TSS \(Int(ride.tss.rounded()))")
                }
                if ride.avgHR > 0 {
                    parts.append("\(Int(ride.avgHR)) bpm")
                }
                if !ride.notes.isEmpty {
                    parts.append("notes: \(ride.notes.prefix(40))")
                }
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                return "\(formatter.string(from: ride.startDate)): \(parts.joined(separator: " · "))"
            }
            .joined(separator: "\n")

        var lastRideContext: LastRideContext?
        if let ride = lastRide {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let dateStr = formatter.localizedString(for: ride.startDate, relativeTo: .now)
            let powerOK = ride.maxPower > 0 || ride.avgPower > 0
            var summaryParts: [String] = [
                "\(Int(ride.duration / 60))min",
                String(format: "%.1fkm", ride.distance / 1000),
            ]
            if powerOK {
                summaryParts.append(contentsOf: [
                    "\(Int(ride.avgPower))W avg",
                    "NP \(Int(ride.normalizedPower))W",
                    "TSS \(Int(ride.tss))",
                ])
            } else {
                summaryParts.append("no power data — NP/TSS not power-based")
                if ride.displayAverageSpeedKmh > 0.5 {
                    summaryParts.append(
                        String(format: "%.1f km/h avg", ride.displayAverageSpeedKmh))
                }
            }
            if ride.avgHR > 0 {
                summaryParts.append("\(Int(ride.avgHR)) bpm avg HR")
            }
            if ride.elevationGain > 1 {
                summaryParts.append(String(format: "%.0f m elev", ride.elevationGain))
            }
            let aerobicDecoupling = AerobicDecouplingAnalytics.compute(from: ride)
            if let aerobicDecoupling {
                summaryParts.append(aerobicDecoupling.plainLanguageSummary)
            }

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
                summary: summaryParts.joined(separator: " · "),
                powerDataAvailable: powerOK,
                aerobicDecouplingPercent: aerobicDecoupling?.decouplingPercent,
                aerobicDecouplingStatus: aerobicDecoupling?.status.rawValue
            )
        }

        let riderPrefs = RidePreferences.shared
        let riderWeight: Double? = riderPrefs.riderWeightKg > 0 ? riderPrefs.riderWeightKg : nil

        let whoop = whoopDataSource
        let whoopLinked = whoop?.isConnected == true
        let whoopPct = whoopLinked ? whoop?.latestRecoveryScore : nil
        let whoopRhr = whoopLinked ? whoop?.latestRecoveryRestingHR : nil
        let whoopHrv = whoopLinked ? whoop?.latestRecoveryHRV : nil

        let ft = FitnessTracker.shared
        let pmcTrendSummary = ft.isLoaded ? PMCTrend.compactTrendLine(history: ft.history) : nil

        let decouplingSamples: [AerobicDecouplingTrend.RideSample] = lastRides
            .filter(\.isValid)
            .prefix(12)
            .reversed()
            .compactMap { ride in
                guard let result = AerobicDecouplingAnalytics.compute(from: ride),
                      result.status != .insufficientData
                else { return nil }
                return AerobicDecouplingTrend.RideSample(
                    date: ride.startDate,
                    decouplingPercent: result.decouplingPercent,
                    status: result.status
                )
            }
        let decouplingTrend = AerobicDecouplingTrend.analyze(rides: decouplingSamples)
        let aerobicDecouplingTrendSummary =
            decouplingTrend.direction == .insufficientData
            ? nil
            : decouplingTrend.plainLanguageSummary

        let powerCurveCandidates = WorkoutMetricsSnapshot.powerCurveCandidates(
            from: lastRides.filter(\.isValid),
            rangeDays: PowerCurveSummary.defaultRangeDays
        )
        let powerCurvePoints = PowerCurveAnalytics.compute(
            from: powerCurveCandidates.map(\.sortedPowers)
        )
        let powerCurveSummaryText = powerCurvePoints.isEmpty
            ? nil
            : PowerCurveSummary.format(
                points: powerCurvePoints,
                ftp: ftp,
                rangeDays: PowerCurveSummary.defaultRangeDays
            )

        let criticalPowerSummaryText = CriticalPowerModel.fit(from: powerCurvePoints).map(\.plainLanguageSummary)

        return UserContext(
            ftp: ftp,
            maxHR: maxHR,
            restingHR: restingHR,
            recentWorkoutsCount: recentCount,
            activePlanName: planName,
            activePlanProgress: planProgressStr,
            activePlanSource: planSource,
            weekActualTss: weekActualTss,
            adaptiveErgPercent: adaptiveErgPercent,
            ftpHistory: ftpHistory.isEmpty ? nil : ftpHistory,
            lastRide: lastRideContext,
            seasonGoalSummary: nil,
            planKeyDaySemanticsHint: planSemanticsHint,
            recentRideDigest: recentRideDigest.isEmpty ? nil : recentRideDigest,
            lastRideAerobicDecoupling: lastRideContext.flatMap { context in
                guard let percent = context.aerobicDecouplingPercent,
                      let status = context.aerobicDecouplingStatus
                else { return nil }
                return String(format: "%.1f%% %@", percent, status)
            },
            riderWeightKg: riderWeight,
            riderAge: riderPrefs.riderAge,
            whoopLinked: whoopLinked,
            whoopRecoveryPercent: whoopPct,
            whoopRestingHR: whoopRhr,
            whoopHrvMs: whoopHrv,
            whoopMaxHeartRate: whoopLinked ? whoop?.latestMaxHeartRateFromProfile : nil,
            currentCtl: ft.isLoaded ? ft.currentCTL : nil,
            currentAtl: ft.isLoaded ? ft.currentATL : nil,
            currentTsb: ft.isLoaded ? ft.currentTSB : nil,
            pmcTrendSummary: pmcTrendSummary,
            aerobicDecouplingTrend: aerobicDecouplingTrendSummary,
            powerCurveSummary: powerCurveSummaryText,
            criticalPowerSummary: criticalPowerSummaryText
        )
    }

    /// Restores the coach thread from SwiftData (in-memory `messages` was always empty after relaunch).
    ///
    /// Stays on the main actor with the view-supplied `ModelContext` so SwiftData never runs
    /// synchronous store work from `Task.detached` (which triggers
    /// "unsafeForcedSync called from Swift Concurrent context" and is structurally unsupported).
    /// Yields first so chat chrome can commit before the capped fetch (100 rows).
    func loadPersistedMessages(modelContext: ModelContext) async {
        guard messages.isEmpty else {
            logger.debug(
                "loadPersistedMessages skipped — \(self.messages.count) messages already in memory")
            return
        }

        await Task.yield()
        await Task.yield()

        if let sessionID = currentSessionID {
            await loadSession(sessionID, modelContext: modelContext)
            return
        }

        let sessionDescriptor = FetchDescriptor<ChatSession>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let sessions = try? modelContext.fetch(sessionDescriptor), let latest = sessions.first {
            currentSessionID = latest.id
            await loadSession(latest.id, modelContext: modelContext)
            return
        }

        logger.debug("No sessions found, starting fresh")
    }

    private func loadSession(_ sessionID: UUID, modelContext: ModelContext) async {
        await Task.yield()
        // Fetch newest 100 messages (sort descending so the limit keeps the tail,
        // then reverse in-memory for chronological display order).
        var descriptor = FetchDescriptor<CoachChatMessage>(
            predicate: #Predicate<CoachChatMessage> { $0.session?.id == sessionID },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        do {
            let rows = try modelContext.fetch(descriptor)
            logger.debug("Loaded \(rows.count) persisted messages from session \(sessionID)")
            // Always replace when loading a session — switching threads must not bail out
            // just because the previous conversation is still in memory.
            messages = rows.reversed().map { $0.toChatMessage() }
        } catch {
            logger.error("Failed to load persisted messages: \(error)")
        }
    }

    /// Creates a new chat session and sets it as the active session.
    func createNewSession(modelContext: ModelContext, cancelInFlightTurn: Bool = true) {
        if cancelInFlightTurn {
            cancelActiveChatTurnIfNeeded()
        }
        resetCoachLanguageSessions()
        invalidateCoachContextCache()
        let session = ChatSession()
        modelContext.insert(session)
        do {
            try modelContext.save()
            currentSessionID = session.id
            messages.removeAll()
            clearPlanIntakeMode()
            planConfirmationDraft = nil
            planSaveCelebration = nil
            workoutConfirmationDraft = nil
            workoutSaveCelebration = nil
            logger.debug("Created new session \(session.id)")
        } catch {
            logger.error("Failed to create new session: \(error)")
        }
    }

    /// Switches to an existing session by ID.
    func switchToSession(_ sessionID: UUID, modelContext: ModelContext) {
        cancelActiveChatTurnIfNeeded()
        resetCoachLanguageSessions()
        invalidateCoachContextCache()
        currentSessionID = sessionID
        clearPlanIntakeMode()
        planConfirmationDraft = nil
        planSaveCelebration = nil
        workoutConfirmationDraft = nil
        workoutSaveCelebration = nil
        messages.removeAll()
        Task { await loadSession(sessionID, modelContext: modelContext) }
    }

    /// Deletes one or more sessions in a single save. Clears in-memory state when the active session is removed.
    func deleteSessions(_ sessionIDs: Set<UUID>, modelContext: ModelContext) {
        guard !sessionIDs.isEmpty else { return }
        let deletingCurrent = currentSessionID.map { sessionIDs.contains($0) } ?? false
        if deletingCurrent {
            cancelActiveChatTurnIfNeeded()
        }

        var deletedCount = 0
        for sessionID in sessionIDs {
            let descriptor = FetchDescriptor<ChatSession>(
                predicate: #Predicate<ChatSession> { $0.id == sessionID }
            )
            guard let sessions = try? modelContext.fetch(descriptor), let session = sessions.first else {
                continue
            }
            modelContext.delete(session)
            deletedCount += 1
        }

        guard deletedCount > 0 else { return }

        do {
            try modelContext.save()
            if deletingCurrent {
                messages.removeAll()
                currentSessionID = nil
                resetCoachLanguageSessions()
                invalidateCoachContextCache()
                clearPlanIntakeMode()
                planConfirmationDraft = nil
                planSaveCelebration = nil
                workoutConfirmationDraft = nil
                workoutSaveCelebration = nil
            }
            logger.debug("Deleted \(deletedCount) coach session(s)")
        } catch {
            logger.error("Failed to delete coach sessions: \(error)")
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
    /// When Apple Intelligence is available, generates a descriptive 3-5 word title via Foundation Models.
    private func updateSessionTitleIfNeeded(modelContext: ModelContext) {
        guard let sessionID = currentSessionID else { return }
        let descriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate<ChatSession> { $0.id == sessionID }
        )
        guard let sessions = try? modelContext.fetch(descriptor), let session = sessions.first else { return }

        if session.title == "New Conversation" {
            // Apply fallback title immediately so the session is never stuck with "New Conversation".
            session.updateTitle(from: session.messages)
            do { try modelContext.save() } catch { logger.error("Failed to update session title: \(error)") }

            // Then attempt AI title generation in background (overwrites fallback if successful).
            let firstUser = session.messages.first(where: { $0.roleRaw == "user" })?.content ?? ""
            let firstAssistant = session.messages.first(where: { $0.roleRaw == "assistant" })?.content ?? ""
            guard !firstUser.isEmpty, !firstAssistant.isEmpty else { return }
            Task { [weak self] in
                guard let aiTitle = await OnDeviceCoachEngine.generateSessionTitle(
                    firstUserMessage: firstUser, firstAssistantReply: firstAssistant) else { return }
                await MainActor.run { [weak self] in
                    guard self != nil else { return }
                    let desc2 = FetchDescriptor<ChatSession>(predicate: #Predicate { $0.id == sessionID })
                    if let found = (try? modelContext.fetch(desc2))?.first, found.title != "New Conversation" {
                        // Only overwrite if we set the 5-word fallback (not a user-renamed session)
                        found.title = aiTitle
                        found.updatedAt = .now
                        try? modelContext.save()
                        self?.logCoachFlow("coachFlow sessionTitle ai=\(aiTitle)")
                    }
                }
            }
        } else {
            session.updatedAt = .now
            do { try modelContext.save() } catch { logger.error("Failed to update session timestamp: \(error)") }
        }
    }

    func clearMessages(modelContext: ModelContext) {
        createNewSession(modelContext: modelContext)
    }

    /// Throws on save failure so callers can surface the error and keep `messages` in
    /// sync with what's actually on disk. Previously this swallowed errors, which is
    /// what produced the "messages disappear after relaunch" symptom.
    private func persistCoachMessage(_ message: ChatMessage, modelContext: ModelContext) throws {
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
        try modelContext.save()
    }

    // MARK: - Helpers

    private func buildHistory() -> [HistoryTurn] {
        // Last 6 turns (12 messages) — exclude the very last user message (sent
        // separately as `ChatRequest.message`); previously the trailing user msg
        // was duplicated, biasing the model toward repeating itself.
        let recent = messages
            .dropLast()
            .suffix(contextWindowSize)
            .map { HistoryTurn(role: $0.role.rawValue, content: $0.content) }
        guard messages.count > contextWindowSize, let summary = conversationSummaryForDroppedMessages()
        else {
            return recent
        }
        return [HistoryTurn(role: "assistant", content: summary)] + recent
    }

    private func conversationSummaryForDroppedMessages() -> String? {
        let kept = contextWindowSize
        guard messages.count > kept else { return nil }
        let dropped = messages.dropLast().dropLast(kept)
        let userTopics = dropped
            .filter { $0.role == .user }
            .map { String($0.content.prefix(72)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(4)
        guard !userTopics.isEmpty else { return nil }
        return "[Earlier in this chat the rider asked about: \(userTopics.joined(separator: "; ")).]"
    }

    private func post<Req: Encodable, Res: Decodable>(
        path: String,
        body: Req,
        extraHTTPHeaders: [String: String] = [:]
    ) async throws -> Res {
        guard let url = URL(string: apiBaseURL + path) else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(userID, forHTTPHeaderField: "X-User-ID")
        req.mangox_applyDevTunnelHeadersIfNeeded(mangoxBaseURL: apiBaseURL)
        for (k, v) in extraHTTPHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }
        req.timeoutInterval = 300
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)

        if let httpResponse = response as? HTTPURLResponse {
            logger.debug("\(path) → HTTP \(httpResponse.statusCode)")
            if httpResponse.statusCode >= 400 {
                let body = String(data: data, encoding: .utf8) ?? ""
                if !body.isEmpty {
                    logger.error("Error body: \(body.prefix(500), privacy: .private)")
                }
                if body.localizedCaseInsensitiveContains("<!doctype") {
                    throw CoachHTTPError.tunnelReturnedHTML(status: httpResponse.statusCode)
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

    // MARK: - Feedback

    func submitFeedback(for messageID: UUID, score: Int) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].feedbackScore = score
        let message = messages[index]
        persistFeedbackScore(score, messageID: messageID, modelContext: persistenceContext)
        let path = CoachDeliveryPath.fromMessageCategory(message.category)
        PrecisionCoachInstrumentation.coachFeedbackReceived(
            score: score,
            category: message.category,
            deliveryPath: path.instrumentationLabel
        )
    }

    private func persistFeedbackScore(_ score: Int, messageID: UUID, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<CoachChatMessage>(
            predicate: #Predicate<CoachChatMessage> { $0.id == messageID }
        )
        guard let row = try? modelContext.fetch(descriptor).first else { return }
        row.feedbackScore = score
        do {
            try modelContext.save()
            bumpSessionUpdatedAt(modelContext: modelContext)
        } catch {
            logger.error("Failed to persist coach feedback: \(error)")
        }
    }

    // MARK: - Regenerate

    func regenerateLastMessage(isPro: Bool, modelContext: ModelContext) async {
        await regenerateLastMessage(
            isPro: isPro,
            preferCloud: false,
            modelContext: modelContext
        )
    }

    func regenerateLastMessagePreferringCloud(isPro: Bool, modelContext: ModelContext) async {
        await regenerateLastMessage(
            isPro: isPro,
            preferCloud: true,
            modelContext: modelContext
        )
    }

    private func regenerateLastMessage(
        isPro: Bool,
        preferCloud: Bool,
        modelContext: ModelContext
    ) async {
        guard let lastUserMsg = messages.last(where: { $0.role == .user }) else {
            logCoachFlow("coachFlow regenerate skip reason=noUserMessage")
            return
        }
        guard !isLoading else {
            logCoachFlow("coachFlow regenerate skip reason=loading")
            return
        }
        if let lastAssistant = messages.last(where: { $0.role == .assistant }) {
            removeCoachMessage(id: lastAssistant.id, modelContext: modelContext)
            logCoachFlow("coachFlow regenerate removedLastAssistant then sendMessage automatic")
        } else {
            logCoachFlow("coachFlow regenerate noAssistantRemoved then sendMessage automatic")
        }
        if preferCloud {
            skipLocalCoachForNextTurn = true
            resetCoachLanguageSessions()
        }
        let retryImage: CoachUserImageAttachment?
        if let jpeg = lastUserMsg.imageJPEG {
            retryImage = CoachUserImageAttachment(jpegData: jpeg, pixelWidth: 0, pixelHeight: 0)
        } else {
            retryImage = nil
        }
        await sendMessage(
            lastUserMsg.content,
            isPro: isPro,
            image: retryImage,
            modelContext: modelContext
        )
    }

    // MARK: - Context Window

    var contextWindowSize: Int { 12 }
    var currentContextCount: Int {
        min(messages.count, contextWindowSize)
    }

    var suggestsFreshConversation: Bool {
        messages.count >= contextWindowSize
    }

    // MARK: - Recovery Status

    enum RecoveryStatus: String {
        case fresh = "Fresh"
        case recovering = "Recovering"
        case fatigued = "Fatigued"

        var icon: String {
            switch self {
            case .fresh: return "battery.100"
            case .recovering: return "battery.50"
            case .fatigued: return "battery.25"
            }
        }

        var color: Color {
            switch self {
            case .fresh: return AppColor.success
            case .recovering: return AppColor.yellow
            case .fatigued: return AppColor.orange
            }
        }
    }

    func recoveryStatus(modelContext: ModelContext) -> RecoveryStatus {
        if let whoop = whoopDataSource, whoop.isConnected, let pct = whoop.latestRecoveryScore {
            if pct >= 67 { return .fresh }
            if pct >= 34 { return .recovering }
            return .fatigued
        }

        let desc = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.statusRaw == "completed" },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        guard let ride = (try? modelContext.fetch(desc))?.first else { return .fresh }
        let hoursSince = Date().timeIntervalSince(ride.startDate) / 3600
        let tss = ride.tss
        if tss > 300 && hoursSince < 24 { return .fatigued }
        if tss > 200 && hoursSince < 12 { return .fatigued }
        if hoursSince < 24 { return .recovering }
        if tss > 150 && hoursSince < 48 { return .recovering }
        return .fresh
    }

    func hasRecentRide(modelContext: ModelContext) -> Bool {
        let desc = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.statusRaw == "completed" },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        guard let ride = (try? modelContext.fetch(desc))?.first else { return false }
        return Date().timeIntervalSince(ride.startDate) / 3600 < 48
    }

    // MARK: - Contextual Quick Prompts

    /// User-visible copy for plan API failures (avoids raw DecodingError strings in the confirm banner).
    static func userFacingPlanGenerationError(_ error: Error) -> String {
        if let planErr = error as? OnDevicePlanGeneratorError {
            return planErr.localizedDescription
        }
        if MangoxPCCSupport.isSessionEstablishmentFailure(error) {
            return "Apple Intelligence couldn't start a plan session. Mangox tried cloud generation — check Settings → AI Coach that **Allow Mangox Cloud fallback** is on and your backend URL is set."
        }
        if let urlErr = error as? URLError, urlErr.code == .badServerResponse {
            return "The plan server returned an error. Check your connection and try again."
        }
        if error is DecodingError {
            return
                "Couldn't read the generated plan from the server (format mismatch). Tap Generate again, or update Mangox if this keeps happening."
        }
        return error.localizedDescription
    }

    func contextualQuickPrompts(modelContext: ModelContext) -> [QuickPrompt] {
        let availability = cachedStarterPromptAvailability(modelContext: modelContext)
        var prompts: [QuickPrompt] = []
        let status = recoveryStatus(modelContext: modelContext)
        if let whoop = whoopDataSource, whoop.isConnected, let pct = whoop.latestRecoveryScore,
            pct < 34
        {
            prompts.append(
                QuickPrompt(
                    text: "How should I train with my WHOOP recovery today?",
                    icon: "waveform.path.ecg"
                )
            )
        }
        if availability.hasRecentRide, status != .fresh {
            prompts.append(QuickPrompt(text: "Analyze my last ride", icon: "chart.bar.fill"))
        }
        if availability.hasActivePlan {
            prompts.append(QuickPrompt(text: "How's my training load?", icon: "heart.fill"))
            prompts.append(
                QuickPrompt(text: "What's my workout today?", icon: "calendar.badge.clock"))
        }
        if availability.hasFTPHistory {
            prompts.append(QuickPrompt(text: "How's my FTP trend?", icon: "bolt.fill"))
        } else if PowerZone.ftp > 0 {
            prompts.append(QuickPrompt(text: "Explain my power zones", icon: "bolt.fill"))
        }
        if prompts.count < 4 {
            prompts.append(
                QuickPrompt(text: "Build me a workout today", icon: "figure.outdoor.cycle"))
        }
        if prompts.isEmpty {
            prompts.append(
                QuickPrompt(text: "What should I do today?", icon: "figure.outdoor.cycle"))
        }
        return groundedQuickPrompts(from: prompts, availability: availability, fallback: [])
    }
}
