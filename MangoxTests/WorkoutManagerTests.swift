import Foundation
import Testing
@testable import Mangox

struct WorkoutManagerTests {

    @MainActor
    @Test func stateTransitionsAndAutoPause() async throws {
        let manager = WorkoutManager()
        let bleManager = BLEManager()
        manager.configure(bleService: bleManager)
        manager.startWorkout()

        #expect(manager.state == .recording)

        manager.ingest(
            sample(
                power: 220, distance: 30, heartRate: 145, speed: 30,
                includesTotalDistanceInPacket: true))
        await waitOneTick()
        manager.pause()

        #expect(manager.state == .paused)

        manager.resume(fromUserControls: false)
        #expect(manager.state == .recording)

        for _ in 0..<3 {
            manager.ingest(
                sample(power: 0, distance: 30, speed: 0, includesTotalDistanceInPacket: true))
            await waitOneTick()
        }

        #expect(manager.state == .autoPaused)

        let workout = try #require(manager.workout)
        #expect(workout.status == .paused)

        manager.pause()
        #expect(manager.state == .paused)

        manager.resume(fromUserControls: false)
        #expect(manager.state == .recording)

        manager.endWorkout()

        #expect(manager.state == .finished)
        #expect(workout.status == .completed)
    }

    @MainActor
    @Test func normalizedPowerAndTSSCalculation() async throws {
        let manager = WorkoutManager()
        let bleManager = BLEManager()
        manager.configure(bleService: bleManager)
        manager.startWorkout()

        for second in 1...31 {
            manager.ingest(
                sample(
                    power: 200, distance: Double(second * 10), heartRate: 150,
                    includesTotalDistanceInPacket: true))
            await waitOneTick()
        }

        manager.endWorkout()

        let workout = try #require(manager.workout)
        let ftp = Double(PowerZone.ftp)
        #expect(workout.duration >= 30 && workout.duration <= 34)
        #expect(workout.normalizedPower >= 170 && workout.normalizedPower <= 210)
        #expect(abs(workout.intensityFactor - (workout.normalizedPower / ftp)) < 0.001)
        #expect(workout.tss > 0)
        #expect(workout.distance > 250)
    }

    @MainActor
    @Test func distanceFallsBackToSpeedIntegrationWhenFTMSDistanceMissing() async throws {
        let manager = WorkoutManager()
        let bleManager = BLEManager()
        manager.configure(bleService: bleManager)
        manager.startWorkout()

        // 36 km/h = 10 m/s. Over 10 seconds expected fallback distance = 100m.
        for _ in 1...10 {
            manager.ingest(sample(power: 180, distance: 0, speed: 36))
            await waitOneTick()
        }

        manager.endWorkout()

        let workout = try #require(manager.workout)
        #expect(abs(workout.distance - 100) < 15)
    }

    /// Speed integration must not advance during pause (timer stopped); first tick after resume uses ~1s dt.
    @MainActor
    @Test func distanceDoesNotSpikeAcrossPauseResume() async throws {
        let manager = WorkoutManager()
        let bleManager = BLEManager()
        manager.configure(bleService: bleManager)
        manager.startWorkout()

        for _ in 1...3 {
            manager.ingest(sample(power: 180, distance: 0, speed: 36))
            await waitOneTick()
        }
        manager.pause()
        try await Task.sleep(for: .milliseconds(2500))
        manager.resume()
        for _ in 1...3 {
            manager.ingest(sample(power: 180, distance: 0, speed: 36))
            await waitOneTick()
        }

        manager.endWorkout()

        let workout = try #require(manager.workout)
        // 6 s × 10 m/s ≈ 60 m; a multi-second dt bug would push this toward ~85 m+.
        #expect(workout.distance > 45)
        #expect(workout.distance < 78)
    }

    /// A bogus `totalDistance` in the struct must not move the odometer unless the transport marked it present.
    @MainActor
    @Test func staleTotalDistanceIgnoredWithoutFieldPresent() async throws {
        let manager = WorkoutManager()
        let bleManager = BLEManager()
        manager.configure(bleService: bleManager)
        manager.startWorkout()

        manager.ingest(
            sample(
                power: 200, distance: 20, speed: 10, includesTotalDistanceInPacket: true))
        await waitOneTick()
        manager.ingest(
            sample(
                power: 200, distance: 40, speed: 10, includesTotalDistanceInPacket: true))
        await waitOneTick()
        manager.ingest(
            sample(
                power: 200, distance: 999_999, speed: 10, includesTotalDistanceInPacket: false))
        await waitOneTick()

        manager.endWorkout()
        let workout = try #require(manager.workout)
        #expect(workout.distance < 1_000)
        #expect(workout.distance > 35)
    }

    @MainActor
    @Test func elapsedBackfillsAfterDelayedTickUsingWallClock() async throws {
        let manager = WorkoutManager()
        let bleManager = BLEManager()
        manager.configure(bleService: bleManager)
        manager.startWorkout()

        let now = Date()
        manager.debugConfigureWallClock(recordingStart: now.addingTimeInterval(-8))
        manager.ingest(
            sample(
                power: 220, distance: 40, heartRate: 145, speed: 30,
                includesTotalDistanceInPacket: true))
        manager.debugProcessSecondSample(at: now)

        #expect(manager.elapsedSeconds >= 8)
        manager.endWorkout()
        let workout = try #require(manager.workout)
        #expect(workout.sampleCount >= 8)
    }

    @MainActor
    @Test func elapsedExcludesPausedDurationWhenDerivedFromWallClock() async throws {
        let manager = WorkoutManager()
        let bleManager = BLEManager()
        manager.configure(bleService: bleManager)
        manager.startWorkout()

        let now = Date()
        manager.debugConfigureWallClock(recordingStart: now.addingTimeInterval(-20), pausedDuration: 7)
        manager.ingest(
            sample(
                power: 210, distance: 30, heartRate: 140, speed: 28,
                includesTotalDistanceInPacket: true))
        manager.debugProcessSecondSample(at: now)

        #expect(manager.elapsedSeconds >= 13)
        #expect(manager.elapsedSeconds <= 14)
    }

    @MainActor
    private func waitOneTick() async {
        try? await Task.sleep(for: .milliseconds(1050))
    }

    private func sample(
        power: Int,
        distance: Double,
        heartRate: Int = 0,
        speed: Double = 32,
        includesTotalDistanceInPacket: Bool = false
    ) -> CyclingMetrics {
        CyclingMetrics(
            power: power,
            cadence: 90,
            speed: speed,
            heartRate: heartRate,
            hrSource: heartRate > 0 ? .ftmsEmbedded : .none,
            totalDistance: distance,
            includesTotalDistanceInPacket: includesTotalDistanceInPacket,
            lastUpdate: Date()
        )
    }
}
