import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - App Color Palette

/// Centralized color constants used throughout the app.
enum AppColor {
    /// Primary brand accent — mango yellow-orange.
    static let mango = Color(red: 255/255, green: 186/255, blue: 50/255)

    /// Semantic green for success states (connected, in-zone, checkmarks).
    static let success = Color(red: 79/255, green: 195/255, blue: 161/255)

    static let yellow = Color(red: 240/255, green: 195/255, blue: 78/255)
    static let orange = Color(red: 240/255, green: 122/255, blue: 58/255)
    static let red = Color(red: 232/255, green: 68/255, blue: 90/255)
    static let blue = Color(red: 107/255, green: 127/255, blue: 212/255)
    static let strava = Color(red: 252/255, green: 82/255, blue: 0)
    static let stravaEnd = Color(red: 232/255, green: 58/255, blue: 0)
    /// WHOOP brand accent (approximate; UI only).
    static let whoop = Color(red: 0/255, green: 158/255, blue: 127/255)
    static let discord = Color(red: 88/255, green: 101/255, blue: 242/255)
    static let bg = Color(red: 0.03, green: 0.04, blue: 0.06)

    /// Heart-rate accent (slightly different from the zone red).
    static let heartRate = Color(red: 245/255, green: 96/255, blue: 108/255)
}

// MARK: - Training Zone Target Color

extension TrainingZoneTarget {
    /// The accent color for this training zone target.
    /// Eliminates the duplicated 15-case `zoneTargetColor(_ zone:)` switch
    /// in WorkoutRowView, DashboardView, and TrainingPlanView.
    var color: Color {
        switch self {
        case .z1:    return AppColor.blue
        case .z2:    return AppColor.success
        case .z3:    return AppColor.yellow
        case .z4:    return AppColor.orange
        case .z5:    return AppColor.red
        case .z1z2:  return AppColor.success
        case .z2z3:  return Color(red: 160/255, green: 195/255, blue: 120/255)
        case .z3z4:  return Color(red: 240/255, green: 158/255, blue: 68/255)
        case .z3z5:  return Color(red: 236/255, green: 130/255, blue: 84/255)
        case .z4z5:  return Color(red: 236/255, green: 95/255, blue: 74/255)
        case .mixed: return Color.white.opacity(0.5)
        case .all:   return AppColor.yellow
        case .rest:  return AppColor.blue.opacity(0.4)
        case .none:  return Color.white.opacity(0.2)
        }
    }
}

// MARK: - Shared Formatting Helpers

/// Centralized formatting utilities.
/// Replaces the duplicated `formatDuration`, `formatSeconds`, etc. helpers
/// in SummaryView, WorkoutRowView, and WorkoutManager.
enum AppFormat {

    // MARK: - Unit Conversion

    /// Convert meters to display distance (km or miles).
    static func distance(_ meters: Double, imperial: Bool) -> (value: Double, unit: String) {
        if imperial {
            return (meters / 1609.344, "mi")
        }
        return (meters / 1000, "km")
    }

    /// Convert km/h to display speed (km/h or mph).
    static func speed(_ kmh: Double, imperial: Bool) -> (value: Double, unit: String) {
        if imperial {
            return (kmh * 0.621371, "mph")
        }
        return (kmh, "km/h")
    }

    /// Convert meters elevation to display (m or ft).
    static func elevation(_ meters: Double, imperial: Bool) -> (value: Double, unit: String) {
        if imperial {
            return (meters * 3.28084, "ft")
        }
        return (meters, "m")
    }

    /// Formats a distance string ready for display.
    static func distanceString(_ meters: Double, imperial: Bool, decimals: Int = 1) -> String {
        let d = distance(meters, imperial: imperial)
        return String(format: "%.\(decimals)f", d.value)
    }

    /// Formats a speed string ready for display.
    static func speedString(_ kmh: Double, imperial: Bool) -> String {
        let s = speed(kmh, imperial: imperial)
        return String(format: "%.1f", s.value)
    }

    /// The distance unit label ("km" or "mi").
    static func distanceUnit(imperial: Bool) -> String {
        imperial ? "mi" : "km"
    }

    /// The speed unit label ("km/h" or "mph").
    static func speedUnit(imperial: Bool) -> String {
        imperial ? "mph" : "km/h"
    }

    /// The elevation unit label ("m" or "ft").
    static func elevationUnit(imperial: Bool) -> String {
        imperial ? "ft" : "m"
    }

    /// Formats an elevation string ready for display.
    static func elevationString(_ meters: Double, imperial: Bool) -> String {
        let e = elevation(meters, imperial: imperial)
        return String(format: "%.0f", e.value)
    }

    // MARK: - Duration

    /// Formats a duration in seconds as `H:MM:SS` or `MM:SS`.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    /// Formats an integer second count as `M:SS` or `H:MM:SS`.
    static func seconds(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let m = total / 60
        let s = total % 60
        if m >= 60 {
            return String(format: "%d:%02d:%02d", m / 60, m % 60, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Human-readable dates in text

    /// Replaces ISO-8601 date/time snippets (e.g. from cached on-device insight copy) with locale-aware formatting.
    static func naturalizeISODateSnippets(in string: String) -> String {
        guard !string.isEmpty else { return string }

        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoStd = ISO8601DateFormatter()
        isoStd.formatOptions = [.withInternetDateTime]
        let isoDay = ISO8601DateFormatter()
        isoDay.formatOptions = [.withFullDate]

        func parse(_ sub: String) -> Date? {
            if let d = isoFrac.date(from: sub) { return d }
            if let d = isoStd.date(from: sub) { return d }
            return isoDay.date(from: sub)
        }

        func format(_ date: Date, dateOnly: Bool) -> String {
            if dateOnly {
                return date.formatted(date: .abbreviated, time: .omitted)
            }
            return date.formatted(date: .abbreviated, time: .shortened)
        }

        // Datetime first, then bare calendar dates (not followed by `T` or more digits).
        let pattern =
            #"(?<![0-9])(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.[0-9]{1,9})?)?(?:Z|[+-]\d{2}(?::)?\d{2})?)|(?<![0-9])(\d{4}-\d{2}-\d{2})(?![0-9T])"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return string
        }

        var result = string
        let nsFull = result as NSString
        let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsFull.length))

        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let sub = String(result[range])
            let dateOnly = !sub.contains("T")
            guard let date = parse(sub) else { continue }
            result.replaceSubrange(range, with: format(date, dateOnly: dateOnly))
        }
        return result
    }
}

// MARK: - Semantic Opacity Scale

/// Canonical opacity levels. Use these instead of ad-hoc `.white.opacity(x)`.
enum AppOpacity {
    // Backgrounds
    static let cardBg: Double    = 0.04   // standard card background
    static let pillBg: Double    = 0.03   // nested pill/chip inside a card
    static let subtleBg: Double  = 0.02   // very subtle section tint
    // Borders
    static let cardBorder: Double  = 0.08 // standard card stroke
    static let divider: Double     = 0.06 // dividers and separators
    // Text hierarchy
    static let textPrimary: Double   = 0.90
    static let textSecondary: Double = 0.60
    static let textTertiary: Double  = 0.35
    static let textQuaternary: Double = 0.25
}

// MARK: - Card Style Modifier

/// Unified visual treatment for all content cards:
/// `Color.white.opacity(0.04)` background + matching stroke + clip.
/// Apply after adding internal padding: `.padding(...).cardStyle()`.
struct CardStyle: ViewModifier {
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(AppOpacity.cardBg))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(AppOpacity.cardBorder), lineWidth: 1)
            )
    }
}

extension View {
    /// Applies the standard Mangox card visual treatment.
    func cardStyle(cornerRadius: CGFloat = 14) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius))
    }

    /// Applies `accessibilityHint` only when `hint` is non-empty (avoids VoiceOver noise).
    @ViewBuilder
    func accessibilityHintIf(_ hint: String) -> some View {
        if hint.isEmpty {
            self
        } else {
            self.accessibilityHint(hint)
        }
    }

    /// Adds a **Done** control above the keyboard. Number pads have no
    /// return key; this dismisses the keyboard via `resignFirstResponder`.
    func keyboardDismissToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    #if canImport(UIKit)
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                    #endif
                }
                .font(.system(size: 17, weight: .semibold))
            }
        }
    }
}

// MARK: - Primary Button Style

/// Press-to-scale feedback for tappable buttons. Applies subtle scale + opacity.
struct MangoxPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Color Hex Initializer

extension Color {
    /// Creates a `Color` from a CSS-style hex string (`#RGB`, `#RRGGBB`, or `#AARRGGBB`).
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a: UInt64, r: UInt64, g: UInt64, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Cached Training Plan

/// Avoids calling `WeddingWeightLossPlan.create()` in computed properties
/// (which rebuilds the full 8-week plan struct on every SwiftUI body evaluation).
/// Access via `CachedPlan.shared` instead.
enum CachedPlan {
    static let shared: TrainingPlan = WeddingWeightLossPlan.create()
}
