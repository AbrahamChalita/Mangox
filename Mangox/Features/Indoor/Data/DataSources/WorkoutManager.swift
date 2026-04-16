import Foundation
import SwiftData
import os.log

private let workoutLogger = Logger(subsystem: "com.abchalita.Mangox", category: "WorkoutManager")

/// Buffers 1 Hz rows before inserting into SwiftData in batches (fewer fault allocations + fewer saves).
private struct PendingWorkoutSample {
    let elapsedSeconds: Int
    let power: Int
    let cadence: Double
    let speed: Double
    let heartRate: Int
}

private struct IndoorRouteSnapshot {
    let routeName: String?
    let plannedDistanceMeters: Double
    let elevationProfilePoints: [(distance: Double, elevation: Double)]

    var hasElevationData: Bool {
        !elevationProfilePoints.isEmpty
    }
}

struct PowerSample: Identifiable {
    let elapsed: Int
    let power: Int

    var id: Int { elapsed }
}

/// A single peak power entry for a given time window.
struct PeakPowerEntry: Identifiable {
    let windowSeconds: Int
    let watts: Int
    let atElapsed: Int  // when during the ride this peak occurred

    var id: Int { windowSeconds }

    var label: String {
        if windowSeconds < 60 { return "\(windowSeconds)s" }
        return "\(windowSeconds / 60)m"
    }
}

enum RecordingState: Equatable {
    case idle
    case recording
    case paused
    case autoPaused
    case finished

    /// True while a ride is in progress (including manual or auto-pause).
    var isLiveSessionActive: Bool {
        switch self {
        case .recording, .paused, .autoPaused: true
        case .idle, .finished: false
        }
    }
}

@Observable
@MainActor
final class WorkoutManager {
    // MARK: - Public State

    var state: RecordingState = .idle {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(oldValue, state)
        }
    }
    var elapsedSeconds: Int = 0  // active time only
    var currentLapNumber: Int = 1
    var powerHistory: [PowerSample] = []  // last 60 points for chart

    // MARK: - Goal Progress (updated every second, read by DashboardView)

    /// Progress fraction (0–1) for each active goal. Keyed by RideGoal.Kind.rawValue.
    var goalProgress: [String: Double] = [:]

    /// Goals that just completed this tick — consumed by DashboardView for banner/haptic.
    var justCompletedGoals: [RideGoal] = []

    // MARK: - Cadence Warning

    /// True when cadence has been below threshold for > 30 consecutive seconds while recording.
    var showLowCadenceWarning: Bool = false
    /// Mirrors ``lowCadenceSeconds`` for ride-tip logic (consecutive seconds below threshold while pedaling).
    private(set) var lowCadenceStreakSeconds: Int = 0

    // MARK: - Step Audio Cue

    /// Set to the step label when a "10s remaining" cue should fire; cleared after consumption.
    var pendingStepCueLabel: String? = nil

    // Rolling averages (updated once per second from averaged BLE data)
    var avg3s: Double = 0
    var avg5s: Double = 0
    var avg30s: Double = 0

    /// Display / zone power: **mean power over the last completed second** (all ~4–8 Hz samples averaged).
    /// This matches physical effort for intervals better than an extra 3s smooth on top.
    /// Rolling 3s / 5s / 30s values are still exposed as `avg3s`, `avg5s`, `avg30s` for smoothing fans.
    var displayPower: Int = 0

    // Live performance metrics (updated every second)
    var liveNP: Double = 0  // Normalized Power (W)
    var liveIF: Double = 0  // Intensity Factor (NP / FTP)
    var liveTSS: Double = 0  // Training Stress Score (running)
    var kilojoules: Double = 0  // Cumulative energy output (kJ)
    var efficiencyFactor: Double = 0  // Watts per heartbeat (W/bpm)
    var variabilityIndex: Double = 0  // NP / avg power (1.0 = perfectly steady)
    var averagePower: Double = 0  // Session average power (W)

    // MARK: - Pre-formatted strings (updated once per second, avoids String(format:) in view body)

    /// Running maximum power seen in the live chart window (last 60 samples).
    /// Tracked here so PowerGraphView never needs to scan the array.
    var powerHistoryMax: Int = 100

    var formattedSpeed: String = "0.0"
    /// Current speed in km/h (raw, not formatted). Used by Live Activity.
    var metricsSpeed: Double = 0
    var formattedCadence: String = "0"
    /// Last completed second’s mean cadence (rpm); 0 when no valid samples.
    private(set) var displayCadenceRpm: Double = 0
    var formattedDistanceKm: String = "0.00"  // 2 dp — phone compact grid
    var formattedDistanceKm1dp: String = "0.0"  // 1 dp — iPad metrics grid
    var formattedEnergyKJ: String = "0"
    var formattedLiveNP: String = "0"
    var formattedLiveIF: String = "0.00"
    var formattedLiveTSS: String = "0"
    var formattedVI: String = "1.00"
    var formattedAvgPower: String = "0"
    var formattedEfficiency: String = "0.00"
    var formattedKJ: String = "0"

    // Trainer control state (exposed for UI)
    var trainerMode: TrainerControlMode = .none

    // MARK: - Peak Power Curve (Best Efforts)

    /// Time windows to track for peak power (in seconds).
    /// Standard cycling intervals: 5s, 15s, 30s, 1m, 5m, 20m.
    static let peakWindows = [5, 15, 30, 60, 300, 1200]

    /// Caps speed–distance integration when the main run loop stalls (pause/end still clear `lastSampleDate`).
    private static let distanceIntegrationMaxDt: TimeInterval = 2.0

    /// Best effort recorded for each peak window.
    /// Updated live during the ride; can be shown in a post-ride summary or a live "best efforts" card.
    var peakPowers: [PeakPowerEntry] = []

    /// Rolling ring buffers for each peak window, filled with 1-second power samples.
    private var peakBuffers: [Int: RingBuffer<Int>] = [:]
    /// Best average seen so far for each window.
    private var peakBests: [Int: (watts: Int, atElapsed: Int)] = [:]
    var currentGrade: Double = 0  // current road grade % from GPX
    var currentElevation: Double?  // current elevation in meters from GPX

    // MARK: - Modifiers

    /// Scales the ERG target power mid-ride (e.g., 0.90 for 90%).
    var intensityMultiplier: Double = 1.0 {
        didSet {
            if let base = baseErgTarget, case .erg = trainerMode {
                setERGMode(watts: base)
            }
        }
    }

    /// Scales the simulated route grade (Zwift "Trainer Difficulty", default 0.5 = 50%).
    var routeDifficultyScale: Double = 0.5 {
        didSet {
            // Force a grade update on the next tick to apply the new difficulty immediately
            lastSentGrade = nil
        }
    }

    /// Called every second with (elapsedSeconds, displayPower).
    /// Used by `GuidedSessionManager` to drive interval tracking.
    var onTick: ((Int, Int) -> Void)?
    /// Called when ride state changes (recording/pause/finish), useful for side-effects such as Live Activity sync.
    var onStateChange: ((RecordingState, RecordingState) -> Void)?

    /// The plan day ID for a guided session. Set before calling `startWorkout()`.
    /// Stored on the `Workout` model so deletion can un-mark plan completion.
    var activePlanDayID: String?
    var activePlanID: String?

    // Current lap accumulators (exposed for UI)
    var currentLapDuration: TimeInterval = 0
    var currentLapAvgPower: Double = 0
    var previousLapAvgPower: Double = 0
    var previousLapDuration: TimeInterval = 0
    var activeDistance: Double = 0  // meters since workout start

    // Workout reference
    var workout: Workout?

    // MARK: - Private

    private var timer: Timer?

    // Goal tracking (previous-tick values for edge detection)
    private var prevGoalDistance: Double = 0  // km
    private var prevGoalMinutes: Double = 0
    private var prevGoalKJ: Double = 0
    private var prevGoalTSS: Double = 0

    // Cadence warning
    private var lowCadenceSeconds: Int = 0
    private var ring3s = RingBuffer<Int>(capacity: 3)
    private var ring5s = RingBuffer<Int>(capacity: 5)
    private var ring30s = RingBuffer<Int>(capacity: 30)

    /// Accumulates all BLE power readings received within the current 1-second window.
    /// On each timer tick we average these into a single sample, eliminating aliasing.
    private var powerAccumulator: [Int] = []
    /// Accumulates cadence readings within the current 1-second window.
    private var cadenceAccumulator: [Double] = []
    /// Accumulates speed readings within the current 1-second window.
    private var speedAccumulator: [Double] = []
    /// Accumulates heart rate readings within the current 1-second window.
    private var hrAccumulator: [Int] = []
    /// Tracks the latest total distance from BLE within the current window.
    private var latestDistanceInWindow: Double?

    private var zeroPowerSeconds = 0
    private let autoPauseThreshold = 3
    /// After the rider hits **Resume** (not BLE-driven auto-resume), ignore auto-pause until this
    /// `elapsedSeconds` so coasting / clipping in does not instantly snap back to AUTO-PAUSED.
    private var autoPauseSuppressedUntilElapsed: Int?
    private static let autoPauseGraceSecondsAfterUserResume = 8

    // Lap accumulation
    private var lapPowerSum: Double = 0
    private var lapSampleCount: Int = 0
    private var lapMaxPower: Int = 0
    private var lapCadenceSum: Double = 0
    private var lapSpeedSum: Double = 0
    private var lapHRSum: Double = 0
    private var lapElapsedSeconds: Int = 0
    private var lapStartDistance: Double = 0

    // NP accumulation
    private var rollingPower4thSum: Double = 0
    private var rollingPower4thCount: Int = 0

    // Session-wide power accumulation for live metrics
    private var totalPowerSum: Double = 0
    private var totalPowerSampleCount: Int = 0
    private var totalEnergyJoules: Double = 0

    // BLE dropout protection: last valid power value to hold during dropouts
    private var lastNonZeroPower: Int = 0

    private var workoutStartDistance: Double = 0
    private var lastRecordedDistance: Double = 0
    private var integratedDistance: Double = 0
    private var integratedDistanceAnchor: Double = 0

    private(set) weak var bleService: (any BLEServiceProtocol)?
    private weak var dataSource: (any DataSourceServiceProtocol)?
    /// Latest packet ingested (BLE or unified coordinator) — used for route simulation and distance when WiFi is active.
    private var lastIngestedMetrics: CyclingMetrics?
    private var modelContext: ModelContext = PersistenceContainer.shared.mainContext
    private weak var routeService: (any RouteServiceProtocol)?
    private var routeSnapshot: IndoorRouteSnapshot?

    /// How often (in seconds) to send grade updates to the trainer during simulation.
    /// 5s is a good balance: responsive enough for steep climbs, not spammy on flat roads.
    private let gradeUpdateInterval = 5

    /// Seconds to wait after workout start before sending any trainer control commands.
    /// Gives the rider time to get on the saddle and start pedalling before ERG locks in.
    let trainerEngageDelay = 5
    /// Last grade sent to avoid redundant BLE writes when grade hasn't changed meaningfully.
    private var lastSentGrade: Double?

    /// Pending 1 Hz samples — flushed in batches to reduce SwiftData insert churn during long rides.
    private var pendingSamples: [PendingWorkoutSample] = []
    private let sampleBatchSize = 5

    /// Base unscaled ERG target.
    private var baseErgTarget: Int?

    /// Active ERG target (if set externally, e.g. by a training plan or manual control).
    private var ergTarget: Int?

    /// Wall-clock anchor used to keep `elapsedSeconds` accurate even if timer callbacks are delayed
    /// while the app is backgrounded.
    private var recordingStartWallClock: Date?
    private var pausedWallClockDuration: TimeInterval = 0
    private var pauseStartedAtWallClock: Date?

    // nonisolated so deinit can access it without crossing actor boundaries.
    private nonisolated static let subscriberID = "WorkoutManager"

    /// Call this before releasing the WorkoutManager (e.g. in onDisappear or scene teardown).
    /// Avoids touching @MainActor properties from deinit, which has inconsistent
    /// actor isolation guarantees across Swift toolchain versions.
    func tearDown() {
        stopTimer()
        onTick = nil
        onStateChange = nil
        bleService?.unsubscribe(id: Self.subscriberID)
        dataSource?.unsubscribeCyclingMetrics(id: Self.subscriberID)
    }

    // MARK: - Lifecycle

    func configure(
        bleService: any BLEServiceProtocol,
        dataSource: (any DataSourceServiceProtocol)? = nil
    ) {
        self.bleService = bleService
        self.dataSource = dataSource

        bleService.unsubscribe(id: Self.subscriberID)
        dataSource?.unsubscribeCyclingMetrics(id: Self.subscriberID)

        if let dataSource {
            dataSource.subscribeCyclingMetrics(id: Self.subscriberID) { [weak self] metrics in
                self?.ingest(metrics)
            }
        } else {
            bleService.subscribe(id: Self.subscriberID) { [weak self] metrics in
                self?.ingest(metrics)
            }
        }
    }

    /// Attach a route manager for GPX-based simulation.
    /// Call before starting the workout if a route is loaded.
    func configureRoute(_ routeService: (any RouteServiceProtocol)?) {
        self.routeService = routeService
        routeSnapshot = Self.makeRouteSnapshot(from: routeService)
    }

    // MARK: - Trainer Control

    /// Enable ERG mode — trainer locks to a fixed wattage.
    func setERGMode(watts: Int) {
        guard let bleService else { return }
        baseErgTarget = watts
        let scaledWatts = Int(Double(watts) * intensityMultiplier)
        ergTarget = scaledWatts
        Task { @MainActor in
            do {
                try await bleService.setTargetPower(watts: scaledWatts)
                self.trainerMode = bleService.ftmsControlActiveMode
                workoutLogger.info("ERG mode set: \(watts)W")
            } catch FTMSControlError.superseded {
                // A newer command arrived before this one completed — not an error.
                workoutLogger.debug("ERG command superseded (rapid step transition)")
            } catch {
                workoutLogger.error("ERG mode failed: \(error.localizedDescription)")
            }
        }
    }

    /// Enable simulation mode with a specific grade (manual override, not from GPX).
    func setSimulationMode(grade: Double) {
        guard let bleService else { return }
        baseErgTarget = nil
        ergTarget = nil
        Task { @MainActor in
            do {
                try await bleService.setSimulationGrade(grade)
                self.trainerMode = bleService.ftmsControlActiveMode
                self.currentGrade = grade
                self.lastSentGrade = grade
                workoutLogger.info("Simulation mode set: \(String(format: "%.1f", grade))% grade")
            } catch FTMSControlError.superseded {
                // A newer command arrived before this one completed — not an error.
                workoutLogger.debug("Simulation command superseded (rapid step transition)")
            } catch {
                workoutLogger.error("Simulation mode failed: \(error.localizedDescription)")
            }
        }
    }

    /// Enable resistance mode — raw resistance level (0.0–1.0).
    func setResistanceMode(level: Double) {
        guard let bleService else { return }
        baseErgTarget = nil
        ergTarget = nil
        Task { @MainActor in
            do {
                try await bleService.setResistanceLevel(level)
                self.trainerMode = bleService.ftmsControlActiveMode
                workoutLogger.info("Resistance mode set: \(String(format: "%.0f%%", level * 100))")
            } catch FTMSControlError.superseded {
                // A newer command arrived before this one completed — not an error.
                workoutLogger.debug("Resistance command superseded (rapid step transition)")
            } catch {
                workoutLogger.error("Resistance mode failed: \(error.localizedDescription)")
            }
        }
    }

    /// Return to free ride — release trainer control.
    func releaseTrainerControl() {
        guard let bleService else { return }
        baseErgTarget = nil
        ergTarget = nil
        lastSentGrade = nil
        Task { @MainActor in
            await bleService.releaseTrainerControl()
            self.trainerMode = .none
            self.currentGrade = 0
            workoutLogger.info("Trainer control released — free ride")
        }
    }

    /// Start GPX route simulation — automatically sends grade updates based on distance.
    func startRouteSimulation() {
        guard let bleService, routeService?.hasRoute == true else {
            workoutLogger.warning("Cannot start route simulation — no route loaded")
            return
        }
        guard bleService.ftmsControlSupportsSimulation else {
            workoutLogger.warning("Trainer does not support simulation mode")
            return
        }
        baseErgTarget = nil
        ergTarget = nil
        // The first grade update will be sent on the next tick
        lastSentGrade = nil
        workoutLogger.info(
            "Route simulation enabled — grade updates every \(self.gradeUpdateInterval)s")
    }

    /// Stop route simulation without releasing control entirely.
    /// Only sends a grade=0 command if the trainer is actually in simulation mode —
    /// avoids a spurious BLE write (and potential mode switch) when the trainer is
    /// already in ERG or free-ride.
    func stopRouteSimulation() {
        lastSentGrade = nil
        guard case .simulation = bleService?.ftmsControlActiveMode else { return }
        setSimulationMode(grade: 0)
    }

    func startWorkout() {
        guard state == .idle else { return }

        let w = Workout(startDate: .now, planDayID: activePlanDayID, planID: activePlanID)
        w.status = .active
        routeSnapshot = Self.makeRouteSnapshot(from: routeService)
        if let routeSnapshot {
            w.savedRouteName = routeSnapshot.routeName
            w.plannedRouteDistanceMeters = routeSnapshot.plannedDistanceMeters
        }
        modelContext.insert(w)
        workout = w

        // Start first lap
        let lap = LapSplit(lapNumber: 1, startTime: .now)
        lap.workout = w
        modelContext.insert(lap)

        resetAccumulators()
        recordingStartWallClock = w.startDate
        pausedWallClockDuration = 0
        pauseStartedAtWallClock = nil
        let initialDistance: Double
        if let ds = dataSource {
            initialDistance = ds.activeTotalDistanceFieldPresent ? ds.totalDistance : 0
        } else if bleService?.metrics.includesTotalDistanceInPacket == true {
            initialDistance = bleService?.metrics.totalDistance ?? 0
        } else {
            initialDistance = 0
        }
        workoutStartDistance = initialDistance
        lapStartDistance = 0
        lastRecordedDistance = initialDistance
        integratedDistanceAnchor = 0

        state = .recording
        startTimer()

        // Do NOT fire onTick at elapsed=0 here. The first real tick comes from
        // the timer after 1 second, which is intentional — it lets the rider
        // clip in and start pedalling before the trainer engages.
        // Route simulation is only auto-started on free rides (no guided session).
        // Guided sessions control the trainer mode themselves step-by-step.
        if onTick == nil,
            routeService?.hasRoute == true,
            bleService?.ftmsControlSupportsSimulation == true
        {
            startRouteSimulation()
        }
    }

    func pause() {
        switch state {
        case .recording:
            flushPendingSamples()
            state = .paused
            stopTimer()
            workout?.status = .paused
            markPauseStartedIfNeeded()
            autoPauseSuppressedUntilElapsed = nil
            do { try modelContext.save() } catch { workoutLogger.error("pause save failed: \(error)") }
        case .autoPaused:
            // Commit to a full manual pause (also covers a race where auto-pause wins just before the
            // rider taps PAUSE while the UI still shows the recording layout).
            flushPendingSamples()
            state = .paused
            workout?.status = .paused
            markPauseStartedIfNeeded()
            autoPauseSuppressedUntilElapsed = nil
            do { try modelContext.save() } catch { workoutLogger.error("pause save failed: \(error)") }
        default:
            return
        }
    }

    /// - Parameter fromUserControls: `true` when the rider used Pause/Resume in the UI — applies a
    ///   short grace window before auto-pause can fire again. `false` for BLE-driven auto-resume.
    func resume(fromUserControls: Bool = false) {
        guard state == .paused || state == .autoPaused else { return }
        consumePausedWallClockDurationIfNeeded()
        state = .recording
        workout?.status = .active
        zeroPowerSeconds = 0
        if fromUserControls {
            autoPauseSuppressedUntilElapsed =
                elapsedSeconds + Self.autoPauseGraceSecondsAfterUserResume
        } else {
            autoPauseSuppressedUntilElapsed = nil
        }
        startTimer()
    }

    func lap() {
        guard state == .recording else { return }

        finishCurrentLap()
        currentLapNumber += 1

        let newLap = LapSplit(lapNumber: currentLapNumber, startTime: .now)
        newLap.workout = workout
        modelContext.insert(newLap)

        resetLapAccumulators()
        lapStartDistance = activeDistance

        // Haptic confirmation for lap
        HapticManager.shared.lapCompleted()
    }

    func endWorkout() {
        stopTimer()
        autoPauseSuppressedUntilElapsed = nil
        flushPendingSamples()
        do { try modelContext.save() } catch {
            workoutLogger.error("endWorkout pre-summary save failed: \(error)")
        }
        finishCurrentLap()
        calculateSummary()
        detectNewFTP()

        state = .finished
        workout?.status = .completed
        workout?.endDate = Date()

        // Release trainer control on workout end
        releaseTrainerControl()

        do {
            try modelContext.save()
            MangoxModelNotifications.postWorkoutAggregatesMayHaveChanged()
        } catch {
            workoutLogger.error("endWorkout final save failed: \(error)")
        }

        Task { await RideLiveActivityManager.shared.endLiveActivity() }
    }

    private func detectNewFTP() {
        let currentFTP = PowerZone.ftp
        var suggestedFTP: Int?

        // 20-minute peak is the standard measure (95% rule)
        if let peak20m = peakBests[1200], peak20m.watts > 0 {
            let est = Int((Double(peak20m.watts) * 0.95).rounded())
            if est > currentFTP { suggestedFTP = est }
        }
        // 5-minute peak fallback (~85% rule)
        else if let peak5m = peakBests[300], peak5m.watts > 0 {
            let est = Int((Double(peak5m.watts) * 0.85).rounded())
            if est > currentFTP { suggestedFTP = est }
        }

        if let newFTP = suggestedFTP, newFTP > currentFTP {
            workoutLogger.info("Detected new FTP: \(newFTP)W (was \(currentFTP)W)")
            PowerZone.setFTP(newFTP)
        }
    }

    /// Stops the workout without saving — deletes the workout and all related
    /// data from SwiftData, resets manager state back to idle.
    func discardWorkout() {
        stopTimer()
        pendingSamples.removeAll(keepingCapacity: false)
        releaseTrainerControl()

        // Delete the workout (cascade rule removes samples & laps automatically).
        if let workout {
            modelContext.delete(workout)
            do {
                try modelContext.save()
                MangoxModelNotifications.postWorkoutAggregatesMayHaveChanged()
            } catch {
                workoutLogger.error("discardWorkout save failed: \(error)")
            }
        }

        workout = nil
        state = .idle

        resetAccumulators()
        resetLapAccumulators()

        Task { await RideLiveActivityManager.shared.endLiveActivity() }
    }

    // MARK: - Event-Driven BLE Ingestion

    /// Called by BLEManager subscriber every time a new BLE packet arrives (~4 Hz for FTMS).
    /// Accumulates readings; the 1-second timer tick will snapshot them into a sample.
    func ingest(_ metrics: CyclingMetrics) {
        guard state == .recording || state == .autoPaused else { return }

        lastIngestedMetrics = metrics

        powerAccumulator.append(metrics.power)
        cadenceAccumulator.append(metrics.cadence)
        speedAccumulator.append(metrics.speed)
        if metrics.heartRate > 0 {
            hrAccumulator.append(metrics.heartRate)
        }
        if metrics.includesTotalDistanceInPacket {
            latestDistanceInWindow = metrics.totalDistance
        }

        // Auto-resume from auto-pause when power returns
        // (this is checked here instead of in SwiftUI onChange to avoid unnecessary view diffs)
        if state == .autoPaused, shouldResume(from: metrics) {
            resume(fromUserControls: false)
        }
    }

    // MARK: - Timer (1 Hz — drives elapsed time and snapshots accumulated BLE data)

    private func startTimer() {
        timer?.invalidate()
        // The block-based Timer initialiser takes a `@Sendable` escaping closure
        // which the compiler treats as nonisolated — calling a @MainActor method
        // from it directly is a Swift 6 error. Wrapping in `Task { @MainActor in }`
        // makes the hop explicit and satisfies the compiler without any overhead
        // (the Timer already fires on the main RunLoop, so this is a no-op hop).
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        // Avoid integrating speed across idle time (pause / auto-pause / end).
        lastSampleDate = nil
    }

    private func tick() {
        guard state == .recording else { return }
        processSecondSample()
    }

    /// Averages all high-rate trainer power samples from the past second into one 1 Hz value,
    /// feeds ring buffers, records to SwiftData, and updates UI-facing state.
    private var lastSampleDate: Date?

    private func processSecondSample(now: Date = Date()) {
        let previousElapsed = elapsedSeconds
        let elapsedDelta = refreshElapsedFromWallClock(now: now)
        guard elapsedDelta > 0 else { return }
        let rawDt = lastSampleDate.map { max(0, now.timeIntervalSince($0)) } ?? 1.0
        let dt = min(rawDt, Self.distanceIntegrationMaxDt)
        lastSampleDate = now

        // Detect BLE dropout: if no packets arrived for > 5 seconds, it's a dropout.
        // During short gaps (< 5s), carry over the last power.
        let timeSinceLastPacket: TimeInterval
        if let lastPacket = bleService?.lastPacketReceived {
            timeSinceLastPacket = Date().timeIntervalSince(lastPacket)
        } else {
            timeSinceLastPacket = .infinity
        }
        let isDropout = timeSinceLastPacket > 5.0
        let isShortGap = timeSinceLastPacket > 1.0 && timeSinceLastPacket <= 5.0

        // Average the accumulated BLE readings for this 1-second window.
        let avgPower: Int
        let maxPowerThisSecond: Int
        if powerAccumulator.isEmpty {
            avgPower = isShortGap ? lastNonZeroPower : 0
            maxPowerThisSecond = isShortGap ? lastNonZeroPower : 0
        } else {
            avgPower = TrainerPowerMetrics.meanInt(samples: powerAccumulator)
            maxPowerThisSecond = TrainerPowerMetrics.peakInt(samples: powerAccumulator)
            lastNonZeroPower = avgPower
        }

        let avgCadence: Double
        let validCadence = cadenceAccumulator.filter { $0 > 0 }
        if validCadence.isEmpty {
            avgCadence = 0
        } else {
            avgCadence = validCadence.reduce(0.0, +) / Double(validCadence.count)
        }

        let avgSpeed: Double
        if speedAccumulator.isEmpty {
            avgSpeed = 0
        } else {
            var sum = 0.0
            for v in speedAccumulator { sum += v }
            avgSpeed = sum / Double(speedAccumulator.count)
        }

        // When using computed speed source in free ride, derive speed from power
        let effectiveSpeed: Double
        if RidePreferences.shared.indoorSpeedSource == .computed,
            trainerMode == .none,
            avgPower > 0
        {
            effectiveSpeed = PowerToSpeed.speedKmh(
                fromPower: Double(avgPower),
                totalMassKg: RidePreferences.shared.totalMassKg,
                gradePercent: currentGrade,
                cda: RidePreferences.shared.riderCda
            )
        } else {
            effectiveSpeed = avgSpeed
        }

        let avgHR: Int
        let validHR = hrAccumulator.filter { $0 > 0 }
        if validHR.isEmpty {
            // Prefer unified coordinator snapshot (WiFi sessions), then BLE.
            avgHR = lastIngestedMetrics?.heartRate ?? bleService?.metrics.heartRate ?? 0
        } else {
            avgHR = validHR.reduce(0, +) / validHR.count
        }

        // Use latest FTMS distance if reported this window
        if let dist = latestDistanceInWindow {
            lastRecordedDistance = max(lastRecordedDistance, dist)
        }

        // Clear accumulators for next second
        powerAccumulator.removeAll(keepingCapacity: true)
        cadenceAccumulator.removeAll(keepingCapacity: true)
        speedAccumulator.removeAll(keepingCapacity: true)
        hrAccumulator.removeAll(keepingCapacity: true)
        latestDistanceInWindow = nil

        // Distance: integrate speed as fallback when FTMS omits total distance
        let integratedDistanceIncrement = (max(0, effectiveSpeed) / 3.6) * dt  // km/h → m/s
        integratedDistance += integratedDistanceIncrement
        let sensorDistance = max(0, lastRecordedDistance - workoutStartDistance)
        if sensorDistance > integratedDistanceAnchor {
            integratedDistanceAnchor = sensorDistance
            integratedDistance = 0
        }
        activeDistance = max(sensorDistance, integratedDistanceAnchor + integratedDistance)

        // --- Route simulation: update grade from GPX every N seconds ---
        // Skip until trainerEngageDelay has passed so the trainer doesn't
        // immediately lock resistance before the rider is ready.
        if elapsedSeconds >= trainerEngageDelay,
            elapsedSeconds % gradeUpdateInterval == 0
        {
            updateRouteGrade()
        }

        // Feed ring buffers for every elapsed second that passed while timer delivery was delayed.
        for secondOffset in 1...elapsedDelta {
            ring3s.append(avgPower)
            ring5s.append(avgPower)
            ring30s.append(avgPower)
            if ring30s.isFull {
                let a = ring30s.average
                let a2 = a * a
                rollingPower4thSum += a2 * a2
                rollingPower4thCount += 1
            }

            // Peak power curve: use peak sample within each second so short spikes count toward best 5s/15s/…
            // Skip BLE dropout zeros — they would artificially deflate best-effort averages.
            if !isDropout || maxPowerThisSecond > 0 {
                for (window, var buffer) in peakBuffers {
                    buffer.append(maxPowerThisSecond)
                    peakBuffers[window] = buffer
                    if buffer.isFull {
                        let avg = Int(buffer.average.rounded())
                        let current = peakBests[window]
                        if current == nil || avg > current!.watts {
                            let sampleElapsed = previousElapsed + secondOffset
                            peakBests[window] = (watts: avg, atElapsed: sampleElapsed)
                        }
                    }
                }
            }
        }
        avg3s = ring3s.average
        avg5s = ring5s.average
        avg30s = ring30s.average

        // Hero readout + zones: user-chosen 1 s mean vs 3 s rolling mean of those seconds (recording stays 1 s mean).
        switch RidePreferences.shared.indoorPowerHeroMode {
        case .oneSecond:
            displayPower = avgPower
        case .threeSecond:
            displayPower = Int(avg3s.rounded())
        }

        // ERG Visual Smoothing: If in ERG mode and actual power is close to target (±5%), lock display to target.
        if case .erg = trainerMode, let target = ergTarget {
            let threshold = max(5.0, Double(target) * 0.05)  // at least 5W or 5%
            if abs(Double(displayPower) - Double(target)) <= threshold {
                displayPower = target
            }
        }

        // Rebuild peakPowers array from current bests
        peakPowers = Self.peakWindows.compactMap { window in
            guard let best = peakBests[window] else { return nil }
            return PeakPowerEntry(
                windowSeconds: window, watts: best.watts, atElapsed: best.atElapsed)
        }

        // --- Live performance metrics ---
        totalPowerSum += Double(avgPower) * Double(elapsedDelta)
        totalPowerSampleCount += elapsedDelta
        totalEnergyJoules += Double(avgPower) * Double(elapsedDelta)  // 1 watt × 1 second = 1 joule

        // Average power
        averagePower = totalPowerSum / Double(totalPowerSampleCount)

        // Kilojoules
        kilojoules = totalEnergyJoules / 1000.0

        // Live NP, IF, TSS
        let ftp = Double(PowerZone.ftp)
        if rollingPower4thCount > 0 {
            liveNP = sqrt(sqrt(rollingPower4thSum / Double(rollingPower4thCount)))

            if ftp > 0 {
                liveIF = liveNP / ftp
                liveTSS = (Double(elapsedSeconds) * liveNP * liveIF) / (ftp * 3600) * 100
            }

            // Variability Index: NP / avg (1.0 = perfectly even pacing)
            if averagePower > 0 {
                variabilityIndex = liveNP / averagePower
            }
        }

        // Efficiency Factor: watts per heartbeat (aerobic decoupling indicator)
        if avgHR > 0, averagePower > 0 {
            efficiencyFactor = averagePower / Double(avgHR)
        }

        // Queue one sample per elapsed second — maintains timeline continuity after background stalls.
        for secondOffset in 1...elapsedDelta {
            let sampleElapsed = previousElapsed + secondOffset
            pendingSamples.append(
                PendingWorkoutSample(
                    elapsedSeconds: sampleElapsed,
                    power: avgPower,
                    cadence: avgCadence,
                    speed: effectiveSpeed,
                    heartRate: avgHR
                )
            )
            if pendingSamples.count >= sampleBatchSize {
                flushPendingSamples()
            }
            if sampleElapsed % 30 == 0 {
                flushPendingSamples()
                do { try modelContext.save() } catch {
                    workoutLogger.error("periodic save failed: \(error)")
                }
            }
        }

        // Power history for chart (keep last 60) — use circular buffer approach for O(1) amortized
        // Instead of removing elements one-by-one (O(n)), we rebuild the array when it grows
        // past 2x capacity to maintain O(1) amortized time.
        for secondOffset in 1...elapsedDelta {
            powerHistory.append(
                PowerSample(elapsed: previousElapsed + secondOffset, power: avgPower)
            )
        }
        if powerHistory.count > 120 {
            // Batch compaction: O(n) but only every 60 insertions → amortized O(1)
            powerHistory.removeFirst(powerHistory.count - 60)
        }
        // Update running chart max — no need to scan the array in the view
        let chartPeak = max(avgPower, maxPowerThisSecond)
        if chartPeak > powerHistoryMax {
            powerHistoryMax = chartPeak
        } else if powerHistory.count == 60 || chartPeak < powerHistoryMax {
            // Only rescan when at capacity or old max may have been evicted
            // Use max(by:) to avoid allocating an intermediate [Int] array
            powerHistoryMax = max(powerHistory.max(by: { $0.power < $1.power })?.power ?? 100, 100)
        }

        // Lap accumulation
        lapPowerSum += Double(avgPower) * Double(elapsedDelta)
        lapSampleCount += elapsedDelta
        lapMaxPower = max(lapMaxPower, maxPowerThisSecond)
        lapCadenceSum += avgCadence * Double(elapsedDelta)
        lapSpeedSum += effectiveSpeed * Double(elapsedDelta)
        lapHRSum += Double(avgHR) * Double(elapsedDelta)
        lapElapsedSeconds += elapsedDelta
        currentLapDuration = TimeInterval(lapElapsedSeconds)
        currentLapAvgPower = lapSampleCount > 0 ? lapPowerSum / Double(lapSampleCount) : 0

        // Auto-pause: trigger after N consecutive seconds of zero averaged power AND zero speed
        let autoPauseAllowed = autoPauseSuppressedUntilElapsed.map { elapsedSeconds >= $0 } ?? true
        if autoPauseAllowed, avgPower == 0 && effectiveSpeed < 1.0 {
            zeroPowerSeconds += elapsedDelta
            if zeroPowerSeconds >= autoPauseThreshold {
                flushPendingSamples()
                do { try modelContext.save() } catch {
                    workoutLogger.error("auto-pause save failed: \(error)")
                }
                state = .autoPaused
                stopTimer()
                workout?.status = .paused
                markPauseStartedIfNeeded()
                return
            }
        } else {
            zeroPowerSeconds = 0
        }

        // Drive guided session (if active)
        onTick?(elapsedSeconds, displayPower)

        // --- Pre-format display strings once per second (match 1 Hz sampled averages, not raw ~4 Hz BLE) ---
        metricsSpeed = effectiveSpeed
        formattedSpeed = String(format: "%.1f", effectiveSpeed)
        formattedCadence = "\(Int(avgCadence.rounded()))"
        displayCadenceRpm = avgCadence
        formattedDistanceKm = String(format: "%.2f", activeDistance / 1000)
        formattedDistanceKm1dp = String(format: "%.1f", activeDistance / 1000)
        formattedEnergyKJ = String(format: "%.0f", kilojoules)
        formattedLiveNP = String(format: "%.0f", liveNP)
        formattedLiveIF = String(format: "%.2f", liveIF)
        formattedLiveTSS = String(format: "%.0f", liveTSS)
        formattedVI = String(format: "%.2f", variabilityIndex)
        formattedAvgPower = String(format: "%.0f", averagePower)
        formattedEfficiency = String(format: "%.2f", efficiencyFactor)
        formattedKJ = String(format: "%.0f", kilojoules)

        // --- Ride Goals ---
        updateGoalProgress(avgCadence: avgCadence)

        // --- Cadence Warning ---
        updateCadenceWarning(avgCadence: avgCadence)
    }

    // MARK: - Goal & Warning Helpers

    private func updateGoalProgress(avgCadence: Double) {
        let prefs = RidePreferences.shared
        guard !prefs.activeGoals.isEmpty else {
            goalProgress = [:]
            justCompletedGoals = []
            return
        }

        let elapsedMinutes = Double(elapsedSeconds) / 60.0
        let distanceKm = activeDistance / 1000.0

        var newProgress: [String: Double] = [:]
        var completed: [RideGoal] = []

        for goal in prefs.activeGoals {
            let progress = goal.progress(
                distance: distanceKm,
                elapsedMinutes: elapsedMinutes,
                kj: kilojoules,
                tss: liveTSS
            )
            newProgress[goal.kind.rawValue] = progress

            // Edge detection: did we just cross the finish line this tick?
            let fired = goal.justCompleted(
                current: distanceKm, elapsedMinutes: elapsedMinutes,
                kj: kilojoules, tss: liveTSS,
                previous: prevGoalDistance, prevMinutes: prevGoalMinutes,
                prevKj: prevGoalKJ, prevTss: prevGoalTSS
            )
            if fired {
                completed.append(goal)
            }
        }

        goalProgress = newProgress
        justCompletedGoals = completed

        // Advance prev-tick snapshot
        prevGoalDistance = activeDistance / 1000.0
        prevGoalMinutes = Double(elapsedSeconds) / 60.0
        prevGoalKJ = kilojoules
        prevGoalTSS = liveTSS
    }

    private func updateCadenceWarning(avgCadence: Double) {
        let prefs = RidePreferences.shared
        guard prefs.lowCadenceWarningEnabled else {
            showLowCadenceWarning = false
            lowCadenceSeconds = 0
            lowCadenceStreakSeconds = 0
            return
        }

        let threshold = Double(prefs.lowCadenceThreshold)

        // Only warn when actively pedalling (power > 0) and cadence is too low
        if avgCadence > 0 && avgCadence < threshold {
            lowCadenceSeconds += 1
        } else {
            lowCadenceSeconds = 0
            showLowCadenceWarning = false
        }

        if lowCadenceSeconds >= 30 {
            showLowCadenceWarning = true
        }
        lowCadenceStreakSeconds = lowCadenceSeconds
    }

    /// Drains `pendingSamples` into SwiftData. Call before summary / pause / end, and on batch boundaries.
    private func flushPendingSamples() {
        let context = modelContext
        guard let w = workout, !pendingSamples.isEmpty else { return }
        let start = w.startDate
        for p in pendingSamples {
            let s = WorkoutSample(
                timestamp: start.addingTimeInterval(TimeInterval(p.elapsedSeconds)),
                elapsedSeconds: p.elapsedSeconds,
                power: p.power,
                cadence: p.cadence,
                speed: p.speed,
                heartRate: p.heartRate
            )
            s.workout = w
            context.insert(s)
        }
        pendingSamples.removeAll(keepingCapacity: true)
    }

    // MARK: - Lap Helpers

    private func finishCurrentLap() {
        guard let workout else { return }
        let laps = workout.laps.sorted { $0.lapNumber < $1.lapNumber }
        guard let currentLap = laps.last else { return }

        currentLap.endTime = .now
        currentLap.duration = TimeInterval(lapElapsedSeconds)
        currentLap.avgPower = lapSampleCount > 0 ? lapPowerSum / Double(lapSampleCount) : 0
        currentLap.maxPower = lapMaxPower
        currentLap.avgCadence = lapSampleCount > 0 ? lapCadenceSum / Double(lapSampleCount) : 0
        currentLap.avgHR = lapSampleCount > 0 ? lapHRSum / Double(lapSampleCount) : 0
        let lapDist = max(0, activeDistance - lapStartDistance)
        currentLap.distance = lapDist
        if currentLap.duration > 0, lapDist > 0 {
            currentLap.avgSpeed = (lapDist / currentLap.duration) * 3.6
        } else {
            currentLap.avgSpeed = 0
        }

        previousLapAvgPower = currentLap.avgPower
        previousLapDuration = currentLap.duration
    }

    private func resetLapAccumulators() {
        lapPowerSum = 0
        lapSampleCount = 0
        lapMaxPower = 0
        lapCadenceSum = 0
        lapSpeedSum = 0
        lapHRSum = 0
        lapElapsedSeconds = 0
        currentLapDuration = 0
        currentLapAvgPower = 0
    }

    private func resetAccumulators() {
        elapsedSeconds = 0
        currentLapNumber = 1
        powerHistory = []

        goalProgress = [:]
        justCompletedGoals = []
        prevGoalDistance = 0
        prevGoalMinutes = 0
        prevGoalKJ = 0
        prevGoalTSS = 0
        lowCadenceSeconds = 0
        showLowCadenceWarning = false
        lowCadenceStreakSeconds = 0
        pendingStepCueLabel = nil
        autoPauseSuppressedUntilElapsed = nil

        ring3s.reset()
        ring5s.reset()
        ring30s.reset()

        rollingPower4thSum = 0
        rollingPower4thCount = 0
        zeroPowerSeconds = 0

        totalPowerSum = 0
        totalPowerSampleCount = 0
        totalEnergyJoules = 0

        avg3s = 0
        avg5s = 0
        avg30s = 0
        displayPower = 0

        liveNP = 0
        liveIF = 0
        liveTSS = 0
        kilojoules = 0
        efficiencyFactor = 0
        variabilityIndex = 0
        averagePower = 0

        previousLapAvgPower = 0
        previousLapDuration = 0
        activeDistance = 0
        integratedDistance = 0
        integratedDistanceAnchor = 0
        workoutStartDistance = 0

        trainerMode = .none
        currentGrade = 0
        currentElevation = nil
        lastSentGrade = nil
        baseErgTarget = nil
        ergTarget = nil

        // Reset pre-formatted strings
        powerHistoryMax = 100
        formattedSpeed = "0.0"
        formattedCadence = "0"
        displayCadenceRpm = 0
        formattedDistanceKm = "0.00"
        formattedDistanceKm1dp = "0.0"
        formattedEnergyKJ = "0"
        formattedLiveNP = "0"
        formattedLiveIF = "0.00"
        formattedLiveTSS = "0"
        formattedVI = "1.00"
        formattedAvgPower = "0"
        formattedEfficiency = "0.00"
        formattedKJ = "0"

        powerAccumulator.removeAll()
        cadenceAccumulator.removeAll()
        speedAccumulator.removeAll()
        hrAccumulator.removeAll()
        latestDistanceInWindow = nil
        lastIngestedMetrics = nil
        pendingSamples.removeAll(keepingCapacity: false)
        lastSampleDate = nil
        recordingStartWallClock = nil
        pausedWallClockDuration = 0
        pauseStartedAtWallClock = nil

        // Peak power curve buffers
        peakBuffers = [:]
        peakBests = [:]
        peakPowers = []
        for window in Self.peakWindows {
            peakBuffers[window] = RingBuffer<Int>(capacity: window)
        }

        resetLapAccumulators()
    }

    private func markPauseStartedIfNeeded(now: Date = Date()) {
        guard pauseStartedAtWallClock == nil else { return }
        pauseStartedAtWallClock = now
    }

    private func consumePausedWallClockDurationIfNeeded(now: Date = Date()) {
        guard let pauseStartedAtWallClock else { return }
        pausedWallClockDuration += max(0, now.timeIntervalSince(pauseStartedAtWallClock))
        self.pauseStartedAtWallClock = nil
    }

    /// Derives active elapsed seconds from wall clock. Timer cadence is only a sampling trigger.
    private func refreshElapsedFromWallClock(now: Date = Date()) -> Int {
        let previous = elapsedSeconds
        guard let recordingStartWallClock else { return 0 }
        let inFlightPause = pauseStartedAtWallClock.map { max(0, now.timeIntervalSince($0)) } ?? 0
        let activeSeconds = max(
            0,
            Int(
                (now.timeIntervalSince(recordingStartWallClock)
                    - pausedWallClockDuration
                    - inFlightPause
                ).rounded(.down)
            )
        )
        elapsedSeconds = max(previous, activeSeconds)
        return elapsedSeconds - previous
    }

    #if DEBUG
    /// Test helper: overrides wall-clock anchors used by elapsed reconciliation.
    func debugConfigureWallClock(
        recordingStart: Date,
        pausedDuration: TimeInterval = 0,
        pauseStart: Date? = nil
    ) {
        recordingStartWallClock = recordingStart
        pausedWallClockDuration = pausedDuration
        pauseStartedAtWallClock = pauseStart
    }

    /// Test helper: runs one sample-processing cycle at a controlled timestamp.
    func debugProcessSecondSample(at now: Date) {
        processSecondSample(now: now)
    }
    #endif

    // MARK: - Summary Calculations

    /// Odometer meters from a metrics snapshot only when the link marked total distance as present.
    private func resolvedTrainerOdometerMeters(from metrics: CyclingMetrics?) -> Double? {
        guard let metrics, metrics.includesTotalDistanceInPacket else { return nil }
        return metrics.totalDistance
    }

    private func calculateSummary() {
        guard let workout else { return }
        let samples = workout.samples
        guard !samples.isEmpty else { return }

        let count = Double(samples.count)
        let ftp = Double(PowerZone.ftp)
        let telemetrySnap =
            resolvedTrainerOdometerMeters(from: lastIngestedMetrics)
            ?? resolvedTrainerOdometerMeters(from: bleService?.metrics)
        let latestDistance = max(lastRecordedDistance, telemetrySnap ?? lastRecordedDistance)
        let sensorDistance = max(0, latestDistance - workoutStartDistance)
        let integratedTotal = integratedDistanceAnchor + integratedDistance
        let workoutDistance = max(sensorDistance, integratedTotal)

        workout.duration = Double(elapsedSeconds)
        workout.distance = workoutDistance
        workout.sampleCount = samples.count
        workout.avgPower = samples.reduce(0.0) { $0 + Double($1.power) } / count
        workout.maxPower = samples.map(\.power).max() ?? 0
        workout.avgCadence = samples.reduce(0.0) { $0 + $1.cadence } / count
        // True average speed (matches Strava / distance÷time), not mean of instantaneous samples.
        if elapsedSeconds > 0, workoutDistance > 0 {
            workout.avgSpeed = (workoutDistance / Double(elapsedSeconds)) * 3.6
        } else {
            workout.avgSpeed = 0
        }

        let hrSamples = samples.filter { $0.heartRate > 0 }
        if !hrSamples.isEmpty {
            workout.avgHR =
                hrSamples.reduce(0.0) { $0 + Double($1.heartRate) } / Double(hrSamples.count)
            workout.maxHR = hrSamples.map(\.heartRate).max() ?? 0
        }

        // Normalized Power: 4th root of mean of 4th powers of 30s rolling averages.
        if rollingPower4thCount > 0, ftp > 0 {
            let np = sqrt(sqrt(rollingPower4thSum / Double(rollingPower4thCount)))
            let intensityFactor = np / ftp
            let tss = (Double(elapsedSeconds) * np * intensityFactor) / (ftp * 3600) * 100

            workout.normalizedPower = np
            workout.intensityFactor = intensityFactor
            workout.tss = tss
        }

        // Elevation gain — only available when a GPX route with <ele> data was loaded.
        // Computed over the portion of the route actually ridden (workoutStartDistance → final distance).
        if let routeSnapshot {
            workout.savedRouteName = routeSnapshot.routeName
            workout.plannedRouteDistanceMeters = routeSnapshot.plannedDistanceMeters
            workout.elevationGain = computeElevationGain(
                routeSnapshot: routeSnapshot,
                startDistance: workoutStartDistance,
                endDistance: workoutStartDistance + workoutDistance
            )
        }
    }

    /// Computes positive elevation gain over a distance range by sampling the GPX elevation
    /// profile at 1-metre intervals (capped at 2000 samples for performance).
    private func computeElevationGain(
        routeSnapshot: IndoorRouteSnapshot,
        startDistance: Double,
        endDistance: Double
    ) -> Double {
        let rideLength = max(0, endDistance - startDistance)
        guard rideLength > 0, routeSnapshot.hasElevationData else { return 0 }

        // Sample at ~10 m intervals, minimum 2, maximum 2000 samples.
        let sampleCount = min(2000, max(2, Int(rideLength / 10)))
        let step = rideLength / Double(sampleCount)

        var gain: Double = 0
        var prevElevation: Double? = nil

        for i in 0...sampleCount {
            let dist = startDistance + Double(i) * step
            guard let elev = elevation(at: dist, in: routeSnapshot) else { continue }
            if let prev = prevElevation, elev > prev {
                gain += elev - prev
            }
            prevElevation = elev
        }

        return gain
    }

    var formattedElapsed: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func shouldResume(from metrics: CyclingMetrics) -> Bool {
        metrics.power > 0 || metrics.cadence > 0 || metrics.speed > 0
    }

    private static func makeRouteSnapshot(from routeService: (any RouteServiceProtocol)?)
        -> IndoorRouteSnapshot?
    {
        guard let routeService, routeService.hasRoute else { return nil }
        return IndoorRouteSnapshot(
            routeName: routeService.routeName,
            plannedDistanceMeters: routeService.totalDistance,
            elevationProfilePoints: routeService.elevationProfilePoints
        )
    }

    private func elevation(at distance: Double, in routeSnapshot: IndoorRouteSnapshot) -> Double? {
        let profile = routeSnapshot.elevationProfilePoints
        guard !profile.isEmpty else { return nil }

        if distance <= profile[0].distance {
            return profile[0].elevation
        }

        if let last = profile.last, distance >= last.distance {
            return last.elevation
        }

        for index in 1..<profile.count {
            let previous = profile[index - 1]
            let current = profile[index]
            guard distance <= current.distance else { continue }

            let segmentDistance = current.distance - previous.distance
            guard segmentDistance > 0 else { return current.elevation }
            let ratio = (distance - previous.distance) / segmentDistance
            return previous.elevation + ((current.elevation - previous.elevation) * ratio)
        }

        return profile.last?.elevation
    }

    // MARK: - Route Simulation (Private)

    /// Compute the current grade from GPX elevation data at the current distance
    /// and send it to the trainer if it has changed meaningfully.
    private func updateRouteGrade() {
        guard let routeService, routeService.hasRoute else { return }
        guard let bleService, bleService.ftmsControlSupportsSimulation else { return }
        // Only update if we're in simulation mode or haven't started yet
        guard ergTarget == nil else { return }

        let distance = activeDistance

        // Look up elevation at current position and a point slightly ahead.
        // Time-based preview: at 30 km/h (~8 m/s), 3s preview = 24m; at 10 km/h (~3 m/s), 3s preview = 9m.
        // This maintains consistent grade-change responsiveness regardless of speed.
        let speedKmh = lastIngestedMetrics?.speed ?? bleService.metrics.speed
        let speedMPS = max(0, speedKmh) / 3.6
        let previewSeconds: Double = 3
        let lookAheadMeters = max(5, speedMPS * previewSeconds)
        guard let elevHere = routeService.elevation(forDistance: distance) else { return }
        currentElevation = elevHere

        let elevAhead = routeService.elevation(forDistance: distance + lookAheadMeters)
        let grade: Double
        if let elevAhead {
            // Grade = (rise / run) × 100
            grade = ((elevAhead - elevHere) / lookAheadMeters) * 100
        } else {
            // Past end of route — flatten out
            grade = 0
        }

        // Clamp to FTMS range
        let clampedGrade = max(-40.0, min(grade * routeDifficultyScale, 40.0))
        currentGrade = clampedGrade

        // Only send if grade changed by more than 0.5% to avoid BLE spam on flat roads.
        // Sub-0.5% changes are imperceptible to the rider and generate unnecessary writes.
        if let lastSent = lastSentGrade, abs(clampedGrade - lastSent) < 0.5 {
            return
        }

        lastSentGrade = clampedGrade

        Task { @MainActor in
            do {
                try await bleService.setSimulationGrade(clampedGrade)
                self.trainerMode = bleService.ftmsControlActiveMode
            } catch {
                workoutLogger.error("Grade update failed: \(error.localizedDescription)")
            }
        }
    }
}
