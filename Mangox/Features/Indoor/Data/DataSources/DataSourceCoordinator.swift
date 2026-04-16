import Foundation

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
final class DataSourceCoordinator: DataSourceServiceProtocol {
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
    private(set) var hrSource: HRSource = .none
    private(set) var activeTotalDistanceFieldPresent: Bool = false

    /// EMA-smoothed watts from the active transport (BLE or Wi‑Fi). **Not** used for workout recording;
    /// `WorkoutManager` ingests raw per-packet power from `CyclingMetrics` instead. Handy for secondary UI or debugging.
    private(set) var smoothedPower: Int = 0

    /// Updated from `publishActiveMetrics` only while a live route is active so views do not observe `lastPacketReceived` every BLE tick.
    private(set) var isTrainerLinkDataStale: Bool = false

    private var metricsSubscribers: [String: (Int, Double, Double, Int, Double) -> Void] = [:]
    private var cyclingMetricsSubscribers: [String: (CyclingMetrics) -> Void] = [:]

    /// Always reflects the latest unified metrics for `subscribeCyclingMetrics` / recording, independent of SwiftUI observation gating.
    private var lastPublishedCyclingMetrics = CyclingMetrics()

    private var bleSubscriberID = "DataSourceCoordinatorBLE"
    private var wifiSubscriberID = "DataSourceCoordinatorWiFi"

    private var lastBLEMetrics: CyclingMetrics?
    private var lastWiFiMetrics: CyclingMetrics?
    private var pendingSourceCandidate: PrimaryDataSource?
    private var pendingSourceSince: Date?

    private let sourceStaleThreshold: TimeInterval = 2.0
    private let sourceSwitchHysteresis: TimeInterval = 1.2

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
        lastBLEMetrics = metrics
        updateActiveSourcePolicy(now: Date())
        publishActiveMetrics()
    }

    private func handleWiFiMetrics(power p: Int, cadence c: Double, speed s: Double, heartRate hr: Int, distance dist: Double) {
        var metrics = CyclingMetrics(lastUpdate: Date())
        metrics.power = p
        metrics.cadence = c
        metrics.speed = s
        metrics.heartRate = hr
        metrics.totalDistance = dist
        metrics.includesTotalDistanceInPacket = wifiService.lastPacketIncludedDistance
        metrics.hrSource = bleManager.metrics.hrSource
        lastWiFiMetrics = metrics

        updateActiveSourcePolicy(now: Date())
        publishActiveMetrics()
    }

    private func updateActiveSourcePolicy(now: Date) {
        let wifiConnected = wifiService.connectionState.isConnected
        let bleConnected = bleManager.trainerConnectionState.isConnected

        let wifiFresh = isWiFiFresh(now)
        let bleFresh = isBLEFresh(now)

        let preferred: PrimaryDataSource
        if wifiFresh {
            preferred = .wifi
        } else if bleFresh {
            preferred = .bluetooth
        } else if wifiConnected {
            preferred = .wifi
        } else if bleConnected {
            preferred = .bluetooth
        } else {
            preferred = .none
        }

        // Immediate switch if current source is stale/missing and an alternate source is available.
        if shouldSwitchImmediately(to: preferred, now: now) {
            activeDataSource = preferred
            pendingSourceCandidate = nil
            pendingSourceSince = nil
            return
        }

        guard preferred != activeDataSource else {
            pendingSourceCandidate = nil
            pendingSourceSince = nil
            return
        }

        if pendingSourceCandidate != preferred {
            pendingSourceCandidate = preferred
            pendingSourceSince = now
            return
        }

        guard let pendingSourceSince else { return }
        if now.timeIntervalSince(pendingSourceSince) >= sourceSwitchHysteresis {
            activeDataSource = preferred
            self.pendingSourceCandidate = nil
            self.pendingSourceSince = nil
        }
    }

    private func shouldSwitchImmediately(to preferred: PrimaryDataSource, now: Date) -> Bool {
        guard preferred != activeDataSource else { return false }
        switch activeDataSource {
        case .wifi:
            return !isWiFiFresh(now) && preferred != .wifi
        case .bluetooth:
            return !isBLEFresh(now) && preferred != .bluetooth
        case .none:
            return true
        }
    }

    private func isWiFiFresh(_ now: Date) -> Bool {
        guard wifiService.connectionState.isConnected, let last = wifiService.lastPacketReceived else {
            return false
        }
        return now.timeIntervalSince(last) <= sourceStaleThreshold
    }

    private func isBLEFresh(_ now: Date) -> Bool {
        guard bleManager.trainerConnectionState.isConnected, let last = bleManager.lastPacketReceived else {
            return false
        }
        return now.timeIntervalSince(last) <= sourceStaleThreshold
    }

    private func publishActiveMetrics() {
        let selectedMetrics: CyclingMetrics?
        let smoothed: Int
        switch activeDataSource {
        case .wifi:
            selectedMetrics = lastWiFiMetrics ?? lastBLEMetrics
            smoothed = wifiService.connectionState.isConnected ? wifiService.smoothedPower : bleManager.smoothedPower
        case .bluetooth:
            selectedMetrics = lastBLEMetrics ?? lastWiFiMetrics
            smoothed = bleManager.smoothedPower
        case .none:
            selectedMetrics = nil
            smoothed = 0
        }

        guard let metrics = selectedMetrics else {
            lastPublishedCyclingMetrics = CyclingMetrics()
            power = 0
            cadence = 0
            speed = 0
            heartRate = 0
            totalDistance = 0
            hrSource = .none
            activeTotalDistanceFieldPresent = false
            smoothedPower = 0
            isTrainerLinkDataStale = false
            notifySubscribersDisconnected()
            notifyCyclingMetricsSubscribersWiFi()
            return
        }

        lastPublishedCyclingMetrics = metrics
        notifyCyclingMetricsSubscribers(metrics: metrics)

        let liveUI = TrainerSensorLiveObservationGate.isLiveRouteActive
        if liveUI {
            power = metrics.power
            cadence = metrics.cadence
            speed = metrics.speed
            heartRate = metrics.heartRate
            totalDistance = metrics.totalDistance
            activeTotalDistanceFieldPresent = metrics.includesTotalDistanceInPacket
            smoothedPower = smoothed
            isTrainerLinkDataStale = computeTrainerLinkDataStale()
        }
        if hrSource != metrics.hrSource {
            hrSource = metrics.hrSource
        }
    }

    private func computeTrainerLinkDataStale() -> Bool {
        if wifiService.connectionState.isConnected {
            guard let last = wifiService.lastPacketReceived else { return true }
            return Date().timeIntervalSince(last) > 2
        }
        guard bleManager.trainerConnectionState.isConnected, let last = bleManager.lastPacketReceived else {
            return false
        }
        return Date().timeIntervalSince(last) > 2
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
        handler(lastPublishedCyclingMetrics)
    }

    func unsubscribeCyclingMetrics(id: String) {
        cyclingMetricsSubscribers.removeValue(forKey: id)
    }

    private func notifySubscribersDisconnected() {
        guard !metricsSubscribers.isEmpty else { return }
        for handler in metricsSubscribers.values {
            handler(0, 0, 0, 0, 0)
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
        for handler in cyclingMetricsSubscribers.values {
            handler(lastPublishedCyclingMetrics)
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

    func snapshotUnifiedMetrics() -> CyclingMetrics {
        lastPublishedCyclingMetrics
    }

    // MARK: - Auto-selection

    /// Called when either data source changes state
    func updateActiveSource() {
        updateActiveSourcePolicy(now: Date())
        publishActiveMetrics()
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

    var connectedWiFiTrainer: DiscoveredWiFiTrainer? {
        wifiService.connectedTrainer
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
