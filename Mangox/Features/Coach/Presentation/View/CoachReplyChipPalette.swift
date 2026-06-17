import SwiftUI

enum CoachSuggestedActionNavigation {
    static func isNavigation(_ type: String) -> Bool {
        let k = type.lowercased()
        return k.hasPrefix("navigate") || k.contains("open_my_plans") || k == "start_workout"
    }
}

// MARK: - Suggested reply chip colors

enum CoachReplyChipPalette {
    case neutral
    case mangoWash
    case cyanWash
    case indigoWash

    static func forAction(_ action: SuggestedAction) -> CoachReplyChipPalette {
        let k = action.type.lowercased()
        if CoachSuggestedActionNavigation.isNavigation(k) { return .indigoWash }
        if k == "escalate_cloud" { return .mangoWash }
        if k == "on_device_followup" { return .cyanWash }
        return .neutral
    }

    func leadingIconTint(isEnabled: Bool) -> Color {
        guard isEnabled else { return .white.opacity(0.22) }
        switch self {
        case .neutral: return AppColor.mango.opacity(0.92)
        case .mangoWash: return AppColor.mango.opacity(0.95)
        case .cyanWash: return Color.cyan.opacity(0.88)
        case .indigoWash: return Color.indigo.opacity(0.85)
        }
    }

    func gradientFill(isEnabled: Bool) -> LinearGradient {
        let top: Color
        let bottom: Color
        switch self {
        case .neutral:
            top = Color.white.opacity(isEnabled ? 0.1 : 0.04)
            bottom = Color.white.opacity(isEnabled ? 0.06 : 0.03)
        case .mangoWash:
            top = AppColor.mango.opacity(isEnabled ? 0.2 : 0.07)
            bottom = Color.white.opacity(isEnabled ? 0.07 : 0.04)
        case .cyanWash:
            top = Color.cyan.opacity(isEnabled ? 0.16 : 0.06)
            bottom = Color.white.opacity(isEnabled ? 0.06 : 0.03)
        case .indigoWash:
            top = Color.indigo.opacity(isEnabled ? 0.22 : 0.08)
            bottom = Color.white.opacity(isEnabled ? 0.07 : 0.04)
        }
        return LinearGradient(
            colors: [top, bottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func strokeColor(isEnabled: Bool) -> Color {
        switch self {
        case .neutral: return Color.white.opacity(isEnabled ? 0.12 : 0.06)
        case .mangoWash: return AppColor.mango.opacity(isEnabled ? 0.42 : 0.14)
        case .cyanWash: return Color.cyan.opacity(isEnabled ? 0.38 : 0.12)
        case .indigoWash: return Color.indigo.opacity(isEnabled ? 0.4 : 0.14)
        }
    }

    func trailingOrbTint(isEnabled: Bool) -> Color {
        guard isEnabled else { return .white.opacity(0.2) }
        switch self {
        case .neutral: return AppColor.mango.opacity(0.95)
        case .mangoWash: return AppColor.mango.opacity(0.98)
        case .cyanWash: return Color.cyan.opacity(0.92)
        case .indigoWash: return Color.indigo.opacity(0.9)
        }
    }
}
