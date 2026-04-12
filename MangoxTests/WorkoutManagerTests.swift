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

        manager.ingest(sample(power: 220, distance: 30, heartRate: 145, speed: 30))
        await waitOneTick()
        manager.pause()

        #expect(manager.state == .paused)

        manager.resume()
        #expect(manager.state == .recording)

        for _ in 0..<3 {
            manager.ingest(sample(power: 0, distance: 30, speed: 0))
            await waitOneTick()
        }

        #expect(manager.state == .autoPaused)

        let workout = try #require(manager.workout)
        #expect(workout.status == .paused)

        manager.resume()
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
            manager.ingest(sample(power: 200, distance: Double(second * 10), heartRate: 150))
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

    @MainActor
    private func waitOneTick() async {
        try? await Task.sleep(for: .milliseconds(1050))
    }

    private func sample(power: Int, distance: Double, heartRate: Int = 0, speed: Double = 32) -> CyclingMetrics {
        CyclingMetrics(
            power: power,
            cadence: 90,
            speed: speed,
            heartRate: heartRate,
            hrSource: heartRate > 0 ? .ftmsEmbedded : .none,
            totalDistance: distance,
            lastUpdate: Date()
        )
    }
}
