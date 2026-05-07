import Foundation
import Supabase
import SwiftData

/// Syncs the rider profile (one row per user, keyed by user_id).
///
/// Source of truth on device is `RidePreferences` plus FTP/HR zone state in
/// `PowerZone` / `HeartRateZone`. We push current values; the trigger that
/// auto-creates the `profiles` row on signup means UPDATE always finds it.
struct ProfileSyncDomain: SupabaseSyncDomain {
    let name = "profiles"

    struct Row: Codable, Sendable {
        let user_id: String
        let display_name: String?
        let birth_year: Int?
        let height_cm: Double?
        let weight_kg: Double?
        let bike_weight_kg: Double?
        let primary_indoor_bike: String?
        let primary_outdoor_bike: String?
        let cda: Double?
        let csc_wheel_circumference_m: Double?
        let unit_system: String
        let ftp_watts: Int?
        let ftp_has_been_set: Bool
        let max_hr: Int?
        let resting_hr: Int?
        let max_hr_manual_override: Bool
        let resting_hr_manual_override: Bool
    }

    @MainActor
    func push(userId: UUID, client: SupabaseClient, context: ModelContext) async throws {
        let prefs = RidePreferences.shared

        let row = Row(
            user_id: userId.uuidString,
            display_name: trimmedOrNil(prefs.riderDisplayName),
            birth_year: prefs.riderBirthYear,
            height_cm: nil,
            weight_kg: prefs.riderWeightKg,
            bike_weight_kg: prefs.bikeWeightKg,
            primary_indoor_bike: trimmedOrNil(prefs.primaryIndoorBikeName),
            primary_outdoor_bike: trimmedOrNil(prefs.primaryOutdoorBikeName),
            cda: prefs.riderCda,
            csc_wheel_circumference_m: prefs.cscWheelCircumferenceMeters,
            unit_system: prefs.isImperial ? "imperial" : "metric",
            ftp_watts: PowerZone.hasSetFTP ? PowerZone.ftp : nil,
            ftp_has_been_set: PowerZone.hasSetFTP,
            max_hr: HeartRateZone.maxHR,
            resting_hr: HeartRateZone.restingHR,
            max_hr_manual_override: HeartRateZone.hasManualMaxHROverride,
            resting_hr_manual_override: HeartRateZone.hasManualRestingHROverride
        )

        try await client.from("profiles").upsert(row, onConflict: "user_id").execute()
    }

    @MainActor
    func pull(userId: UUID, client: SupabaseClient, context: ModelContext) async throws {
        // Pull is intentionally a no-op for the first release: device-local prefs
        // win on conflict to keep onboarding simple. When we add multi-device
        // support, fetch the row and merge non-null fields.
    }
}

private func trimmedOrNil(_ s: String) -> String? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
}
