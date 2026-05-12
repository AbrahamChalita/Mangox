// Features/ActivityLog/Presentation/View/LoggedActivityIcon.swift
import SwiftUI

enum LoggedActivityIcon {
    static func symbol(for type: LoggedActivityType) -> String {
        type.sfSymbol
    }

    static func color(for type: LoggedActivityType) -> Color {
        switch type {
        case .run, .walk, .hike: AppColor.mango
        case .strengthDumbbells, .strengthBarbell, .strengthBodyweight, .strengthMachine, .crossfit:
            AppColor.orange
        case .yoga, .pilates, .mobility: Color(hex: "#A78BFA")
        case .swim, .rowing: AppColor.blue
        case .climbing: AppColor.success
        case .hiit: AppColor.red
        case .boxing, .martialArts: AppColor.orange
        case .soccer, .basketball, .tennis, .padel: AppColor.yellow
        case .other: AppColor.fg2
        }
    }

    static func sourceBadge(for source: LoggedActivitySource) -> (text: String, color: Color) {
        switch source {
        case .manual: ("Manual", AppColor.fg3)
        case .whoop: ("WHOOP", AppColor.whoop)
        case .strava: ("Strava", AppColor.strava)
        }
    }
}
