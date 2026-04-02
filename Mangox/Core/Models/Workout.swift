import Foundation
import SwiftData

/// Minimum active seconds for a workout to be considered valid.
/// Workouts shorter than this are treated as accidental starts and
/// will not count toward training plan completion.
let kMinimumValidWorkoutSeconds: Int = 60

@Model
final class Workout {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date?
    var duration: TimeInterval = 0          // active seconds only (excludes pauses)
    var distance: Double = 0                // meters
    var avgPower: Double = 0
    var maxPower: Int = 0
    var avgCadence: Double = 0
    var avgSpeed: Double = 0                // km/h
    var avgHR: Double = 0
    var maxHR: Int = 0
    var normalizedPower: Double = 0
    var tss: Double = 0
    var intensityFactor: Double = 0
    var elevationGain: Double = 0           // meters of positive elevation gain (from GPX route)
    var statusRaw: String = "active"        // active, paused, completed
    var notes: String = ""                  // user-added post-ride notes

    /// Outdoor route label at save time (GPX name or Apple Maps destination).
    var savedRouteName: String?
    /// `free`, `gpx`, or `directions` — mirrors `SavedRouteKind` for persistence.
    var savedRouteKindRaw: String?
    /// Planned route length in meters when the ride was saved (GPX or calculated).
    var plannedRouteDistanceMeters: Double = 0
    /// Optional subtitle for directions (e.g. address line).
    var routeDestinationSummary: String?

    /// Optional link to a training plan day (e.g. "w2d2").
    /// Set when the workout is started from a guided plan session.
    /// Used to un-mark plan completion if the workout is deleted.
    var planDayID: String?
    /// Which plan this workout belongs to. Needed so saved AI plans can
    /// round-trip through summary, history, and completion state.
    var planID: String?

    /// Denormalized sample count — avoids faulting in all samples just to check if empty.
    /// Set at workout save time in calculateSummary().
    var sampleCount: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSample.workout)
    var samples: [WorkoutSample] = []

    @Relationship(deleteRule: .cascade, inverse: \LapSplit.workout)
    var laps: [LapSplit] = []

    var status: WorkoutStatus {
        get { WorkoutStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    /// Whether this workout meets the minimum duration to be considered valid
    /// (not an accidental start/stop).
    var isValid: Bool {
        Int(duration) >= kMinimumValidWorkoutSeconds
    }

    init(startDate: Date = .now, planDayID: String? = nil, planID: String? = nil) {
        self.id = UUID()
        self.startDate = startDate
        self.planDayID = planDayID
        self.planID = planID
    }
}

enum WorkoutStatus: String, Codable {
    case active
    case paused
    case completed
}

/// Persisted outdoor route source for saved workouts.
enum SavedRouteKind: String, Codable {
    case free
    case gpx
    case directions
}

extension Workout {
    var savedRouteKind: SavedRouteKind? {
        get { savedRouteKindRaw.flatMap { SavedRouteKind(rawValue: $0) } }
        set { savedRouteKindRaw = newValue?.rawValue }
    }
}
