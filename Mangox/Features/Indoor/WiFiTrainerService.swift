import Foundation
import Network
import os.log
import CoreBluetooth

private let wifiLogger = Logger(subsystem: "com.abchalita.Mangox", category: "WiFiTrainer")

enum WiFiConnectionState: Equatable {
    case disconnected
    case discovering
    case connecting(String)
    case connected(String)
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

struct DiscoveredWiFiTrainer: Identifiable, Equatable {
    let id: String
    let name: String
    let ipAddress: String
    let port: UInt16

    static func == (lhs: DiscoveredWiFiTrainer, rhs: DiscoveredWiFiTrainer) -> Bool {
        lhs.id == rhs.id
    }
}

@Observable
@MainActor
final class WiFiTrainerService: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    var connectionState: WiFiConnectionState = .disconnected
    var discoveredTrainers: [DiscoveredWiFiTrainer] = []
    var connectedTrainer: DiscoveredWiFiTrainer?

    var power: Int = 0
    var cadence: Double = 0
    var speed: Double = 0
    var heartRate: Int = 0
    var totalDistance: Double = 0
    var smoothedPower: Int = 0
    var lastPacketReceived: Date?

    private let powerEMAAlpha: Double = 0.2
    private var powerEMA: Double = 0

    private var connection: NWConnection?
    private var pollingTask: Task<Void, Never>?

    private var metricsSubscribers: [String: (Int, Double, Double, Int, Double) -> Void] = [:]

    private var serviceBrowser: NetServiceBrowser?
    private var pendingServices: [NetService] = []
    private let serviceTypes = [
        "_wahoo-fitness-ble._tcp.",
        "_zwift-companion._tcp.",
        "_ftms-trainer._tcp.",
    ]

    // MARK: - Subscriber API

    func subscribe(id: String, handler: @escaping (Int, Double, Double, Int, Double) -> Void) {
        metricsSubscribers[id] = handler
    }

    func unsubscribe(id: String) {
        metricsSubscribers.removeValue(forKey: id)
    }

    private func notifySubscribers() {
        lastPacketReceived = Date()
        let currentPower = power
        let currentCadence = cadence
        let currentSpeed = speed
        let currentHR = heartRate
        let currentDistance = totalDistance
        for handler in metricsSubscribers.values {
            handler(currentPower, currentCadence, currentSpeed, currentHR, currentDistance)
        }
    }

    // MARK: - Discovery

    func startDiscovery() {
        if connectionState.isConnected { return }
        if case .connecting = connectionState { return }

        discoveredTrainers.removeAll()
        tearDownDiscoveryBrowsers()
        connectionState = .discovering

        // NetServiceBrowser must be scheduled on a run loop with a common mode.
        // Creating it on the main thread and scheduling explicitly avoids the
        // -72008 (DNSServiceDiscovery) error that occurs on background threads.
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.includesPeerToPeer = false
        serviceBrowser = browser

        // Schedule on the main run loop in common mode so discovery survives
        // UI interaction and doesn't get starved.
        browser.schedule(in: .main, forMode: .common)

        for serviceType in serviceTypes {
            browser.searchForServices(ofType: serviceType, inDomain: "local.")
            wifiLogger.info("Browsing for \(serviceType)")
        }
    }

    /// Stops mDNS browse / pending resolves without changing `connectionState` (used when restarting discovery).
    private func tearDownDiscoveryBrowsers() {
        serviceBrowser?.stop()
        serviceBrowser = nil

        for service in pendingServices {
            service.stop()
        }
        pendingServices.removeAll()
    }

    func stopDiscovery() {
        tearDownDiscoveryBrowsers()

        if !connectionState.isConnected {
            connectionState = .disconnected
        }
    }

    // MARK: - NetServiceBrowserDelegate

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let name = service.name
        let type = service.type
        service.delegate = self
        service.resolve(withTimeout: 10)
        // NetService is not Sendable, but delegate callbacks are main-thread only
        // and the Task below is @MainActor — safe to transfer without copying.
        nonisolated(unsafe) let svc = service
        Task { @MainActor in
            wifiLogger.info("Found service: \(name) type: \(type)")
            pendingServices.append(svc)
        }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let name = service.name
        Task { @MainActor in
            wifiLogger.info("Removed service: \(name)")
            pendingServices.removeAll { $0.name == name }
            discoveredTrainers.removeAll { $0.name == name }
        }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        Task { @MainActor in
            wifiLogger.error("mDNS browse failed: \(errorDict)")
            connectionState = .error("mDNS discovery failed")
        }
    }

    // MARK: - NetServiceDelegate

    nonisolated func netServiceDidResolveAddress(_ service: NetService) {
        let addresses = service.addresses
        let name = service.name
        let port = service.port
        Task { @MainActor in
            guard let addresses else { return }

            for addressData in addresses {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = addressData.withUnsafeBytes { rawBufferPointer in
                    guard let addr = rawBufferPointer.baseAddress?.assumingMemoryBound(to: sockaddr.self) else {
                        return Int32(1)
                    }
                    return getnameinfo(
                        addr,
                        socklen_t(addressData.count),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                }

                guard result == 0 else { continue }
                let ip = String(cString: hostname)

                guard !ip.isEmpty, !ip.hasPrefix("fe80") else { continue }

                let trainer = DiscoveredWiFiTrainer(
                    id: "\(ip):\(port)",
                    name: name,
                    ipAddress: ip,
                    port: UInt16(port)
                )

                if !discoveredTrainers.contains(where: { $0.id == trainer.id }) {
                    discoveredTrainers.append(trainer)
                    wifiLogger.info("Resolved trainer: \(trainer.name) at \(trainer.ipAddress):\(trainer.port)")
                }
                break
            }

            pendingServices.removeAll { $0.name == name }
        }
    }

    nonisolated func netService(_ service: NetService, didNotResolve errorDict: [String: NSNumber]) {
        let name = service.name
        Task { @MainActor in
            wifiLogger.error("Failed to resolve \(name): \(errorDict)")
            pendingServices.removeAll { $0.name == name }
        }
    }

    // MARK: - Connection

    func connect(to trainer: DiscoveredWiFiTrainer) {
        stopDiscovery()

        connectionState = .connecting(trainer.name)
        connectedTrainer = trainer

        let trainerName = trainer.name
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(trainer.ipAddress),
            port: NWEndpoint.Port(rawValue: trainer.port)!
        )

        connection = NWConnection(to: endpoint, using: .tcp)

        connection?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    wifiLogger.info("Connected to \(trainerName)")
                    self.connectionState = .connected(trainerName)
                    self.startPolling()

                case .failed(let error):
                    wifiLogger.error("Connection failed: \(error.localizedDescription)")
                    self.connectionState = .error(error.localizedDescription)

                case .cancelled:
                    self.connectionState = .disconnected

                default:
                    break
                }
            }
        }

        connection?.start(queue: .global(qos: .userInteractive))
    }

    func disconnect() {
        stopDiscovery()
        pollingTask?.cancel()
        pollingTask = nil
        connection?.cancel()
        connection = nil
        connectedTrainer = nil
        connectionState = .disconnected

        power = 0
        cadence = 0
        speed = 0
        heartRate = 0
        totalDistance = 0
        smoothedPower = 0
        powerEMA = 0
        lastPacketReceived = nil
    }

    // MARK: - Data Polling

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.receiveData()
                try? await Task.sleep(nanoseconds: 125_000_000) // ~8Hz
            }
        }
    }

    private func receiveData() async {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data = content, !data.isEmpty {
                    self.parseTrainerData(data)
                }

                if let error = error {
                    wifiLogger.error("Receive error: \(error.localizedDescription)")
                }

                if isComplete {
                    self.disconnect()
                }
            }
        }
    }

    private func parseTrainerData(_ data: Data) {
        guard data.count >= 4 else { return }

        // Quick heuristic: JSON starts with '{' (0x7B). Binary FTMS typically doesn't.
        // This avoids the overhead of JSONSerialization + ObjC exception on every binary packet.
        if data.first == 0x7B, // '{'
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            parseJSONTrainerData(json)
            return
        }

        // Binary FTMS format
        parseBinaryTrainerData(data)
    }

    private func parseJSONTrainerData(_ json: [String: Any]) {
        if let p = json["power"] as? Int {
            power = p
            updateSmoothedPower(p)
        }
        if let c = json["cadence"] as? Double {
            cadence = c
        }
        if let s = json["speed"] as? Double {
            speed = s
        }
        if let h = json["heartRate"] as? Int {
            heartRate = h
        }
        if let d = json["distance"] as? Double {
            totalDistance = d
        }

        notifySubscribers()
    }

    private func parseBinaryTrainerData(_ data: Data) {
        // Attempt to parse as FTMS Indoor Bike Data
        guard data.count >= 4 else { return }

        let flags = UInt16(data[0]) | (UInt16(data[1]) << 8)
        var offset = 2

        // Speed (bit 0, inverted - 0 means present)
        if (flags & 0x0001) == 0 && offset + 2 <= data.count {
            let raw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            speed = Double(raw) * 0.01
            offset += 2
        }

        // Cadence (bit 2)
        if flags & 0x0004 != 0 && offset + 2 <= data.count {
            let raw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            cadence = Double(raw) * 0.5
            offset += 2
        }

        // Distance (bit 4)
        if flags & 0x0010 != 0 && offset + 3 <= data.count {
            let raw = UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16)
            totalDistance = Double(raw)
            offset += 3
        }

        // Power (bit 6)
        if flags & 0x0040 != 0 && offset + 2 <= data.count {
            let raw = Int16(bitPattern: UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
            power = max(0, Int(raw))
            updateSmoothedPower(power)
            offset += 2
        }

        // Heart Rate (bit 9)
        if flags & 0x0200 != 0 && offset + 1 <= data.count {
            heartRate = Int(data[offset])
        }

        notifySubscribers()
    }

    private func updateSmoothedPower(_ newPower: Int) {
        if powerEMA == 0 {
            powerEMA = Double(newPower)
        } else {
            powerEMA = powerEMAAlpha * Double(newPower) + (1 - powerEMAAlpha) * powerEMA
        }
        smoothedPower = Int(powerEMA.rounded())
    }
}
