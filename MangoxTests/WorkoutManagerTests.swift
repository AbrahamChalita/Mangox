import Foundation
import SwiftData
import Testing
@testable import Mangox

struct WorkoutManagerTests {

    @MainActor
    @Test func stateTransitionsAndAutoPause() throws {
        let manager = WorkoutManager()
        let bleManager = BLEManager()

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSample.self,
            LapSplit.self,
            configurations: config
        )
        let context = ModelContext(container)

        manager.configure(bleManager: bleManager, modelContext: context)
        manager.startWorkout()

        #expect(manager.state == .recording)

        manager.ingest(sample(power: 220, distance: 30, heartRate: 145))
        manager.pause()

        #expect(manager.state == .paused)

        manager.resume()
        #expect(manager.state == .recording)

        manager.ingest(sample(power: 0, distance: 30))
        manager.ingest(sample(power: 0, distance: 30))
        manager.ingest(sample(power: 0, distance: 30))

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
    @Test func normalizedPowerAndTSSCalculation() throws {
        let manager = WorkoutManager()
        let bleManager = BLEManager()

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSample.self,
            LapSplit.self,
            configurations: config
        )
        let context = ModelContext(container)

        manager.configure(bleManager: bleManager, modelContext: context)
        manager.startWorkout()

        for second in 1...60 {
            manager.ingest(sample(power: 200, distance: Double(second * 10), heartRate: 150))
        }

        manager.endWorkout()

        let workout = try #require(manager.workout)
        let ftp = Double(PowerZone.ftp)
        let expectedNP = 200.0
        let expectedIF = expectedNP / ftp
        let expectedTSS = (60.0 * expectedNP * expectedIF) / (ftp * 3600.0) * 100.0

        #expect(workout.duration == 60)
        #expect(abs(workout.normalizedPower - expectedNP) < 0.001)
        #expect(abs(workout.intensityFactor - expectedIF) < 0.001)
        #expect(abs(workout.tss - expectedTSS) < 0.001)
        #expect(abs(workout.distance - 600) < 0.001)
    }

    @MainActor
    @Test func distanceFallsBackToSpeedIntegrationWhenFTMSDistanceMissing() throws {
        let manager = WorkoutManager()
        let bleManager = BLEManager()

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSample.self,
            LapSplit.self,
            configurations: config
        )
        let context = ModelContext(container)

        manager.configure(bleManager: bleManager, modelContext: context)
        manager.startWorkout()

        // 36 km/h = 10 m/s. Over 10 seconds expected fallback distance = 100m.
        for _ in 1...10 {
            manager.ingest(sample(power: 180, distance: 0, speed: 36))
        }

        manager.endWorkout()

        let workout = try #require(manager.workout)
        #expect(abs(workout.distance - 100) < 0.001)
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
