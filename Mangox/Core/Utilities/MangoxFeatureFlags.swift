import Foundation

/// User-tunable feature switches (persisted in `UserDefaults`).
enum MangoxFeatureFlags {
    private static let trainingNotificationsKey = "mangox_feature_training_notifications_v1"
    private static let appShellMapPrewarmKey = "mangox_feature_app_shell_map_prewarm_v1"
    private static let outdoorMapPrewarmKey = "mangox_feature_outdoor_map_prewarm_v1"
    private static let outdoorMapPrewarmCompletedKey = "mangox_feature_outdoor_map_prewarm_completed_v1"

    /// Master switch for locally scheduled training reminders (evening preview, missed-key nudge, FTP nudge).
    /// Defaults to `true` when the key has never been set.
    static var allowsTrainingNotifications: Bool {
        get {
            guard UserDefaults.standard.object(forKey: trainingNotificationsKey) != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: trainingNotificationsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: trainingNotificationsKey)
        }
    }

    /// Enables the hidden shell-level `Map()` warmup in `ContentView`.
    /// Defaults to `false` to reduce baseline GPU/MapKit pressure.
    static var allowsAppShellMapPrewarm: Bool {
        get {
            guard UserDefaults.standard.object(forKey: appShellMapPrewarmKey) != nil else {
                return false
            }
            return UserDefaults.standard.bool(forKey: appShellMapPrewarmKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: appShellMapPrewarmKey)
        }
    }

    /// Enables the Outdoor screen's one-shot hidden MapKit prewarm.
    /// Defaults to `true` for navigation UX, but runs once and then stays off.
    static var allowsOutdoorMapPrewarm: Bool {
        get {
            guard UserDefaults.standard.object(forKey: outdoorMapPrewarmKey) != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: outdoorMapPrewarmKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: outdoorMapPrewarmKey)
        }
    }

    /// Tracks whether Outdoor prewarm already completed on this install.
    static var hasCompletedOutdoorMapPrewarm: Bool {
        get { UserDefaults.standard.bool(forKey: outdoorMapPrewarmCompletedKey) }
        set { UserDefaults.standard.set(newValue, forKey: outdoorMapPrewarmCompletedKey) }
    }
}
