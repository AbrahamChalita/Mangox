import Foundation

/// User-tunable layout and export options for the ride summary Instagram Story card.
struct InstagramStoryCardOptions: Equatable, Codable, Sendable {
    enum Accent: String, Codable, CaseIterable, Identifiable, Sendable {
        case dominantZone
        case brandMango

        var id: String { rawValue }

        var pickerTitle: String {
            switch self {
            case .dominantZone: return "Power zone"
            case .brandMango: return "Mangox mango"
            }
        }
    }

    var accent: Accent
    /// Background gradient + stats as a movable rounded sticker in Instagram.
    var layeredShare: Bool
    var showPowerHRChart: Bool
    var showHeartRateLineOnChart: Bool
    var showMetaLine: Bool
    var showFooterBranding: Bool
    var showElevation: Bool
    var showNPAndTSS: Bool

    static let `default` = InstagramStoryCardOptions(
        accent: .dominantZone,
        layeredShare: false,
        showPowerHRChart: true,
        showHeartRateLineOnChart: true,
        showMetaLine: true,
        showFooterBranding: true,
        showElevation: true,
        showNPAndTSS: true
    )
}

enum InstagramStoryStudioPreferences {
    private static let key = "instagramStoryStudioOptions.v1"

    static func load() -> InstagramStoryCardOptions {
        guard let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode(InstagramStoryCardOptions.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    static func save(_ options: InstagramStoryCardOptions) {
        guard let data = try? JSONEncoder().encode(options) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
