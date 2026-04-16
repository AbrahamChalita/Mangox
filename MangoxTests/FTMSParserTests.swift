import Testing
import Foundation
@testable import Mangox

struct FTMSParserTests {

    // MARK: - Indoor Bike Data

    @Test func parseSpeedOnly() throws {
        // Flags: 0x0000 (bit 0 = 0 → speed present, inverted logic)
        // Speed: 3200 → 32.00 km/h (0x0C80 little-endian)
        let data = Data([0x00, 0x00, 0x80, 0x0C])
        let metrics = try #require(FTMSParser.parseIndoorBikeData(data))

        #expect(metrics.speed == 32.0)
        #expect(metrics.cadence == 0)
        #expect(metrics.power == 0)
        #expect(metrics.includesTotalDistanceInPacket == false)
    }

    @Test func parseSpeedNotPresent() throws {
        // Flags: 0x0001 (bit 0 = 1 → speed NOT present, inverted logic)
        let data = Data([0x01, 0x00])
        let metrics = try #require(FTMSParser.parseIndoorBikeData(data))

        #expect(metrics.speed == 0)
    }

    @Test func parseSpeedAndCadence() throws {
        // Flags: 0x0004 (bit 0=0 speed present, bit 2=1 cadence present)
        // Speed: 2500 → 25.00 km/h
        // Cadence: 176 → 88.0 rpm (resolution 0.5)
        let data = Data([0x04, 0x00, 0xC4, 0x09, 0xB0, 0x00])
        let metrics = try #require(FTMSParser.parseIndoorBikeData(data))

        #expect(metrics.speed == 25.0)
        #expect(metrics.cadence == 88.0)
    }

    @Test func parseSpeedCadenceAndPower() throws {
        // Flags: 0x0044 (bit 0=0 speed, bit 2=1 cadence, bit 6=1 power)
        // Speed: 3000 → 30.00 km/h (0x0BB8)
        // Cadence: 180 → 90.0 rpm (0x00B4)
        // Power: 245W (0x00F5)
        let data = Data([0x44, 0x00, 0xB8, 0x0B, 0xB4, 0x00, 0xF5, 0x00])
        let metrics = try #require(FTMSParser.parseIndoorBikeData(data))

        #expect(metrics.speed == 30.0)
        #expect(metrics.cadence == 90.0)
        #expect(metrics.power == 245)
    }

    @Test func parseWithTotalDistance() throws {
        // Flags: 0x0054 (bit 0=0 speed, bit 2=1 cadence, bit 4=1 distance, bit 6=1 power)
        // Speed: 2800 → 28.00 km/h (0x0AF0)
        // Cadence: 160 → 80.0 rpm (0x00A0)
        // Distance: 12500 meters (3 bytes: 0xD4, 0x30, 0x00)
        // Power: 200W (0x00C8)
        let data = Data([0x54, 0x00, 0xF0, 0x0A, 0xA0, 0x00, 0xD4, 0x30, 0x00, 0xC8, 0x00])
        let metrics = try #require(FTMSParser.parseIndoorBikeData(data))

        #expect(metrics.speed == 28.0)
        #expect(metrics.cadence == 80.0)
        #expect(metrics.totalDistance == 12500.0)
        #expect(metrics.power == 200)
        #expect(metrics.includesTotalDistanceInPacket == true)
    }

    @Test func parseTotalDistanceZeroMetersStillMarksFieldPresent() throws {
        // Flags: 0x0010 — speed present (bit 0 = 0), total distance present (bit 4).
        // Speed 1000 → 10.00 km/h; distance uint24 = 0.
        let data = Data([0x10, 0x00, 0xE8, 0x03, 0x00, 0x00, 0x00])
        let metrics = try #require(FTMSParser.parseIndoorBikeData(data))
        #expect(metrics.speed == 10.0)
        #expect(metrics.totalDistance == 0)
        #expect(metrics.includesTotalDistanceInPacket == true)
    }

    @Test func parseWithHeartRate() throws {
        // Flags: 0x0244 (bit 0=0 speed, bit 2=1 cadence, bit 6=1 power, bit 9=1 HR)
        // Speed: 3500 → 35.00 km/h (0x0DAC)
        // Cadence: 190 → 95.0 rpm (0x00BE)
        // Power: 280W (0x0118)
        // HR: 155 bpm
        let data = Data([0x44, 0x02, 0xAC, 0x0D, 0xBE, 0x00, 0x18, 0x01, 0x9B])
        let metrics = try #require(FTMSParser.parseIndoorBikeData(data))

        #expect(metrics.speed == 35.0)
        #expect(metrics.cadence == 95.0)
        #expect(metrics.power == 280)
        #expect(metrics.heartRate == 155)
    }

    @Test func parseAllFieldsPresent() throws {
        // Flags: 0x027E
        //   bit 0=0 (speed present), bit 1=1 (avg speed), bit 2=1 (cadence),
        //   bit 3=1 (avg cadence), bit 4=1 (distance), bit 5=1 (resistance),
        //   bit 6=1 (power), bit 9=1 (HR)
        // Speed: 3000 (0x0BB8)
        // Avg Speed: 2800 (skip 2 bytes)
        // Cadence: 180 (0x00B4)
        // Avg Cadence: 175 (skip 2 bytes)
        // Distance: 5000 (3 bytes: 0x88, 0x13, 0x00)
        // Resistance: 50 (skip 2 bytes)
        // Power: 265W (0x0109)
        // HR: 162
        let data = Data([
            0x7E, 0x02,       // flags
            0xB8, 0x0B,       // speed
            0xF0, 0x0A,       // avg speed (skip)
            0xB4, 0x00,       // cadence
            0xAF, 0x00,       // avg cadence (skip)
            0x88, 0x13, 0x00, // distance
            0x32, 0x00,       // resistance (skip)
            0x09, 0x01,       // power
            0xA2,             // heart rate
        ])
        let metrics = try #require(FTMSParser.parseIndoorBikeData(data))

        #expect(metrics.speed == 30.0)
        #expect(metrics.cadence == 90.0)
        #expect(metrics.totalDistance == 5000.0)
        #expect(metrics.power == 265)
        #expect(metrics.heartRate == 162)
    }

    @Test func parseNegativePowerClampedToZero() throws {
        // Flags: 0x0041 (bit 0=1 no speed, bit 6=1 power)
        // Power: -5 (0xFFFB as sint16)
        let data = Data([0x41, 0x00, 0xFB, 0xFF])
        let metrics = try #require(FTMSParser.parseIndoorBikeData(data))

        #expect(metrics.power == 0)
    }

    @Test func parsePacketPresenceFlags() throws {
        // Flags: 0x0044 (speed + cadence + power present, no distance, no HR)
        let data = Data([0x44, 0x00, 0xB8, 0x0B, 0xB4, 0x00, 0xF5, 0x00])
        let packet = try #require(FTMSParser.parseIndoorBikeDataPacket(data))

        #expect(packet.hasSpeed == true)
        #expect(packet.hasCadence == true)
        #expect(packet.hasPower == true)
        #expect(packet.hasTotalDistance == false)
        #expect(packet.hasHeartRate == false)
        #expect(packet.metrics.includesTotalDistanceInPacket == false)
    }

    @Test func parseTooShortReturnsNil() throws {
        let data = Data([0x00])
        #expect(FTMSParser.parseIndoorBikeData(data) == nil)
    }

    @Test func parseEmptyReturnsNil() throws {
        let data = Data()
        #expect(FTMSParser.parseIndoorBikeData(data) == nil)
    }

    // MARK: - Cycling Power Service (CPS / 0x2A63)

    /// Build a CPS packet: flags (uint16 LE) + power (sint16 LE) + optional crank data (uint16+uint16 LE).
    private func cpsPacket(
        flags: UInt16,
        power: Int16,
        crankRevs: UInt16? = nil,
        lastCrankEvent: UInt16? = nil
    ) -> Data {
        var bytes: [UInt8] = [
            UInt8(flags & 0xFF), UInt8(flags >> 8),
            UInt8(bitPattern: Int8(truncatingIfNeeded: Int(power) & 0xFF)),
            UInt8(bitPattern: Int8(truncatingIfNeeded: Int(power) >> 8))
        ]
        if let revs = crankRevs, let event = lastCrankEvent {
            bytes += [UInt8(revs & 0xFF), UInt8(revs >> 8),
                      UInt8(event & 0xFF), UInt8(event >> 8)]
        }
        return Data(bytes)
    }

    @Test func cpsPowerOnly() throws {
        var crankState = CPSCrankState()
        // Flags: 0x0000 (no crank data), Power: 250W
        let data = cpsPacket(flags: 0x0000, power: 250)
        let metrics = try #require(FTMSParser.parseCyclingPowerMeasurement(data, crankState: &crankState))
        #expect(metrics.power == 250)
        #expect(metrics.cadence == 0)
    }

    @Test func cpsNegativePowerClamped() throws {
        var crankState = CPSCrankState()
        // Power: -10 (coasting / braking)
        let data = cpsPacket(flags: 0x0000, power: -10)
        let metrics = try #require(FTMSParser.parseCyclingPowerMeasurement(data, crankState: &crankState))
        #expect(metrics.power == 0)
    }

    @Test func cpsCadenceFirstPacketReturnsNil() throws {
        var crankState = CPSCrankState()
        // Flags: 0x0020 (bit 5 = crank revolution data present)
        // First packet — no previous state, cadence must be 0 (not derived)
        let data = cpsPacket(flags: 0x0020, power: 200, crankRevs: 100, lastCrankEvent: 1024)
        let metrics = try #require(FTMSParser.parseCyclingPowerMeasurement(data, crankState: &crankState))
        #expect(metrics.power == 200)
        #expect(metrics.cadence == 0) // first packet: no diff possible
    }

    @Test func cpsCadenceNormalDerivation() throws {
        var crankState = CPSCrankState()
        // First packet: 0 revs, time 0
        _ = FTMSParser.parseCyclingPowerMeasurement(
            cpsPacket(flags: 0x0020, power: 200, crankRevs: 0, lastCrankEvent: 0),
            crankState: &crankState
        )
        // Second packet: 1 rev in 1024 ticks (1024/1024 = 1.0 s) → 60 rpm
        let data = cpsPacket(flags: 0x0020, power: 210, crankRevs: 1, lastCrankEvent: 1024)
        let metrics = try #require(FTMSParser.parseCyclingPowerMeasurement(data, crankState: &crankState))
        #expect(abs(metrics.cadence - 60.0) < 0.5)
    }

    @Test func cpsCadenceUint16Rollover() throws {
        var crankState = CPSCrankState()
        // Simulate counter rollover: prevRevs = 65534, nextRevs = 1 → delta = 3 (wrapping)
        // prevTime = 65000, nextTime = 1512 → deltaTime = 2048 ticks = 2.0 s → 3 revs/2s × 60 = 90 rpm
        _ = FTMSParser.parseCyclingPowerMeasurement(
            cpsPacket(flags: 0x0020, power: 200, crankRevs: 65534, lastCrankEvent: 65000),
            crankState: &crankState
        )
        let data = cpsPacket(flags: 0x0020, power: 210, crankRevs: 1, lastCrankEvent: 1512)
        let metrics = try #require(FTMSParser.parseCyclingPowerMeasurement(data, crankState: &crankState))
        // delta revs = 1 &- 65534 = 3 (uint16 wrapping)
        // delta time = 1512 &- 65000 = 2048 ticks = 2.0 s
        // cadence = (3 / 2.0) × 60 = 90 rpm
        #expect(abs(metrics.cadence - 90.0) < 1.0)
    }

    @Test func cpsCadenceCoastingZeroDelta() throws {
        var crankState = CPSCrankState()
        // Two identical crank event times → coasting, cadence should remain 0
        _ = FTMSParser.parseCyclingPowerMeasurement(
            cpsPacket(flags: 0x0020, power: 200, crankRevs: 50, lastCrankEvent: 2048),
            crankState: &crankState
        )
        let data = cpsPacket(flags: 0x0020, power: 200, crankRevs: 50, lastCrankEvent: 2048)
        let metrics = try #require(FTMSParser.parseCyclingPowerMeasurement(data, crankState: &crankState))
        #expect(metrics.cadence == 0)
    }

    @Test func cpsCadenceSanityCapAt250rpm() throws {
        var crankState = CPSCrankState()
        _ = FTMSParser.parseCyclingPowerMeasurement(
            cpsPacket(flags: 0x0020, power: 200, crankRevs: 0, lastCrankEvent: 0),
            crankState: &crankState
        )
        // 100 revs in 1 tick (1/1024 s) → astronomically high rpm → must be rejected
        let data = cpsPacket(flags: 0x0020, power: 200, crankRevs: 100, lastCrankEvent: 1)
        let metrics = try #require(FTMSParser.parseCyclingPowerMeasurement(data, crankState: &crankState))
        #expect(metrics.cadence == 0) // sanity guard rejects absurd value
    }

    // MARK: - Heart Rate Measurement

    @Test func parseHeartRate8Bit() throws {
        // Flags: 0x00 (8-bit HR value), HR: 142
        let data = Data([0x00, 0x8E])
        let hr = try #require(FTMSParser.parseHeartRate(data))
        #expect(hr == 142)
    }

    @Test func parseHeartRate16Bit() throws {
        // Flags: 0x01 (16-bit HR value), HR: 180 (0x00B4 LE) — parser rejects > 250 bpm.
        let data = Data([0x01, 0xB4, 0x00])
        let hr = try #require(FTMSParser.parseHeartRate(data))
        #expect(hr == 180)
    }

    @Test func parseHeartRateTooShortReturnsNil() throws {
        let data = Data([0x00])
        #expect(FTMSParser.parseHeartRate(data) == nil)
    }
}
