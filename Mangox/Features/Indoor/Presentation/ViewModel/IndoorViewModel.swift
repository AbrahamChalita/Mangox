// Features/Indoor/Presentation/ViewModel/IndoorViewModel.swift
import Foundation
import SwiftData

enum IndoorMilestoneTrigger: Equatable {
    case distanceInterval(km: Int)
    case distanceGoalProgress(percent: Int, currentKm: Double, targetKm: Double)
    case distanceGoalCompleted(targetKm: Double)
}

struct IndoorWorkoutCompletionPlan {
    let shouldMarkPlanDayCompleted: Bool
    let resolvedPlanID: String?
    let summaryRoute: AppRoute?
}

enum IndoorNavigationAction {
    case pop
    case resetRoot
    case route(AppRoute)
}

@MainActor
@Observable
final class IndoorViewModel {

    // MARK: - Service Dependencies

    let bleService: BLEServiceProtocol
    let dataSourceService: DataSourceServiceProtocol
    let routeService: RouteServiceProtocol
    let healthKitService: HealthKitServiceProtocol
    let liveActivityService: LiveActivityServiceProtocol
    private let workoutPersistenceRepository: WorkoutPersistenceRepositoryProtocol
    private let trainingPlanPersistenceRepository: TrainingPlanPersistenceRepositoryProtocol
    let workoutManager = WorkoutManager()
    let guidedSession = GuidedSessionManager()

    // MARK: - View state (sourced from DataSourceCoordinator / BLEManager via DIContainer)
    var currentMetrics: CyclingMetrics = CyclingMetrics()
    var isConnected: Bool = false
    var connectionError: String? = nil
    var elapsedSeconds: Int = 0
    var isRecording: Bool = false
    var activeRideTip: RideNudgeDisplay?
    var milestoneText: String?
    var isMilestoneVisible = false
    var pendingRideBriefing: String?
    var showEndConfirmation = false
    var showRideTipsOnboardingPrompt = false

    // MARK: - Computed Display Properties (for DashboardView)

    /// Unified metrics from DataSourceService (HR attribution included — avoids reading `BLEManager.metrics` for SwiftUI).
    var metrics: CyclingMetrics {
        var m = CyclingMetrics(lastUpdate: Date())
        m.power = dataSourceService.power
        m.cadence = dataSourceService.cadence
        m.speed = dataSourceService.speed
        m.heartRate = dataSourceService.heartRate
        m.totalDistance = dataSourceService.totalDistance
        m.includesTotalDistanceInPacket = dataSourceService.activeTotalDistanceFieldPresent
        m.hrSource = dataSourceService.hrSource
        return m
    }

    /// Live strap HR for the indoor dashboard (same transport as `metrics`, without aggregating `CyclingMetrics` in parents).
    var liveHeartRateBpm: Int { dataSourceService.heartRate }

    // DataSource metrics
    var power: Int { dataSourceService.power }
    var cadence: Double { dataSourceService.cadence }
    var speed: Double { dataSourceService.speed }
    var heartRate: Int { dataSourceService.heartRate }
    var totalDistance: Double { dataSourceService.totalDistance }

    // Trainer link display
    var trainerLinkDisplayState: BLEConnectionState { dataSourceService.trainerLinkDisplayState }
    var isTrainerLinkDataStale: Bool { dataSourceService.isTrainerLinkDataStale }

    // BLE
    var hrSource: HRSource { dataSourceService.hrSource }
    var hrConnectionState: BLEConnectionState { bleService.hrConnectionState }
    var ftmsControlIsAvailable: Bool { bleService.ftmsControlIsAvailable }
    var ftmsControlSupportsERG: Bool { bleService.ftmsControlSupportsERG }
    var ftmsControlSupportsSimulation: Bool { bleService.ftmsControlSupportsSimulation }
    var ftmsControlSupportsResistance: Bool { bleService.ftmsControlSupportsResistance }
    var ftmsControlActiveMode: TrainerControlMode { bleService.ftmsControlActiveMode }

    // Route
    var hasRoute: Bool { routeService.hasRoute }
    var routeName: String? { routeService.routeName }

    // MARK: - Init

    init(
        bleService: BLEServiceProtocol,
        dataSourceService: DataSourceServiceProtocol,
        routeService: RouteServiceProtocol,
        healthKitService: HealthKitServiceProtocol,
        liveActivityService: LiveActivityServiceProtocol,
        workoutPersistenceRepository: WorkoutPersistenceRepositoryProtocol,
        trainingPlanPersistenceRepository: TrainingPlanPersistenceRepositoryProtocol
    ) {
        self.bleService = bleService
        self.dataSourceService = dataSourceService
        self.routeService = routeService
        self.healthKitService = healthKitService
        self.liveActivityService = liveActivityService
        self.workoutPersistenceRepository = workoutPersistenceRepository
        self.trainingPlanPersistenceRepository = trainingPlanPersistenceRepository
    }

    private var lastMilestoneKm = 0
    private var crossedDistanceGoalPercents: Set<Int> = []
    private var lastDelightOverlayAt: Date?
    private var rideNudgeSession = RideNudgeSessionState()
    private var lastPersistenceError: String?
    private var liveActivitySyncTask: Task<Void, Never>?

    // MARK: - Trainer metrics helpers
    func meanPower(samples: [Int]) -> Int {
        TrainerPowerMetrics.meanInt(samples: samples)
    }

    func peakPower(samples: [Int]) -> Int {
        TrainerPowerMetrics.peakInt(samples: samples)
    }

    // MARK: - Ride feedback state

    func setPendingRideBriefing(_ text: String) {
        pendingRideBriefing = text
    }

    func consumePendingRideBriefing() -> String? {
        defer { pendingRideBriefing = nil }
        return pendingRideBriefing
    }

    func resetRideFeedbackState() {
        lastMilestoneKm = 0
        crossedDistanceGoalPercents = []
        rideNudgeSession.reset()
        activeRideTip = nil
        milestoneText = nil
        isMilestoneVisible = false
        lastDelightOverlayAt = nil
    }

    func showMilestone(_ text: String) {
        lastDelightOverlayAt = Date()
        milestoneText = text
        isMilestoneVisible = true
    }

    func hideMilestone() {
        isMilestoneVisible = false
    }

    func presentRideTip(_ tip: RideNudgeDisplay) {
        activeRideTip = tip
    }

    func clearRideTip(ifMatching tipID: String? = nil) {
        guard let tipID else {
            activeRideTip = nil
            return
        }
        if activeRideTip?.id == tipID {
            activeRideTip = nil
        }
    }

    func consumePersistenceError() -> String? {
        defer { lastPersistenceError = nil }
        return lastPersistenceError
    }

    func clearPersistenceError() {
        lastPersistenceError = nil
    }

    func nextRideTip(
        now: Date = Date(),
        rideTipsEnabled: Bool,
        isRecording: Bool,
        elapsedSeconds: Int,
        activeDistanceMeters: Double,
        activeDistanceGoalKm: Double?,
        displayPower: Int,
        displayCadenceRpm: Double,
        zoneId: Int,
        lowCadenceThreshold: Int,
        lowCadenceStreakSeconds: Int,
        showLowCadenceHardWarning: Bool,
        guidedIsActive: Bool,
        guidedStepIsRecovery: Bool,
        guidedSecondsIntoStep: Int?,
        guidedStepIsHardIntensity: Bool,
        prefs: RidePreferences,
        guidedStepIndex: Int
    ) -> RideNudgeDisplay? {
        guard rideTipsEnabled else { return nil }
        guard isRecording else { return nil }
        if let t = lastDelightOverlayAt, now.timeIntervalSince(t) < 5.5 { return nil }

        let context = RideNudgeContext(
            now: now,
            isRecording: isRecording,
            elapsedSeconds: elapsedSeconds,
            displayPower: displayPower,
            displayCadenceRpm: displayCadenceRpm,
            zoneId: zoneId,
            lowCadenceThreshold: lowCadenceThreshold,
            lowCadenceStreakSeconds: lowCadenceStreakSeconds,
            showLowCadenceHardWarning: showLowCadenceHardWarning,
            activeDistanceMeters: activeDistanceMeters,
            distanceGoalKm: activeDistanceGoalKm,
            distanceGoalProgress: {
                guard let goalKm = activeDistanceGoalKm, goalKm > 0 else { return nil }
                let progress = activeDistanceMeters / (goalKm * 1000.0)
                return min(max(progress, 0), 1)
            }(),
            guidedIsActive: guidedIsActive,
            guidedStepIsRecovery: guidedStepIsRecovery,
            guidedSecondsIntoStep: guidedSecondsIntoStep,
            guidedStepIsHardIntensity: guidedStepIsHardIntensity,
            suppressUntil: nil
        )

        return RideNudgeEngine.nextTip(
            context: context,
            prefs: prefs,
            guidedStepIndex: guidedStepIndex,
            session: &rideNudgeSession
        )
    }

    func milestoneTriggers(
        distanceMeters: Double,
        isRecording: Bool,
        activeDistanceGoalKm: Double?
    ) -> [IndoorMilestoneTrigger] {
        guard isRecording else { return [] }
        let km = distanceMeters / 1000.0

        if let target = activeDistanceGoalKm, target > 0 {
            let progress = km / target
            let thresholds = [25, 50, 75]
            let newly = thresholds.filter {
                progress >= Double($0) / 100.0 && !crossedDistanceGoalPercents.contains($0)
            }
            guard !newly.isEmpty else { return [] }
            for percent in newly {
                crossedDistanceGoalPercents.insert(percent)
            }
            return newly.sorted().map {
                .distanceGoalProgress(percent: $0, currentKm: km, targetKm: target)
            }
        }

        let step = 5
        let kmInt = Int(distanceMeters / 1000)
        let milestone = (kmInt / step) * step
        guard milestone >= step && milestone > lastMilestoneKm else { return [] }
        lastMilestoneKm = milestone
        return [.distanceInterval(km: milestone)]
    }

    func distanceGoalCompletedTrigger(targetKm: Double) -> IndoorMilestoneTrigger {
        .distanceGoalCompleted(targetKm: targetKm)
    }

    func presentEndConfirmation() {
        showEndConfirmation = true
    }

    func dismissEndConfirmation() {
        showEndConfirmation = false
    }

    func evaluateRideTipsOnboardingPrompt(prefs: RidePreferences, isInPreRide: Bool) {
        guard isInPreRide else {
            showRideTipsOnboardingPrompt = false
            return
        }
        if prefs.shouldShowRideTipsOnboardingPrompt {
            showRideTipsOnboardingPrompt = true
        }
    }

    func applyRideTipsOnboardingEnable(prefs: RidePreferences) {
        prefs.applyRideTipsEssentialsPreset()
        prefs.rideTipsPromptSeen = true
        showRideTipsOnboardingPrompt = false
    }

    func applyRideTipsOnboardingDecline(prefs: RidePreferences) {
        prefs.rideTipsEnabled = false
        prefs.rideTipsPromptSeen = true
        showRideTipsOnboardingPrompt = false
    }

    func configureGuidedSession(
        loadedCustomPlanDay: PlanDay?,
        planDayID: String?,
        customWorkoutTemplateID: UUID?,
        planID: String?,
        allProgress: [TrainingPlanProgress],
        plan: TrainingPlan?
    ) {
        configureWorkoutCallbacks()

        let day: PlanDay?
        if let loadedCustomPlanDay {
            day = loadedCustomPlanDay
        } else if let planDayID, let plan {
            day = plan.day(id: planDayID)
        } else {
            day = nil
        }
        guard let day else {
            guidedSession.tearDown()
            guidedSession.onTrainerModeChange = nil
            return
        }

        let adaptiveScale: Double
        if customWorkoutTemplateID != nil {
            adaptiveScale = 1.0
        } else {
            adaptiveScale =
                planID.flatMap { id in
                    allProgress.first(where: { $0.planID == id })?.adaptiveLoadMultiplier
                } ?? 1.0
        }

        guidedSession.configure(planDay: day, adaptiveERGScale: adaptiveScale)

        let capturedTimeline = guidedSession.timeline
        let capturedTitle = guidedSession.dayTitle
        let capturedNotes = guidedSession.dayNotes
        let capturedFTP = PowerZone.ftp
        Task { @MainActor in
            guard
                let text = await OnDeviceCoachEngine.generateRideBriefing(
                    dayTitle: capturedTitle,
                    dayNotes: capturedNotes,
                    timeline: capturedTimeline,
                    ftpWatts: capturedFTP
                )
            else { return }
            self.pendingRideBriefing = text
        }

        let guidedSession = self.guidedSession
        let workoutManager = self.workoutManager

        guidedSession.onTrainerModeChange = { [weak workoutManager] mode, ergWatts, grade in
            guard let workoutManager else { return }
            guard workoutManager.elapsedSeconds >= workoutManager.trainerEngageDelay else { return }

            switch mode {
            case .erg:
                if let ergWatts {
                    workoutManager.setERGMode(watts: ergWatts)
                }
            case .simulation:
                if let grade {
                    workoutManager.setSimulationMode(grade: grade)
                }
            case .freeRide:
                if workoutManager.bleService?.ftmsControlSupportsResistance == true {
                    workoutManager.setResistanceMode(level: 0)
                } else {
                    workoutManager.releaseTrainerControl()
                }
            }
        }
    }

    func syncLiveActivity(isRecording: Bool, prefs: RidePreferences) async {
        await liveActivityService.syncIndoorRecording(
            isRecording: isRecording,
            prefs: prefs,
            workoutManager: workoutManager,
            dataSourceService: dataSourceService,
            bleService: bleService
        )
    }

    func prepareWorkoutSession(
        customWorkoutTemplateID: UUID?,
        planDayID: String?,
        planID: String?
    ) -> PlanDay? {
        if let customWorkoutTemplateID {
            workoutManager.activePlanDayID = nil
            workoutManager.activePlanID = nil
            do {
                return try workoutPersistenceRepository.fetchCustomWorkoutTemplate(
                    id: customWorkoutTemplateID)
            } catch {
                lastPersistenceError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return nil
            }
        }

        workoutManager.activePlanDayID = planDayID
        workoutManager.activePlanID = planID
        return nil
    }

    func bootstrapDashboard(
        customWorkoutTemplateID: UUID?,
        planDayID: String?,
        planID: String?,
        allProgress: [TrainingPlanProgress],
        plan: TrainingPlan?
    ) {
        dataSourceService.updateActiveSource()
        workoutManager.configure(
            bleService: bleService,
            dataSource: dataSourceService
        )
        workoutManager.configureRoute(routeService)
        configureWorkoutCallbacks()

        // Returning from Live Activity / Dynamic Island can push a fresh `DashboardView` (often without
        // plan/template IDs). Re-running session prep would clear plan metadata and disturb guided mode.
        if workoutManager.state.isLiveSessionActive {
            scheduleIndoorLiveActivitySync(isRecording: workoutManager.state == .recording)
            return
        }

        let loadedCustomPlanDay = prepareWorkoutSession(
            customWorkoutTemplateID: customWorkoutTemplateID,
            planDayID: planDayID,
            planID: planID
        )

        configureGuidedSession(
            loadedCustomPlanDay: loadedCustomPlanDay,
            planDayID: planDayID,
            customWorkoutTemplateID: customWorkoutTemplateID,
            planID: planID,
            allProgress: allProgress,
            plan: plan
        )

        if workoutManager.state == .idle {
            workoutManager.startWorkout()
        }
        scheduleIndoorLiveActivitySync(isRecording: workoutManager.state == .recording)
    }

    func handleWorkoutStateChange(oldState: RecordingState, newState: RecordingState) -> String? {
        switch (oldState, newState) {
        case (.idle, .recording):
            resetRideFeedbackState()
            HapticManager.shared.workoutStarted()
            guard guidedSession.isActive else { return nil }
            return consumePendingRideBriefing()
        case (.recording, .autoPaused):
            HapticManager.shared.autoPaused()
        case (.autoPaused, .recording):
            HapticManager.shared.autoResumed()
        case (_, .finished):
            HapticManager.shared.workoutEnded()
        default:
            break
        }

        return nil
    }

    func shouldAutoResumeWorkout(displayPower: Int, state: RecordingState) -> Bool {
        state == .autoPaused && displayPower > 0
    }

    func tearDownWorkoutSession() {
        liveActivitySyncTask?.cancel()
        liveActivitySyncTask = nil
        workoutManager.tearDown()
    }

    func startWorkout() {
        workoutManager.startWorkout()
    }

    func pauseWorkout() {
        workoutManager.pause()
    }

    /// - Parameter fromUserControls: Pass `false` for power-driven auto-resume paths so auto-pause
    ///   timing matches physical pedalling; use `true` (default) for Pause/Resume buttons.
    func resumeWorkout(fromUserControls: Bool = true) {
        workoutManager.resume(fromUserControls: fromUserControls)
    }

    func lapWorkout() {
        workoutManager.lap()
    }

    func exitPreRideAction(pathIsEmpty: Bool) -> IndoorNavigationAction {
        pathIsEmpty ? .resetRoot : .pop
    }

    func discardRide() -> IndoorNavigationAction {
        liveActivitySyncTask?.cancel()
        liveActivitySyncTask = nil
        workoutManager.discardWorkout()
        guidedSession.tearDown()
        bleService.disconnectAll(clearSaved: false)
        dismissEndConfirmation()
        resetRideFeedbackState()
        return .resetRoot
    }

    private func configureWorkoutCallbacks() {
        let guidedSession = self.guidedSession
        let workoutManager = self.workoutManager

        workoutManager.onTick = { [weak self, weak guidedSession] elapsed, power in
            guidedSession?.tick(elapsed: elapsed, currentPower: power)
            guard elapsed > 0,
                elapsed.isMultiple(of: Int(RideLiveActivityConfiguration.publishIntervalSeconds))
            else { return }
            self?.scheduleIndoorLiveActivitySync(isRecording: true)
        }

        workoutManager.onStateChange = { [weak self] _, newState in
            self?.scheduleIndoorLiveActivitySync(isRecording: newState == .recording)
        }
    }

    private func scheduleIndoorLiveActivitySync(isRecording: Bool) {
        liveActivitySyncTask?.cancel()
        liveActivitySyncTask = Task { [weak self] in
            guard let self else { return }
            await self.syncLiveActivity(
                isRecording: isRecording,
                prefs: RidePreferences.shared
            )
        }
    }

    func completionPlan(
        completedWorkout: Workout?,
        customWorkoutTemplateID: UUID?,
        planID: String?,
        planDayID: String?
    ) -> IndoorWorkoutCompletionPlan {
        let shouldMarkPlanDayCompleted =
            customWorkoutTemplateID == nil
            && planID != nil
            && planDayID != nil
            && (completedWorkout?.isValid ?? false)
        let summaryRoute: AppRoute?
        if let workoutID = completedWorkout?.id {
            summaryRoute = .summary(workoutID: workoutID)
        } else {
            summaryRoute = nil
        }

        return IndoorWorkoutCompletionPlan(
            shouldMarkPlanDayCompleted: shouldMarkPlanDayCompleted,
            resolvedPlanID: shouldMarkPlanDayCompleted ? planID : nil,
            summaryRoute: summaryRoute
        )
    }

    func endRide(
        customWorkoutTemplateID: UUID?,
        planID: String?,
        planDayID: String?,
        linkedPlanDay: PlanDay?,
        allProgress: [TrainingPlanProgress]
    ) -> IndoorNavigationAction? {
        workoutManager.endWorkout()

        let completedWorkout = workoutManager.workout
        let completion = completionPlan(
            completedWorkout: completedWorkout,
            customWorkoutTemplateID: customWorkoutTemplateID,
            planID: planID,
            planDayID: planDayID
        )

        if completion.shouldMarkPlanDayCompleted,
            let dayID = planDayID,
            let resolvedPlanID = completion.resolvedPlanID
        {
            markPlanDayCompleted(
                dayID: dayID,
                resolvedPlanID: resolvedPlanID,
                linkedPlanDay: linkedPlanDay,
                completedWorkout: completedWorkout,
                allProgress: allProgress
            )
        }

        guidedSession.tearDown()

        if let workout = completedWorkout {
            Task {
                await healthKitService.saveCyclingWorkoutToHealthIfEnabled(workout)
            }
        }

        dismissEndConfirmation()
        resetRideFeedbackState()

        guard let summaryRoute = completion.summaryRoute else { return nil }
        return .route(summaryRoute)
    }

    private func markPlanDayCompleted(
        dayID: String,
        resolvedPlanID: String,
        linkedPlanDay: PlanDay?,
        completedWorkout: Workout?,
        allProgress: [TrainingPlanProgress]
    ) {
        if let progress = allProgress.first(where: { $0.planID == resolvedPlanID }) {
            do {
                try trainingPlanPersistenceRepository.markCompleted(dayID, progress: progress)
            } catch {
                lastPersistenceError =
                    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }

        if let workout = completedWorkout,
            let linkedPlanDay,
            let progress = allProgress.first(where: { $0.planID == resolvedPlanID })
        {
            AdaptiveTrainingAdjuster.adjustAfterCompletedPlanWorkout(
                workout: workout,
                planDay: linkedPlanDay,
                progress: progress
            )
            do {
                try trainingPlanPersistenceRepository.save(progress: progress)
            } catch {
                lastPersistenceError =
                    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
