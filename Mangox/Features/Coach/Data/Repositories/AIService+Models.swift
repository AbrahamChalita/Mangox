import Foundation

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

struct UserContext: Encodable, Sendable {
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
    /// Localized readiness label computed from recent rides / WHOOP (for fact-sheet rendering).
    let recoveryStatusLabel: String
    /// Whether FitnessTracker PMC history is loaded.
    let fitnessTrackerLoaded: Bool
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
    /// Sleep performance percentage (0–100) from the latest scored WHOOP sleep.
    let whoopSleepPerformancePercent: Double?
    /// Total time in bed for the latest scored WHOOP sleep, in hours.
    let whoopSleepHours: Double?
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

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ftp, forKey: .ftp)
        try c.encode(maxHR, forKey: .maxHR)
        try c.encode(restingHR, forKey: .restingHR)
        try c.encode(recentWorkoutsCount, forKey: .recentWorkoutsCount)
        try c.encodeIfPresent(activePlanName, forKey: .activePlanName)
        try c.encodeIfPresent(activePlanProgress, forKey: .activePlanProgress)
        try c.encodeIfPresent(activePlanSource, forKey: .activePlanSource)
        try c.encode(weekActualTss, forKey: .weekActualTss)
        try c.encode(adaptiveErgPercent, forKey: .adaptiveErgPercent)
        try c.encodeIfPresent(ftpHistory, forKey: .ftpHistory)
        try c.encodeIfPresent(lastRide, forKey: .lastRide)
        try c.encodeIfPresent(seasonGoalSummary, forKey: .seasonGoalSummary)
        try c.encodeIfPresent(planKeyDaySemanticsHint, forKey: .planKeyDaySemanticsHint)
        try c.encodeIfPresent(recentRideDigest, forKey: .recentRideDigest)
        try c.encodeIfPresent(lastRideAerobicDecoupling, forKey: .lastRideAerobicDecoupling)
        try c.encodeIfPresent(riderWeightKg, forKey: .riderWeightKg)
        try c.encodeIfPresent(riderAge, forKey: .riderAge)
        try c.encode(recoveryStatusLabel, forKey: .recoveryStatusLabel)
        try c.encode(fitnessTrackerLoaded, forKey: .fitnessTrackerLoaded)
        try c.encode(whoopLinked, forKey: .whoopLinked)
        try c.encodeIfPresent(whoopRecoveryPercent, forKey: .whoopRecoveryPercent)
        try c.encodeIfPresent(whoopRestingHR, forKey: .whoopRestingHR)
        try c.encodeIfPresent(whoopHrvMs, forKey: .whoopHrvMs)
        try c.encodeIfPresent(whoopMaxHeartRate, forKey: .whoopMaxHeartRate)
        try c.encodeIfPresent(whoopSleepPerformancePercent, forKey: .whoopSleepPerformancePercent)
        try c.encodeIfPresent(whoopSleepHours, forKey: .whoopSleepHours)
        try c.encodeIfPresent(currentCtl, forKey: .currentCtl)
        try c.encodeIfPresent(currentAtl, forKey: .currentAtl)
        try c.encodeIfPresent(currentTsb, forKey: .currentTsb)
        try c.encodeIfPresent(pmcTrendSummary, forKey: .pmcTrendSummary)
        try c.encodeIfPresent(aerobicDecouplingTrend, forKey: .aerobicDecouplingTrend)
        try c.encodeIfPresent(powerCurveSummary, forKey: .powerCurveSummary)
        try c.encodeIfPresent(criticalPowerSummary, forKey: .criticalPowerSummary)
    }

    private enum CodingKeys: String, CodingKey {
        case ftp, maxHR, restingHR, recentWorkoutsCount
        case activePlanName, activePlanProgress, activePlanSource, weekActualTss
        case adaptiveErgPercent, ftpHistory, lastRide, seasonGoalSummary
        case planKeyDaySemanticsHint, recentRideDigest, lastRideAerobicDecoupling
        case riderWeightKg, riderAge, recoveryStatusLabel, fitnessTrackerLoaded
        case whoopLinked, whoopRecoveryPercent, whoopRestingHR, whoopHrvMs
        case whoopMaxHeartRate, whoopSleepPerformancePercent, whoopSleepHours
        case currentCtl, currentAtl, currentTsb, pmcTrendSummary
        case aerobicDecouplingTrend, powerCurveSummary, criticalPowerSummary
    }
}

struct LastRideContext: Encodable, Sendable {
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

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encode(durationMinutes, forKey: .durationMinutes)
        try c.encode(distanceKm, forKey: .distanceKm)
        try c.encode(avgPower, forKey: .avgPower)
        try c.encode(maxPower, forKey: .maxPower)
        try c.encode(avgHR, forKey: .avgHR)
        try c.encode(avgSpeed, forKey: .avgSpeed)
        try c.encode(elevationGain, forKey: .elevationGain)
        try c.encode(normalizedPower, forKey: .normalizedPower)
        try c.encode(tss, forKey: .tss)
        try c.encode(intensityFactor, forKey: .intensityFactor)
        try c.encode(summary, forKey: .summary)
        try c.encode(powerDataAvailable, forKey: .powerDataAvailable)
        try c.encodeIfPresent(aerobicDecouplingPercent, forKey: .aerobicDecouplingPercent)
        try c.encodeIfPresent(aerobicDecouplingStatus, forKey: .aerobicDecouplingStatus)
    }

    private enum CodingKeys: String, CodingKey {
        case date, durationMinutes, distanceKm, avgPower, maxPower, avgHR, avgSpeed
        case elevationGain, normalizedPower, tss, intensityFactor, summary
        case powerDataAvailable, aerobicDecouplingPercent, aerobicDecouplingStatus
    }
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
struct GeneratePlanToolDetail: Decodable {
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

struct GenerateWorkoutToolDetail: Decodable {
    let goal: String
    let duration_minutes: Int?
    let experience: String?
    let preferred_intensity: String?
    let environment: String?
    let planned_date: String?
    let plan_context: String?
}

/// Normalizes model-supplied dates to `yyyy-MM-dd` for `/api/generate-plan` and UI.
enum PlanEventDateNormalization {
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
    case searchStarted
    case searchCompleted
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
