// Features/Workout/Presentation/ViewModel/WorkoutViewModel.swift
import Foundation

@MainActor
@Observable
final class WorkoutViewModel {
    // MARK: - View state
    var workouts: [Workout] = []
    var isLoading: Bool = false
    var error: String? = nil

    // MARK: - Live workout metrics (during recording)
    var elapsedSeconds: Int = 0
    var currentPower: Int = 0
    var currentCadence: Double = 0
    var currentHeartRate: Int = 0
    var normalizedPower: Double = 0
    var intensityFactor: Double = 0
    var tss: Double = 0

    func updateMetrics(powerSamples: [Int], durationSeconds: Int, ftp: Double) {
        let result = WorkoutMetricsAggregator.normalizedPowerIntensityAndTSS(
            powerSamples: powerSamples,
            durationSeconds: durationSeconds,
            ftp: ftp
        )
        normalizedPower = result.np
        intensityFactor = result.intensityFactor
        tss = result.tss
    }
}
