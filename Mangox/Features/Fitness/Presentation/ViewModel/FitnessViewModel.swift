// Features/Fitness/Presentation/ViewModel/FitnessViewModel.swift
import Foundation

@MainActor
@Observable
final class FitnessViewModel {
    // MARK: - Dependencies
    private let fitnessTracker: FitnessTrackerProtocol
    private let healthKit: HealthKitServiceProtocol

    // MARK: - View state
    var weeklyTSS: Double = 0
    var weeklyRides: Int = 0
    var powerCurve: [PowerCurveAnalytics.Point] = []
    var isLoading: Bool = false
    var error: String? = nil

    init(fitnessTracker: FitnessTrackerProtocol, healthKit: HealthKitServiceProtocol) {
        self.fitnessTracker = fitnessTracker
        self.healthKit = healthKit
    }

    func loadPowerCurve(from powerStreams: [[Int]]) {
        powerCurve = PowerCurveAnalytics.compute(from: powerStreams)
    }
}
