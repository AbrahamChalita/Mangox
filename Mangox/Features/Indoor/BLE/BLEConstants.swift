import CoreBluetooth

enum BLEConstants {
    // FTMS (Fitness Machine Service)
    // `nonisolated(unsafe)` because CBUUID(string:) is @MainActor in iOS 26 SDK,
    // which would otherwise isolate these static lets to the main actor.
    // The values are immutable compile-time constants — safe from any context.
    nonisolated(unsafe) static let ftmsServiceUUID = CBUUID(string: "1826")
    nonisolated(unsafe) static let indoorBikeDataUUID = CBUUID(string: "2AD2")
    nonisolated(unsafe) static let ftmsControlPointUUID = CBUUID(string: "2AD9")
    nonisolated(unsafe) static let ftmsFeatureUUID = CBUUID(string: "2ACC")
    nonisolated(unsafe) static let ftmsSupportedResistanceLevelRangeUUID = CBUUID(string: "2AD6")
    nonisolated(unsafe) static let ftmsStatusUUID = CBUUID(string: "2ADA")

    // Heart Rate Service
    nonisolated(unsafe) static let heartRateServiceUUID = CBUUID(string: "180D")
    nonisolated(unsafe) static let heartRateMeasurementUUID = CBUUID(string: "2A37")

    // Cycling Power Service (fallback if trainer exposes this instead)
    nonisolated(unsafe) static let cyclingPowerServiceUUID = CBUUID(string: "1818")
    nonisolated(unsafe) static let cyclingPowerMeasurementUUID = CBUUID(string: "2A63")

    // Cycling Speed and Cadence (Garmin / Wahoo wheel + crank pods)
    nonisolated(unsafe) static let cyclingSpeedCadenceServiceUUID = CBUUID(string: "1816")
    nonisolated(unsafe) static let cscMeasurementUUID = CBUUID(string: "2A5B")

    // Include Cycling Power Service in scan filter so trainers that only
    // advertise 0x1818 (e.g. ThinkRider Pro XX) are discovered.
    nonisolated(unsafe) static let scanServices: [CBUUID] = [
        ftmsServiceUUID,
        heartRateServiceUUID,
        cyclingPowerServiceUUID,
        cyclingSpeedCadenceServiceUUID
    ]
}
