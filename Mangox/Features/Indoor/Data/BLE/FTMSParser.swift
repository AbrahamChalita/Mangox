import Foundation

struct IndoorBikeDataPacket {
    let metrics: CyclingMetrics
    let hasSpeed: Bool
    let hasCadence: Bool
    let hasTotalDistance: Bool
    let hasPower: Bool
    let hasHeartRate: Bool
}

// MARK: - CPS Crank State Helper

/// Derives instantaneous cadence from successive Cycling Power Service
/// Crank Revolution Data fields.
///
/// Per the BT spec both `cumulativeCrankRevolutions` and `lastCrankEventTime`
/// are uint16 and roll over at 65536. We handle roll-over via wrapping arithmetic.
struct CPSCrankState {
    private var prevRevs: UInt16?
    private var prevEventTime: UInt16? // units: 1/1024 s

    /// Returns cadence in RPM, or nil if this is the first packet or the crank
    /// hasn't moved (identical event time — rider is coasting).
    mutating func cadence(revs: UInt16, eventTime: UInt16) -> Double? {
        defer {
            prevRevs = revs
            prevEventTime = eventTime
        }

        guard let pRevs = prevRevs, let pTime = prevEventTime else {
            return nil // first packet — no diff possible yet
        }

        // Wrapping subtraction handles uint16 roll-over correctly
        let deltaRevs = revs &- pRevs
        let deltaTime = eventTime &- pTime // in 1/1024-second ticks

        // No crank movement or no time elapsed — coasting or duplicate packet
        guard deltaRevs > 0, deltaTime > 0 else { return nil }

        // deltaTime is in units of 1/1024 s → convert to seconds
        let deltaSeconds = Double(deltaTime) / 1024.0

        // Sanity guard: ignore packets where computed cadence would be absurd
        // (> 250 rpm means a spurious event-time jump or corrupt packet)
        let rpm = (Double(deltaRevs) / deltaSeconds) * 60.0
        guard rpm <= 250 else { return nil }

        return rpm
    }

    mutating func reset() {
        prevRevs = nil
        prevEventTime = nil
    }
}

// MARK: - FTMSParser

enum FTMSParser {

    // MARK: - Indoor Bike Data (0x2AD2)

    /// Parse Indoor Bike Data characteristic (0x2AD2) per Bluetooth SIG FTMS spec.
    ///
    /// Bytes 0-1: 16-bit flags field.
    /// **Bit 0 uses inverted logic**: 0 = instantaneous speed present, 1 = not present.
    /// Remaining bits use normal logic: 1 = field present.
    /// Fields appear in fixed order; byte offset advances through each preceding field.
    static func parseIndoorBikeData(_ data: Data) -> CyclingMetrics? {
        parseIndoorBikeDataPacket(data)?.metrics
    }

    static func parseIndoorBikeDataPacket(_ data: Data) -> IndoorBikeDataPacket? {
        guard data.count >= 2 else { return nil }

        let flags = UInt16(data[0]) | (UInt16(data[1]) << 8)
        var offset = 2
        var metrics = CyclingMetrics(lastUpdate: Date())

        // Bit 0 (inverted): Instantaneous Speed — 0 means present
        let speedPresent = (flags & 0x0001) == 0
        if speedPresent {
            guard offset + 2 <= data.count else { return nil }
            let raw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            let speed = Double(raw) * 0.01 // resolution: 0.01 km/h
            guard speed <= 120 else { return nil } // sanity: 120 km/h max
            metrics.speed = speed
            offset += 2
        }

        // Bit 1: Average Speed
        if flags & 0x0002 != 0 {
            offset += 2 // skip
        }

        // Bit 2: Instantaneous Cadence
        let cadencePresent = flags & 0x0004 != 0
        if cadencePresent {
            guard offset + 2 <= data.count else { return nil }
            let raw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            let cadence = Double(raw) * 0.5 // resolution: 0.5 rpm
            guard cadence <= 250 else { return nil } // sanity: 250 rpm max
            metrics.cadence = cadence
            offset += 2
        }

        // Bit 3: Average Cadence
        if flags & 0x0008 != 0 {
            offset += 2 // skip
        }

        // Bit 4: Total Distance (3 bytes, uint24)
        let distancePresent = flags & 0x0010 != 0
        if distancePresent {
            guard offset + 3 <= data.count else { return nil }
            let raw = UInt32(data[offset])
                | (UInt32(data[offset + 1]) << 8)
                | (UInt32(data[offset + 2]) << 16)
            metrics.totalDistance = Double(raw) // meters
            offset += 3
        }

        // Bit 5: Resistance Level (sint16)
        if flags & 0x0020 != 0 {
            offset += 2
        }

        // Bit 6: Instantaneous Power (sint16)
        let powerPresent = flags & 0x0040 != 0
        if powerPresent {
            guard offset + 2 <= data.count else { return nil }
            let raw = Int16(bitPattern: UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
            let power = max(0, Int(raw)) // clamp negative to 0
            guard power <= 3000 else { return nil } // sanity: 3000W max
            metrics.power = power
            offset += 2
        }

        // Bit 7: Average Power (sint16)
        if flags & 0x0080 != 0 {
            offset += 2
        }

        // Bit 8: Expended Energy (total uint16 + per-hour uint16 + per-minute uint8 = 5 bytes)
        if flags & 0x0100 != 0 {
            offset += 5
        }

        // Bit 9: Heart Rate (uint8)
        let heartRatePresent = flags & 0x0200 != 0
        if heartRatePresent {
            guard offset + 1 <= data.count else { return nil }
            let hr = Int(data[offset])
            guard hr <= 250 else { return nil } // sanity: 250 bpm max
            metrics.heartRate = hr
            offset += 1
        }

        // Remaining bits (metabolic equivalent, elapsed time, remaining time) skipped

        metrics.includesTotalDistanceInPacket = distancePresent

        return IndoorBikeDataPacket(
            metrics: metrics,
            hasSpeed: speedPresent,
            hasCadence: cadencePresent,
            hasTotalDistance: distancePresent,
            hasPower: powerPresent,
            hasHeartRate: heartRatePresent
        )
    }

    // MARK: - Cycling Power Measurement (0x2A63)

    /// Parse Cycling Power Measurement characteristic per Bluetooth SIG Cycling Power Service spec.
    ///
    /// Bytes 0-1: 16-bit flags field.
    /// Bytes 2-3: Instantaneous Power (sint16, watts) — always present.
    /// Remaining fields depend on flags.
    ///
    /// Cadence is derived from Crank Revolution Data (bit 5) by diffing successive packets:
    ///   cadence (rpm) = (ΔcumulativeRevs / Δtime_s) × 60
    /// Both counters are uint16 and roll over at 65536 — handled with wrapping arithmetic.
    ///
    /// `crankState` is owned by the caller (BLEManager) so its lifetime matches the connection,
    /// not the process — eliminating any shared global state between sessions.
    static func parseCyclingPowerMeasurement(_ data: Data, crankState: inout CPSCrankState) -> CyclingMetrics? {
        guard data.count >= 4 else { return nil }

        let flags = UInt16(data[0]) | (UInt16(data[1]) << 8)
        var offset = 2
        var metrics = CyclingMetrics(lastUpdate: Date())

        // Instantaneous Power — always present (sint16, watts)
        let rawPower = Int16(bitPattern: UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
        let power = max(0, Int(rawPower))
        guard power <= 3000 else { return nil } // sanity: 3000W max
        metrics.power = power
        offset += 2

        // Bit 0: Pedal Power Balance Present (uint8)
        if flags & 0x0001 != 0 {
            offset += 1
        }

        // Bit 2: Accumulated Torque Present (uint16)
        if flags & 0x0004 != 0 {
            offset += 2
        }

        // Bit 4: Wheel Revolution Data Present (cumulative revs uint32 + last event uint16 = 6 bytes)
        if flags & 0x0010 != 0 {
            offset += 6
        }

        // Bit 5: Crank Revolution Data Present (cumulative revs uint16 + last event uint16 = 4 bytes)
        // Cadence is derived by diffing successive packets using the stateful crankState tracker.
        if flags & 0x0020 != 0 {
            guard offset + 4 <= data.count else { return metrics }
            let crankRevs      = UInt16(data[offset])     | (UInt16(data[offset + 1]) << 8)
            let lastCrankEvent = UInt16(data[offset + 2]) | (UInt16(data[offset + 3]) << 8)
            offset += 4

            if let cadence = crankState.cadence(revs: crankRevs, eventTime: lastCrankEvent) {
                metrics.cadence = cadence
            }
        }

        return metrics
    }

    // MARK: - Heart Rate Measurement (0x2A37)

    /// Parse Heart Rate Measurement characteristic (0x2A37).
    static func parseHeartRate(_ data: Data) -> Int? {
        guard data.count >= 2 else { return nil }
        let flags = data[0]
        let is16Bit = (flags & 0x01) != 0

        let hr: Int
        if is16Bit {
            guard data.count >= 3 else { return nil }
            hr = Int(UInt16(data[1]) | (UInt16(data[2]) << 8))
        } else {
            hr = Int(data[1])
        }
        guard hr <= 250 else { return nil } // sanity: 250 bpm max
        return hr
    }
}
