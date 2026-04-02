import Foundation
import Combine

enum DataSourceType: String, Sendable {
    case bluetooth
    case wifi
    case none
}

enum PrimaryDataSource: Sendable {
    case bluetooth
    case wifi
    case none

    var description: String {
        switch self {
        case .bluetooth: return "Bluetooth"
        case .wifi: return "WiFi"
        case .none: return "None"
        }
    }
}

@Observable
@MainActor
final class DataSourceCoordinator {
    let bleManager: BLEManager
    let wifiService: WiFiTrainerService

    var activeDataSource: PrimaryDataSource = .none

    // Stored directly — the two-level computed proxy (public → effectiveX → activeX)
    // added two dead function calls per access with no logic in between.
    private(set) var power: Int = 0
    private(set) var cadence: Double = 0
    private(set) var speed: Double = 0
    private(set) var heartRate: Int = 0
    private(set) var totalDistance: Double = 0

    /// EMA-smoothed watts from the active transport (BLE or Wi‑Fi). **Not** used for workout recording;
    /// `WorkoutManager` ingests raw per-packet power from `CyclingMetrics` instead. Handy for secondary UI or debugging.
    private(set) var smoothedPower: Int = 0

    private var metricsSubscribers: [String: (Int, Double, Double, Int, Double) -> Void] = [:]
    private var cyclingMetricsSubscribers: [String: (CyclingMetrics) -> Void] = [:]

    private var bleSubscriberID = "DataSourceCoordinatorBLE"
    private var wifiSubscriberID = "DataSourceCoordinatorWiFi"

    init(bleManager: BLEManager, wifiService: WiFiTrainerService) {
        self.bleManager = bleManager
        self.wifiService = wifiService

        setupSubscriptions()
    }

    private func setupSubscriptions() {
        // Both BLEManager (DispatchQueue.main + assumeIsolated) and WiFiTrainerService
        // (Task { @MainActor }) already hop to main before calling subscribers.
        // No extra Task wrapper needed — avoids ~12 unnecessary Task allocs/sec.
        bleManager.subscribe(id: bleSubscriberID) { [weak self] metrics in
            self?.handleBLEMetrics(metrics)
        }

        wifiService.subscribe(id: wifiSubscriberID) { [weak self] p, c, s, hr, dist in
            self?.handleWiFiMetrics(power: p, cadence: c, speed: s, heartRate: hr, distance: dist)
        }
    }

    private func handleBLEMetrics(_ metrics: CyclingMetrics) {
        // WiFi stream takes priority whenever a WiFi trainer session is active.
        if wifiService.connectionState.isConnected {
            return
        }

        activeDataSource = .bluetooth
        power = metrics.power
        cadence = metrics.cadence
        speed = metrics.speed
        heartRate = metrics.heartRate
        totalDistance = metrics.totalDistance
        smoothedPower = bleManager.smoothedPower

        notifySubscribers()
        notifyCyclingMetricsSubscribers(metrics: metrics)
    }

    private func handleWiFiMetrics(power p: Int, cadence c: Double, speed s: Double, heartRate hr: Int, distance dist: Double) {
        // WiFi always takes priority
        activeDataSource = .wifi

        power = p
        cadence = c
        speed = s
        heartRate = hr
        totalDistance = dist
        smoothedPower = wifiService.smoothedPower

        notifySubscribers()
        notifyCyclingMetricsSubscribersWiFi()
    }

    // MARK: - Public API

    func subscribe(id: String, handler: @escaping (Int, Double, Double, Int, Double) -> Void) {
        metricsSubscribers[id] = handler
    }

    func unsubscribe(id: String) {
        metricsSubscribers.removeValue(forKey: id)
    }

    /// Unified `CyclingMetrics` for workout recording (BLE + WiFi). Prefer over raw `bleManager` when both exist.
    func subscribeCyclingMetrics(id: String, handler: @escaping (CyclingMetrics) -> Void) {
        cyclingMetricsSubscribers[id] = handler
        var m = CyclingMetrics(lastUpdate: Date())
        m.power = power
        m.cadence = cadence
        m.speed = speed
        m.heartRate = heartRate
        m.totalDistance = totalDistance
        m.hrSource = bleManager.metrics.hrSource
        handler(m)
    }

    func unsubscribeCyclingMetrics(id: String) {
        cyclingMetricsSubscribers.removeValue(forKey: id)
    }

    private func notifySubscribers() {
        guard !metricsSubscribers.isEmpty else { return }
        for handler in metricsSubscribers.values {
            handler(power, cadence, speed, heartRate, totalDistance)
        }
    }

    private func notifyCyclingMetricsSubscribers(metrics: CyclingMetrics) {
        guard !cyclingMetricsSubscribers.isEmpty else { return }
        for handler in cyclingMetricsSubscribers.values {
            handler(metrics)
        }
    }

    private func notifyCyclingMetricsSubscribersWiFi() {
        guard !cyclingMetricsSubscribers.isEmpty else { return }
        var m = CyclingMetrics(lastUpdate: Date())
        m.power = power
        m.cadence = cadence
        m.speed = speed
        m.heartRate = heartRate
        m.totalDistance = totalDistance
        m.hrSource = bleManager.metrics.hrSource
        for handler in cyclingMetricsSubscribers.values {
            handler(m)
        }
    }

    // MARK: - Connection Management

    func startWiFiDiscovery() {
        wifiService.startDiscovery()
    }

    func stopWiFiDiscovery() {
        wifiService.stopDiscovery()
    }

    func connectWiFi(to trainer: DiscoveredWiFiTrainer) {
        wifiService.connect(to: trainer)
    }

    func disconnectWiFi() {
        wifiService.disconnect()
    }

    // MARK: - Auto-selection

    /// Called when either data source changes state
    func updateActiveSource() {
        let wifiConnected = wifiService.connectionState.isConnected
        let bleConnected = bleManager.trainerConnectionState.isConnected

        // WiFi takes priority if available
        if wifiConnected {
            activeDataSource = .wifi
        } else if bleConnected {
            activeDataSource = .bluetooth
        } else {
            activeDataSource = .none
        }
    }

    // MARK: - Computed Properties

    var isConnected: Bool {
        bleManager.trainerConnectionState.isConnected || wifiService.connectionState.isConnected
    }

    var connectionDescription: String {
        if wifiService.connectionState.isConnected {
            return "WiFi: \(wifiService.connectedTrainer?.name ?? "Unknown")"
        } else if bleManager.trainerConnectionState.isConnected {
            return "BLE: \(bleManager.connectedTrainerName ?? "Unknown")"
        } else {
            return "Disconnected"
        }
    }

    var trainerConnectionQuality: String {
        if wifiService.connectionState.isConnected {
            return "WiFi (Excellent)"
        } else if bleManager.trainerConnectionState.isConnected {
            return "BLE (\(bleManager.trainerConnectionQuality.description))"
        } else {
            return "Disconnected"
        }
    }

    var rssi: Int {
        wifiService.connectionState.isConnected ? -30 : bleManager.trainerRSSI
    }

    var isWiFiAvailable: Bool {
        !wifiService.discoveredTrainers.isEmpty || wifiService.connectionState == .discovering
    }

    var discoveredWiFiTrainers: [DiscoveredWiFiTrainer] {
        wifiService.discoveredTrainers
    }

    var wifiConnectionState: WiFiConnectionState {
        wifiService.connectionState
    }

    /// Trainer link as a single BLE-style state for status badges (Wi‑Fi takes priority when active).
    var trainerLinkDisplayState: BLEConnectionState {
        switch wifiService.connectionState {
        case .connected(let name):
            return .connected(name)
        case .connecting(let name):
            return .connecting(name)
        case .discovering:
            return .scanning
        default:
            break
        }
        return bleManager.trainerConnectionState
    }

    /// True when the active trainer link shows connected but power/data has gone quiet (>2s).
    var isTrainerLinkDataStale: Bool {
        if wifiService.connectionState.isConnected {
            guard let last = wifiService.lastPacketReceived else { return true }
            return Date().timeIntervalSince(last) > 2
        }
        return bleManager.isDataStale
    }

    var bleConnectionState: BLEConnectionState {
        bleManager.trainerConnectionState
    }

    var hrConnectionState: BLEConnectionState {
        bleManager.hrConnectionState
    }

    var connectedHRName: String? {
        bleManager.connectedHRName
    }

    func disconnectAll() {
        bleManager.disconnectAll()
        wifiService.disconnect()
    }
}
