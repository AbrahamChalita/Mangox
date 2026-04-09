import Foundation

extension Notification.Name {
    /// Posted after workouts are persisted in ways that may not reshuffle `@Query` array identity
    /// (e.g. in-place field edits). Home, Calendar, and PMC listen to refresh derived caches.
    static let mangoxWorkoutAggregatesMayHaveChanged = Notification.Name(
        "mangox.workoutAggregatesMayHaveChanged")
}

enum MangoxModelNotifications {
    static func postWorkoutAggregatesMayHaveChanged() {
        NotificationCenter.default.post(name: .mangoxWorkoutAggregatesMayHaveChanged, object: nil)
    }
}
