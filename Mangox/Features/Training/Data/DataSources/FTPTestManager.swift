// Features/Training/Data/DataSources/FTPTestManager.swift
import Foundation
import UIKit
import os.log

private let ftpLogger = Logger(subsystem: "com.abchalita.Mangox", category: "FTPTestManager")

enum FTPTestState: Equatable {
    case idle
    case running
    case paused
    case completed
}

/// A logged trainer resistance change event during the FTP test.
struct TrainerEvent: Identifiable {
    let id = UUID()
    let elapsed: Int  // seconds since test start
    let phaseName: String
    let mode: String  // e.g. "ERG 133W", "Free Ride", "Resistance 0%"
    let timestamp: Date = .now
}

struct FTPTestPhase: Identifiable, Equatable {
    let id: Int
    let name: String
    let duration: Int
    let detail: String
    /// Target power as a fraction of FTP for ERG mode. `nil` means free ride (e.g. the 20-min test).
    let ergTargetPercent: Double?

    init(id: Int, name: String, duration: Int, detail: String, ergTargetPercent: Double? = nil) {
        self.id = id
        self.name = name
        self.duration = duration
        self.detail = detail
        self.ergTargetPercent = ergTargetPercent
    }

    /// The ERG target in watts based on the current FTP, or nil for free-ride phases.
    var ergTargetWatts: Int? {
        guard let pct = ergTargetPercent else { return nil }
        return Int((pct * Double(PowerZone.ftp)).rounded())
    }

    /// Human-readable target string for the UI, e.g. "~146 W (55% FTP)" or "Free Ride".
    var targetLabel: String {
        guard let pct = ergTargetPercent, let watts = ergTargetWatts else {
            return "Free Ride — max sustainable effort"
        }
        return "~\(watts) W (\(Int(pct * 100))% FTP)"
    }

    /// The power zone this phase falls into (based on its ERG target).
    var targetZone: PowerZone? {
        guard let watts = ergTargetWatts else { return nil }
        return PowerZone.zone(for: watts)
    }
}

@Observable
@MainActor
final class FTPTestManager {
    static let protocolPhases: [FTPTestPhase] = [
        // Warm-up ramps progressively: Z1 → Z2 → Z3 (easy → endurance → tempo)
        FTPTestPhase(
            id: 1, name: "Warm Up — Easy", duration: 5 * 60,
            detail: "Easy spin, loosen the legs.",
            ergTargetPercent: 0.50),
        FTPTestPhase(
            id: 2, name: "Warm Up — Endurance", duration: 5 * 60,
            detail: "Build into endurance pace.",
            ergTargetPercent: 0.65),
        FTPTestPhase(
            id: 3, name: "Warm Up — Tempo", duration: 5 * 60,
            detail: "Tempo effort. You should feel the work.",
            ergTargetPercent: 0.80),
        FTPTestPhase(
            id: 4, name: "5-Min Clearing", duration: 5 * 60,
            detail: "All-out anaerobic blowout to clear W-prime. Hold on!",
            ergTargetPercent: 1.10),
        FTPTestPhase(
            id: 5, name: "Recovery", duration: 10 * 60,
            detail: "Easy spin. Breathe and prepare for the main effort.",
            ergTargetPercent: 0.45),
        FTPTestPhase(
            id: 6, name: "20 Min Test", duration: 20 * 60,
            detail: "Sustained best effort. Pace evenly — don't go out too hard."),
        FTPTestPhase(
            id: 7, name: "Cool Down", duration: 10 * 60,
            detail: "Easy spin and controlled breathing.",
            ergTargetPercent: 0.45),
    ]

    // MARK: - Public State

    var state: FTPTestState = .idle
    var currentPhaseIndex: Int = 0
    var secondsRemainingInPhase: Int = protocolPhases.first?.duration ?? 0
    var totalElapsedSeconds: Int = 0

    /// Whether ERG mode is being used for guided phases.
    var ergEnabled = false
    /// The current ERG target in watts (nil during free-ride phases like the 20-min test).
    var currentERGTarget: Int?

    /// Seconds to wait after test start before sending any trainer control commands.
    /// Gives the rider time to get on the saddle before ERG locks in.
    let trainerEngageDelay = 5

    /// Mean power over the last completed second (same cadence as `WorkoutManager` — no extra 3s smooth).
    var displayPower: Int = 0

    /// Raw latest power from BLE (kept for reference / debug).
    var currentPower: Int = 0

    /// Running average over the 20-minute test block. Updated every second during phase 4.
    var runningTwentyMinAvg: Double = 0

    /// Final 20-minute average (set once on completion).
    var averageTwentyMinutePower: Double = 0
    var estimatedFTP: Int = 0

    /// Gamification: Live estimated FTP based on running 20-minute average.
    var liveProjectedFTP: Int {
        if currentPhaseIndex == 5 && runningTwentyMinAvg > 0 {
            return Int((runningTwentyMinAvg * 0.95).rounded())
        }
        return 0
    }

    /// Dynamic pacing coach text during the 20-minute test.
    var dynamicCoachingText: String? {
        guard currentPhase.id == 6 else { return nil }
        let elapsedInPhase = currentPhase.duration - secondsRemainingInPhase

        switch elapsedInPhase {
        case 0..<300:
            return "Settle in. Find a sustainable rhythm. Don't go out too hard!"
        case 300..<600:
            return "Hold the line. Keep your breathing deep and controlled."
        case 600..<900:
            return "Over halfway. This is where it counts. Dig deep."
        default:
            return "Empty the tank! Hold nothing back. Give it everything you have left!"
        }
    }

    /// Per-phase average power so the user can review pacing after the test.
    var phaseAveragePowers: [Int: Double] = [:]  // phase id → avg watts

    /// Max power observed during the 20-minute test block.
    var testMaxPower: Int = 0

    // MARK: - Trainer Activity (Improvement #1)

    /// Logged resistance change events during this test session.
    var recentEvents: [TrainerEvent] = []

    /// Human-readable label for the current trainer mode.
    var trainerModeLabel: String {
        if state == .idle { return "Idle" }
        if let watts = currentERGTarget {
            return "ERG \(watts)W"
        }
        if currentPhase.ergTargetPercent == nil && state == .running {
            return "Free Ride"
        }
        return ergEnabled ? "Waiting…" : "No ERG"
    }

    /// Set to the upcoming phase name when a "10s remaining" cue should fire.
    var pendingPhaseWarning: String? = nil

    /// ID of the most recent saved result, used to mark it as applied.
    var lastResultID: UUID?

    var phases: [FTPTestPhase] { Self.protocolPhases }

    // MARK: - Private

    private weak var bleManager: BLEManager?
    private weak var dataSource: DataSourceCoordinator?
    private var timer: Timer?

    /// Accumulates all BLE power readings within the current 1-second window.
    /// Averaged on each timer tick to eliminate aliasing from ~4 Hz BLE updates.
    private var powerAccumulator: [Int] = []

    /// Last three **one-second** average powers — for optional 3 s hero display (same setting as indoor rides).
    private var ring3s = RingBuffer<Int>(capacity: 3)

    // 20-minute test accumulators
    private var testPowerSum: Double = 0
    private var testSampleCount: Int = 0

    // Per-phase accumulators
    private var phasePowerSum: Double = 0
    private var phaseSampleCount: Int = 0

    // ERG ramp state (Improvement #5)
    /// When non-nil, the manager is ramping from one ERG target to another.
    private var rampFromWatts: Int?
    private var rampToWatts: Int?
    /// Seconds into the current ramp (0 = just started).
    private var rampElapsed: Int = 0
    /// Total ramp duration in seconds.
    private let rampDuration: Int = 10
    /// How often (in seconds) to send an intermediate ERG target during a ramp.
    private let rampStepInterval: Int = 2

    private static let subscriberID = "FTPTestManager"

    nonisolated deinit {
        // Timer and BLE cleanup happen via reset() before dealloc in practice.
        // deinit cannot call @MainActor methods, so we only guard against leaks.
    }

    // MARK: - Configuration

    func configure(bleManager: BLEManager, dataSource: DataSourceCoordinator? = nil) {
        self.bleManager?.unsubscribe(id: Self.subscriberID)
        self.dataSource?.unsubscribeCyclingMetrics(id: Self.subscriberID)

        self.bleManager = bleManager
        self.dataSource = dataSource

        // ERG only applies when a BLE trainer is connected; Wi‑Fi bridges are manual resistance.
        ergEnabled =
            bleManager.ftmsControl.supportsERG && bleManager.trainerConnectionState.isConnected

        if let dataSource {
            dataSource.subscribeCyclingMetrics(id: Self.subscriberID) { [weak self] metrics in
                self?.ingestBLEPacket(metrics)
            }
        } else {
            bleManager.subscribe(id: Self.subscriberID) { [weak self] metrics in
                self?.ingestBLEPacket(metrics)
            }
        }
    }

    /// Call when leaving the FTP test screen so subscriptions are released.
    func tearDown() {
        stopTimer()
        bleManager?.unsubscribe(id: Self.subscriberID)
        dataSource?.unsubscribeCyclingMetrics(id: Self.subscriberID)
    }

    /// FTMS control targets the BLE trainer; skip when power comes from a Wi‑Fi bridge.
    private var trainerControlViaBLE: Bool {
        guard let ble = bleManager, ble.trainerConnectionState.isConnected else { return false }
        if let ds = dataSource, ds.activeDataSource == .wifi { return false }
        return true
    }

    // MARK: - Computed Properties

    var canStart: Bool {
        if let ds = dataSource {
            return ds.isConnected
        }
        return bleManager?.trainerConnectionState.isConnected == true
    }

    var currentPhase: FTPTestPhase {
        let safeIndex = min(max(0, currentPhaseIndex), phases.count - 1)
        return phases[safeIndex]
    }

    var phaseProgress: Double {
        let duration = max(1, currentPhase.duration)
        let completed = duration - secondsRemainingInPhase
        return min(max(Double(completed) / Double(duration), 0), 1)
    }

    var formattedRemaining: String {
        Self.format(seconds: secondsRemainingInPhase)
    }

    var formattedElapsed: String {
        Self.format(seconds: totalElapsedSeconds)
    }

    /// Percentage of the 20-minute test block completed (0–1). Zero outside phase 6.
    var testBlockProgress: Double {
        guard currentPhase.id == 6 else {
            return state == .completed ? 1.0 : 0.0
        }
        let testDuration = Double(phases.first { $0.id == 6 }?.duration ?? 1200)
        return min(Double(testSampleCount) / testDuration, 1.0)
    }

    // MARK: - Actions

    func start() {
        guard canStart else { return }
        if state == .completed {
            reset()
        }
        guard state == .idle else { return }
        state = .running
        startTimer()
        // Do NOT apply ERG immediately — wait for the engage delay so the
        // rider has time to clip in before the trainer locks resistance.
        // applyERGForCurrentPhase() is called from tick() once the delay passes.
    }

    func pause() {
        guard state == .running else { return }
        state = .paused
        stopTimer()
    }

    func resume() {
        guard state == .paused else { return }
        state = .running
        startTimer()
    }

    func reset() {
        stopTimer()
        releaseERG()
        state = .idle
        currentPhaseIndex = 0
        secondsRemainingInPhase = phases.first?.duration ?? 0
        totalElapsedSeconds = 0
        currentPower = 0
        displayPower = 0
        runningTwentyMinAvg = 0
        averageTwentyMinutePower = 0
        estimatedFTP = 0
        testMaxPower = 0
        testPowerSum = 0
        testSampleCount = 0
        phasePowerSum = 0
        phaseSampleCount = 0
        phaseAveragePowers.removeAll()
        powerAccumulator.removeAll()
        ring3s.reset()
        currentERGTarget = nil
        lastResultID = nil
        recentEvents.removeAll()
        pendingPhaseWarning = nil
        rampFromWatts = nil
        rampToWatts = nil
        rampElapsed = 0
    }

    func applyEstimatedFTP() {
        guard estimatedFTP > 0 else { return }
        PowerZone.setFTP(estimatedFTP)
        if let id = lastResultID {
            FTPTestHistory.markApplied(id: id)
        }
    }

    // MARK: - Event-Driven BLE Ingestion

    /// Called by BLEManager subscriber every time a new BLE packet arrives (~4 Hz).
    /// Accumulates power readings; the 1-second timer tick averages them.
    private func ingestBLEPacket(_ metrics: CyclingMetrics) {
        guard state == .running else { return }
        powerAccumulator.append(metrics.power)
        currentPower = metrics.power
        // Capture true spike within the 20‑min block (not just per-second averages).
        if currentPhase.id == 6 {
            testMaxPower = max(testMaxPower, max(0, metrics.power))
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private var lastNonZeroPower: Int = 0

    private func tick() {
        guard state == .running else { return }
        totalElapsedSeconds += 1

        let timeSinceLastPacket: TimeInterval
        if let lastPacket = bleManager?.lastPacketReceived {
            timeSinceLastPacket = Date().timeIntervalSince(lastPacket)
        } else {
            timeSinceLastPacket = .infinity
        }
        let isShortGap = timeSinceLastPacket > 1.0 && timeSinceLastPacket <= 5.0

        // Average all BLE readings from this 1-second window.
        let avgPower: Int
        if powerAccumulator.isEmpty {
            // Smooth over short BLE drops (< 5s), otherwise zero out
            avgPower = isShortGap ? lastNonZeroPower : 0
        } else {
            avgPower = TrainerPowerMetrics.meanInt(samples: powerAccumulator)
            lastNonZeroPower = avgPower
        }
        powerAccumulator.removeAll(keepingCapacity: true)

        ring3s.append(avgPower)
        switch RidePreferences.shared.indoorPowerHeroMode {
        case .oneSecond:
            displayPower = avgPower
        case .threeSecond:
            displayPower = Int(ring3s.average.rounded())
        }

        // Per-phase accumulation
        phasePowerSum += Double(max(0, avgPower))
        phaseSampleCount += 1

        // 20-minute test block accumulation (phase id == 6)
        if currentPhase.id == 6 {
            let clampedPower = max(0, avgPower)
            testPowerSum += Double(clampedPower)
            testSampleCount += 1

            // Update live running average
            if testSampleCount > 0 {
                runningTwentyMinAvg = testPowerSum / Double(testSampleCount)
            }
        }

        // Apply ERG once the engage delay has passed (first tick after delay).
        if totalElapsedSeconds == trainerEngageDelay {
            applyERGForCurrentPhase()
        }

        // Advance ERG ramp (if active)
        tickRamp()

        // Phase countdown
        secondsRemainingInPhase -= 1

        // Dynamic coaching haptics for the 20-minute test block
        if currentPhase.id == 6 {
            let elapsedInPhase = currentPhase.duration - secondsRemainingInPhase
            if elapsedInPhase == 300 || elapsedInPhase == 600 || elapsedInPhase == 900 {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }

        // 10-second warning before next phase (haptic + audio cue)
        if secondsRemainingInPhase == 10 && currentPhaseIndex < phases.count - 1 {
            let nextPhase = phases[currentPhaseIndex + 1]
            pendingPhaseWarning = nextPhase.name
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }

        if secondsRemainingInPhase > 0 {
            return
        }

        // Phase completed — record its average power
        finishCurrentPhase()

        if currentPhaseIndex < phases.count - 1 {
            currentPhaseIndex += 1
            secondsRemainingInPhase = phases[currentPhaseIndex].duration
            resetPhaseAccumulators()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            applyERGForCurrentPhase()
        } else {
            finish()
        }
    }

    // MARK: - Phase Management

    private func finishCurrentPhase() {
        let phaseID = currentPhase.id
        if phaseSampleCount > 0 {
            phaseAveragePowers[phaseID] = phasePowerSum / Double(phaseSampleCount)
        }
    }

    private func resetPhaseAccumulators() {
        phasePowerSum = 0
        phaseSampleCount = 0
    }

    // MARK: - Completion

    private func finish() {
        stopTimer()
        releaseERG()

        // Record the last phase average
        finishCurrentPhase()

        state = .completed

        guard testSampleCount > 0 else {
            // Edge case: somehow no samples during the test block
            averageTwentyMinutePower = 0
            estimatedFTP = 0
            return
        }

        averageTwentyMinutePower = testPowerSum / Double(testSampleCount)
        // Industry-standard estimate: FTP ≈ 95% of 20-minute average power.
        estimatedFTP = Int((averageTwentyMinutePower * 0.95).rounded())

        // Guard against nonsensical results
        if estimatedFTP < 50 {
            estimatedFTP = 0
            return
        }

        // Persist the result
        let result = FTPTestResult(
            twentyMinuteAvgPower: averageTwentyMinutePower,
            estimatedFTP: estimatedFTP,
            maxPower: testMaxPower,
            phaseAverages: phaseAveragePowers
        )
        FTPTestHistory.append(result)
        lastResultID = result.id
    }

    // MARK: - ERG Control

    /// Apply the ERG target for the current phase, or drop to minimum resistance for free-ride phases.
    private func applyERGForCurrentPhase() {
        guard ergEnabled else {
            currentERGTarget = nil
            logEvent(mode: "ERG Disabled")
            return
        }
        guard let bleManager else {
            currentERGTarget = nil
            logEvent(mode: "No Trainer")
            return
        }
        guard trainerControlViaBLE else {
            currentERGTarget = nil
            logEvent(mode: "WiFi — set resistance on trainer")
            return
        }

        let phase = currentPhase
        if let targetWatts = phase.ergTargetWatts {
            // If we have a previous ERG target, ramp gradually; otherwise set instantly.
            if let previousWatts = currentERGTarget, previousWatts != targetWatts {
                startRamp(from: previousWatts, to: targetWatts)
            } else {
                // First phase or same target — set immediately.
                currentERGTarget = targetWatts
                logEvent(mode: "ERG \(targetWatts)W")
                sendERGCommand(watts: targetWatts)
            }
        } else {
            // Free-ride phase (the 20-min test).
            // Drop to resistance 0 instead of a full FTMS reset — a reset forces
            // a re-negotiate cycle that causes a brief hard lock before the trainer
            // releases, which feels jarring mid-workout.
            currentERGTarget = nil
            cancelRamp()
            logEvent(mode: "Free Ride")
            Task {
                do {
                    if bleManager.ftmsControl.supportsResistance {
                        // Apply ~45% resistance to provide "pacing rails" and a solid road-like feel for the 20-min block
                        try await bleManager.ftmsControl.setResistanceLevel(0.45)
                        ftpLogger.info(
                            "FTP Test: Resistance → 45% for free-ride phase \(phase.name)")
                    } else {
                        await bleManager.ftmsControl.releaseControl()
                        ftpLogger.info(
                            "FTP Test: Released control for free-ride phase \(phase.name)")
                    }
                } catch {
                    ftpLogger.error(
                        "FTP Test: Free-ride transition failed for phase \(phase.name): \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    /// Send a single ERG command to the trainer.
    private func sendERGCommand(watts: Int) {
        guard let bleManager, trainerControlViaBLE else { return }
        Task {
            do {
                try await bleManager.ftmsControl.setTargetPower(watts: watts)
                ftpLogger.info("FTP Test: ERG set to \(watts)W")
            } catch {
                ftpLogger.error("FTP Test: ERG command failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - ERG Ramp (Smooth Transitions)

    /// Start a gradual ramp from one ERG target to another over `rampDuration` seconds.
    private func startRamp(from: Int, to: Int) {
        rampFromWatts = from
        rampToWatts = to
        rampElapsed = 0
        // Set the display target to the final value immediately so the UI shows where we're heading.
        currentERGTarget = to
        logEvent(mode: "Ramp → \(to)W")
        // Send the first intermediate value right away.
        let firstStep = interpolateRamp(elapsed: 0)
        sendERGCommand(watts: firstStep)
    }

    /// Advance the ramp by one second, sending intermediate ERG targets at regular intervals.
    private func tickRamp() {
        guard rampFromWatts != nil, let to = rampToWatts else { return }
        rampElapsed += 1

        if rampElapsed >= rampDuration {
            // Ramp complete — send final target and clean up.
            sendERGCommand(watts: to)
            cancelRamp()
            return
        }

        // Send intermediate target every `rampStepInterval` seconds.
        if rampElapsed % rampStepInterval == 0 {
            let intermediate = interpolateRamp(elapsed: rampElapsed)
            sendERGCommand(watts: intermediate)
        }
    }

    /// Linear interpolation between ramp start and end.
    private func interpolateRamp(elapsed: Int) -> Int {
        guard let from = rampFromWatts, let to = rampToWatts, rampDuration > 0 else {
            return rampToWatts ?? 0
        }
        let fraction = min(Double(elapsed) / Double(rampDuration), 1.0)
        return Int((Double(from) + fraction * Double(to - from)).rounded())
    }

    /// Cancel any in-progress ramp.
    private func cancelRamp() {
        rampFromWatts = nil
        rampToWatts = nil
        rampElapsed = 0
    }

    /// Release ERG control (used on reset/completion).
    /// Uses resistance 0 for a smooth release, falling back to full reset only
    /// when resistance mode is not supported.
    private func releaseERG() {
        currentERGTarget = nil
        guard let bleManager, trainerControlViaBLE else { return }
        Task { @MainActor in
            do {
                if bleManager.ftmsControl.supportsResistance {
                    try await bleManager.ftmsControl.setResistanceLevel(0)
                } else {
                    await bleManager.ftmsControl.releaseControl()
                }
            } catch {
                ftpLogger.error("FTP Test: releaseERG failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Event Logging

    /// Log a trainer event (capped at 20 most recent).
    private func logEvent(mode: String) {
        let event = TrainerEvent(
            elapsed: totalElapsedSeconds,
            phaseName: currentPhase.name,
            mode: mode
        )
        recentEvents.append(event)
        if recentEvents.count > 20 {
            recentEvents.removeFirst(recentEvents.count - 20)
        }
    }

    // MARK: - Formatting

    static func format(seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let h = safeSeconds / 3600
        let m = (safeSeconds % 3600) / 60
        let s = safeSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
