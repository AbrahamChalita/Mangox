// Features/Indoor/Presentation/ViewModel/IndoorViewModel.swift
import Foundation

@MainActor
@Observable
final class IndoorViewModel {
    // MARK: - View state (sourced from DataSourceCoordinator / BLEManager via DIContainer)
    var currentMetrics: CyclingMetrics = CyclingMetrics()
    var isConnected: Bool = false
    var connectionError: String? = nil
    var elapsedSeconds: Int = 0
    var isRecording: Bool = false

    // MARK: - Trainer metrics helpers
    func meanPower(samples: [Int]) -> Int {
        TrainerPowerMetrics.meanInt(samples: samples)
    }

    func peakPower(samples: [Int]) -> Int {
        TrainerPowerMetrics.peakInt(samples: samples)
    }
}
