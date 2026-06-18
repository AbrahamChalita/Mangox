// Features/Social/Domain/Entities/InstagramStoryCardOptions.swift
import Foundation

struct InstagramStoryCardOptions: Equatable, Codable, Sendable {
    enum Template: String, Codable, CaseIterable, Identifiable, Sendable {
        case cleanStats
        case bigAchievement
        case routeDay
        case indoorPower
        case raceEffort
        case recoveryRide
        case prFlex
        case minimalDark
        case photoFirst

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .cleanStats: return "Clean Stats"
            case .bigAchievement: return "Achievement"
            case .routeDay: return "Route Day"
            case .indoorPower: return "Indoor Power"
            case .raceEffort: return "Race Effort"
            case .recoveryRide: return "Recovery"
            case .prFlex: return "PR Flex"
            case .minimalDark: return "Minimal"
            case .photoFirst: return "Photo First"
            }
        }

        var shortDescription: String {
            switch self {
            case .cleanStats: return "Balanced ride recap"
            case .bigAchievement: return "Lead with the headline"
            case .routeDay: return "Outdoor route energy"
            case .indoorPower: return "Power and zones first"
            case .raceEffort: return "Bold effort card"
            case .recoveryRide: return "Quiet, low-pressure share"
            case .prFlex: return "Personal records up front"
            case .minimalDark: return "Sparse and premium"
            case .photoFirst: return "Let the image breathe"
            }
        }
    }

    enum VisualStyle: String, Codable, CaseIterable, Identifiable, Sendable {
        case mangoEditorial
        case proBroadcast
        case raceBib
        case cafeRide
        case neonNight
        case topoMap
        case analyst

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .mangoEditorial: return "Mango Editorial"
            case .proBroadcast: return "Pro Broadcast"
            case .raceBib: return "Race Bib"
            case .cafeRide: return "Cafe Ride"
            case .neonNight: return "Neon Night"
            case .topoMap: return "Topo Map"
            case .analyst: return "Analyst"
            }
        }
    }

    enum MetricSlot: String, Codable, CaseIterable, Identifiable, Sendable {
        case distance
        case movingTime
        case avgPower
        case normalizedPower
        case tss
        case intensityFactor
        case heartRate
        case cadence
        case elevation
        case calories
        case speed
        case maxPower

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .distance: return "Distance"
            case .movingTime: return "Moving Time"
            case .avgPower: return "Avg Power"
            case .normalizedPower: return "NP"
            case .tss: return "TSS"
            case .intensityFactor: return "IF"
            case .heartRate: return "HR"
            case .cadence: return "Cadence"
            case .elevation: return "Elevation"
            case .calories: return "Calories"
            case .speed: return "Speed"
            case .maxPower: return "Max Power"
            }
        }
    }

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

        /// Time-of-day + elevation aware suggestion for outdoor rides.
        /// `hour` is a 0–23 calendar hour from the ride start; `elevationMeters` is the ride's positive gain.
        static func recommended(hour: Int, elevationMeters: Double) -> StoryPreset {
            switch hour {
            case ..<6, 20...: return .nightRide
            case 6..<8:       return .dawnGradient
            case 18..<20:     return .sunsetMango
            default: break
            }
            if elevationMeters > 500 { return .mountainSilhouette }
            return .darkAtmospheric
        }
    }

    var accent: Accent
    var template: Template
    var visualStyle: VisualStyle
    var backgroundSource: BackgroundSource
    var selectedPreset: StoryPreset
    var layeredShare: Bool
    var carouselExport: Bool
    var showHeader: Bool
    var showHeroTitle: Bool
    var showRouteName: Bool
    var showTrainingLoad: Bool
    var showSummaryCards: Bool
    var showBottomStrip: Bool
    var showBrandBadge: Bool
    var quickStatSlots: [MetricSlot]
    /// When WHOOP is linked and recovery/strain values are passed in at render time, show a line on the training load card.
    var showWhoopReadiness: Bool
    var privacyHideRoute: Bool
    var privacyHidePower: Bool
    var privacyHideHeartRate: Bool

    static let `default` = InstagramStoryCardOptions(
        accent: .dominantZone,
        template: .cleanStats,
        visualStyle: .mangoEditorial,
        backgroundSource: .none,
        selectedPreset: .darkAtmospheric,
        layeredShare: false,
        carouselExport: false,
        showHeader: true,
        showHeroTitle: true,
        showRouteName: true,
        showTrainingLoad: true,
        showSummaryCards: true,
        showBottomStrip: true,
        showBrandBadge: true,
        quickStatSlots: [.heartRate, .cadence, .elevation, .speed],
        showWhoopReadiness: true,
        privacyHideRoute: false,
        privacyHidePower: false,
        privacyHideHeartRate: false
    )

    init(
        accent: Accent,
        template: Template,
        visualStyle: VisualStyle,
        backgroundSource: BackgroundSource,
        selectedPreset: StoryPreset,
        layeredShare: Bool,
        carouselExport: Bool,
        showHeader: Bool,
        showHeroTitle: Bool,
        showRouteName: Bool,
        showTrainingLoad: Bool,
        showSummaryCards: Bool,
        showBottomStrip: Bool,
        showBrandBadge: Bool,
        quickStatSlots: [MetricSlot],
        showWhoopReadiness: Bool,
        privacyHideRoute: Bool,
        privacyHidePower: Bool,
        privacyHideHeartRate: Bool
    ) {
        self.accent = accent
        self.template = template
        self.visualStyle = visualStyle
        self.backgroundSource = backgroundSource
        self.selectedPreset = selectedPreset
        self.layeredShare = layeredShare
        self.carouselExport = carouselExport
        self.showHeader = showHeader
        self.showHeroTitle = showHeroTitle
        self.showRouteName = showRouteName
        self.showTrainingLoad = showTrainingLoad
        self.showSummaryCards = showSummaryCards
        self.showBottomStrip = showBottomStrip
        self.showBrandBadge = showBrandBadge
        self.quickStatSlots = quickStatSlots
        self.showWhoopReadiness = showWhoopReadiness
        self.privacyHideRoute = privacyHideRoute
        self.privacyHidePower = privacyHidePower
        self.privacyHideHeartRate = privacyHideHeartRate
    }

    private enum CodingKeys: String, CodingKey {
        case accent
        case template
        case visualStyle
        case backgroundSource
        case selectedPreset
        case layeredShare
        case carouselExport
        case showHeader
        case showHeroTitle
        case showRouteName
        case showTrainingLoad
        case showSummaryCards
        case showBottomStrip
        case showBrandBadge
        case quickStatSlots
        case showWhoopReadiness
        case privacyHideRoute
        case privacyHidePower
        case privacyHideHeartRate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = InstagramStoryCardOptions.default
        accent = try c.decodeIfPresent(Accent.self, forKey: .accent) ?? defaults.accent
        template = try c.decodeIfPresent(Template.self, forKey: .template) ?? defaults.template
        visualStyle = try c.decodeIfPresent(VisualStyle.self, forKey: .visualStyle) ?? defaults.visualStyle
        backgroundSource = try c.decodeIfPresent(BackgroundSource.self, forKey: .backgroundSource) ?? defaults.backgroundSource
        selectedPreset = try c.decodeIfPresent(StoryPreset.self, forKey: .selectedPreset) ?? defaults.selectedPreset
        layeredShare = try c.decodeIfPresent(Bool.self, forKey: .layeredShare) ?? defaults.layeredShare
        carouselExport = try c.decodeIfPresent(Bool.self, forKey: .carouselExport) ?? defaults.carouselExport
        showHeader = try c.decodeIfPresent(Bool.self, forKey: .showHeader) ?? defaults.showHeader
        showHeroTitle = try c.decodeIfPresent(Bool.self, forKey: .showHeroTitle) ?? defaults.showHeroTitle
        showRouteName = try c.decodeIfPresent(Bool.self, forKey: .showRouteName) ?? defaults.showRouteName
        showTrainingLoad = try c.decodeIfPresent(Bool.self, forKey: .showTrainingLoad) ?? defaults.showTrainingLoad
        showSummaryCards = try c.decodeIfPresent(Bool.self, forKey: .showSummaryCards) ?? defaults.showSummaryCards
        showBottomStrip = try c.decodeIfPresent(Bool.self, forKey: .showBottomStrip) ?? defaults.showBottomStrip
        showBrandBadge = try c.decodeIfPresent(Bool.self, forKey: .showBrandBadge) ?? defaults.showBrandBadge
        quickStatSlots = try c.decodeIfPresent([MetricSlot].self, forKey: .quickStatSlots) ?? defaults.quickStatSlots
        showWhoopReadiness = try c.decodeIfPresent(Bool.self, forKey: .showWhoopReadiness) ?? defaults.showWhoopReadiness
        privacyHideRoute = try c.decodeIfPresent(Bool.self, forKey: .privacyHideRoute) ?? defaults.privacyHideRoute
        privacyHidePower = try c.decodeIfPresent(Bool.self, forKey: .privacyHidePower) ?? defaults.privacyHidePower
        privacyHideHeartRate = try c.decodeIfPresent(Bool.self, forKey: .privacyHideHeartRate) ?? defaults.privacyHideHeartRate
    }
}

enum InstagramStoryStudioPreferences {
    private static let key = "instagramStoryStudioOptions.v5"

    static func load() -> InstagramStoryCardOptions {
        guard let data = UserDefaults.standard.data(forKey: key),
              var decoded = try? JSONDecoder().decode(InstagramStoryCardOptions.self, from: data)
        else { return .default }
        // Custom photos are intentionally session-only. Never restore a source that has no image.
        if decoded.backgroundSource == .custom {
            decoded.backgroundSource = .preset
        }
        return decoded
    }

    static func save(_ options: InstagramStoryCardOptions) {
        var persisted = options
        if persisted.backgroundSource == .custom {
            persisted.backgroundSource = .preset
        }
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
