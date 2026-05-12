// Features/ActivityLog/Domain/Entities/LoggedActivityIntensity.swift
import Foundation

enum LoggedActivityIntensity: String, Codable, Sendable, CaseIterable, Hashable {
    case easy
    case moderate
    case hard
    case max

    var displayName: String {
        switch self {
        case .easy: "Easy"
        case .moderate: "Moderate"
        case .hard: "Hard"
        case .max: "Max"
        }
    }
}
