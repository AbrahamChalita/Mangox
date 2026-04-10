// Features/Coach/Domain/Entities/CoachPlanGenerationModels.swift
import Foundation

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
    let phase: String
    let message: String
    let current: Int?
    let total: Int?

    var fraction: Double {
        guard phase == "weeks", let current, let total, total > 0 else {
            switch phase {
            case "skeleton": return 0.05
            case "validating", "assembling": return 0.95
            default: return 0
            }
        }
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

struct AIGeneratedPlanDraft: Sendable {
    let id: String
    let userPrompt: String
    let regenerationInputsJSON: Data?
}
