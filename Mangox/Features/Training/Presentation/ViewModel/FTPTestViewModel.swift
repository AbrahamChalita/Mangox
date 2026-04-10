// Features/Training/Presentation/ViewModel/FTPTestViewModel.swift
import Foundation

/// ViewModel for the FTP Test screen.
/// Owns protocol-typed service dependencies so the view is decoupled from concrete types.
@Observable
@MainActor
final class FTPTestViewModel {

    // MARK: - Service Dependencies (protocol-typed)

    private let bleService: BLEServiceProtocol
    private let dataSourceService: DataSourceServiceProtocol

    // MARK: - Manager

    let manager = FTPTestManager()

    // MARK: - Init

    init(
        bleService: BLEServiceProtocol,
        dataSourceService: DataSourceServiceProtocol
    ) {
        self.bleService = bleService
        self.dataSourceService = dataSourceService
    }

    // MARK: - Lifecycle

    /// Call on view appear to activate the data source and wire up the manager.
    func onAppear() {
        dataSourceService.updateActiveSource()
        manager.configure(bleService: bleService, dataSourceService: dataSourceService)
    }

    /// Call on view disappear to release subscriptions.
    func onDisappear() {
        manager.tearDown()
    }

    // MARK: - Live Metrics

    /// Aggregated cycling metrics from the data source and BLE service.
    var metrics: CyclingMetrics {
        var m = CyclingMetrics(lastUpdate: Date())
        m.power = dataSourceService.power
        m.cadence = dataSourceService.cadence
        m.speed = dataSourceService.speed
        m.heartRate = dataSourceService.heartRate
        m.totalDistance = dataSourceService.totalDistance
        m.hrSource = bleService.metrics.hrSource
        return m
    }
}
