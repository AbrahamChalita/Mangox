import CoreBluetooth
import Foundation

/// Contract for Bluetooth Low Energy device management and cycling metrics.
/// Concrete implementation: `BLEManager` in Indoor/Data/BLE/.
@MainActor
protocol BLEServiceProtocol: AnyObject {
    // MARK: - Connection States
    var trainerConnectionState: BLEConnectionState { get }
    var hrConnectionState: BLEConnectionState { get }
    var cscConnectionState: BLEConnectionState { get }
    var bluetoothState: CBManagerState { get }

    // MARK: - Connected Device Names
    var connectedTrainerName: String? { get }
    var connectedHRName: String? { get }
    var connectedCSCName: String? { get }

    // MARK: - Discovery
    var discoveredPeripherals: [DiscoveredPeripheral] { get }
    var isScanningForDevices: Bool { get }
    var activePeripheralIDs: Set<UUID> { get }

    // MARK: - Metrics
    var metrics: CyclingMetrics { get }
    var smoothedPower: Int { get }
    var smoothedHR: Int { get }

    // MARK: - Connection Quality
    var trainerRSSI: Int { get }
    var trainerConnectionQuality: ConnectionQuality { get }
    var isDataStale: Bool { get }
    var isReconnecting: Bool { get }

    // MARK: - FTMS Trainer Control
    var ftmsControlIsAvailable: Bool { get }
    var ftmsControlSupportsERG: Bool { get }
    var ftmsControlSupportsSimulation: Bool { get }
    var ftmsControlSupportsResistance: Bool { get }
    var ftmsControlActiveMode: TrainerControlMode { get }

    /// Timestamp of the most recent BLE data packet from the trainer.
    var lastPacketReceived: Date? { get }

    // MARK: - FTMS Trainer Control Actions
    /// Set ERG mode — trainer locks to a specific wattage regardless of cadence.
    func setTargetPower(watts: Int) async throws
    /// Set resistance level (0.0–1.0 normalized, mapped to trainer's supported range).
    func setResistanceLevel(_ fraction: Double) async throws
    /// Set simulation mode grade in percent.
    func setSimulationGrade(_ gradePercent: Double) async throws
    /// Release trainer control and return to free ride.
    func releaseTrainerControl() async

    // MARK: - Scan & Connect
    func startScan()
    func stopScan()
    func reconnectOrScan()
    func connectTrainer(_ peripheral: CBPeripheral)
    func connectHRMonitor(_ peripheral: CBPeripheral)
    func connectCSCSensor(_ peripheral: CBPeripheral)
    func disconnectAll(clearSaved: Bool)
    func disconnectCSC()

    // MARK: - Metrics Subscription
    func subscribe(id: String, handler: @escaping (CyclingMetrics) -> Void)
    func unsubscribe(id: String)
}
