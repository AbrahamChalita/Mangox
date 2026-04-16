// Features/Social/Domain/Entities/InstagramStoryCardOptions.swift
import Foundation

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

        var colorKey: String {
            switch self {
            case .dominantZone: return "orange"
            case .brandMango: return "mango"
            }
        }
    }

    enum BackgroundSource: String, Codable, CaseIterable, Identifiable, Sendable {
        case preset
        case custom
        case none

        var id: String { rawValue }

        var pickerTitle: String {
            switch self {
            case .preset: return "Preset"
            case .custom: return "My Photo"
            case .none: return "Dark"
            }
        }
    }

    enum StoryPreset: String, Codable, CaseIterable, Identifiable, Sendable {
        case sunsetMango
        case nightRide
        case dawnGradient
        case mountainSilhouette
        case roadTexture
        case darkAtmospheric

        var id: String { rawValue }

        var assetName: String {
            switch self {
            case .sunsetMango: return "StoryBG_SunsetMango"
            case .nightRide: return "StoryBG_NightRide"
            case .dawnGradient: return "StoryBG_DawnGradient"
            case .mountainSilhouette: return "StoryBG_MountainSilhouette"
            case .roadTexture: return "StoryBG_RoadTexture"
            case .darkAtmospheric: return "StoryBG_DarkAtmospheric"
            }
        }

        var displayName: String {
            switch self {
            case .sunsetMango: return "Sunset Mango"
            case .nightRide: return "Night Ride"
            case .dawnGradient: return "Dawn"
            case .mountainSilhouette: return "Mountain"
            case .roadTexture: return "Road"
            case .darkAtmospheric: return "Atmospheric"
            }
        }
    }

    var accent: Accent
    var backgroundSource: BackgroundSource
    var selectedPreset: StoryPreset
    var layeredShare: Bool
    var showHeader: Bool
    var showHeroTitle: Bool
    var showRouteName: Bool
    var showTrainingLoad: Bool
    var showSummaryCards: Bool
    var showBottomStrip: Bool
    /// Third quick-stat tile: `true` = elevation (m), `false` = normalized power (W).
    var showElevation: Bool
    var showBrandBadge: Bool
    /// Per-metric visibility in the four-up quick stats row (when `showBottomStrip` is on).
    var showQuickStatHeartRate: Bool
    var showQuickStatCadence: Bool
    var showQuickStatThird: Bool
    var showQuickStatSpeed: Bool
    /// When WHOOP is linked and recovery/strain values are passed in at render time, show a line on the training load card.
    var showWhoopReadiness: Bool

    static let `default` = InstagramStoryCardOptions(
        accent: .dominantZone,
        backgroundSource: .none,
        selectedPreset: .darkAtmospheric,
        layeredShare: false,
        showHeader: true,
        showHeroTitle: true,
        showRouteName: true,
        showTrainingLoad: true,
        showSummaryCards: true,
        showBottomStrip: true,
        showElevation: true,
        showBrandBadge: true,
        showQuickStatHeartRate: true,
        showQuickStatCadence: true,
        showQuickStatThird: true,
        showQuickStatSpeed: true,
        showWhoopReadiness: true
    )
}

enum InstagramStoryStudioPreferences {
    private static let key = "instagramStoryStudioOptions.v5"

    static func load() -> InstagramStoryCardOptions {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(InstagramStoryCardOptions.self, from: data)
        else { return .default }
        return decoded
    }

    static func save(_ options: InstagramStoryCardOptions) {
        guard let data = try? JSONEncoder().encode(options) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}