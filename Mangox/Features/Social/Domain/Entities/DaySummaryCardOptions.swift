// Features/Social/Domain/Entities/DaySummaryCardOptions.swift
import Foundation

struct DaySummaryCardOptions: Equatable, Codable, Sendable {
    enum Template: String, Codable, CaseIterable, Identifiable, Sendable {
        case dayBriefing
        case dayHeroStack
        case dayMosaic
        case dayTimelineRibbon
        case dayMinimalist
        case dayPosterGrid
        case dayOrbit
        case dayScoreboard

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .dayBriefing: "Briefing"
            case .dayHeroStack: "Hero Stack"
            case .dayMosaic: "Mosaic"
            case .dayTimelineRibbon: "Timeline"
            case .dayMinimalist: "Minimalist"
            case .dayPosterGrid: "Poster Grid"
            case .dayOrbit: "Orbit"
            case .dayScoreboard: "Scoreboard"
            }
        }

    }

    enum StatSlot: String, Codable, CaseIterable, Identifiable, Sendable {
        case totalTime, totalDistance, totalElevation, totalKJ, totalTSS, activityCount
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .totalTime: "Total Time"
            case .totalDistance: "Distance"
            case .totalElevation: "Elevation"
            case .totalKJ: "Energy (kJ)"
            case .totalTSS: "TSS"
            case .activityCount: "Activities"
            }
        }
    }

    enum BackgroundSource: String, Codable, CaseIterable, Identifiable, Sendable {
        case gradient
        case photo
        var id: String { rawValue }
        var pickerTitle: String {
            switch self {
            case .gradient: "Gradient"
            case .photo: "Photo"
            }
        }
    }

    var template: Template = .dayBriefing
    var statSlots: [StatSlot] = [.totalTime, .totalDistance, .totalKJ]
    var showBrandBadge = true
    var privacyHidePower = false
    var privacyHideHeartRate = false
    var privacyHideStrengthLoad = false
    var backgroundGradientIndex = 0
    var backgroundSource: BackgroundSource = .gradient

    static let `default` = DaySummaryCardOptions()
}
