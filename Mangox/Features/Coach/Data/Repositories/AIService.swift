import CryptoKit
import Foundation
import FoundationModels
import SwiftData
import SwiftUI
import os.log

// MARK: - Chat Models

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
            id: UUID(), role: .user, content: text, timestamp: .now,
            suggestedActions: [], followUpQuestion: nil, followUpBlocks: [],
            thinkingSteps: [],
            category: nil, tags: [], references: [], usedWebSearch: false,
            feedbackScore: nil, confidence: 1.0
        )
    }
}

enum MessageRole: String, Equatable, Sendable {
    case user, assistant
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

struct ChatReference: Codable, Equatable, Sendable {
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
    /// `builtin` (template) or `ai` when an active plan is resolved.
    let activePlanSource: String?
    /// Sum of TSS from valid completed rides in the current calendar week.
    let weekActualTss: Int
    /// Guided ERG scale as percent (100 = plan as written).
    let adaptiveErgPercent: Int
    let ftpHistory: String?
    let lastRide: LastRideContext?
    /// Optional goal event / phase from in-app settings.
    let seasonGoalSummary: String?
    /// Short hint about optional vs mandatory plan days when the active week includes flexible sessions.
    let planKeyDaySemanticsHint: String?
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
}

struct PlanGenerationRequest: Encodable {
    let inputs: PlanInputs
    let is_pro: Bool
    let user_context_encrypted: String?
    let client_local_date: String
    let client_time_zone: String
}

struct PlanInputs: Codable, Equatable, Sendable {
    let event_name: String
    let event_date: String
    let ftp: Int
    let weekly_hours: Int?
    let experience: String?
    /// e.g. long, medium, short — when the event publishes multiple routes.
    let route_option: String?
    /// Official or user-stated route distance (km).
    let target_distance_km: Double?
    /// Total climbing (m) when known.
    let target_elevation_m: Double?
    let event_location: String?
    /// Short free-text: mass start, gravel, etc.
    let event_notes: String?

    /// Lines for the confirm UI (omits empty fields).
    var coachConfirmDetailLines: [String] {
        var lines: [String] = []
        if let r = route_option?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty {
            lines.append("Route: \(r)")
        }
        if let km = target_distance_km, km > 0 {
            let s = km >= 100 ? String(format: "%.0f km", km) : String(format: "%.1f km", km)
            lines.append("Distance: \(s)")
        }
        if let m = target_elevation_m, m > 0 {
            lines.append("Climbing: \(Int(m.rounded())) m")
        }
        if let loc = event_location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
            lines.append("Location: \(loc)")
        }
        if let n = event_notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            lines.append(n)
        }
        return lines
    }
}

struct PlanGenerationResponse: Decodable {
    let plan: TrainingPlan
    let credits_used: Int?
    let credits_remaining: Int?
    let request_id: String?
    let validation_warnings: [String]?
    let generation_metrics: PlanGenerationMetrics?
}

struct PlanLLMModelsResolved: Decodable, Sendable, Equatable {
    let skeleton: String
    let week: String
    /// Taper/race week tier; absent on older API responses.
    let weekPremium: String?

    enum CodingKeys: String, CodingKey {
        case skeleton
        case week
        case weekPremium = "week_premium"
    }
}

struct PlanGenerationMetrics: Decodable, Sendable, Equatable {
    let expectedWeeks: Int
    let skeletonMs: Int
    let weeksMs: Int
    let totalMs: Int
    let parallelConcurrency: Int
    let weeksSucceededLlm: Int
    let weeksUsedFallback: Int
    let fallbackWeekNumbers: [Int]
    let templateIntervalExpansions: Int
    let models: PlanLLMModelsResolved?
    let rulesVersion: String
    let weekBatchSize: Int?
    let weekLlmCalls: Int?
    let planParallelVersion: String?
    let skeletonProgressionWarnings: [String]?

    enum CodingKeys: String, CodingKey {
        case expectedWeeks = "expected_weeks"
        case skeletonMs = "skeleton_ms"
        case weeksMs = "weeks_ms"
        case totalMs = "total_ms"
        case parallelConcurrency = "parallel_concurrency"
        case weeksSucceededLlm = "weeks_succeeded_llm"
        case weeksUsedFallback = "weeks_used_fallback"
        case fallbackWeekNumbers = "fallback_week_numbers"
        case templateIntervalExpansions = "template_interval_expansions"
        case models
        case rulesVersion = "rules_version"
        case weekBatchSize = "week_batch_size"
        case weekLlmCalls = "week_llm_calls"
        case planParallelVersion = "plan_parallel_version"
        case skeletonProgressionWarnings = "skeleton_progression_warnings"
    }
}

struct PlanGenerationResult: Sendable {
    let plan: TrainingPlan
    let requestId: String?
    let validationWarnings: [String]
    let creditsRemaining: Int?
    let generationMetrics: PlanGenerationMetrics?
}

/// Progress state streamed from `/api/generate-plan/stream`.
struct PlanGenerationProgress: Equatable {
    let phase: String  // "skeleton", "weeks", "validating", "assembling"
    let message: String
    let current: Int?  // current week (during "weeks" phase)
    let total: Int?  // total weeks
    var fraction: Double {
        guard phase == "weeks", let current, let total, total > 0 else {
            switch phase {
            case "skeleton": return 0.05
            case "validating", "assembling": return 0.95
            default: return 0
            }
        }
        // skeleton=5%, weeks=5-90%, validate=90-100%
        return 0.05 + 0.85 * (Double(current) / Double(total))
    }
}

/// Shown in a sheet so the user confirms before `/api/generate-plan` runs.
struct PlanGenerationDraft: Identifiable, Equatable {
    let id: UUID
    var inputs: PlanInputs
    var summaryLine: String

    init(id: UUID = UUID(), inputs: PlanInputs, summaryLine: String) {
        self.id = id
        self.inputs = inputs
        self.summaryLine = summaryLine
    }
}

struct PlanSaveCelebration: Identifiable, Equatable {
    let planID: String
    let planName: String
    let warnings: [String]
    /// Weeks that used server-side fallback days; user can retry via `/api/regenerate-plan-week`.
    let fallbackWeekNumbers: [Int]
    /// Latest full plan JSON (for week regeneration + persistence).
    let planSnapshotJSON: Data?
    let planInputs: PlanInputs?

    var id: String { planID }
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

// MARK: - Coach routing (quick starters vs typed input)

/// Controls whether a send tries on-device narrow first or goes straight to Mangox Cloud.
enum CoachChatDelivery: Sendable {
    /// Heuristics + on-device classifier (default for typed messages).
    case automatic
    /// Quick starter tap: on-device narrow first, no cloud-biased classification.
    case starter
    /// Skip on-device (e.g. user chose “Go deeper with cloud coach”).
    case cloudOnly

    fileprivate var logLabel: String {
        switch self {
        case .automatic: "automatic"
        case .starter: "starter"
        case .cloudOnly: "cloudOnly"
        }
    }
}

// MARK: - AIService

@Observable @MainActor
final class AIService: AIServiceProtocol {

    /// Injected from `DIContainer` so coach context and recovery heuristics can use WHOOP when linked.
    var whoopDataSource: (any WhoopServiceProtocol)?

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

    /// Shown while the backend streams the coach reply (`/api/chat/stream` extracts `content` text).
    /// Refreshes on a short debounce so the UI does not repaint every token.
    var streamDraftText: String = ""
    /// Short status from SSE before the first content delta (e.g. "Reviewing your training context").
    var streamStatusText: String?
    /// True while the model is emitting a `<think>` block with no visible content yet.
    var streamIsThinking: Bool = false
    /// True while on-device Foundation Models is streaming (bubble chrome + status copy).
    var streamUsesOnDeviceAppearance: Bool = false

    private var streamRawBuffer: String = ""
    private var streamDisplayThrottleTask: Task<Void, Never>?

    /// Persistent on-device narrow-reply session. Reused across turns so the model has multi-turn
    /// memory. Reset to nil on createNewSession / switchToSession / context-window overflow.
    private var onDeviceNarrowSession: LanguageModelSession?

    /// The currently active chat session. Nil means no session selected.
    var currentSessionID: UUID?

    // MARK: Constants

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
    private static func planIntakeClarificationChips() -> [SuggestedAction] {
        [
            SuggestedAction(label: "Target event & date", type: "ask_followup"),
            SuggestedAction(label: "Distance & elevation", type: "ask_followup"),
            SuggestedAction(label: "FTP & hours per week", type: "ask_followup"),
            SuggestedAction(label: "I’m new — guide me step by step", type: "ask_followup"),
        ]
    }

    /// Matches server `used_web_search` only. References alone can be model-invented URLs;
    /// inferring "live search" from `references` caused false "Answer used live web sources" badges.
    private static func resolvedUsedWebSearch(_ response: ChatAPIResponse) -> Bool {
        response.usedWebSearch
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

    var todayMessageCount: Int {
        guard UserDefaults.standard.string(forKey: udDateKey) == todayDateString else { return 0 }
        return UserDefaults.standard.integer(forKey: udCountKey)
    }

    func hasReachedFreeLimit(isPro: Bool) -> Bool {
        if isPro { return false }
        if Self.bypassesDailyCoachMessageLimit { return false }
        return todayMessageCount >= Self.freeDailyLimit
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
        if cfg.kind == .mangoxBackend, !cfg.baseURL.isEmpty {
            return MangoxBackendBaseURLFormatting.normalizedRoot(cfg.baseURL)
        }
        let raw =
            Bundle.main.object(forInfoDictionaryKey: "MangoxAPIBaseURL") as? String
            ?? "https://mangox-backend-production.up.railway.app"
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

    /// AES-256-GCM key from build-time `UserDataKey` Info.plist var.
    /// Nil when not configured (dev builds without the key set).
    private var encryptionKey: SymmetricKey? {
        guard let b64 = Bundle.main.object(forInfoDictionaryKey: "UserDataKey") as? String,
            !b64.isEmpty,
            let keyData = Data(base64Encoded: b64),
            keyData.count == 32
        else { return nil }
        return SymmetricKey(data: keyData)
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

    private func scheduleStreamDraftDisplayFlush() {
        streamDisplayThrottleTask?.cancel()
        streamDisplayThrottleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            let snap = CoachThinkingTagParser.snapshot(streamBuffer: streamRawBuffer)
            streamDraftText = snap.visible
            streamIsThinking =
                snap.visible.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && snap.openDraft != nil
        }
    }

    private func flushStreamDraftToUI() {
        streamDisplayThrottleTask?.cancel()
        streamDisplayThrottleTask = nil
        let snap = CoachThinkingTagParser.snapshot(streamBuffer: streamRawBuffer)
        streamDraftText = snap.visible
        streamIsThinking = false
    }

    private func applyOnDeviceNarrowPartial(_ partial: NarrowCoachReply.PartiallyGenerated) {
        let body = partial.body ?? ""
        let reasoning = partial.reasoning ?? ""
        let bodyTrim = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if bodyTrim.isEmpty {
            streamRawBuffer = ""
            streamDraftText = ""
            streamIsThinking = !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            streamIsThinking = false
            streamStatusText = nil
            streamRawBuffer = body
            scheduleStreamDraftDisplayFlush()
        }
    }

    /// When Mangox Cloud (or plan UI) is mid–multi-turn intake, typed replies must not be hijacked by the on-device narrow path.
    private func resolveCoachDelivery(proposed: CoachChatDelivery) -> CoachChatDelivery {
        if proposed == .cloudOnly { return .cloudOnly }
        if planConfirmationDraft != nil || planSaveCelebration != nil {
            return .cloudOnly
        }
        if proposed != .starter, shouldRouteToCloudAfterStructuredAssistantTurn() {
            return .cloudOnly
        }
        return proposed
    }

    private func shouldRouteToCloudAfterStructuredAssistantTurn() -> Bool {
        guard let assistant = messages.reversed().first(where: { $0.role == .assistant }) else {
            return false
        }
        if assistant.category == "on_device_coach" { return false }
        if assistant.category == "error" { return false }
        let cat = (assistant.category ?? "").lowercased()
        if cat == "clarification" || cat.contains("clarif") { return true }
        if !assistant.followUpBlocks.isEmpty { return true }
        // Mangox Cloud uses `ask_followup` chips for plan intake and other continuations; free-text replies must stay on-thread.
        if assistant.suggestedActions.contains(where: { $0.type.lowercased() == "ask_followup" }) {
            return true
        }
        return false
    }

    /// Streams an on-device narrow reply when routing allows. Returns `true` if handled (no cloud call).
    private func streamOnDeviceNarrowIfEligible(
        userMessage: String,
        modelContext: ModelContext,
        delivery: CoachChatDelivery
    ) async -> Bool {
        if delivery == .cloudOnly {
            logCoachFlow("coachFlow onDevice skip reason=deliveryCloudOnly")
            return false
        }
        guard OnDeviceCoachEngine.isSystemModelAvailable else {
            logCoachFlow(
                "coachFlow onDevice skip reason=systemModelUnavailable systemModel=\(OnDeviceCoachEngine.systemModelAvailabilityLogDescription)"
            )
            return false
        }
        guard SystemLanguageModel.default.supportsLocale(Locale.current) else {
            logCoachFlow("coachFlow onDevice skip reason=unsupportedLocale")
            return false
        }
        if OnDeviceCoachEngine.heuristicCloudRoute(for: userMessage) {
            logCoachFlow("coachFlow onDevice skip reason=heuristicCloudRoute")
            return false
        }

        let factSheet = coachFactSheetText(modelContext: modelContext)
        let route: CoachRouteKind
        if delivery == .starter {
            route = .localNarrowReply
            logCoachFlow("coachFlow onDevice route delivery=starter decision=forcedLocalNarrow")
        } else {
            do {
                if OnDeviceCoachEngine.heuristicLocalPreferred(for: userMessage) {
                    route = .localNarrowReply
                    logCoachFlow("coachFlow onDevice route delivery=automatic decision=heuristicLocalPreferred")
                } else {
                    route = try await OnDeviceCoachEngine.classifyRoute(
                        userMessage: userMessage,
                        factSheet: factSheet
                    )
                    logCoachFlow(
                        "coachFlow onDevice route delivery=automatic classifier=\(route.rawValue)"
                    )
                }
            } catch {
                logger.warning("On-device route classification failed: \(error.localizedDescription)")
                logCoachFlow("coachFlow onDevice skip reason=classifierError")
                return false
            }
            guard route == .localNarrowReply else {
                logCoachFlow(
                    "coachFlow onDevice skip reason=classifierNotLocalNarrow route=\(route.rawValue)"
                )
                return false
            }
        }

        logCoachFlow("coachFlow onDevice streamNarrowReply begin")
        var trainingSnapshot = await coachTrainingSnapshotForOnDeviceNarrow(modelContext: modelContext)
        WorkoutRAGIndex.ensureRecentIndexed(modelContext: modelContext, maxNewEmbeddings: 16)
        if let vectorAppendix = WorkoutRAGRetriever.appendixIfRelevant(
            userMessage: userMessage,
            modelContext: modelContext
        ) {
            trainingSnapshot += "\n\n\(vectorAppendix)"
        }
        if let ragAppendix = WorkoutHistoryKeywordRetriever.appendixIfRelevant(
            userMessage: userMessage,
            modelContext: modelContext
        ) {
            trainingSnapshot += "\n\n\(ragAppendix)"
        }

        // Create the narrow session once per coach conversation; reuse it across turns for multi-turn memory.
        // Tools are bound at creation with a data snapshot from this moment.
        if onDeviceNarrowSession == nil {
            let narrowTools: [any Tool] = [
                MangoxOnDeviceRecentWorkoutsTool(
                    digest: coachWorkoutHistoryDigestForOnDeviceTools(modelContext: modelContext)),
                MangoxOnDeviceRiderExtendedTool(
                    digest: coachRiderExtendedProfileToolPayload(modelContext: modelContext)),
                MangoxOnDeviceFTPHistoryTool(digest: coachFTPTestHistoryToolPayload()),
            ]
            let newSession = OnDeviceCoachEngine.makeNarrowSession(tools: narrowTools)
            newSession.prewarm()
            onDeviceNarrowSession = newSession
            logCoachFlow("coachFlow onDevice narrowSession created prewarm=true")
        }
        let narrowSession = onDeviceNarrowSession!

        streamUsesOnDeviceAppearance = true
        streamStatusText = "On-device coach"
        defer {
            streamUsesOnDeviceAppearance = false
            streamStatusText = nil
        }

        do {
            let reply: NarrowCoachReply? = try await OnDeviceCoachEngine.signpostOnDeviceNarrow {
                try await OnDeviceCoachEngine.streamNarrowReply(
                    userMessage: userMessage,
                    trainingSnapshot: trainingSnapshot,
                    session: narrowSession
                ) { [weak self] partial in
                    await MainActor.run {
                        self?.applyOnDeviceNarrowPartial(partial)
                    }
                }
            }

            flushStreamDraftToUI()
            streamDraftText = ""
            streamRawBuffer = ""
            streamDisplayThrottleTask?.cancel()
            streamDisplayThrottleTask = nil
            streamIsThinking = false

            guard let narrow = reply else {
                logCoachFlow("coachFlow onDevice stream end emptyReply")
                return false
            }
            let body = narrow.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else {
                logCoachFlow("coachFlow onDevice stream end emptyBody")
                return false
            }

            let fu = narrow.followUp.trimmingCharacters(in: .whitespacesAndNewlines)
            let onDeviceChips = narrow.suggestedActions.map {
                SuggestedAction(label: $0.label, type: "on_device_followup")
            }
            let escalateChip: [SuggestedAction] =
                delivery == .starter
                ? [SuggestedAction(label: "Go deeper with cloud coach", type: "escalate_cloud")]
                : []
            let aiMsg = ChatMessage(
                id: UUID(),
                role: .assistant,
                content: body,
                timestamp: .now,
                suggestedActions: onDeviceChips + escalateChip,
                followUpQuestion: fu.isEmpty ? nil : fu,
                followUpBlocks: [],
                thinkingSteps: [],
                category: "on_device_coach",
                tags: ["on_device"],
                references: [],
                usedWebSearch: false,
                feedbackScore: nil,
                confidence: 0.95
            )
            messages.append(aiMsg)
            persistCoachMessage(aiMsg, modelContext: modelContext)
            isLoading = false
            logCoachFlow(
                "coachFlow onDevice success category=on_device_coach escalateChip=\(delivery == .starter ? "yes" : "no") bodyChars=\(body.count)"
            )
            return true
        } catch {
            logger.warning("On-device narrow stream failed: \(error.localizedDescription)")
            MangoxFoundationModelsSupport.logGenerationFailure(error, label: "coach_narrow_aiservice")
            if let gen = error as? LanguageModelSession.GenerationError {
                switch gen {
                case .exceededContextWindowSize:
                    // Reset session so the next turn starts fresh; this message falls to cloud.
                    onDeviceNarrowSession = nil
                    logCoachFlow("coachFlow onDevice stream error exceededContextWindow sessionReset=true")
                case .guardrailViolation:
                    logCoachFlow("coachFlow onDevice stream error guardrailViolation")
                case .unsupportedLanguageOrLocale:
                    logCoachFlow("coachFlow onDevice stream error unsupportedLanguageOrLocale")
                default:
                    logCoachFlow("coachFlow onDevice stream error generation")
                }
            } else if error is LanguageModelSession.ToolCallError {
                logCoachFlow("coachFlow onDevice stream error toolCall")
            } else {
                logCoachFlow("coachFlow onDevice stream error narrowStreamFailed")
            }
            flushStreamDraftToUI()
            streamDraftText = ""
            streamRawBuffer = ""
            streamDisplayThrottleTask?.cancel()
            streamDisplayThrottleTask = nil
            streamIsThinking = false
            return false
        }
    }

    // MARK: - Mangox Cloud coach turn (no new user row)

    private func runMangoxCloudCoachTurn(
        userText: String,
        isPro: Bool,
        modelContext: ModelContext
    ) async {
        streamUsesOnDeviceAppearance = false

        let history = buildHistory()
        let context = buildUserContext(modelContext: modelContext)
        let encryptedContext = encryptUserContext(context)
        let request = ChatRequest(
            message: userText,
            history: history,
            user_context: encryptedContext == nil ? context : nil,
            user_context_encrypted: encryptedContext,
            is_pro: isPro,
            client_local_date: Self.dateFormatter.string(from: .now),
            client_time_zone: TimeZone.current.identifier
        )

        let provider = ChatProviderResolver().resolve()
        let adapter = ChatProviderFactory.makeAdapter(for: provider.kind)

        logCoachFlow(
            "coachFlow cloud runMangoxCloudCoachTurn begin provider=\(provider.kind.rawValue) historyTurns=\(history.count) userChars=\(userText.count)"
        )

        do {
            var finalResponse: ChatAPIResponse?
            var streamFailure: String?

            for try await event in adapter.streamChat(
                request: request, configuration: provider, userID: userID)
            {
                switch event {
                case .status(let s):
                    streamStatusText = s
                case .textDelta(let delta):
                    streamRawBuffer += delta
                    streamStatusText = nil
                    scheduleStreamDraftDisplayFlush()
                case .toolCalls:
                    break
                case .completed(let message):
                    finalResponse = message
                case .failed(let err):
                    streamFailure = err
                }
            }

            flushStreamDraftToUI()
            streamDraftText = ""
            streamRawBuffer = ""
            streamDisplayThrottleTask?.cancel()
            streamDisplayThrottleTask = nil
            streamStatusText = nil
            streamIsThinking = false
            isLoading = false

            if let streamFailure {
                let errMsg = ChatMessage(
                    id: UUID(),
                    role: .assistant,
                    content: streamFailure,
                    timestamp: .now,
                    suggestedActions: [],
                    followUpQuestion: nil,
                    followUpBlocks: [],
                    thinkingSteps: [],
                    category: "error",
                    tags: [],
                    references: [],
                    usedWebSearch: false,
                    feedbackScore: nil,
                    confidence: 0
                )
                messages.append(errMsg)
                persistCoachMessage(errMsg, modelContext: modelContext)
                self.error = streamFailure
                logCoachFlow("coachFlow cloud end streamFailure assistantErrorBubble")
                return
            }

            guard let response = finalResponse else {
                let errMsg = ChatMessage(
                    id: UUID(),
                    role: .assistant,
                    content: "The coach didn't return a complete reply. Please try again.",
                    timestamp: .now,
                    suggestedActions: [],
                    followUpQuestion: nil,
                    followUpBlocks: [],
                    thinkingSteps: [],
                    category: "error",
                    tags: [],
                    references: [],
                    usedWebSearch: false,
                    feedbackScore: nil,
                    confidence: 0
                )
                messages.append(errMsg)
                persistCoachMessage(errMsg, modelContext: modelContext)
                self.error = "Empty response"
                logCoachFlow("coachFlow cloud end emptyFinalResponse")
                return
            }

            let (cleanContent, parsedThinkingBlocks) = CoachThinkingTagParser.finalizedContent(
                response.content)

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

            if blocks.isEmpty,
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

            // For Mangox Cloud: use server-supplied thinkingSteps.
            // For OpenAI-compatible (e.g. local Ollama): capture <redacted_thinking> blocks parsed from content.
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
                category: response.category,
                tags: response.tags,
                references: response.references,
                usedWebSearch: Self.resolvedUsedWebSearch(response),
                feedbackScore: nil,
                confidence: response.confidence
            )
            messages.append(aiMsg)
            persistCoachMessage(aiMsg, modelContext: modelContext)

            logCoachFlow(
                "coachFlow cloud success category=\(response.category) suggestedActions=\(panelActions.count) followUpBlocks=\(blocks.count)"
            )

            await executePendingGeneratePlanToolIfNeeded(from: response, modelContext: modelContext)
        } catch {
            logger.error("runMangoxCloudCoachTurn failed: \(error)")
            logCoachFlow("coachFlow cloud catch transportOrDecodeError")
            streamDraftText = ""
            streamRawBuffer = ""
            streamDisplayThrottleTask?.cancel()
            streamDisplayThrottleTask = nil
            streamStatusText = nil
            streamIsThinking = false
            isLoading = false
            let errMsg = ChatMessage(
                id: UUID(),
                role: .assistant,
                content:
                    "I couldn't connect to the coaching server. Please check your connection and try again.",
                timestamp: .now,
                suggestedActions: [],
                followUpQuestion: nil,
                followUpBlocks: [],
                thinkingSteps: [],
                category: "error",
                tags: [],
                references: [],
                usedWebSearch: false,
                feedbackScore: nil,
                confidence: 0
            )
            messages.append(errMsg)
            persistCoachMessage(errMsg, modelContext: modelContext)
            self.error = error.localizedDescription
        }
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

    /// Replaces the latest on-device starter reply with a full Mangox Cloud turn for the same user message (no extra daily count).
    func escalateStarterOnDeviceToCloud(isPro: Bool, modelContext: ModelContext) async {
        guard !isLoading else {
            logCoachFlow("coachFlow escalate skip reason=alreadyLoading")
            return
        }
        guard let assistantIdx = messages.lastIndex(where: {
            $0.role == .assistant && $0.category == "on_device_coach"
        }) else {
            logCoachFlow("coachFlow escalate skip reason=noOnDeviceAssistant")
            return
        }
        guard assistantIdx > 0 else {
            logCoachFlow("coachFlow escalate skip reason=assistantAtIndexZero")
            return
        }

        var userText: String?
        for j in (0..<assistantIdx).reversed() {
            if messages[j].role == .user {
                userText = messages[j].content
                break
            }
        }
        guard let userText else {
            logCoachFlow("coachFlow escalate skip reason=noPrecedingUserMessage")
            return
        }
        let assistantID = messages[assistantIdx].id

        logCoachFlow(
            "coachFlow escalate begin removeAssistant=\(assistantID.uuidString) userChars=\(userText.count)"
        )
        removeCoachMessage(id: assistantID, modelContext: modelContext)

        isLoading = true
        error = nil
        streamDraftText = ""
        streamRawBuffer = ""
        streamDisplayThrottleTask?.cancel()
        streamDisplayThrottleTask = nil
        streamStatusText = nil
        streamUsesOnDeviceAppearance = false

        await runMangoxCloudCoachTurn(userText: userText, isPro: isPro, modelContext: modelContext)
    }

    // MARK: - Send Chat Message

    func sendMessage(
        _ text: String,
        isPro: Bool,
        modelContext: ModelContext,
        delivery: CoachChatDelivery = .automatic
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logCoachFlow("coachFlow sendMessage abort reason=empty")
            return
        }
        guard !hasReachedFreeLimit(isPro: isPro) else {
            logCoachFlow("coachFlow sendMessage abort reason=dailyLimit isPro=\(isPro)")
            return
        }

        let sessionBefore = currentSessionID
        let effectiveDelivery = resolveCoachDelivery(proposed: delivery)
        if effectiveDelivery != delivery {
            logCoachFlow(
                "coachFlow sendMessage deliveryOverride proposed=\(delivery.logLabel) effective=\(effectiveDelivery.logLabel)"
            )
        }

        logCoachFlow(
            "coachFlow sendMessage start delivery=\(effectiveDelivery.logLabel) isPro=\(isPro) chars=\(trimmed.count) session=\(sessionBefore?.uuidString ?? "nil")"
        )

        incrementDailyCount()

        // Auto-create a session if none exists
        if currentSessionID == nil {
            createNewSession(modelContext: modelContext)
            logCoachFlow(
                "coachFlow sendMessage createdSession id=\(currentSessionID?.uuidString ?? "?")"
            )
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
        streamDraftText = ""
        streamRawBuffer = ""
        streamDisplayThrottleTask?.cancel()
        streamDisplayThrottleTask = nil
        streamStatusText = nil
        streamUsesOnDeviceAppearance = false

        if await streamOnDeviceNarrowIfEligible(
            userMessage: trimmed,
            modelContext: modelContext,
            delivery: effectiveDelivery
        ) {
            logCoachFlow("coachFlow sendMessage path=finishedOnDeviceNarrow")
            return
        }

        streamUsesOnDeviceAppearance = false

        logCoachFlow("coachFlow sendMessage path=cloudAfterOnDeviceSkippedOrFailed")
        await runMangoxCloudCoachTurn(userText: trimmed, isPro: isPro, modelContext: modelContext)
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

        let encrypted = encryptUserContext(buildUserContext(modelContext: modelContext))
        let request = PlanGenerationRequest(
            inputs: inputs,
            is_pro: isPro,
            user_context_encrypted: encrypted,
            client_local_date: Self.dateFormatter.string(from: .now),
            client_time_zone: TimeZone.current.identifier
        )

        // Try streaming endpoint first (progress events); fall back to regular endpoint.
        do {
            return try await generatePlanStreaming(request: request, idempotencyKey: idempotencyKey)
        } catch {
            logger.info(
                "Streaming plan endpoint unavailable, falling back to regular: \(error.localizedDescription)"
            )
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

        let (bytes, response) = try await URLSession.shared.bytes(for: urlReq)

        if let http = response as? HTTPURLResponse {
            // If the streaming endpoint doesn't exist (404) or returns non-SSE, throw to trigger fallback
            guard http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let ct = http.value(forHTTPHeaderField: "Content-Type") ?? ""
            if ct.contains("application/json") {
                // Server returned a cached idempotent response (regular JSON, not SSE)
                var data = Data()
                for try await byte in bytes { data.append(byte) }
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
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let json = String(line.dropFirst(6))
            guard let data = json.data(using: .utf8) else { continue }

            guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = event["type"] as? String
            else { continue }

            switch type {
            case "progress":
                let phase = event["phase"] as? String ?? ""
                let message = event["message"] as? String ?? ""
                let current = event["current"] as? Int
                let total = event["total"] as? Int
                planProgress = PlanGenerationProgress(
                    phase: phase, message: message, current: current, total: total
                )

            case "complete":
                // The complete event contains the full response payload
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
                let errorMsg = event["error"] as? String ?? "Plan generation failed"
                throw NSError(
                    domain: "PlanGeneration", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: errorMsg])

            default:
                break
            }
        }

        throw URLError(.badServerResponse)
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
        planSaveCelebration = PlanSaveCelebration(
            planID: result.plan.id,
            planName: result.plan.name,
            warnings: result.validationWarnings,
            fallbackWeekNumbers: fb,
            planSnapshotJSON: snap,
            planInputs: draft.inputs
        )

        appendLocalAssistantMessage(
            "Your plan **\(result.plan.name)** is saved. You can open it from **My Plans** or tap **Open plan** on the celebration screen.",
            category: "plan_analysis",
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

        let enc = encryptUserContext(buildUserContext(modelContext: modelContext))
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
            planInputs: inputs
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
            confidence: 1.0
        )
        messages.append(msg)
        persistCoachMessage(msg, modelContext: modelContext)
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
            planSource = p.planID == CachedPlan.shared.id ? "builtin" : "ai"
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
                powerDataAvailable: powerOK
            )
        }

        let riderPrefs = RidePreferences.shared
        let riderWeight: Double? = riderPrefs.riderWeightKg > 0 ? riderPrefs.riderWeightKg : nil

        let whoop = whoopDataSource
        let whoopLinked = whoop?.isConnected == true
        let whoopPct = whoopLinked ? whoop?.latestRecoveryScore : nil
        let whoopRhr = whoopLinked ? whoop?.latestRecoveryRestingHR : nil
        let whoopHrv = whoopLinked ? whoop?.latestRecoveryHRV : nil

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
            seasonGoalSummary: MangoxTrainingGoals.summaryLineForCoach,
            planKeyDaySemanticsHint: planSemanticsHint,
            riderWeightKg: riderWeight,
            riderAge: riderPrefs.riderAge,
            whoopLinked: whoopLinked,
            whoopRecoveryPercent: whoopPct,
            whoopRestingHR: whoopRhr,
            whoopHrvMs: whoopHrv,
            whoopMaxHeartRate: whoopLinked ? whoop?.latestMaxHeartRateFromProfile : nil
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
            loadSession(sessionID, modelContext: modelContext)
            return
        }

        let sessionDescriptor = FetchDescriptor<ChatSession>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let sessions = try? modelContext.fetch(sessionDescriptor), let latest = sessions.first {
            currentSessionID = latest.id
            loadSession(latest.id, modelContext: modelContext)
            return
        }

        logger.debug("No sessions found, starting fresh")
    }

    private func loadSession(_ sessionID: UUID, modelContext: ModelContext) {
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
    func createNewSession(modelContext: ModelContext) {
        let session = ChatSession()
        modelContext.insert(session)
        do {
            try modelContext.save()
            currentSessionID = session.id
            messages.removeAll()
            onDeviceNarrowSession = nil
            logger.debug("Created new session \(session.id)")
        } catch {
            logger.error("Failed to create new session: \(error)")
        }
    }

    /// Switches to an existing session by ID.
    func switchToSession(_ sessionID: UUID, modelContext: ModelContext) {
        currentSessionID = sessionID
        onDeviceNarrowSession = nil
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
        if let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages[index].feedbackScore = score
        }
    }

    // MARK: - Regenerate

    func regenerateLastMessage(isPro: Bool, modelContext: ModelContext) async {
        guard let lastUserMsg = messages.last(where: { $0.role == .user }) else {
            logCoachFlow("coachFlow regenerate skip reason=noUserMessage")
            return
        }
        guard !isLoading else {
            logCoachFlow("coachFlow regenerate skip reason=loading")
            return
        }
        if let lastIdx = messages.lastIndex(where: { $0.role == .assistant }) {
            messages.remove(at: lastIdx)
            logCoachFlow("coachFlow regenerate removedLastAssistant then sendMessage automatic")
        } else {
            logCoachFlow("coachFlow regenerate noAssistantRemoved then sendMessage automatic")
        }
        await sendMessage(lastUserMsg.content, isPro: isPro, modelContext: modelContext)
    }

    // MARK: - Context Window

    var contextWindowSize: Int { 12 }
    var currentContextCount: Int {
        min(messages.count, contextWindowSize)
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

    struct QuickPrompt: Identifiable, Equatable {
        var id: String { text }
        let text: String
        let icon: String
    }

    /// Empty-state quick starters plus optional content-tagging topic chips (Foundation Models).
    struct CoachEmptyStartersContent: Equatable {
        let prompts: [QuickPrompt]
        let topicTags: [String]
    }

    /// User-visible copy for plan API failures (avoids raw DecodingError strings in the confirm banner).
    static func userFacingPlanGenerationError(_ error: Error) -> String {
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
        var prompts: [QuickPrompt] = []
        let status = recoveryStatus(modelContext: modelContext)
        if let whoop = whoopDataSource, whoop.isConnected, let pct = whoop.latestRecoveryScore, pct < 34 {
            prompts.append(
                QuickPrompt(
                    text: "How should I train with my WHOOP recovery today?",
                    icon: "waveform.path.ecg"
                )
            )
        }
        if status != .fresh {
            prompts.append(QuickPrompt(text: "Analyze my last ride", icon: "chart.bar.fill"))
        }
        let pd = FetchDescriptor<TrainingPlanProgress>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        if let p = try? modelContext.fetch(pd), !p.isEmpty {
            prompts.append(QuickPrompt(text: "How's my training load?", icon: "heart.fill"))
            prompts.append(
                QuickPrompt(text: "What's my workout today?", icon: "calendar.badge.clock"))
        }
        prompts.append(QuickPrompt(text: "How's my FTP trend?", icon: "bolt.fill"))
        if prompts.isEmpty {
            prompts.append(
                QuickPrompt(text: "What should I do today?", icon: "figure.outdoor.cycle"))
        }
        return Array(prompts.prefix(4))
    }
}
