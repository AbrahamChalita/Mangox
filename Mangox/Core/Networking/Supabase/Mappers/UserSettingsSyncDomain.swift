import Foundation
import Supabase
import SwiftData

/// Pushes the device's `RidePreferences` snapshot into Postgres `user_settings`.
struct UserSettingsSyncDomain: SupabaseSyncDomain {
    let name = "user_settings"

    struct Row: Codable, Sendable {
        let user_id: String
        let show_laps: Bool
        let step_audio_cue: Bool
        let navigation_turn_cues: Bool
        let ride_tips_enabled: Bool
        let ride_tips_audio: Bool
        let ride_tips_spacing: String
        let ride_tips_indoor_heat: Bool
        let ride_tips_categories: [String]
        let low_cadence_warning: Bool
        let low_cadence_threshold_rpm: Int
        let indoor_power_hero_mode: String
        let indoor_speed_source: String
        let outdoor_auto_lap_meters: Double
        let live_activity_outdoor: Bool
        let live_activity_indoor: Bool
        let gpx_privacy_trim_start_m: Double
        let gpx_privacy_trim_end_m: Double
        let ride_goals: AnyJSON
        let quick_interval: AnyJSON?
    }

    @MainActor
    func push(userId: UUID, client: SupabaseClient, context: ModelContext) async throws {
        let prefs = RidePreferences.shared

        let goalsJSON: [[String: AnyJSON]] = prefs.goals.map { goal in
            [
                "kind":      .string(goal.kind.rawValue),
                "target":    .double(goal.target),
                "isEnabled": .bool(goal.isEnabled)
            ]
        }

        let quickIntervalJSON: AnyJSON? = {
            let qi = prefs.quickInterval
            return .object([
                "isEnabled":   .bool(qi.isEnabled),
                "sets":        .integer(qi.sets),
                "workMinutes": .integer(qi.workMinutes),
                "restMinutes": .integer(qi.restMinutes),
                "targetZone":  .integer(qi.targetZone)
            ])
        }()

        let row = Row(
            user_id: userId.uuidString,
            show_laps: prefs.showLaps,
            step_audio_cue: prefs.stepAudioCueEnabled,
            navigation_turn_cues: prefs.navigationTurnCuesEnabled,
            ride_tips_enabled: prefs.rideTipsEnabled,
            ride_tips_audio: prefs.rideTipsAudioEnabled,
            ride_tips_spacing: prefs.rideTipsSpacing.rawValue,
            ride_tips_indoor_heat: prefs.rideTipsIndoorHeatAwareness,
            ride_tips_categories: prefs.rideTipsEnabledCategories.map(\.rawValue).sorted(),
            low_cadence_warning: prefs.lowCadenceWarningEnabled,
            low_cadence_threshold_rpm: prefs.lowCadenceThreshold,
            indoor_power_hero_mode: prefs.indoorPowerHeroMode.rawValue,
            indoor_speed_source: prefs.indoorSpeedSource.rawValue,
            outdoor_auto_lap_meters: prefs.outdoorAutoLapIntervalMeters,
            live_activity_outdoor: prefs.outdoorLiveActivityEnabled,
            live_activity_indoor: prefs.indoorLiveActivityEnabled,
            gpx_privacy_trim_start_m: prefs.gpxPrivacyTrimStartMeters,
            gpx_privacy_trim_end_m: prefs.gpxPrivacyTrimEndMeters,
            ride_goals: .array(goalsJSON.map { .object($0) }),
            quick_interval: quickIntervalJSON
        )

        try await client.from("user_settings").upsert(row, onConflict: "user_id").execute()
    }
}
