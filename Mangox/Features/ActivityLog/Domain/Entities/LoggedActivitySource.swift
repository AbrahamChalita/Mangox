// Features/ActivityLog/Domain/Entities/LoggedActivitySource.swift
import Foundation

enum LoggedActivitySource: String, Codable, Sendable, CaseIterable, Hashable {
    case manual
    case whoop
    case strava

    var displayName: String {
        switch self {
        case .manual: "Manual"
        case .whoop: "WHOOP"
        case .strava: "Strava"
        }
    }
}
