import Foundation

/// Plain ride metrics for outdoor Live Activity sync. Built at the call site from navigation, location, and BLE state.
struct OutdoorLiveActivitySnapshot: Equatable {
    let isEnabled: Bool
    let isRecording: Bool
    let useImperial: Bool
    let modeLabel: String
    let nextTurnShort: String?
    let speedKmh: Double
    let distanceM: Double
    let durationSeconds: Double
    let heartRateBpm: Int
    let powerWatts: Int
    let cadenceRpm: Double
    let isAutoPaused: Bool
    let isManuallyPaused: Bool
}

/// Plain ride metrics for indoor Live Activity sync. Built at the call site from workout and sensor state.
struct IndoorLiveActivitySnapshot: Equatable {
    let isEnabled: Bool
    let isRecording: Bool
    let useImperial: Bool
    let speedKmh: Double
    let distanceM: Double
    let durationSeconds: Double
    let heartRateBpm: Int
    let powerWatts: Int
    let cadenceRpm: Double
    let isAutoPaused: Bool
    let isManuallyPaused: Bool
}
