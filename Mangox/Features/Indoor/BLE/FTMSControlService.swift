import CoreBluetooth
import os.log

private let ftmsControlLogger = Logger(subsystem: "com.abchalita.Mangox", category: "FTMSControl")

// MARK: - FTMS Control Point Op Codes

/// Op codes defined by the Bluetooth FTMS specification for the
/// Fitness Machine Control Point characteristic (0x2AD9).
enum FTMSOpCode: UInt8 {
    case requestControl          = 0x00
    case reset                   = 0x01
    case setTargetSpeed          = 0x02
    case setTargetInclination    = 0x03
    case setTargetResistance     = 0x04
    case setTargetPower          = 0x05
    case setTargetHeartRate      = 0x06
    case startOrResume           = 0x07
    case stopOrPause             = 0x08
    case setIndoorBikeSimulation = 0x11
    case spinDownControl         = 0x13
    case responseCode            = 0x80
}

/// Result codes returned by the trainer in Control Point indication responses.
enum FTMSResultCode: UInt8 {
    case success                = 0x01
    case notSupported           = 0x02
    case invalidParameter       = 0x03
    case operationFailed        = 0x04
    case controlNotPermitted    = 0x05
    case unknown                = 0xFF

    var description: String {
        switch self {
        case .success:             return "Success"
        case .notSupported:        return "Op code not supported"
        case .invalidParameter:    return "Invalid parameter"
        case .operationFailed:     return "Operation failed"
        case .controlNotPermitted: return "Control not permitted"
        case .unknown:             return "Unknown result"
        }
    }
}

// MARK: - Trainer Control Mode

/// The active control mode being used to drive the trainer.
enum TrainerControlMode: Equatable, Sendable {
    /// No control — trainer is free-ride / uncontrolled.
    case none
    /// ERG mode — trainer locks to a specific wattage.
    case erg(watts: Int)
    /// Resistance mode — trainer set to a raw resistance level (0.0–1.0 normalized).
    case resistance(level: Double)
    /// Simulation mode — trainer adjusts resistance based on grade, wind, etc.
    case simulation(gradePercent: Double)
    /// Spin-down calibration in progress.
    case calibrating

    var label: String {
        switch self {
        case .none:                    return "Free Ride"
        case .erg(let watts):          return "ERG \(watts)W"
        case .resistance(let level):   return "Resistance \(Int(level * 100))%"
        case .simulation(let grade):   return String(format: "SIM %.1f%%", grade)
        case .calibrating:             return "Calibrating…"
        }
    }

    var isActive: Bool {
        if case .none = self { return false }
        return true
    }
}

// MARK: - FTMS Feature Flags

/// Parsed feature flags from the FTMS Feature characteristic (0x2ACC).
/// Tells us which control modes the trainer actually supports.
struct FTMSFeatures: OptionSet, Sendable {
    let rawValue: UInt32

    // Fitness Machine Features (first 4 bytes)
    static let averageSpeedSupported            = FTMSFeatures(rawValue: 1 << 0)
    static let cadenceSupported                 = FTMSFeatures(rawValue: 1 << 1)
    static let totalDistanceSupported           = FTMSFeatures(rawValue: 1 << 2)
    static let inclinationSupported             = FTMSFeatures(rawValue: 1 << 3)
    static let elevationGainSupported           = FTMSFeatures(rawValue: 1 << 4)
    static let paceSupported                    = FTMSFeatures(rawValue: 1 << 5)
    static let stepCountSupported               = FTMSFeatures(rawValue: 1 << 6)
    static let resistanceLevelSupported         = FTMSFeatures(rawValue: 1 << 7)
    static let strideCountSupported             = FTMSFeatures(rawValue: 1 << 8)
    static let expendedEnergySupported          = FTMSFeatures(rawValue: 1 << 9)
    static let heartRateSupported               = FTMSFeatures(rawValue: 1 << 10)
    static let metabolicEquivalentSupported      = FTMSFeatures(rawValue: 1 << 11)
    static let elapsedTimeSupported             = FTMSFeatures(rawValue: 1 << 12)
    static let remainingTimeSupported           = FTMSFeatures(rawValue: 1 << 13)
    static let powerMeasurementSupported        = FTMSFeatures(rawValue: 1 << 14)
    static let forceOnBeltAndPowerSupported     = FTMSFeatures(rawValue: 1 << 15)
    static let userDataRetentionSupported       = FTMSFeatures(rawValue: 1 << 16)

    static let none: FTMSFeatures = []
}

/// Parsed target setting features from the FTMS Feature characteristic (bytes 4–7).
struct FTMSTargetSettingFeatures: OptionSet, Sendable {
    let rawValue: UInt32

    static let speedTargetSupported                  = FTMSTargetSettingFeatures(rawValue: 1 << 0)
    static let inclinationTargetSupported            = FTMSTargetSettingFeatures(rawValue: 1 << 1)
    static let resistanceTargetSupported             = FTMSTargetSettingFeatures(rawValue: 1 << 2)
    static let powerTargetSupported                  = FTMSTargetSettingFeatures(rawValue: 1 << 3)
    static let heartRateTargetSupported              = FTMSTargetSettingFeatures(rawValue: 1 << 4)
    static let expendedEnergyConfigSupported         = FTMSTargetSettingFeatures(rawValue: 1 << 5)
    static let stepNumberConfigSupported             = FTMSTargetSettingFeatures(rawValue: 1 << 6)
    static let strideNumberConfigSupported           = FTMSTargetSettingFeatures(rawValue: 1 << 7)
    static let distanceConfigSupported               = FTMSTargetSettingFeatures(rawValue: 1 << 8)
    static let trainingTimeConfigSupported           = FTMSTargetSettingFeatures(rawValue: 1 << 9)
    static let timeInZoneConfigSupported             = FTMSTargetSettingFeatures(rawValue: 1 << 10)
    static let indoorBikeSimulationSupported         = FTMSTargetSettingFeatures(rawValue: 1 << 13)
    static let wheelCircumferenceConfigSupported     = FTMSTargetSettingFeatures(rawValue: 1 << 14)
    static let spinDownControlSupported              = FTMSTargetSettingFeatures(rawValue: 1 << 15)
    static let targetedCadenceConfigSupported        = FTMSTargetSettingFeatures(rawValue: 1 << 16)

    static let none: FTMSTargetSettingFeatures = []

    /// Human-readable list of supported target features.
    var supportedModes: [String] {
        var modes: [String] = []
        if contains(.powerTargetSupported) { modes.append("ERG (Target Power)") }
        if contains(.resistanceTargetSupported) { modes.append("Resistance Level") }
        if contains(.indoorBikeSimulationSupported) { modes.append("Simulation (Grade/Wind)") }
        if contains(.inclinationTargetSupported) { modes.append("Inclination Target") }
        if contains(.speedTargetSupported) { modes.append("Speed Target") }
        if contains(.spinDownControlSupported) { modes.append("Spin Down") }
        return modes
    }
}

// MARK: - Resistance Range

/// The supported resistance level range reported by the trainer (characteristic 0x2AD6).
struct ResistanceRange: Sendable {
    let minimum: Double   // e.g. 0.0
    let maximum: Double   // e.g. 100.0
    let increment: Double // e.g. 1.0

    static let `default` = ResistanceRange(minimum: 0, maximum: 100, increment: 1)
}

// MARK: - FTMSControlService

/// Manages the FTMS Control Point characteristic to send commands to a smart trainer.
///
/// Lifecycle:
/// 1. `BLEManager` discovers the FTMS service and calls `attach(peripheral:service:)`.
/// 2. This service discovers the Control Point (0x2AD9), Feature (0x2ACC), and Status (0x2ADA)
///    characteristics, reads features, and subscribes to indications.
/// 3. Before sending any command, `requestControl()` must succeed.
/// 4. Commands like `setTargetPower`, `setSimulation`, `setResistanceLevel` are then available.
/// 5. On disconnect, call `detach()` to clean up.
@Observable
@MainActor
final class FTMSControlService {

    // MARK: - Public State

    /// Whether the trainer supports FTMS control (Control Point characteristic was found).
    var isAvailable = false

    /// Whether we have been granted control of the trainer.
    var hasControl = false

    /// The currently active control mode.
    var activeMode: TrainerControlMode = .none

    /// Parsed machine features.
    var machineFeatures: FTMSFeatures = .none

    /// Parsed target setting features (which control modes the trainer supports).
    var targetSettingFeatures: FTMSTargetSettingFeatures = .none

    /// Supported resistance level range.
    var resistanceRange: ResistanceRange = .default

    /// Last error message from a control point response.
    var lastError: String?

    // MARK: - Computed Capabilities

    var supportsERG: Bool { targetSettingFeatures.contains(.powerTargetSupported) }
    var supportsSimulation: Bool { targetSettingFeatures.contains(.indoorBikeSimulationSupported) }
    var supportsResistance: Bool { targetSettingFeatures.contains(.resistanceTargetSupported) }
    var supportsInclination: Bool { targetSettingFeatures.contains(.inclinationTargetSupported) }
    var supportsSpinDown: Bool { targetSettingFeatures.contains(.spinDownControlSupported) }

    // MARK: - Private

    private weak var peripheral: CBPeripheral?
    private var controlPointCharacteristic: CBCharacteristic?
    private var ftmsStatusCharacteristic: CBCharacteristic?
    private var featureCharacteristic: CBCharacteristic?
    private var resistanceRangeCharacteristic: CBCharacteristic?

    /// Pending continuation for the current control point write → indication round-trip.
    private var pendingContinuation: CheckedContinuation<FTMSResultCode, Error>?

    /// Timeout task for the pending control point write.
    private var pendingTimeoutTask: Task<Void, Never>?

    // MARK: - Attach / Detach

    /// Called by BLEManager after discovering the FTMS service on the trainer peripheral.
    /// Discovers the required characteristics.
    func attach(peripheral: CBPeripheral, service: CBService) {
        self.peripheral = peripheral
        isAvailable = false
        hasControl = false
        activeMode = .none
        lastError = nil
        controlPointCharacteristic = nil
        ftmsStatusCharacteristic = nil
        featureCharacteristic = nil
        resistanceRangeCharacteristic = nil
        machineFeatures = .none
        targetSettingFeatures = .none
        resistanceRange = .default

        ftmsControlLogger.info("FTMS Control: attaching to \(peripheral.name ?? "Unknown")")

        // Discover characteristics for this service.
        // BLEManager's peripheral delegate will call back into
        // `didDiscoverCharacteristic` which routes to our `handleDiscoveredCharacteristic`.
        peripheral.discoverCharacteristics([
            BLEConstants.ftmsControlPointUUID,
            BLEConstants.ftmsFeatureUUID,
            BLEConstants.ftmsSupportedResistanceLevelRangeUUID,
            BLEConstants.ftmsStatusUUID,
        ], for: service)
    }

    /// Called when the trainer disconnects.
    func detach() {
        ftmsControlLogger.info("FTMS Control: detached")
        cancelPending(with: FTMSControlError.disconnected)
        peripheral = nil
        controlPointCharacteristic = nil
        ftmsStatusCharacteristic = nil
        featureCharacteristic = nil
        resistanceRangeCharacteristic = nil
        isAvailable = false
        hasControl = false
        activeMode = .none
        lastError = nil
        machineFeatures = .none
        targetSettingFeatures = .none
        resistanceRange = .default
    }

    // MARK: - Characteristic Discovery Callback

    /// Called by BLEManager when characteristics are discovered on the FTMS service.
    func handleDiscoveredCharacteristic(_ characteristic: CBCharacteristic) {
        switch characteristic.uuid {
        case BLEConstants.ftmsControlPointUUID:
            controlPointCharacteristic = characteristic
            isAvailable = true
            ftmsControlLogger.info("FTMS Control Point found ✅")

            // Subscribe to indications (required for control point responses)
            if characteristic.properties.contains(.indicate) {
                peripheral?.setNotifyValue(true, for: characteristic)
                ftmsControlLogger.info("Subscribed to Control Point indications")
            }

        case BLEConstants.ftmsFeatureUUID:
            featureCharacteristic = characteristic
            // Read the feature characteristic to learn what the trainer supports
            peripheral?.readValue(for: characteristic)
            ftmsControlLogger.info("FTMS Feature characteristic found, reading…")

        case BLEConstants.ftmsSupportedResistanceLevelRangeUUID:
            resistanceRangeCharacteristic = characteristic
            peripheral?.readValue(for: characteristic)
            ftmsControlLogger.info("Resistance Level Range characteristic found, reading…")

        case BLEConstants.ftmsStatusUUID:
            ftmsStatusCharacteristic = characteristic
            if characteristic.properties.contains(.notify) {
                peripheral?.setNotifyValue(true, for: characteristic)
                ftmsControlLogger.info("Subscribed to FTMS Status notifications")
            }

        default:
            break
        }
    }

    // MARK: - Characteristic Value Updates

    /// Called by BLEManager when a characteristic value is updated (indication/read response).
    func handleValueUpdate(for characteristic: CBCharacteristic) {
        guard let data = characteristic.value else { return }

        switch characteristic.uuid {
        case BLEConstants.ftmsControlPointUUID:
            parseControlPointResponse(data)

        case BLEConstants.ftmsFeatureUUID:
            parseFeatures(data)

        case BLEConstants.ftmsSupportedResistanceLevelRangeUUID:
            parseResistanceRange(data)

        case BLEConstants.ftmsStatusUUID:
            parseFTMSStatus(data)

        default:
            break
        }
    }

    // MARK: - Control Commands

    /// Request control of the trainer. Must be called before any other command.
    @discardableResult
    func requestControl() async throws -> FTMSResultCode {
        let result = try await writeControlPoint(opCode: .requestControl)
        if result == .success {
            hasControl = true
            ftmsControlLogger.info("FTMS: Control granted ✅")
        } else {
            ftmsControlLogger.error("FTMS: Request control failed — \(result.description)")
            lastError = "Request control: \(result.description)"
        }
        return result
    }

    /// Reset the trainer to its default state and release control.
    func reset() async throws {
        let result = try await writeControlPoint(opCode: .reset)
        if result == .success {
            activeMode = .none
            hasControl = false
            ftmsControlLogger.info("FTMS: Reset successful")
        } else {
            lastError = "Reset: \(result.description)"
        }
    }

    /// Set ERG mode — trainer locks to a specific wattage regardless of cadence.
    ///
    /// - Parameter watts: Target power in watts (clamped to 0–2000).
    func setTargetPower(watts: Int) async throws {
        guard supportsERG else {
            ftmsControlLogger.warning("Trainer does not support ERG mode (target power)")
            throw FTMSControlError.modeNotSupported("ERG / Target Power")
        }

        if !hasControl {
            try await requestControl()
        }

        let clamped = UInt16(clamping: max(0, min(watts, 2000)))

        // Op code 0x05: Set Target Power
        // Payload: sint16 in watts (we use uint16 since we clamp to positive)
        var data = Data([FTMSOpCode.setTargetPower.rawValue])
        data.append(UInt8(clamped & 0xFF))
        data.append(UInt8((clamped >> 8) & 0xFF))

        let result = try await writeControlPoint(data: data)
        if result == .success {
            activeMode = .erg(watts: Int(clamped))
            lastError = nil
            ftmsControlLogger.info("FTMS: ERG mode set to \(clamped)W ✅")
        } else {
            lastError = "Set target power: \(result.description)"
            ftmsControlLogger.error("FTMS: Set target power failed — \(result.description)")
        }
    }

    /// Set resistance level.
    ///
    /// - Parameter level: Resistance as a fraction 0.0–1.0 (mapped to the trainer's supported range).
    func setResistanceLevel(_ level: Double) async throws {
        guard supportsResistance else {
            ftmsControlLogger.warning("Trainer does not support resistance level control")
            throw FTMSControlError.modeNotSupported("Resistance Level")
        }

        if !hasControl {
            try await requestControl()
        }

        let clamped = max(0, min(level, 1.0))
        let range = resistanceRange
        let mappedValue = range.minimum + clamped * (range.maximum - range.minimum)

        // Op code 0x04: Set Target Resistance Level
        // Payload: uint8 resistance level (unitless, resolution 0.1 per FTMS spec,
        // encoded as sint16 with 0.1 resolution in some implementations).
        // Most trainers accept a simple uint8 value within their reported range.
        let intValue = UInt16(clamping: Int(mappedValue * 10)) // 0.1 resolution

        var data = Data([FTMSOpCode.setTargetResistance.rawValue])
        data.append(UInt8(intValue & 0xFF))
        data.append(UInt8((intValue >> 8) & 0xFF))

        let result = try await writeControlPoint(data: data)
        if result == .success {
            activeMode = .resistance(level: clamped)
            lastError = nil
            ftmsControlLogger.info("FTMS: Resistance set to \(String(format: "%.0f%%", clamped * 100)) (raw: \(mappedValue)) ✅")
        } else {
            lastError = "Set resistance: \(result.description)"
            ftmsControlLogger.error("FTMS: Set resistance failed — \(result.description)")
        }
    }

    /// Set indoor bike simulation parameters.
    ///
    /// This is the richest control mode — the trainer adjusts resistance dynamically
    /// to simulate real-world riding conditions based on grade, wind, and surface.
    ///
    /// - Parameters:
    ///   - windSpeed: Wind speed in meters per second (negative = headwind). Range: -33.27 to +33.27.
    ///   - grade: Road grade in percent (negative = downhill). Range: -40.0% to +40.0%.
    ///   - crr: Coefficient of rolling resistance. Typical: 0.004 (road) to 0.008 (MTB). Range: 0–0.0254.
    ///   - cw: Wind resistance coefficient (drag area Cd×A in kg/m). Typical: 0.3–0.6. Range: 0–1.86.
    func setSimulation(
        windSpeed: Double = 0,
        grade: Double = 0,
        crr: Double = 0.004,
        cw: Double = 0.51
    ) async throws {
        guard supportsSimulation else {
            ftmsControlLogger.warning("Trainer does not support simulation mode")
            throw FTMSControlError.modeNotSupported("Indoor Bike Simulation")
        }

        if !hasControl {
            try await requestControl()
        }

        // Op code 0x11: Set Indoor Bike Simulation Parameters
        // Payload (per FTMS spec):
        //   Wind Speed:    sint16, resolution 0.001 m/s
        //   Grade:         sint16, resolution 0.01 %
        //   CRR:           uint8,  resolution 0.0001
        //   Wind Resistance Coefficient (Cw): uint8, resolution 0.01 kg/m

        let windRaw = Int16(clamping: Int((max(-33.27, min(windSpeed, 33.27)) * 1000).rounded()))
        let gradeRaw = Int16(clamping: Int((max(-40.0, min(grade, 40.0)) * 100).rounded()))
        let crrRaw = UInt8(clamping: Int((max(0, min(crr, 0.0254)) * 10000).rounded()))
        let cwRaw = UInt8(clamping: Int((max(0, min(cw, 1.86)) * 100).rounded()))

        var data = Data([FTMSOpCode.setIndoorBikeSimulation.rawValue])
        // Wind speed (sint16 LE)
        data.append(UInt8(UInt16(bitPattern: windRaw) & 0xFF))
        data.append(UInt8((UInt16(bitPattern: windRaw) >> 8) & 0xFF))
        // Grade (sint16 LE)
        data.append(UInt8(UInt16(bitPattern: gradeRaw) & 0xFF))
        data.append(UInt8((UInt16(bitPattern: gradeRaw) >> 8) & 0xFF))
        // CRR (uint8)
        data.append(crrRaw)
        // Wind resistance coefficient (uint8)
        data.append(cwRaw)

        let result = try await writeControlPoint(data: data)
        if result == .success {
            activeMode = .simulation(gradePercent: grade)
            lastError = nil
            ftmsControlLogger.info("FTMS: Simulation set — grade: \(String(format: "%.1f%%", grade)), wind: \(String(format: "%.1f", windSpeed)) m/s ✅")
        } else {
            lastError = "Set simulation: \(result.description)"
            ftmsControlLogger.error("FTMS: Set simulation failed — \(result.description)")
        }
    }

    /// Convenience: set simulation with just a grade (most common use case for GPX route following).
    func setGrade(_ gradePercent: Double) async throws {
        try await setSimulation(grade: gradePercent)
    }

    /// Start spin-down calibration.
    ///
    /// Per the FTMS spec, op code 0x13 triggers a spin-down calibration sequence.
    /// The trainer will prompt the user to accelerate to > 30 km/h then coast.
    /// The trainer measures deceleration time to calibrate power/speed accuracy.
    ///
    /// The calibration result comes back via the FTMS Status characteristic.
    /// Monitor `activeMode` — it will change from `.calibrating` when done.
    func startSpinDown() async throws {
        guard supportsSpinDown else {
            ftmsControlLogger.warning("Trainer does not support spin-down control")
            throw FTMSControlError.modeNotSupported("Spin Down Calibration")
        }

        if !hasControl {
            try await requestControl()
        }

        let result = try await writeControlPoint(opCode: .spinDownControl)
        if result == .success {
            activeMode = .calibrating
            lastError = nil
            ftmsControlLogger.info("FTMS: Spin-down calibration started ✅")
        } else {
            lastError = "Spin-down: \(result.description)"
            ftmsControlLogger.error("FTMS: Spin-down failed — \(result.description)")
        }
    }

    /// Release control and return to free ride.
    func releaseControl() async {
        if hasControl {
            do {
                try await reset()
            } catch {
                ftmsControlLogger.error("FTMS: Release control failed — \(error.localizedDescription)")
            }
        }
        activeMode = .none
        hasControl = false
    }

    // MARK: - Private: Write to Control Point

    private func writeControlPoint(opCode: FTMSOpCode) async throws -> FTMSResultCode {
        try await writeControlPoint(data: Data([opCode.rawValue]))
    }

    private func writeControlPoint(data: Data) async throws -> FTMSResultCode {
        guard let peripheral, let characteristic = controlPointCharacteristic else {
            throw FTMSControlError.notAvailable
        }

        // Cancel any in-flight request
        cancelPending(with: FTMSControlError.superseded)

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingContinuation = continuation

            // Timeout after 5 seconds.
            // Explicitly inherit @MainActor so `cancelPending` is called on the
            // correct actor without a forced-sync re-entry (unsafeForcedSync warning).
            self.pendingTimeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                self.cancelPending(with: FTMSControlError.timeout)
            }

            let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            ftmsControlLogger.debug("FTMS Control Point write: \(hexString)")

            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        }
    }

    // MARK: - Private: Parse Responses

    /// Parse a Control Point indication response.
    /// Format: [0x80] [Request Op Code] [Result Code] [optional response parameters]
    private func parseControlPointResponse(_ data: Data) {
        guard data.count >= 3 else {
            ftmsControlLogger.warning("FTMS Control Point response too short (\(data.count) bytes)")
            return
        }

        let responseOpCode = data[0]
        guard responseOpCode == FTMSOpCode.responseCode.rawValue else {
            ftmsControlLogger.warning("Unexpected Control Point op code: 0x\(String(format: "%02X", responseOpCode))")
            return
        }

        let requestOpCode = data[1]
        let resultByte = data[2]
        let result = FTMSResultCode(rawValue: resultByte) ?? .unknown

        let opName = FTMSOpCode(rawValue: requestOpCode).map { "\($0)" } ?? "0x\(String(format: "%02X", requestOpCode))"
        ftmsControlLogger.info("FTMS Response: \(opName) → \(result.description)")

        // Resume the pending continuation
        pendingTimeoutTask?.cancel()
        pendingTimeoutTask = nil
        let continuation = pendingContinuation
        pendingContinuation = nil
        continuation?.resume(returning: result)
    }

    /// Parse the FTMS Feature characteristic (0x2ACC).
    /// Format: [4 bytes: Fitness Machine Features] [4 bytes: Target Setting Features]
    private func parseFeatures(_ data: Data) {
        guard data.count >= 4 else {
            ftmsControlLogger.warning("FTMS Feature data too short (\(data.count) bytes)")
            return
        }

        let machineFeaturesRaw: UInt32 = data.withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: 0, as: UInt32.self)
        }
        machineFeatures = FTMSFeatures(rawValue: UInt32(littleEndian: machineFeaturesRaw))

        if data.count >= 8 {
            let targetFeaturesRaw: UInt32 = data.withUnsafeBytes { ptr in
                ptr.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
            }
            targetSettingFeatures = FTMSTargetSettingFeatures(rawValue: UInt32(littleEndian: targetFeaturesRaw))
        }

        let modes = targetSettingFeatures.supportedModes
        ftmsControlLogger.info("FTMS Features parsed — supported modes: \(modes.joined(separator: ", "))")
    }

    /// Parse the Supported Resistance Level Range characteristic (0x2AD6).
    /// Format (6-byte spec): [sint16 minimum] [sint16 maximum] [uint16 increment] — all with 0.1 resolution.
    /// Format (3-byte compact): [uint8 minimum] [uint8 maximum] [uint8 increment] — used by ThinkRider and others.
    private func parseResistanceRange(_ data: Data) {
        if data.count >= 6 {
            // Standard FTMS spec: 3 × sint16/uint16 with 0.1 resolution
            let minRaw = Int16(bitPattern: UInt16(data[0]) | (UInt16(data[1]) << 8))
            let maxRaw = Int16(bitPattern: UInt16(data[2]) | (UInt16(data[3]) << 8))
            let incRaw = UInt16(data[4]) | (UInt16(data[5]) << 8)

            resistanceRange = ResistanceRange(
                minimum: Double(minRaw) * 0.1,
                maximum: Double(maxRaw) * 0.1,
                increment: Double(incRaw) * 0.1
            )
        } else if data.count >= 3 {
            // Compact 3-byte format (ThinkRider, some Saris/Elite trainers):
            // 3 × uint8, no 0.1 scaling — values are direct resistance levels.
            let minVal = Double(data[0])
            let maxVal = Double(data[1])
            let incVal = Double(data[2])

            resistanceRange = ResistanceRange(
                minimum: minVal,
                maximum: maxVal,
                increment: max(incVal, 1)
            )

            ftmsControlLogger.info("FTMS Resistance range (compact 3-byte format): \(minVal)–\(maxVal), step \(max(incVal, 1))")
        } else {
            ftmsControlLogger.warning("Resistance range data too short (\(data.count) bytes), using defaults")
            return
        }

        ftmsControlLogger.info("FTMS Resistance range: \(self.resistanceRange.minimum)–\(self.resistanceRange.maximum), step \(self.resistanceRange.increment)")
    }

    /// Parse FTMS Machine Status notifications (0x2ADA).
    /// These are informational — the trainer tells us about state changes
    /// (e.g. "target power changed", "control permission lost", "reset").
    private func parseFTMSStatus(_ data: Data) {
        guard let first = data.first else { return }

        switch first {
        case 0x01:
            ftmsControlLogger.info("FTMS Status: Reset")
            hasControl = false
            activeMode = .none
        case 0x02:
            ftmsControlLogger.info("FTMS Status: Stopped/Paused by safety key")
            activeMode = .none
        case 0x04:
            ftmsControlLogger.info("FTMS Status: Started/Resumed by safety key")
        case 0x05:
            // Target speed changed
            break
        case 0x07:
            // Target power changed
            if data.count >= 3 {
                let watts = Int(Int16(bitPattern: UInt16(data[1]) | (UInt16(data[2]) << 8)))
                ftmsControlLogger.info("FTMS Status: Target power changed to \(watts)W")
            }
        case 0x08:
            // Target resistance changed
            break
        case 0x12:
            // Indoor bike simulation parameters changed
            ftmsControlLogger.info("FTMS Status: Simulation parameters changed")
        case 0x0C:
            ftmsControlLogger.info("FTMS Status: Spin down — stop pedaling, coast to zero")
        case 0x0D:
            ftmsControlLogger.info("FTMS Status: Spin down — speed too high, slow down")
        case 0x0E:
            ftmsControlLogger.info("FTMS Status: Spin down — speed too low, speed up")
        case 0x0F:
            ftmsControlLogger.info("FTMS Status: Spin down calibration complete ✅")
            activeMode = .none
        case 0xFF:
            ftmsControlLogger.info("FTMS Status: Control permission lost")
            hasControl = false
            activeMode = .none
        default:
            ftmsControlLogger.debug("FTMS Status: 0x\(String(format: "%02X", first))")
        }
    }

    // MARK: - Private: Helpers

    private func cancelPending(with error: Error) {
        pendingTimeoutTask?.cancel()
        pendingTimeoutTask = nil
        let continuation = pendingContinuation
        pendingContinuation = nil
        continuation?.resume(throwing: error)
    }
}

// MARK: - Errors

enum FTMSControlError: LocalizedError {
    case notAvailable
    case modeNotSupported(String)
    case timeout
    case disconnected
    case superseded
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "FTMS Control Point is not available on this trainer."
        case .modeNotSupported(let mode):
            return "This trainer does not support \(mode)."
        case .timeout:
            return "Trainer did not respond to the control command in time."
        case .disconnected:
            return "Trainer disconnected."
        case .superseded:
            return "Command was superseded by a newer command."
        case .commandFailed(let detail):
            return "Trainer command failed: \(detail)"
        }
    }
}
