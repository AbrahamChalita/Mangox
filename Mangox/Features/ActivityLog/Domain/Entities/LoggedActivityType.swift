// Features/ActivityLog/Domain/Entities/LoggedActivityType.swift
import Foundation

enum LoggedActivityType: String, Codable, Sendable, CaseIterable, Hashable {
    case run
    case walk
    case hike
    case strengthDumbbells
    case strengthBarbell
    case strengthBodyweight
    case strengthMachine
    case yoga
    case pilates
    case mobility
    case swim
    case rowing
    case climbing
    case hiit
    case crossfit
    case boxing
    case martialArts
    case soccer
    case basketball
    case tennis
    case padel
    case other

    var displayName: String {
        switch self {
        case .run: "Run"
        case .walk: "Walk"
        case .hike: "Hike"
        case .strengthDumbbells: "Dumbbells"
        case .strengthBarbell: "Barbell"
        case .strengthBodyweight: "Bodyweight"
        case .strengthMachine: "Machine"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .mobility: "Mobility"
        case .swim: "Swim"
        case .rowing: "Rowing"
        case .climbing: "Climbing"
        case .hiit: "HIIT"
        case .crossfit: "CrossFit"
        case .boxing: "Boxing"
        case .martialArts: "Martial Arts"
        case .soccer: "Soccer"
        case .basketball: "Basketball"
        case .tennis: "Tennis"
        case .padel: "Padel"
        case .other: "Other"
        }
    }

    var sfSymbol: String {
        switch self {
        case .run: "figure.run"
        case .walk: "figure.walk"
        case .hike: "figure.hiking"
        case .strengthDumbbells, .strengthBarbell, .strengthMachine: "figure.strengthtraining.traditional"
        case .strengthBodyweight: "figure.strengthtraining.functional"
        case .yoga: "figure.yoga"
        case .pilates: "figure.pilates"
        case .mobility: "figure.flexibility"
        case .swim: "figure.pool.swim"
        case .rowing: "figure.rower"
        case .climbing: "figure.climbing"
        case .hiit, .crossfit: "figure.highintensity.intervaltraining"
        case .boxing: "figure.boxing"
        case .martialArts: "figure.martial.arts"
        case .soccer: "figure.soccer"
        case .basketball: "figure.basketball"
        case .tennis: "figure.tennis"
        case .padel: "figure.badminton"
        case .other: "figure.mixed.cardio"
        }
    }

    var isStrength: Bool {
        switch self {
        case .strengthDumbbells, .strengthBarbell, .strengthBodyweight, .strengthMachine, .crossfit: true
        default: false
        }
    }

    var isCardioDistance: Bool {
        switch self {
        case .run, .walk, .hike, .swim, .rowing: true
        default: false
        }
    }
}
