import Foundation

extension Notification.Name {
    /// Posted after workouts are persisted in ways that may not reshuffle `@Query` array identity
    /// (e.g. in-place field edits). Home, Calendar, and PMC listen to refresh derived caches.
    static let mangoxWorkoutAggregatesMayHaveChanged = Notification.Name(
        "mangox.workoutAggregatesMayHaveChanged")

    /// Posted after logged (non-cycling) activities are created, updated, or deleted.
    static let mangoxLoggedActivitiesAggregatesMayHaveChanged = Notification.Name(
        "mangox.loggedActivitiesAggregatesMayHaveChanged")
}

enum MangoxModelNotifications {
    static func postWorkoutAggregatesMayHaveChanged() {
        NotificationCenter.default.post(name: .mangoxWorkoutAggregatesMayHaveChanged, object: nil)
    }

    static func postLoggedActivitiesAggregatesMayHaveChanged() {
        NotificationCenter.default.post(name: .mangoxLoggedActivitiesAggregatesMayHaveChanged, object: nil)
    }
}
