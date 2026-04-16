@preconcurrency import CoreBluetooth
import os.log

nonisolated private let bleLogger = Logger(subsystem: "com.abchalita.Mangox", category: "BLEManager")

// CoreBluetooth types are Objective-C classes and are not `Sendable`; we only ever finish delegate
// callbacks on the main actor. These wrappers silence Swift 6 diagnostics when crossing `@Sendable` boundaries.
private struct SendablePeripheral: @unchecked Sendable { let value: CBPeripheral }
private struct SendableService: @unchecked Sendable { let value: CBService }
private struct SendableCharacteristic: @unchecked Sendable { let value: CBCharacteristic }

enum BLEConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting(String)
    case connected(String)

    var label: String {
        switch self {
        case .disconnected: "Disconnected"
        case .scanning: "Scanning..."
        case .connecting(let name): "Connecting to \(name)..."
        case .connected(let name): "Connected to \(name)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

enum DeviceType: String, Sendable {
    case trainer
    case heartRateMonitor
    case cyclingSpeedCadence
    case unknown
}

struct DiscoveredPeripheral: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    var rssi: Int
    var deviceType: DeviceType
}

/// Connection quality based on RSSI signal strength.
enum ConnectionQuality: String, Sendable {
    case excellent
    case good
    case fair
    case poor
    case disconnected

    var description: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .disconnected: return "Disconnected"
        }
    }
}

@Observable
@MainActor
final class BLEManager: NSObject, BLEServiceProtocol {
    // Backward compatibility for existing UI logic.
    var connectionState: BLEConnectionState { trainerConnectionState }
    var isScanningForDevices: Bool { isScanning }

    var connectedTrainerName: String? {
        if case .connected(let name) = trainerConnectionState {
            return name
        }
        return nil
    }

    var connectedHRName: String? {
        if case .connected(let name) = hrConnectionState {
            return name
        }
        return nil
    }

    var connectedCSCName: String? {
        if case .connected(let name) = cscConnectionState {
            return name
        }
        return nil
    }

    var trainerConnectionState: BLEConnectionState = .disconnected
    var hrConnectionState: BLEConnectionState = .disconnected
    var cscConnectionState: BLEConnectionState = .disconnected

    /// UUIDs of peripherals that are currently connected or connecting — used to
    /// filter them out of the "discovered devices" scan list so they don't appear twice.
    var activePeripheralIDs: Set<UUID> {
        var ids = Set<UUID>()
        if let id = trainerPeripheral?.identifier { ids.insert(id) }
        if let id = hrPeripheral?.identifier { ids.insert(id) }
        if let id = cscPeripheral?.identifier { ids.insert(id) }
        return ids
    }
    var metrics = CyclingMetrics()
    var discoveredPeripherals: [DiscoveredPeripheral] = []
    var bluetoothState: CBManagerState = .unknown

    /// FTMS trainer control service — handles ERG, simulation, and resistance commands.
    let ftmsControl = FTMSControlService()

    // MARK: - FTMS Control Protocol Witnesses

    /// Whether an FTMS control point is available on the connected trainer.
    var ftmsControlIsAvailable: Bool { ftmsControl.isAvailable }

    /// Whether the trainer supports ERG (power target) mode.
    var ftmsControlSupportsERG: Bool { ftmsControl.supportsERG }

    /// Whether the trainer supports simulation (grade/wind) mode.
    var ftmsControlSupportsSimulation: Bool { ftmsControl.supportsSimulation }

    /// Whether the trainer supports resistance level mode.
    var ftmsControlSupportsResistance: Bool { ftmsControl.supportsResistance }

    /// The currently active FTMS trainer control mode.
    var ftmsControlActiveMode: TrainerControlMode { ftmsControl.activeMode }

    // MARK: - FTMS Trainer Control Actions (BLEServiceProtocol conformance)

    /// Set ERG mode — trainer locks to a specific wattage regardless of cadence.
    func setTargetPower(watts: Int) async throws {
        try await ftmsControl.setTargetPower(watts: watts)
    }

    /// Set resistance level (0.0–1.0 normalized, mapped to trainer's supported range).
    func setResistanceLevel(_ fraction: Double) async throws {
        try await ftmsControl.setResistanceLevel(fraction)
    }

    /// Set simulation mode using a grade percentage.
    func setSimulationGrade(_ gradePercent: Double) async throws {
        try await ftmsControl.setSimulation(grade: gradePercent)
    }

    /// Release trainer control and return to free ride.
    func releaseTrainerControl() async {
        await ftmsControl.releaseControl()
    }

    /// Smoothed power: exponential moving average of instantaneous BLE power readings.
    /// Updated on every incoming packet (~4 Hz) — no separate timer, no drift.
    /// α = 0.2 gives roughly a 4-packet (~1 second) smoothing window.
    /// UI should display this instead of raw `metrics.power` to avoid jitter.
    var smoothedPower: Int = 0

    /// Timestamp of the last BLE data packet received from the trainer.
    /// Used to detect radio silence while the peripheral stays "connected".
    var lastPacketReceived: Date? = nil

    /// True when the trainer is connected but no data packet has arrived in > 2 seconds.
    /// Distinguishes radio silence / BLE stack hiccup from intentional stopped-pedaling.
    var isDataStale: Bool {
        guard trainerConnectionState.isConnected, let last = lastPacketReceived else { return false }
        return Date().timeIntervalSince(last) > 2
    }

    /// Subscribers register closures here to receive event-driven metric updates
    /// every time a new BLE packet arrives. Key = arbitrary subscriber ID.
    private var metricsSubscribers: [String: (CyclingMetrics) -> Void] = [:]

    /// EMA smoothing factor for smoothedPower. 0.2 ≈ 1-second time constant at ~4 Hz packet rate.
    private let powerEMAAlpha: Double = 0.2
    /// Running EMA value (stored as Double for precision, exposed as Int).
    private var powerEMA: Double = 0

    /// Smoothed heart rate: exponential moving average of instantaneous HR readings.
    /// α = 0.3 gives roughly a 2-3 second smoothing window at ~1 Hz HR update rate.
    /// UI should display this instead of raw `metrics.heartRate` to avoid jitter.
    var smoothedHR: Int = 0

    /// EMA smoothing factor for HR. 0.3 ≈ 2-3 second window at ~1 Hz.
    private let hrEMAAlpha: Double = 0.3
    private var hrEMA: Double = 0

    /// Per-connection crank state for CPS cadence derivation.
    /// Owned here (not as a static on FTMSParser) so it resets automatically on disconnect
    /// and has no shared state between sessions.
    private var crankState = CPSCrankState()

    private var cscCrankState = CSCParser.CrankState()
    private var cscWheelState = CSCParser.WheelState()

    /// Dedicated serial queue for CoreBluetooth I/O.
    /// All delegate callbacks arrive on this queue, then are re-dispatched to the main
    /// thread via `DispatchQueue.main.async` + `MainActor.assumeIsolated`, keeping the
    /// main thread free from BLE I/O and avoiding `unsafeForcedSync` runtime warnings.
    private let bleQueue = DispatchQueue(label: "com.abchalita.Mangox.ble", qos: .userInteractive)

    private var centralManager: CBCentralManager!
    private static let centralRestoreIdentifier = "com.abchalita.Mangox.BLECentral"
    private var trainerPeripheral: CBPeripheral?
    private var hrPeripheral: CBPeripheral?
    private var cscPeripheral: CBPeripheral?
    private var peripheralRoles: [UUID: DeviceType] = [:]
    private var isScanning = false

    /// Connection timeout tasks — CoreBluetooth's `connect()` never times out
    /// on its own, so stale cache entries can hang forever.
    private var trainerConnectTimeout: Task<Void, Never>?
    private var hrConnectTimeout: Task<Void, Never>?
    private var cscConnectTimeout: Task<Void, Never>?
    /// Scan timeout task — auto-stops scanning after a fixed window so the UI
    /// doesn't sit on "Looking for devices…" indefinitely.
    private var scanTimeoutTask: Task<Void, Never>?

    /// How long to wait for a `didConnect` callback before giving up.
    private let connectionTimeoutSeconds: UInt64 = 8
    /// How long a scan runs before auto-stopping.
    private let scanTimeoutSeconds: UInt64 = 12

    /// Mid-ride BLE recovery — attempt to reconnect before fully disconnecting.
    /// Set to true when a disconnect happens during an active workout.
    /// The UI can check this to show "Reconnecting..." instead of "Disconnected".
    var isReconnecting: Bool = false
    private var reconnectTask: Task<Void, Never>?
    private let reconnectTimeoutSeconds: UInt64 = 15
    /// The trainer peripheral UUID to attempt reconnection to.
    private var reconnectTrainerUUID: UUID?

    // MARK: - RSSI Monitoring

    /// RSSI polling timer for connection quality monitoring
    private var rssiMonitorTask: Task<Void, Never>?

    /// Current signal strength (updated during connection)
    var trainerRSSI: Int = 0
    var hrRSSI: Int = 0

    /// Current connection quality for UI display
    var trainerConnectionQuality: ConnectionQuality {
        guard trainerConnectionState.isConnected else { return .disconnected }
        return qualityFromRSSI(trainerRSSI)
    }

    private func qualityFromRSSI(_ rssi: Int) -> ConnectionQuality {
        switch rssi {
        case -50...0: return .excellent
        case -60..<(-50): return .good
        case -70..<(-60): return .fair
        default: return .poor
        }
    }

    // MARK: - Mid-Ride Recovery

    /// Attempt to reconnect to the trainer after an unexpected disconnect.
    /// Preserves last-known metrics during the reconnect window.
    /// If reconnection succeeds within `reconnectTimeoutSeconds`, metrics resume seamlessly.
    /// If it fails, the trainer is fully disconnected and metrics are cleared.
    private func attemptReconnect(for role: DeviceType) {
        guard role == .trainer else { return }
        guard let uuid = savedTrainerUUID else { return }

        isReconnecting = true
        reconnectTask?.cancel()

        reconnectTask = Task { [weak self] in
            // BLEManager is @MainActor; closure inherits isolation — no hop needed
            guard let self else { return }

            // Try to retrieve the peripheral from cache and reconnect
            let cached = self.centralManager.retrievePeripherals(withIdentifiers: [uuid])
            guard let boxed = cached.first.map(SendablePeripheral.init) else {
                // No cached peripheral — fall back to scan
                self.finishReconnect(success: false)
                return
            }

            self.trainerPeripheral = boxed.value
            self.peripheralRoles[boxed.value.identifier] = .trainer
            self.trainerConnectionState = .connecting(boxed.value.name ?? "Unknown")
            boxed.value.delegate = self
            self.centralManager.connect(boxed.value, options: nil)

            // Wait for reconnect timeout
            try? await Task.sleep(nanoseconds: self.reconnectTimeoutSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }

            // If still not connected, give up
            if !self.trainerConnectionState.isConnected {
                self.centralManager.cancelPeripheralConnection(boxed.value)
                self.finishReconnect(success: false)
            }
        }
    }

    /// Clean up after reconnect attempt succeeds or fails.
    private func finishReconnect(success: Bool) {
        reconnectTask?.cancel()
        reconnectTask = nil
        isReconnecting = false

        if !success {
            // Full disconnect — clear everything
            trainerPeripheral = nil
            trainerConnectionState = .disconnected
            ftmsControl.detach()
            crankState.reset()
            trainerFTMSService = nil
            smoothedPower = 0
            powerEMA = 0
            smoothedHR = 0
            hrEMA = 0
            lastPacketReceived = nil
            trainerRSSI = 0

            if metrics.hrSource != .dedicated {
                metrics.heartRate = 0
                metrics.hrSource = .none
            }
        }
    }

    // MARK: - Persisted last-connected UUIDs

    private static let savedTrainerUUIDKey = "ble.lastTrainerUUID"
    private static let savedHRUUIDKey      = "ble.lastHRUUID"
    private static let savedCSCUUIDKey     = "ble.lastCSCUUID"

    private var savedTrainerUUID: UUID? {
        get {
            UserDefaults.standard.string(forKey: Self.savedTrainerUUIDKey)
                .flatMap { UUID(uuidString: $0) }
        }
        set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: Self.savedTrainerUUIDKey)
        }
    }

    private var savedHRUUID: UUID? {
        get {
            UserDefaults.standard.string(forKey: Self.savedHRUUIDKey)
                .flatMap { UUID(uuidString: $0) }
        }
        set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: Self.savedHRUUIDKey)
        }
    }

    private var savedCSCUUID: UUID? {
        get {
            UserDefaults.standard.string(forKey: Self.savedCSCUUIDKey)
                .flatMap { UUID(uuidString: $0) }
        }
        set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: Self.savedCSCUUIDKey)
        }
    }

    /// Reference to the FTMS service discovered on the trainer, used for control point attachment.
    private var trainerFTMSService: CBService?

    override init() {
        super.init()
        // Pass the dedicated BLE queue — CoreBluetooth callbacks arrive there
        // instead of the main thread, keeping the main runloop free for UI work.
        // Callbacks hop to main thread via DispatchQueue.main.async + MainActor.assumeIsolated.
        centralManager = CBCentralManager(
            delegate: self,
            queue: bleQueue,
            options: [CBCentralManagerOptionRestoreIdentifierKey: Self.centralRestoreIdentifier]
        )
    }

    // MARK: - Subscriber API

    /// Register a closure that fires every time new BLE metrics arrive.
    func subscribe(id: String, handler: @escaping (CyclingMetrics) -> Void) {
        metricsSubscribers[id] = handler
    }

    /// Remove a previously registered subscriber.
    func unsubscribe(id: String) {
        metricsSubscribers.removeValue(forKey: id)
    }

    private func notifySubscribers() {
        lastPacketReceived = Date()
        let snapshot = metrics
        for handler in metricsSubscribers.values {
            handler(snapshot)
        }
    }

    // MARK: - EMA Power Smoothing

    /// Update the EMA with a new instantaneous power reading.
    /// Called on every BLE packet — no timer needed, no drift possible.
    private func updateSmoothedPower(_ newPower: Int) {
        if powerEMA == 0 {
            // Seed the EMA with the first real reading instead of blending from 0.
            powerEMA = Double(newPower)
        } else {
            powerEMA = powerEMAAlpha * Double(newPower) + (1 - powerEMAAlpha) * powerEMA
        }
        smoothedPower = Int(powerEMA.rounded())
    }

    /// Update the EMA with a new instantaneous heart rate reading.
    private func updateSmoothedHR(_ newHR: Int) {
        guard newHR > 0 else { return }
        if hrEMA == 0 {
            hrEMA = Double(newHR)
        } else {
            hrEMA = hrEMAAlpha * Double(newHR) + (1 - hrEMAAlpha) * hrEMA
        }
        smoothedHR = Int(hrEMA.rounded())
    }

    /// Try to reconnect to the last-known peripherals instantly via the CoreBluetooth
    /// cache before falling back to a full RF scan. Call this on view appear.
    func reconnectOrScan() {
        guard centralManager.state == .poweredOn else { return }

        let needTrainer = !trainerConnectionState.isConnected && trainerPeripheral == nil
        let needHR      = !hrConnectionState.isConnected && hrPeripheral == nil
        let needCSC     = !cscConnectionState.isConnected && cscPeripheral == nil

        // Nothing to do — both slots filled.
        guard needTrainer || needHR || needCSC else { return }

        var uuidsToRetrieve: [UUID] = []
        if needTrainer, let tid = savedTrainerUUID {
            uuidsToRetrieve.append(tid)
        }
        if needHR, let hid = savedHRUUID, hid != savedTrainerUUID {
            uuidsToRetrieve.append(hid)
        }
        if needCSC,
           let cid = savedCSCUUID,
           cid != savedTrainerUUID,
           cid != savedHRUUID {
            uuidsToRetrieve.append(cid)
        }

        guard !uuidsToRetrieve.isEmpty else {
            startScan()
            return
        }

        let cached = centralManager.retrievePeripherals(withIdentifiers: uuidsToRetrieve)

        for peripheral in cached {
            let id = peripheral.identifier
            if id == savedTrainerUUID, needTrainer {
                peripheralRoles[id] = .trainer
                // Connect directly without stopping the scan — we may still
                // need to discover the other device type.
                let name = peripheral.name ?? "Unknown"
                trainerConnectionState = .connecting(name)
                trainerPeripheral = peripheral
                peripheral.delegate = self
                centralManager.connect(peripheral, options: nil)
                scheduleConnectTimeout(for: .trainer, peripheral: peripheral)
            } else if id == savedHRUUID, needHR {
                peripheralRoles[id] = .heartRateMonitor
                let name = peripheral.name ?? "Unknown"
                hrConnectionState = .connecting(name)
                hrPeripheral = peripheral
                peripheral.delegate = self
                centralManager.connect(peripheral, options: nil)
                scheduleConnectTimeout(for: .heartRateMonitor, peripheral: peripheral)
            } else if id == savedCSCUUID, needCSC {
                peripheralRoles[id] = .cyclingSpeedCadence
                let name = peripheral.name ?? "Unknown"
                cscConnectionState = .connecting(name)
                cscPeripheral = peripheral
                peripheral.delegate = self
                centralManager.connect(peripheral, options: nil)
                scheduleConnectTimeout(for: .cyclingSpeedCadence, peripheral: peripheral)
            }
        }

        // Still need to discover devices that weren't in the cache — start
        // a scan so the missing device type can be found over the air.
        let trainerHandled = !needTrainer || cached.contains(where: { $0.identifier == savedTrainerUUID })
        let hrHandled      = !needHR      || cached.contains(where: { $0.identifier == savedHRUUID })
        let cscHandled     = !needCSC     || cached.contains(where: { $0.identifier == savedCSCUUID })
        if !trainerHandled || !hrHandled || !cscHandled {
            startScan()
        }
    }

    // MARK: - Connection Timeout

    /// Schedule a timeout for a pending `connect()` call. If `didConnect` hasn't
    /// fired within `connectionTimeoutSeconds`, cancel the attempt and fall back
    /// to a fresh scan so the user isn't stuck on "Connecting…" forever.
    private func scheduleConnectTimeout(for role: DeviceType, peripheral: CBPeripheral) {
        let peripheralID = peripheral.identifier
        // Task inherits @MainActor isolation from containing class — no explicit hop needed
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: (self?.connectionTimeoutSeconds ?? 8) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }

            switch role {
            case .trainer:
                guard !self.trainerConnectionState.isConnected else { return }
                guard self.trainerPeripheral?.identifier == peripheralID else { return }
                bleLogger.warning("Trainer connection timed out; falling back to scan")
                if let p = self.trainerPeripheral {
                    self.centralManager.cancelPeripheralConnection(p)
                }
                self.trainerPeripheral = nil
                self.peripheralRoles.removeValue(forKey: peripheralID)
                self.trainerConnectionState = .disconnected
                self.startScan()

            case .heartRateMonitor:
                guard !self.hrConnectionState.isConnected else { return }
                guard self.hrPeripheral?.identifier == peripheralID else { return }
                bleLogger.warning("Heart-rate connection timed out; falling back to scan")
                if let p = self.hrPeripheral {
                    self.centralManager.cancelPeripheralConnection(p)
                }
                self.hrPeripheral = nil
                self.peripheralRoles.removeValue(forKey: peripheralID)
                self.hrConnectionState = .disconnected
                self.startScan()

            case .cyclingSpeedCadence:
                guard !self.cscConnectionState.isConnected else { return }
                guard self.cscPeripheral?.identifier == peripheralID else { return }
                bleLogger.warning("CSC connection timed out; falling back to scan")
                if let p = self.cscPeripheral {
                    self.centralManager.cancelPeripheralConnection(p)
                }
                self.cscPeripheral = nil
                self.peripheralRoles.removeValue(forKey: peripheralID)
                self.cscConnectionState = .disconnected
                self.startScan()

            case .unknown:
                break
            }
        }

        switch role {
        case .trainer:
            trainerConnectTimeout?.cancel()
            trainerConnectTimeout = task
        case .heartRateMonitor:
            hrConnectTimeout?.cancel()
            hrConnectTimeout = task
        case .cyclingSpeedCadence:
            cscConnectTimeout?.cancel()
            cscConnectTimeout = task
        case .unknown:
            break
        }
    }

    /// Cancel a running timeout (called when `didConnect` succeeds).
    private func cancelConnectTimeout(for role: DeviceType) {
        switch role {
        case .trainer:
            trainerConnectTimeout?.cancel()
            trainerConnectTimeout = nil
        case .heartRateMonitor:
            hrConnectTimeout?.cancel()
            hrConnectTimeout = nil
        case .cyclingSpeedCadence:
            cscConnectTimeout?.cancel()
            cscConnectTimeout = nil
        case .unknown:
            break
        }
    }

    func startScan() {
        guard centralManager.state == .poweredOn else { return }
        guard !isScanning else { return }

        discoveredPeripherals.removeAll()
        isScanning = true

        if !trainerConnectionState.isConnected {
            trainerConnectionState = .scanning
        }
        if !hrConnectionState.isConnected {
            hrConnectionState = .scanning
        }
        if !cscConnectionState.isConnected {
            cscConnectionState = .scanning
        }

        centralManager.scanForPeripherals(
            withServices: BLEConstants.scanServices,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        // Auto-stop scanning after a fixed window so the UI never sits on
        // "Looking for devices…" indefinitely.
        scanTimeoutTask?.cancel()
        // Task inherits @MainActor isolation — avoids redundant executor hop
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: (self?.scanTimeoutSeconds ?? 12) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            guard let self, self.isScanning else { return }
            bleLogger.debug("Scan timeout reached after \(self.scanTimeoutSeconds)s")
            self.stopScan()
        }
    }

    func stopScan() {
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        centralManager.stopScan()
        isScanning = false

        if case .scanning = trainerConnectionState {
            trainerConnectionState = .disconnected
        }
        if case .scanning = hrConnectionState {
            hrConnectionState = .disconnected
        }
        if case .scanning = cscConnectionState {
            cscConnectionState = .disconnected
        }
    }

    func connectTrainer(_ peripheral: CBPeripheral) {
        // Keep scanning if we still need an HR monitor or CSC sensor.
        let needsHR = !hrConnectionState.isConnected && hrPeripheral == nil
        let needsCSC = !cscConnectionState.isConnected && cscPeripheral == nil
        if !needsHR && !needsCSC {
            stopScan()
        }

        let name = peripheral.name ?? "Unknown"
        trainerConnectionState = .connecting(name)
        trainerPeripheral = peripheral
        peripheralRoles[peripheral.identifier] = .trainer
        savedTrainerUUID = peripheral.identifier

        peripheral.delegate = self

        // Omit NotifyOnConnection / NotifyOnNotification — they cause iOS to surface
        // "accessory wants to open Mangox" when the trainer reconnects or sends
        // FTMS data while the app is backgrounded (same as HR/CSC below).
        let options: [String: Any] = [
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ]
        centralManager.connect(peripheral, options: options)
        scheduleConnectTimeout(for: .trainer, peripheral: peripheral)
    }

    func connectHRMonitor(_ peripheral: CBPeripheral) {
        // Keep scanning if we still need a trainer or CSC sensor.
        let needsTrainer = !trainerConnectionState.isConnected && trainerPeripheral == nil
        let needsCSC = !cscConnectionState.isConnected && cscPeripheral == nil
        if !needsTrainer && !needsCSC {
            stopScan()
        }

        let name = peripheral.name ?? "Unknown"
        hrConnectionState = .connecting(name)
        hrPeripheral = peripheral
        peripheralRoles[peripheral.identifier] = .heartRateMonitor
        savedHRUUID = peripheral.identifier

        peripheral.delegate = self

        // NotifyOnConnection omitted — it causes iOS to show an "accessory wants
        // to open Mangox" system notification whenever the sensor wakes up nearby.
        let options: [String: Any] = [
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ]
        centralManager.connect(peripheral, options: options)
        scheduleConnectTimeout(for: .heartRateMonitor, peripheral: peripheral)
    }

    func connectCSCSensor(_ peripheral: CBPeripheral) {
        // Keep scanning if we still need a trainer or HR monitor.
        let needsTrainer = !trainerConnectionState.isConnected && trainerPeripheral == nil
        let needsHR = !hrConnectionState.isConnected && hrPeripheral == nil
        if !needsTrainer && !needsHR {
            stopScan()
        }

        let name = peripheral.name ?? "Unknown"
        cscConnectionState = .connecting(name)
        cscPeripheral = peripheral
        peripheralRoles[peripheral.identifier] = .cyclingSpeedCadence
        savedCSCUUID = peripheral.identifier

        peripheral.delegate = self
        // NotifyOnConnection omitted — it causes iOS to show an "accessory wants
        // to open Mangox" system notification whenever the sensor wakes up nearby.
        let options: [String: Any] = [
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ]
        centralManager.connect(peripheral, options: options)
        scheduleConnectTimeout(for: .cyclingSpeedCadence, peripheral: peripheral)
    }

    // Backward compatibility for old call sites.
    func connect(_ peripheral: CBPeripheral) {
        connectTrainer(peripheral)
    }

    func disconnectAll(clearSaved: Bool = false) {
        stopScan()
        stopRSSIMonitoring()
        trainerConnectTimeout?.cancel()
        trainerConnectTimeout = nil
        hrConnectTimeout?.cancel()
        hrConnectTimeout = nil
        cscConnectTimeout?.cancel()
        cscConnectTimeout = nil

        ftmsControl.detach()
        crankState.reset()
        trainerFTMSService = nil

        if let trainerPeripheral {
            centralManager.cancelPeripheralConnection(trainerPeripheral)
        }
        if let hrPeripheral,
           hrPeripheral.identifier != trainerPeripheral?.identifier {
            centralManager.cancelPeripheralConnection(hrPeripheral)
        }
        if let cscPeripheral,
           cscPeripheral.identifier != trainerPeripheral?.identifier,
           cscPeripheral.identifier != hrPeripheral?.identifier {
            centralManager.cancelPeripheralConnection(cscPeripheral)
        }

        trainerPeripheral = nil
        hrPeripheral = nil
        cscPeripheral = nil
        peripheralRoles.removeAll()
        trainerConnectionState = .disconnected
        hrConnectionState = .disconnected
        cscConnectionState = .disconnected
        cscCrankState = CSCParser.CrankState()
        cscWheelState = CSCParser.WheelState()
        metrics = CyclingMetrics()
        smoothedPower = 0
        powerEMA = 0
        smoothedHR = 0
        hrEMA = 0
        lastPacketReceived = nil
        trainerRSSI = 0
        hrRSSI = 0

        if clearSaved {
            savedTrainerUUID = nil
            savedHRUUID = nil
            savedCSCUUID = nil
        }
    }

    /// Disconnect only the CSC (speed/cadence) sensor, leaving trainer + HR intact.
    /// Call when leaving the outdoor dashboard to cancel the pending CoreBluetooth
    /// connection — otherwise iOS keeps trying to reconnect in the background,
    /// triggering "accessory wants to open Mangox" notifications.
    func disconnectCSC() {
        cscConnectTimeout?.cancel()
        cscConnectTimeout = nil
        let cscID = cscPeripheral?.identifier
        if let cscPeripheral {
            centralManager.cancelPeripheralConnection(cscPeripheral)
        }
        cscPeripheral = nil
        if let cscID {
            peripheralRoles.removeValue(forKey: cscID)
        }
        cscConnectionState = .disconnected
        cscCrankState = CSCParser.CrankState()
        cscWheelState = CSCParser.WheelState()
    }

    // Backward compatibility for old call sites.
    func disconnect() {
        disconnectAll()
    }

    // MARK: - RSSI Monitoring

    /// Start periodic RSSI monitoring for connected peripherals
    private func startRSSIMonitoring() {
        rssiMonitorTask?.cancel()
        // Task inherits @MainActor isolation — readRSSI() is async but MainActor-isolated
        rssiMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                guard !Task.isCancelled else { break }
                await self?.readRSSI()
            }
        }
    }

    /// Stop RSSI monitoring
    private func stopRSSIMonitoring() {
        rssiMonitorTask?.cancel()
        rssiMonitorTask = nil
    }

    /// Read RSSI from connected peripherals
    private func readRSSI() async {
        if let trainer = trainerPeripheral, trainerConnectionState.isConnected {
            trainer.readRSSI()
        }
        if let hr = hrPeripheral, hrConnectionState.isConnected {
            hr.readRSSI()
        }
        if let csc = cscPeripheral, cscConnectionState.isConnected {
            csc.readRSSI()
        }
    }

    private nonisolated func inferDeviceType(advertisementData: [String: Any], peripheralName: String?) -> DeviceType {
        var serviceUUIDs: [CBUUID] = []
        if let advertised = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            serviceUUIDs.append(contentsOf: advertised)
        }
        if let overflow = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] {
            serviceUUIDs.append(contentsOf: overflow)
        }

        if serviceUUIDs.contains(BLEConstants.ftmsServiceUUID)
            || serviceUUIDs.contains(BLEConstants.cyclingPowerServiceUUID) {
            return .trainer
        }

        if serviceUUIDs.contains(BLEConstants.cyclingSpeedCadenceServiceUUID) {
            return .cyclingSpeedCadence
        }

        if serviceUUIDs.contains(BLEConstants.heartRateServiceUUID) {
            return .heartRateMonitor
        }

        let lowerName = (peripheralName ?? "").lowercased()
        if lowerName.contains("cadence") || lowerName.contains("gsc") || lowerName.contains("speed sensor") {
            return .cyclingSpeedCadence
        }
        if lowerName.contains("whoop") || lowerName.contains("heart") || lowerName.contains("hr") {
            return .heartRateMonitor
        }
        if lowerName.contains("trainer") || lowerName.contains("bike") {
            return .trainer
        }

        return .unknown
    }

    private func role(for peripheral: CBPeripheral) -> DeviceType {
        let id = peripheral.identifier
        if let role = peripheralRoles[id] {
            return role
        }
        if trainerPeripheral?.identifier == id {
            return .trainer
        }
        if hrPeripheral?.identifier == id {
            return .heartRateMonitor
        }
        if cscPeripheral?.identifier == id {
            return .cyclingSpeedCadence
        }
        return .unknown
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        let restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]
            ?? []
        let restoredScanningServices = dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID]

        let boxedPeripherals = restoredPeripherals.map { SendablePeripheral(value: $0) }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                for boxed in boxedPeripherals {
                    let peripheral = boxed.value
                    peripheral.delegate = self
                    let id = peripheral.identifier
                    let name = peripheral.name ?? "Unknown"

                    let role: DeviceType
                    if id == self.savedTrainerUUID {
                        role = .trainer
                    } else if id == self.savedHRUUID {
                        role = .heartRateMonitor
                    } else if id == self.savedCSCUUID {
                        role = .cyclingSpeedCadence
                    } else {
                        role = .unknown
                    }
                    self.peripheralRoles[id] = role

                    switch role {
                    case .trainer:
                        self.trainerPeripheral = peripheral
                        self.trainerConnectionState =
                            peripheral.state == .connected ? .connected(name) : .connecting(name)
                        if peripheral.state == .connected {
                            peripheral.discoverServices([
                                BLEConstants.ftmsServiceUUID,
                                BLEConstants.cyclingPowerServiceUUID,
                                BLEConstants.heartRateServiceUUID,
                            ])
                        }
                    case .heartRateMonitor:
                        self.hrPeripheral = peripheral
                        self.hrConnectionState =
                            peripheral.state == .connected ? .connected(name) : .connecting(name)
                        if peripheral.state == .connected {
                            peripheral.discoverServices([BLEConstants.heartRateServiceUUID])
                        }
                    case .cyclingSpeedCadence:
                        self.cscPeripheral = peripheral
                        self.cscConnectionState =
                            peripheral.state == .connected ? .connected(name) : .connecting(name)
                        if peripheral.state == .connected {
                            peripheral.discoverServices([BLEConstants.cyclingSpeedCadenceServiceUUID])
                        }
                    case .unknown:
                        break
                    }
                }

                self.isScanning = restoredScanningServices != nil
            }
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.bluetoothState = state
                if state == .poweredOn {
                    // Second async hop: lets `sensorLiveRouteScope()` run so we only auto-reconnect on ride surfaces.
                    DispatchQueue.main.async { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self else { return }
                            guard TrainerSensorLiveObservationGate.isLiveRouteActive else { return }
                            if !self.trainerConnectionState.isConnected
                                || !self.hrConnectionState.isConnected
                                || !self.cscConnectionState.isConnected
                            {
                                self.reconnectOrScan()
                            }
                        }
                    }
                } else {
                    self.stopScan()
                    self.trainerConnectionState = .disconnected
                    self.hrConnectionState = .disconnected
                    self.cscConnectionState = .disconnected
                    self.trainerPeripheral = nil
                    self.hrPeripheral = nil
                    self.cscPeripheral = nil
                    self.peripheralRoles.removeAll()
                    self.cscCrankState = CSCParser.CrankState()
                    self.cscWheelState = CSCParser.WheelState()
                    self.metrics = CyclingMetrics()
                }
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Unknown Device"
        let id = peripheral.identifier
        let rssi = RSSI.intValue
        let type = inferDeviceType(advertisementData: advertisementData, peripheralName: name)

        let box = SendablePeripheral(value: peripheral)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let peripheral = box.value

                if let index = self.discoveredPeripherals.firstIndex(where: { $0.id == id }) {
                    self.discoveredPeripherals[index].rssi = rssi
                    if self.discoveredPeripherals[index].deviceType == .unknown,
                       type != .unknown {
                        self.discoveredPeripherals[index].deviceType = type
                    }
                } else {
                    self.discoveredPeripherals.append(
                        DiscoveredPeripheral(
                            id: id,
                            peripheral: peripheral,
                            name: name,
                            rssi: rssi,
                            deviceType: type
                        )
                    )
                }

                if self.peripheralRoles[id] == nil, type != .unknown {
                    self.peripheralRoles[id] = type
                }
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        let box = SendablePeripheral(value: peripheral)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let peripheral = box.value

                let name = peripheral.name ?? "Unknown"
                let role = self.role(for: peripheral)

                self.cancelConnectTimeout(for: role)

                if role == .trainer && self.isReconnecting {
                    self.reconnectTask?.cancel()
                    self.reconnectTask = nil
                    self.isReconnecting = false
                }

                switch role {
                case .trainer:
                    self.trainerPeripheral = peripheral
                    self.trainerConnectionState = .connected(name)
                case .heartRateMonitor:
                    self.hrPeripheral = peripheral
                    self.hrConnectionState = .connected(name)
                case .cyclingSpeedCadence:
                    self.cscPeripheral = peripheral
                    self.cscConnectionState = .connected(name)
                case .unknown:
                    if self.trainerPeripheral == nil {
                        self.trainerPeripheral = peripheral
                        self.peripheralRoles[peripheral.identifier] = .trainer
                        self.trainerConnectionState = .connected(name)
                    } else {
                        self.hrPeripheral = peripheral
                        self.peripheralRoles[peripheral.identifier] = .heartRateMonitor
                        self.hrConnectionState = .connected(name)
                    }
                }

                peripheral.delegate = self
                self.startRSSIMonitoring()

                let servicesToDiscover: [CBUUID]
                switch self.role(for: peripheral) {
                case .heartRateMonitor:
                    servicesToDiscover = [BLEConstants.heartRateServiceUUID]
                case .cyclingSpeedCadence:
                    servicesToDiscover = [BLEConstants.cyclingSpeedCadenceServiceUUID]
                case .trainer, .unknown:
                    servicesToDiscover = [
                        BLEConstants.ftmsServiceUUID,
                        BLEConstants.cyclingPowerServiceUUID,
                        BLEConstants.heartRateServiceUUID,
                    ]
                }
                peripheral.discoverServices(servicesToDiscover)
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let box = SendablePeripheral(value: peripheral)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let peripheral = box.value

                let role = self.role(for: peripheral)
                self.peripheralRoles.removeValue(forKey: peripheral.identifier)

                if !self.trainerConnectionState.isConnected && !self.hrConnectionState.isConnected && !self.cscConnectionState.isConnected {
                    self.stopRSSIMonitoring()
                }

                switch role {
                case .trainer:
                    self.reconnectTask?.cancel()
                    self.reconnectTask = nil

                    if !self.hrConnectionState.isConnected && !self.cscConnectionState.isConnected {
                        self.stopRSSIMonitoring()
                    }

                    if self.metrics.power > 0 || self.metrics.cadence > 0 {
                        self.attemptReconnect(for: .trainer)
                        return
                    }

                    self.ftmsControl.detach()
                    self.crankState.reset()
                    self.trainerFTMSService = nil
                    self.trainerPeripheral = nil
                    self.trainerConnectionState = .disconnected
                    self.smoothedPower = 0
                    self.powerEMA = 0
                    self.lastPacketReceived = nil
                    self.metrics.power = 0
                    self.metrics.cadence = 0
                    self.metrics.speed = 0
                    self.metrics.totalDistance = 0
                    self.metrics.includesTotalDistanceInPacket = false
                    self.metrics.lastUpdate = nil

                    if self.metrics.hrSource != .dedicated {
                        self.metrics.heartRate = 0
                        self.metrics.hrSource = .none
                        self.smoothedHR = 0
                        self.hrEMA = 0
                    }

                case .heartRateMonitor:
                    self.hrPeripheral = nil
                    self.hrConnectionState = .disconnected

                    if self.metrics.hrSource == .dedicated {
                        self.metrics.heartRate = 0
                        self.metrics.hrSource = .none
                        self.smoothedHR = 0
                        self.hrEMA = 0
                    }

                    if !self.trainerConnectionState.isConnected && !self.cscConnectionState.isConnected {
                        self.stopRSSIMonitoring()
                    }

                case .cyclingSpeedCadence:
                    self.cscPeripheral = nil
                    self.cscConnectionState = .disconnected
                    self.cscCrankState = CSCParser.CrankState()
                    self.cscWheelState = CSCParser.WheelState()
                    if !self.trainerConnectionState.isConnected {
                        self.metrics.cadence = 0
                        if self.metrics.speed > 0 {
                            self.metrics.speed = 0
                        }
                    }

                    if !self.trainerConnectionState.isConnected && !self.hrConnectionState.isConnected {
                        self.stopRSSIMonitoring()
                    }

                case .unknown:
                    if self.trainerPeripheral?.identifier == peripheral.identifier {
                        self.trainerPeripheral = nil
                        self.trainerConnectionState = .disconnected
                    }
                    if self.hrPeripheral?.identifier == peripheral.identifier {
                        self.hrPeripheral = nil
                        self.hrConnectionState = .disconnected
                    }
                    if self.cscPeripheral?.identifier == peripheral.identifier {
                        self.cscPeripheral = nil
                        self.cscConnectionState = .disconnected
                        self.cscCrankState = CSCParser.CrankState()
                        self.cscWheelState = CSCParser.WheelState()
                    }
                }
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let box = SendablePeripheral(value: peripheral)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let peripheral = box.value

                let role = self.role(for: peripheral)
                self.peripheralRoles.removeValue(forKey: peripheral.identifier)

                switch role {
                case .trainer:
                    self.trainerPeripheral = nil
                    self.trainerConnectionState = .disconnected
                case .heartRateMonitor:
                    self.hrPeripheral = nil
                    self.hrConnectionState = .disconnected
                case .cyclingSpeedCadence:
                    self.cscPeripheral = nil
                    self.cscConnectionState = .disconnected
                case .unknown:
                    break
                }
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        if let error {
            bleLogger.error("Service discovery failed for \(peripheral.name ?? "Unknown", privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        guard let services = peripheral.services else {
            bleLogger.error("No services found on \(peripheral.name ?? "Unknown", privacy: .public)")
            return
        }
        for service in services {
            #if DEBUG
            bleLogger.debug("Discovered service \(service.uuid.uuidString, privacy: .public) (\(self.serviceName(for: service.uuid), privacy: .public)) on \(peripheral.name ?? "Unknown", privacy: .public)")
            #endif

            // For the FTMS service on the trainer, store a reference and attach
            // the control service so it has the peripheral reference it needs
            // to read features, subscribe to indications, and send commands.
            if service.uuid == BLEConstants.ftmsServiceUUID {
                let pBox = SendablePeripheral(value: peripheral)
                let sBox = SendableService(value: service)
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        let peripheral = pBox.value
                        let service = sBox.value
                        let deviceRole = self.role(for: peripheral)
                        if deviceRole == .trainer || deviceRole == .unknown {
                            self.trainerFTMSService = service
                            self.ftmsControl.attach(peripheral: peripheral, service: service)
                        }
                    }
                }
            }

            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            bleLogger.error("Characteristic discovery failed for \(service.uuid.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        guard let characteristics = service.characteristics else {
            bleLogger.error("No characteristics found for service \(service.uuid.uuidString, privacy: .public)")
            return
        }

        for characteristic in characteristics {
            let props = characteristicPropertiesDescription(characteristic.properties)
            #if DEBUG
            bleLogger.debug("Characteristic \(characteristic.uuid.uuidString, privacy: .public) (\(self.characteristicName(for: characteristic.uuid), privacy: .public)) properties: \(props, privacy: .public)")
            #endif

            switch characteristic.uuid {
                case BLEConstants.indoorBikeDataUUID,
                 BLEConstants.heartRateMeasurementUUID,
                 BLEConstants.cyclingPowerMeasurementUUID,
                 BLEConstants.cscMeasurementUUID:
                let canSubscribe = characteristic.properties.contains(.notify)
                    || characteristic.properties.contains(.indicate)
                if canSubscribe {
                    #if DEBUG
                    bleLogger.debug("Subscribing to \(self.characteristicName(for: characteristic.uuid), privacy: .public) notify/indicate")
                    #endif
                    peripheral.setNotifyValue(true, for: characteristic)
                } else {
                    bleLogger.warning("\(self.characteristicName(for: characteristic.uuid), privacy: .public) does not support notify or indicate")
                }

            case BLEConstants.ftmsControlPointUUID,
                 BLEConstants.ftmsFeatureUUID,
                 BLEConstants.ftmsSupportedResistanceLevelRangeUUID,
                 BLEConstants.ftmsStatusUUID:
                // Route FTMS control-related characteristics to FTMSControlService
                if service.uuid == BLEConstants.ftmsServiceUUID {
                    let cBox = SendableCharacteristic(value: characteristic)
                    DispatchQueue.main.async { [weak self] in
                        MainActor.assumeIsolated {
                            self?.ftmsControl.handleDiscoveredCharacteristic(cBox.value)
                        }
                    }
                }

            default:
                continue
            }
        }
    }

    // MARK: - Debug Helpers

    private nonisolated func serviceName(for uuid: CBUUID) -> String {
        switch uuid {
        case BLEConstants.ftmsServiceUUID: return "FTMS"
        case BLEConstants.cyclingPowerServiceUUID: return "Cycling Power Service"
        case BLEConstants.heartRateServiceUUID: return "Heart Rate Service"
        case BLEConstants.cyclingSpeedCadenceServiceUUID: return "Cycling Speed and Cadence"
        default: return "Unknown"
        }
    }

    private nonisolated func characteristicName(for uuid: CBUUID) -> String {
        switch uuid {
        case BLEConstants.indoorBikeDataUUID: return "Indoor Bike Data"
        case BLEConstants.cyclingPowerMeasurementUUID: return "Cycling Power Measurement"
        case BLEConstants.heartRateMeasurementUUID: return "Heart Rate Measurement"
        case BLEConstants.ftmsControlPointUUID: return "FTMS Control Point"
        case BLEConstants.ftmsFeatureUUID: return "FTMS Feature"
        case BLEConstants.ftmsSupportedResistanceLevelRangeUUID: return "Supported Resistance Level Range"
        case BLEConstants.ftmsStatusUUID: return "FTMS Machine Status"
        case BLEConstants.cscMeasurementUUID: return "CSC Measurement"
        default: return uuid.uuidString
        }
    }

    private nonisolated func characteristicPropertiesDescription(_ props: CBCharacteristicProperties) -> String {
        var parts: [String] = []
        if props.contains(.broadcast) { parts.append("broadcast") }
        if props.contains(.read) { parts.append("read") }
        if props.contains(.writeWithoutResponse) { parts.append("writeNoResp") }
        if props.contains(.write) { parts.append("write") }
        if props.contains(.notify) { parts.append("notify") }
        if props.contains(.indicate) { parts.append("indicate") }
        return parts.isEmpty ? "none" : parts.joined(separator: ", ")
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value else { return }

        // BLE_VERBOSE is a custom flag — add -DBLE_VERBOSE to Other Swift Flags only when
        // you need raw packet hex dumps. Keeping it out of the default DEBUG build
        // eliminates ~12 main-thread String allocations/prints per second during a ride.
        #if BLE_VERBOSE
        let hexStr = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("[BLE] \(characteristic.uuid.uuidString): \(hexStr)")
        #endif

        // Use GCD + assumeIsolated instead of Task { @MainActor in } to avoid
        // unsafeForcedSync warnings from Swift Concurrency's actor-checking path.
        let box = SendableCharacteristic(value: characteristic)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let characteristic = box.value
                let uuid = characteristic.uuid

                // Route FTMS control-related value updates to FTMSControlService
                switch uuid {
                case BLEConstants.ftmsControlPointUUID,
                     BLEConstants.ftmsFeatureUUID,
                     BLEConstants.ftmsSupportedResistanceLevelRangeUUID,
                     BLEConstants.ftmsStatusUUID:
                    self.ftmsControl.handleValueUpdate(for: characteristic)
                    return
                default:
                    break
                }

                switch uuid {
                case BLEConstants.indoorBikeDataUUID:
                    if let packet = FTMSParser.parseIndoorBikeDataPacket(data) {
                        let parsed = packet.metrics
                        // `trainerPeripheral != nil` covers connecting + connected (not only `.isConnected`).
                        let trainerLinked = self.trainerPeripheral != nil

                        // Trainer FTMS always wins over CSC when both are paired; CSC was blocking speed/cadence before.
                        if packet.hasSpeed {
                            if trainerLinked || !self.cscConnectionState.isConnected {
                                self.metrics.speed = parsed.speed
                            }
                        } else if trainerLinked {
                            // Field absent — avoid stale speed from older packets (Bluetooth: bit 0 = not present).
                            self.metrics.speed = 0
                        }

                        if packet.hasCadence {
                            if trainerLinked || !self.cscConnectionState.isConnected {
                                self.metrics.cadence = parsed.cadence
                            }
                        }
                        if packet.hasPower {
                            self.metrics.power = parsed.power
                            self.updateSmoothedPower(parsed.power)
                        }
                        if packet.hasTotalDistance {
                            self.metrics.totalDistance = parsed.totalDistance
                        }
                        self.metrics.includesTotalDistanceInPacket = packet.hasTotalDistance
                        self.metrics.lastUpdate = parsed.lastUpdate

                        if packet.hasHeartRate, parsed.heartRate > 0, !self.hrConnectionState.isConnected {
                            self.metrics.heartRate = parsed.heartRate
                            self.metrics.hrSource = .ftmsEmbedded
                            self.updateSmoothedHR(parsed.heartRate)
                        }

                        self.notifySubscribers()
                        self.lastPacketReceived = .now
                        #if BLE_VERBOSE
                        print("[FTMS] P:\(self.metrics.power)W  C:\(Int(self.metrics.cadence))rpm  S:\(String(format: "%.1f", self.metrics.speed))km/h  HR:\(self.metrics.heartRate)bpm")
                        #endif
                    }

                case BLEConstants.cyclingPowerMeasurementUUID:
                    if let parsed = FTMSParser.parseCyclingPowerMeasurement(data, crankState: &self.crankState) {
                        self.metrics.includesTotalDistanceInPacket = false
                        self.metrics.power = parsed.power
                        // Match FTMS indoor bike: trainer-linked CPS wins over a separate CSC pod.
                        let trainerLinked = self.trainerPeripheral != nil
                        if trainerLinked || !self.cscConnectionState.isConnected,
                           let cadence = parsed.cadence > 0 ? parsed.cadence : nil {
                            self.metrics.cadence = cadence
                        }
                        self.metrics.lastUpdate = parsed.lastUpdate
                        self.updateSmoothedPower(parsed.power)
                        self.notifySubscribers()
                        self.lastPacketReceived = .now
                    }

                case BLEConstants.heartRateMeasurementUUID:
                    if let hr = FTMSParser.parseHeartRate(data) {
                        self.metrics.includesTotalDistanceInPacket = false
                        self.metrics.heartRate = hr
                        self.metrics.hrSource = .dedicated
                        self.metrics.lastUpdate = .now
                        self.updateSmoothedHR(hr)
                        self.notifySubscribers()
                    }

                case BLEConstants.cscMeasurementUUID:
                    var crank = self.cscCrankState
                    let cad = CSCParser.cadenceRPM(from: data, state: &crank)
                    self.cscCrankState = crank
                    var wheel = self.cscWheelState
                    let wheelKmh = CSCParser.wheelSpeedKmh(
                        from: data,
                        state: &wheel,
                        wheelCircumferenceMeters: RidePreferences.shared.cscWheelCircumferenceMeters
                    )
                    self.cscWheelState = wheel
                    if cad > 0, self.trainerPeripheral == nil {
                        self.metrics.cadence = cad
                    }
                    if wheelKmh > 0, self.trainerPeripheral == nil {
                        self.metrics.speed = wheelKmh
                    }
                    self.metrics.includesTotalDistanceInPacket = false
                    self.metrics.lastUpdate = .now
                    self.notifySubscribers()

                default:
                    break
                }
            }
        }
    }

    // MARK: - RSSI Callback

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let error {
            #if DEBUG
            bleLogger.debug("RSSI read error: \(error.localizedDescription, privacy: .public)")
            #endif
            return
        }

        let rssi = RSSI.intValue
        let peripheralID = peripheral.identifier
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if peripheralID == self.trainerPeripheral?.identifier {
                    self.trainerRSSI = rssi
                    #if DEBUG
                    bleLogger.debug("Trainer RSSI: \(rssi) dBm (\(self.trainerConnectionQuality.description, privacy: .public))")
                    #endif
                } else if peripheralID == self.hrPeripheral?.identifier {
                    self.hrRSSI = rssi
                }
            }
        }
    }
}
