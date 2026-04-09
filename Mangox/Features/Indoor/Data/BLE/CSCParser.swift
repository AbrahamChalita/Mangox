import Foundation

/// Parses Bluetooth Cycling Speed and Cadence (CSC) Measurement (0x2A5B).
/// Used for Garmin / Wahoo wheel + crank sensors on outdoor rides.
enum CSCParser {

    struct CrankState {
        var lastRevs: UInt16?
        var lastTime1024: UInt16?
    }

    struct WheelState {
        var lastRevs: UInt32?
        var lastTime1024: UInt16?
    }

    /// Returns cadence (rpm) from crank data; 0 if not enough samples.
    static func cadenceRPM(from data: Data, state: inout CrankState) -> Double {
        guard data.count >= 1 else { return 0 }
        let flags = data[0]
        guard (flags & 0x02) != 0 else { return 0 }

        var o = 1
        if (flags & 0x01) != 0 {
            o += 6 // wheel revs (4) + last wheel event time (2)
        }
        guard data.count >= o + 4 else { return 0 }

        let revs = UInt16(data[o]) | (UInt16(data[o + 1]) << 8)
        let time1024 = UInt16(data[o + 2]) | (UInt16(data[o + 3]) << 8)

        defer {
            state.lastRevs = revs
            state.lastTime1024 = time1024
        }

        guard let prevRevs = state.lastRevs, let prevTime = state.lastTime1024 else {
            return 0
        }

        var deltaRevs = Int(revs) &- Int(prevRevs)
        if deltaRevs < 0 { deltaRevs += 65536 }

        var deltaTime = Int(time1024) &- Int(prevTime)
        if deltaTime < 0 { deltaTime += 65536 }

        guard deltaRevs > 0, deltaTime > 0 else { return 0 }

        let seconds = Double(deltaTime) / 1024.0
        guard seconds > 0.05 else { return 0 }

        return Double(deltaRevs) / seconds * 60.0
    }

    /// Wheel speed in km/h using wheel rev deltas and `wheelCircumferenceMeters` (default ~700×25).
    static func wheelSpeedKmh(from data: Data, state: inout WheelState, wheelCircumferenceMeters: Double = 2.096) -> Double {
        guard data.count >= 1 else { return 0 }
        let flags = data[0]
        guard (flags & 0x01) != 0, data.count >= 7 else { return 0 }

        let revs = UInt32(data[1]) | (UInt32(data[2]) << 8) | (UInt32(data[3]) << 16) | (UInt32(data[4]) << 24)
        let time1024 = UInt16(data[5]) | (UInt16(data[6]) << 8)

        defer {
            state.lastRevs = revs
            state.lastTime1024 = time1024
        }

        guard let prevRevs = state.lastRevs, let prevTime = state.lastTime1024 else {
            return 0
        }

        var deltaRevs = Int64(revs) - Int64(prevRevs)
        if deltaRevs < 0 { deltaRevs += Int64(UInt32.max) + 1 }

        var deltaTime = Int(time1024) &- Int(prevTime)
        if deltaTime < 0 { deltaTime += 65536 }

        guard deltaRevs > 0, deltaTime > 0 else { return 0 }

        let seconds = Double(deltaTime) / 1024.0
        guard seconds > 0.05 else { return 0 }

        let distanceM = Double(deltaRevs) * wheelCircumferenceMeters
        let ms = distanceM / seconds
        return ms * 3.6
    }
}
