// Features/Profile/Data/DataSources/UserDataWipeService.swift
import Foundation
import Security
import SwiftData

// Needed only for the direct Supabase fallback path
import Supabase
import Auth

/// Coordinates a full local data wipe ("Delete all my data").
/// Clears SwiftData, connected service credentials (Keychain), relevant UserDefaults,
/// and triggers Supabase sign-out + cursor cleanup.
///
/// Cloud data on Supabase is intentionally left intact (user can delete their account
/// separately via the Account screen or web).
@MainActor
enum UserDataWipeService {

    struct WipeResult {
        let deletedWorkoutCount: Int
        let disconnectedStrava: Bool
        let disconnectedWhoop: Bool
        let signedOutOfCloud: Bool
    }

    /// Performs a best-effort full local wipe. Throws only on catastrophic failure.
    /// Callers should show strong confirmation before invoking.
    static func performFullWipe(
        modelContext: ModelContext,
        stravaService: StravaServiceProtocol?,
        whoopService: WhoopServiceProtocol?,
        syncCoordinator: SyncCoordinator?,
        linkedOAuthBridge: LinkedOAuthSessionBridge? = nil
    ) async throws -> WipeResult {
        var deletedWorkoutCount = 0
        var disconnectedStrava = false
        var disconnectedWhoop = false
        var signedOutOfCloud = false

        // 1. Disconnect third-party services (clears their Keychain tokens)
        if let strava = stravaService {
            strava.disconnect()           // Strava protocol version is synchronous
            disconnectedStrava = true
        }
        if let whoop = whoopService {
            await whoop.disconnect()
            disconnectedWhoop = true
        }

        // Intervals.icu (used in some profiles)
        clearIntervalsIcuKeychain()

        // 2. Delete all SwiftData content (order matters for relationships in some schemas)
        let workoutDescriptor = FetchDescriptor<Workout>()
        let workouts = (try? modelContext.fetch(workoutDescriptor)) ?? []
        deletedWorkoutCount = workouts.count

        for type in Self.swiftDataTypesToClear {
            try? deleteAll(of: type, in: modelContext)
        }
        try? modelContext.save()

        // 3. Clear known preference / state UserDefaults keys (best-effort, non-exhaustive)
        Self.clearKnownUserDefaults()

        // Clear local profile avatar file cache
        RiderProfileAvatarStore.clearLocalAvatar()

        // 4. Remove encrypted OAuth backups from cloud, then sign out
        if let bridge = linkedOAuthBridge {
            await bridge.deleteAllCloudSessions()
        }

        if let sync = syncCoordinator {
            await sync.signOut()
            signedOutOfCloud = true
        } else if MangoxSupabase.isConfigured {
            // Best-effort direct sign-out if no SyncCoordinator was provided
            SyncCoordinator.clearAllCursors()
            signedOutOfCloud = true
        }

        // 5. Reset onboarding flag so the user experiences a fresh start if they want
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")

        // 6. Nuke common cached / derived values that survive the above
        UserDefaults.standard.removeObject(forKey: "MangoxDevForcePro") // dev override only
        UserDefaults.standard.removeObject(forKey: "user_device_id")

        return WipeResult(
            deletedWorkoutCount: deletedWorkoutCount,
            disconnectedStrava: disconnectedStrava,
            disconnectedWhoop: disconnectedWhoop,
            signedOutOfCloud: signedOutOfCloud
        )
    }

    // MARK: - Private helpers

    private static let swiftDataTypesToClear: [any PersistentModel.Type] = [
        Workout.self,
        WorkoutSample.self,
        LapSplit.self,
        WorkoutRAGChunk.self,
        CustomWorkoutTemplate.self,
        ChatSession.self,
        CoachChatMessage.self,
        AIGeneratedPlan.self,
        FitnessSettingsSnapshot.self,
        TrainingPlanProgress.self,
        LoggedActivityRecord.self
    ]

    private static func deleteAll<T: PersistentModel>(of type: T.Type, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<T>()
        let items = (try? context.fetch(descriptor)) ?? []
        for item in items {
            context.delete(item)
        }
    }

    private static func clearKnownUserDefaults() {
        let keys: [String] = [
            // Ride preferences (big one)
            "showLaps", "lowCadenceWarning", "lowCadenceThreshold", "stepAudioCue",
            "navigationTurnCues", "rideTipsEnabled", "rideTipsAudio", "rideTipsSpacing",
            "rideTipsIndoorHeat", "rideTipsPromptSeen", "unitSystem",
            "outdoorAutoLapMeters", "prioritizeNavMapless", "outdoorLiveActivity",
            "indoorLiveActivity", "cscWheelCircumferenceM", "indoorPowerHeroMode",
            "riderWeightKg", "bikeWeightKg", "indoorSpeedSource", "riderCda",
            "riderDisplayName", "riderBirthYear", "bikeOutdoorName", "bikeIndoorName",
            "goals", "quickInterval", "rideTipsCategories", "gpxTrimStartM", "gpxTrimEndM",

            // Zones
            "ftpWatts", "ftpHasBeenSet", "ftpLastUpdate",
            "maxHR", "restingHR", "manualMaxHR", "manualRestingHR",

            // Fitness / readiness snapshots
            "restingHR", "maxHR", "vo2Max", "healthReadinessSnapshot",

            // Training notifications & plan state
            "trainingNotificationsTomorrow", "trainingNotificationsTomorrowHour",
            "trainingNotificationsMissedKey", "trainingNotificationsFtpDue",
            "planICSStartHour", "planICSValarm",

            // Coach / AI local state
            "AIChatProvider", "AIChatProviderBaseURL", "coachTranscriptDebug",
            "mangox_ai_backend_url",

            // Various feature flags and last-used values
            "hasCompletedOnboarding", // will be reset explicitly above too
            "outdoorMapPrewarmCompleted", "appShellMapPrewarm",
            "outdoorMapPrewarm", "trainingNotificationsEnabled"
        ]

        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

// MARK: - Intervals.icu keychain clearing (used only during full data wipe)
private func clearIntervalsIcuKeychain() {
    let account = "intervals_icu_api_key"
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: account
    ]
    SecItemDelete(query as CFDictionary)
    UserDefaults.standard.removeObject(forKey: "intervals_icu_athlete_id")
}
