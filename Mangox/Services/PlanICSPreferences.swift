import Foundation

/// User defaults for training plan `.ics` export (timed events + optional alarm).
enum PlanICSPreferences {
    private static let startHourKey = "plan_ics_export_start_hour"
    private static let valarmKey = "plan_ics_export_include_valarm"

    /// Local hour (0–23) for timed workout blocks in exported calendars.
    static var defaultStartHour: Int {
        get {
            if UserDefaults.standard.object(forKey: startHourKey) == nil {
                return 7
            }
            return min(23, max(0, UserDefaults.standard.integer(forKey: startHourKey)))
        }
        set {
            UserDefaults.standard.set(min(23, max(0, newValue)), forKey: startHourKey)
        }
    }

    /// 15-minute calendar alert before each timed workout.
    static var includeWorkoutReminder: Bool {
        get { UserDefaults.standard.bool(forKey: valarmKey) }
        set { UserDefaults.standard.set(newValue, forKey: valarmKey) }
    }
}
