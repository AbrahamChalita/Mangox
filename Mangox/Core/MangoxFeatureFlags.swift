import Foundation

/// User-tunable feature switches (persisted in `UserDefaults`).
enum MangoxFeatureFlags {
    private static let trainingNotificationsKey = "mangox_feature_training_notifications_v1"

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
}
