import Foundation

/// Contract for unified data-source coordination (BLE + Wi-Fi).
/// Concrete implementation: `DataSourceCoordinator` in Indoor/Data/DataSources/.
@MainActor
protocol DataSourceServiceProtocol: AnyObject {
    // MARK: - Metrics
    var power: Int { get }
    var cadence: Double { get }
    var speed: Double { get }
    var heartRate: Int { get }
    var totalDistance: Double { get }
    var smoothedPower: Int { get }

    // MARK: - Active Source
    var activeDataSource: PrimaryDataSource { get }

    // MARK: - Connection Status
    var isConnected: Bool { get }
    var connectionDescription: String { get }
    var trainerConnectionQuality: String { get }
    var rssi: Int { get }

    // MARK: - Trainer Link Display
    var trainerLinkDisplayState: BLEConnectionState { get }
    var isTrainerLinkDataStale: Bool { get }

    // MARK: - BLE Pass-through
    var bleConnectionState: BLEConnectionState { get }
    var hrConnectionState: BLEConnectionState { get }
    var connectedHRName: String? { get }

    // MARK: - Wi-Fi
    var isWiFiAvailable: Bool { get }
    var discoveredWiFiTrainers: [DiscoveredWiFiTrainer] { get }
    var wifiConnectionState: WiFiConnectionState { get }
    var connectedWiFiTrainer: DiscoveredWiFiTrainer? { get }

    // MARK: - Methods
    func updateActiveSource()
    func disconnectAll()
    func disconnectWiFi()
    func startWiFiDiscovery()
    func stopWiFiDiscovery()
    func connectWiFi(to trainer: DiscoveredWiFiTrainer)

    // MARK: - Metrics Subscription
    func subscribeCyclingMetrics(id: String, handler: @escaping (CyclingMetrics) -> Void)
    func unsubscribeCyclingMetrics(id: String)
}
