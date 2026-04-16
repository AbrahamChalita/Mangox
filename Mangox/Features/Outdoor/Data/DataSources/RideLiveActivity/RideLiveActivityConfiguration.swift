import Foundation

/// Shared tuning for indoor and outdoor ride Live Activities (ActivityKit).
///
/// - `publishIntervalSeconds` drives how often we *attempt* updates from ride engines (indoor tick cadence,
///   outdoor polling). `RideLiveActivityManager` still applies a matching throttle so ActivityKit is not spammed.
enum RideLiveActivityConfiguration {
    /// Whole seconds between publish attempts while recording (matches manager throttle).
    static let publishIntervalSeconds: UInt = 5

    /// Minimum time between `Activity.update` calls for the same activity.
    static var minUpdateInterval: TimeInterval { TimeInterval(publishIntervalSeconds) }

    /// How long `ContentState` stays visually fresh before iOS may mark the widget stale.
    static let staleWindow: TimeInterval = 60

    /// Outdoor sync loop: poll this often when not recording so we notice `startRecording` quickly.
    static let idlePollInterval: TimeInterval = 1
}
