// Features/Outdoor/Domain/Entities/RideNudgeModels.swift
import Foundation

// MARK: - Spacing preset

/// Controls minimum time between on-bike training tips (global cooldown multiplier).
enum RideNudgeSpacing: String, CaseIterable, Codable {
    case rare
    case normal
    case more

    var label: String {
        switch self {
        case .rare: return "Rare"
        case .normal: return "Normal"
        case .more: return "More"
        }
    }

    /// Multiplier applied to base global cooldown (seconds).
    var globalCooldownMultiplier: Double {
        switch self {
        case .rare: return 1.45
        case .normal: return 1.0
        case .more: return 0.72
        }
    }
}

// MARK: - Category (cooldown grouping)

enum RideNudgeCategory: String, CaseIterable, Codable {
    case fueling
    case cadence
    case posture
    case recovery
    case heatFluids

    var label: String {
        switch self {
        case .fueling: return "Fueling"
        case .cadence: return "Cadence"
        case .posture: return "Posture"
        case .recovery: return "Recovery"
        case .heatFluids: return "Heat & Fluids"
        }
    }

    static var essentials: Set<RideNudgeCategory> {
        [.fueling, .cadence]
    }
}

// MARK: - Display payload

struct RideNudgeDisplay: Equatable {
    let id: String
    let category: RideNudgeCategory
    /// Short label (e.g. “Training tip”).
    let headline: String
    let body: String
    let audioScript: String
}

// MARK: - Evaluation context (built by dashboard / outdoor host)

struct RideNudgeContext: Sendable {
    var now: Date
    var isRecording: Bool
    var elapsedSeconds: Int
    var displayPower: Int
    /// Last completed second’s mean cadence (rpm).
    var displayCadenceRpm: Double
    var zoneId: Int
    var lowCadenceThreshold: Int
    /// Consecutive seconds cadence has been below threshold while pedaling (mirrors warning counter).
    var lowCadenceStreakSeconds: Int
    var showLowCadenceHardWarning: Bool
    var activeDistanceMeters: Double
    var distanceGoalKm: Double?
    var distanceGoalProgress: Double?
    var guidedIsActive: Bool
    var guidedStepIsRecovery: Bool
    /// Seconds since start of current guided step; `nil` if not in a step.
    var guidedSecondsIntoStep: Int?
    /// True when guided step targets hard zones (fueling tips suppressed).
    var guidedStepIsHardIntensity: Bool
    /// Skip tips for a few seconds after milestone / goal toasts.
    var suppressUntil: Date?
}
