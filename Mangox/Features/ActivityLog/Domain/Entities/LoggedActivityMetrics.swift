// Features/ActivityLog/Domain/Entities/LoggedActivityMetrics.swift
import Foundation

struct LoggedActivityMetrics: Codable, Sendable, Hashable {
    var distanceMeters: Double?
    var elevationGainMeters: Double?
    var avgHeartRate: Int?
    var maxHeartRate: Int?
    var calories: Int?
    var sets: Int?
    var reps: Int?
    var weightKg: Double?
    /// Whoop-provided strain score (0–21 scale).
    var strain: Double?
    /// Energy in kilojoules (Strava and Whoop both provide this).
    var kilojoules: Double?
    /// Moving average speed from source services, in meters per second.
    var avgSpeedMetersPerSecond: Double?
    var maxSpeedMetersPerSecond: Double?
    /// Strava relative effort / suffer score when available.
    var relativeEffort: Int?
    var achievementCount: Int?
    var prCount: Int?
    /// Encoded Strava summary polyline for map-based activities.
    var mapSummaryPolyline: String?
    /// WHOOP score quality and vertical movement.
    var percentRecorded: Double?
    var altitudeChangeMeters: Double?
    /// WHOOP HR zone durations, milliseconds, zones 0...5.
    var heartRateZoneMillis: [Int]?
    /// Average cadence — strides/min for runs, rpm for cycling, strokes/min for rowing/swims.
    var avgCadence: Double?
    /// Average power in watts (Strava reports for activities recorded with a power meter or Stryd-equivalent).
    var avgPowerWatts: Double?
    /// Ambient temperature averaged over the activity, in Celsius.
    var avgTempCelsius: Double?
    /// Fastest 1km split in seconds (running/walking/hiking activities, computed from streams).
    var bestKmSplitSeconds: Int?

    static let empty = LoggedActivityMetrics()
}
