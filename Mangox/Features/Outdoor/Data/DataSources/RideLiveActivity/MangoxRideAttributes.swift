import ActivityKit
import Foundation

/// Shared by the app (`Activity.request`) and the Widget Extension (Live Activity UI). Keep definitions in sync.
struct MangoxRideAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var speedKmh: Double
        var distanceM: Double
        var durationSeconds: Double
        var nextTurnShort: String?
        /// Smoothed / live heart rate from BLE (0 = none).
        var heartRateBpm: Int
        /// Smoothed power from BLE (0 = none).
        var powerWatts: Int
        /// Instantaneous cadence from BLE (0 = none).
        var cadenceRpm: Double
        /// Heart rate zone id 1…5 (0 = none / unknown).
        var hrZoneId: Int
        /// Power zone id 1…5 (0 = none / unknown).
        var powerZoneId: Int
        /// Distance and speed labels use imperial units when true.
        var useImperial: Bool
    }

    var rideModeLabel: String

    /// Deep link used when the user taps the Live Activity.
    /// Keep stable for compatibility with already-running activities.
    static let outdoorDeepLinkURL = URL(string: "mangox://ride/outdoor/live")!
}
