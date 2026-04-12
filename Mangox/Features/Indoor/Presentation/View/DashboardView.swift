import SwiftData
import SwiftUI

struct DashboardView: View {
    @State private var viewModel: IndoorViewModel
    private let trainingPlanLookupService: TrainingPlanLookupServiceProtocol
    @Binding var navigationPath: NavigationPath
    var planID: String? = nil
    var planDayID: String? = nil
    /// When set, guided ERG follows this saved template; plan completion and adaptive load are skipped.
    var customWorkoutTemplateID: UUID? = nil

    private static let planProgressDescriptor: FetchDescriptor<TrainingPlanProgress> = {
        var d = FetchDescriptor<TrainingPlanProgress>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        d.fetchLimit = 256
        return d
    }()

    @Query(Self.planProgressDescriptor) private var allProgress: [TrainingPlanProgress]

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // Delight state
    @State private var zonePulse = false
    @State private var zonePulseResetTask: Task<Void, Never>?
    @State private var rideBriefingTask: Task<Void, Never>?
    @State private var liveActivitySyncTask: Task<Void, Never>?
    @State private var milestoneTasks: [UUID: Task<Void, Never>] = [:]
    @State private var tipDismissTask: Task<Void, Never>?
    @State private var milestoneHideTask: Task<Void, Never>?
    @State private var persistenceErrorMessage: String?
    private let prefs = RidePreferences.shared

    /// Whole-km toast + haptic when crossing each multiple (e.g. 5 → 5 km, 10 km, …).
    private static let indoorDistanceMilestoneIntervalKm = 5

    init(
        navigationPath: Binding<NavigationPath>,
        planID: String? = nil,
        planDayID: String? = nil,
        customWorkoutTemplateID: UUID? = nil,
        trainingPlanLookupService: TrainingPlanLookupServiceProtocol,
        viewModel: IndoorViewModel
    ) {
        self._navigationPath = navigationPath
        self.planID = planID
        self.planDayID = planDayID
        self.customWorkoutTemplateID = customWorkoutTemplateID
        self.trainingPlanLookupService = trainingPlanLookupService
        self._viewModel = State(initialValue: viewModel)
    }

    private var plan: TrainingPlan? {
        trainingPlanLookupService.resolvePlan(planID: planID)
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<IndoorViewModel, Value>)
        -> Binding<Value>
    {
        Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }

    private var workoutManager: WorkoutManager { viewModel.workoutManager }
    private var guidedSession: GuidedSessionManager { viewModel.guidedSession }
    private var hapticManager: HapticManager { .shared }

    /// Unified BLE / WiFi metrics (WiFi takes priority when connected).
    private var metrics: CyclingMetrics { viewModel.metrics }

    /// Mean power over the last full second (from all high-rate trainer samples). Zones and arc track effort without an extra 3s lag.
    private var smoothedWatts: Int { workoutManager.displayPower }

    private var zone: PowerZone {
        PowerZone.zone(for: smoothedWatts)
    }

    /// iPhone landscape: split primary metrics and charts horizontally.
    private var isLandscapePhone: Bool {
        hSizeClass == .compact && verticalSizeClass == .compact
    }

    /// Tighter layout while riding so the phone dashboard fits without scrolling (arc stays on iPad / landscape).
    private var isActiveRide: Bool {
        workoutManager.state == .recording
            || workoutManager.state == .paused
            || workoutManager.state == .autoPaused
    }

    var body: some View {
        FTPRefreshScope {
            ZStack {
                Group {
                    if viewModel.hasRoute || accessibilityReduceTransparency {
                        Color(red: 0.03, green: 0.04, blue: 0.06)
                    } else {
                        LinearGradient(
                            colors: [
                                Color(red: 0.035, green: 0.05, blue: 0.09),
                                Color(red: 0.03, green: 0.04, blue: 0.06),
                                Color(red: 0.045, green: 0.045, blue: 0.075),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    headerBar

                    if hSizeClass == .compact {
                        if isLandscapePhone {
                            compactLandscapeLayout
                        } else {
                            compactLayout
                                .frame(maxHeight: .infinity)
                        }
                    } else {
                        wideLayout
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }

                    // Control bar
                    WorkoutControlBar(
                        state: workoutManager.state,
                        onStart: { viewModel.startWorkout() },
                        onPause: { viewModel.pauseWorkout() },
                        onResume: { viewModel.resumeWorkout() },
                        onLap: { viewModel.lapWorkout() },
                        showEndConfirmation: binding(\.showEndConfirmation),
                        showLap: prefs.showLaps
                    )
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }

                if viewModel.showEndConfirmation {
                    indoorEndWorkoutOverlay
                        .zIndex(200)
                }

                if viewModel.showRideTipsOnboardingPrompt {
                    rideTipsOnboardingOverlay
                        .zIndex(201)
                }

                if let persistenceErrorMessage {
                    persistenceErrorOverlay(message: persistenceErrorMessage)
                        .zIndex(202)
                }
            }
            .overlay {
                // Edge glow — zone color washes in from both screen edges on zone change.
                // Feels directional and immersive, like the room is lighting up.
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [zone.color.opacity(zonePulse ? 0.18 : 0.06), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 120)
                    Spacer()
                    LinearGradient(
                        colors: [.clear, zone.color.opacity(zonePulse ? 0.18 : 0.06)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 120)
                }
                .allowsHitTesting(false)
                .ignoresSafeArea()
                .animation(
                    .easeOut(duration: accessibilityReduceMotion ? 0 : 0.25), value: zonePulse)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                viewModel.bootstrapDashboard(
                    customWorkoutTemplateID: customWorkoutTemplateID,
                    planDayID: planDayID,
                    planID: planID,
                    allProgress: allProgress,
                    plan: plan
                )
                viewModel.evaluateRideTipsOnboardingPrompt(
                    prefs: prefs,
                    isInPreRide: workoutManager.state == .idle
                )
                persistenceErrorMessage = viewModel.consumePersistenceError()
            }
            .onDisappear {
                cancelTransientTasks()
                // Only tear down subscriptions/timer when the ride session is inactive.
                // Active sessions should survive transient view transitions.
                if workoutManager.state == .idle || workoutManager.state == .finished {
                    viewModel.tearDownWorkoutSession()
                }
            }
            .onChange(of: zone.id) { _, newZone in
                if workoutManager.state == .recording {
                    hapticManager.zoneChanged(to: newZone)
                    if accessibilityReduceMotion {
                        zonePulse = false
                    } else {
                        zonePulse = true
                        zonePulseResetTask?.cancel()
                        zonePulseResetTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            guard !Task.isCancelled else { return }
                            zonePulse = false
                        }
                    }
                }
            }
            .onChange(of: workoutManager.state) { oldState, newState in
                if let briefing = viewModel.handleWorkoutStateChange(
                    oldState: oldState,
                    newState: newState
                ) {
                    rideBriefingTask?.cancel()
                    rideBriefingTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(1800))
                        guard !Task.isCancelled else { return }
                        guard workoutManager.state == .recording else { return }
                        presentRideTip(RideNudgeDisplay(
                            id: "ai_ride_briefing",
                            category: .recovery,
                            headline: "Workout Briefing",
                            body: briefing,
                            audioScript: briefing
                        ))
                    }
                }
                liveActivitySyncTask?.cancel()
                liveActivitySyncTask = Task {
                    await viewModel.syncLiveActivity(
                        isRecording: newState == .recording,
                        prefs: prefs
                    )
                }
                viewModel.evaluateRideTipsOnboardingPrompt(
                    prefs: prefs,
                    isInPreRide: newState == .idle
                )
                if persistenceErrorMessage == nil {
                    persistenceErrorMessage = viewModel.consumePersistenceError()
                }
            }
            .onChange(of: workoutManager.currentLapNumber) { old, new in
                if new > old { hapticManager.lapCompleted() }
            }
            .onChange(of: workoutManager.justCompletedGoals) { _, completed in
                if !completed.isEmpty { hapticManager.goalCompleted() }
                if let goal = completed.first(where: { $0.kind == .distance }) {
                    flashDistanceGoalCompleteToast(targetKm: goal.target)
                }
            }
            .onChange(of: workoutManager.activeDistance) { _, dist in
                processIndoorDistanceMilestones(distanceMeters: dist)
            }
            .onChange(of: workoutManager.displayPower) { _, newPower in
                // Auto-resume when the last completed second shows power again (works for BLE + Wi‑Fi).
                if viewModel.shouldAutoResumeWorkout(
                    displayPower: newPower,
                    state: workoutManager.state
                ) {
                    viewModel.resumeWorkout()
                }
            }
            .onChange(of: workoutManager.elapsedSeconds) { _, _ in
                tickRideTipsIfNeeded()
                liveActivitySyncTask?.cancel()
                liveActivitySyncTask = Task {
                    await viewModel.syncLiveActivity(
                        isRecording: workoutManager.state == .recording,
                        prefs: prefs
                    )
                }
            }
            .overlay(alignment: .top) {
                if viewModel.isMilestoneVisible, let text = viewModel.milestoneText {
                    milestoneToast(text)
                        .padding(.top, 56)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                }
            }
        }
        .environment(viewModel)
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                if workoutManager.state == .idle {
                    Button {
                        exitPreRide()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: 28, height: 28)
                            .mangoxSurface(.frostedInteractive, shape: .circle)
                    }
                    .frame(minHeight: 28)
                }

                // Show plan day title in header when guided session is active
                if guidedSession.isActive {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("GUIDED WORKOUT")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppColor.mango.opacity(0.7))
                            .tracking(1.0)
                        Text(guidedSession.dayTitle)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    }
                    .frame(minHeight: 28)
                }

                Spacer()

                HStack(alignment: .center, spacing: 10) {
                    // Timer
                    Text(workoutManager.formattedElapsed)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(1)
                        .frame(minHeight: 28)

                    // Device badges
                    DeviceStatusBadge(
                        icon: "bicycle",
                        state: viewModel.trainerLinkDisplayState,
                        fallbackName: "Trainer",
                        isDataStale: viewModel.isTrainerLinkDataStale
                    )
                    DeviceStatusBadge(
                        icon: "heart.fill",
                        state: viewModel.hrConnectionState,
                        fallbackName: "HR"
                    )
                }
                .frame(minHeight: 28)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, guidedSession.isActive ? 6 : 14)

            // Mini overall progress bar when guided session is active
            if guidedSession.isActive
                && (workoutManager.state == .recording || workoutManager.state == .paused
                    || workoutManager.state == .autoPaused)
            {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                        Rectangle()
                            .fill(AppColor.mango)
                            .frame(width: max(0, geo.size.width * guidedSession.overallProgress))
                            .animation(
                                .easeInOut(duration: 0.5), value: guidedSession.overallProgress)
                    }
                }
                .frame(height: 3)
            }
        }
        .mangoxSurface(.frosted, shape: .rectangle)
    }

    // MARK: - End / discard (matches outdoor `endDiscardOverlays` chrome)

    private var indoorEndWorkoutOverlay: some View {
        MangoxConfirmOverlay(
            title: "End workout?",
            message:
                "We’ll open the summary next so you can review power, heart rate, and time — or discard this session with no save.",
            onDismiss: { viewModel.dismissEndConfirmation() }
        ) {
            HStack(spacing: 12) {
                Button {
                    viewModel.dismissEndConfirmation()
                } label: {
                    Text("Cancel")
                        .mangoxFont(.bodyBold)
                        .mangoxButtonChrome(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    endRide()
                } label: {
                    Text("End & Save")
                        .mangoxButtonChrome(.hero)
                }
                .buttonStyle(.plain)
            }

            Button {
                discardRide()
            } label: {
                Text("Discard without saving")
                    .mangoxFont(.bodyBold)
                    .mangoxButtonChrome(.destructive)
            }
            .buttonStyle(.plain)
        }
    }

    private var rideTipsOnboardingOverlay: some View {
        MangoxConfirmOverlay(
            title: "Try Smart Ride Tips?",
            message:
                "Get occasional fueling, cadence, and posture nudges for long indoor rides. You can change this anytime in Settings.",
            onDismiss: { viewModel.applyRideTipsOnboardingDecline(prefs: prefs) }
        ) {
            HStack(spacing: 12) {
                Button {
                    viewModel.applyRideTipsOnboardingDecline(prefs: prefs)
                } label: {
                    Text("Not now")
                        .mangoxFont(.bodyBold)
                        .mangoxButtonChrome(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.applyRideTipsOnboardingEnable(prefs: prefs)
                } label: {
                    Text("Enable Essentials")
                        .mangoxButtonChrome(.hero)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func persistenceErrorOverlay(message: String) -> some View {
        MangoxConfirmOverlay(
            title: "Save Failed",
            message: message,
            onDismiss: { persistenceErrorMessage = nil }
        ) {
            Button {
                persistenceErrorMessage = nil
            } label: {
                Text("OK")
                    .mangoxButtonChrome(.hero)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Compact Layout (iPhone portrait)

    /// Portrait iPhone: prefer a single glanceable screen while pedaling — no redundant arc (hero + zone bar already show power).
    /// While recording, we try a dense non-scrolling column first (`ViewThatFits`); if it cannot fit, we fall back to scroll.
    private var compactLayout: some View {
        Group {
            if isActiveRide {
                ViewThatFits(in: .vertical) {
                    compactPortraitStack(fit: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    ScrollView {
                        compactPortraitStack(fit: false)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .scrollIndicators(.hidden)
                }
            } else {
                ScrollView {
                    compactPortraitStack(fit: false)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private func compactPortraitStack(fit: Bool) -> some View {
        let stackSpacing: CGFloat = isActiveRide ? (fit ? 4 : 6) : 10
        let liveLayout: LivePerformanceBar.LayoutMode = fit ? .oneLine : .horizontalScroll
        let chartHeight: CGFloat? = {
            if !isActiveRide { return nil }
            return fit ? 36 : 44
        }()
        let mapH: CGFloat = {
            guard viewModel.hasRoute else { return 0 }
            if !isActiveRide { return 160 }
            return fit ? 100 : 140
        }()
        let elevH: CGFloat = {
            guard viewModel.hasRoute else { return 0 }
            if !isActiveRide { return 60 }
            return fit ? 44 : 52
        }()

        VStack(spacing: stackSpacing) {
            phonePowerDisplay

            if showRideModeBanner, viewModel.hasRoute {
                IndoorRideModeContext(
                    hasRoute: true,
                    routeName: viewModel.routeName,
                    compact: fit
                )
            }

            // Free ride: stats + strip up front (after banner). GPX: same controls after map + elevation so the route stays high in the stack.
            if !viewModel.hasRoute {
                indoorLivePerformanceBar(compact: true, layoutMode: liveLayout, collapsible: true)

                PowerGraphView(
                    powerHistory: workoutManager.powerHistory,
                    powerHistoryMax: workoutManager.powerHistoryMax,
                    compact: true,
                    chartHeightCompact: chartHeight,
                    flatStrip: true
                )
            }

            phoneMetricsGrid

            if metrics.heartRate > 0 {
                HeartRateBarView(heartRate: metrics.heartRate, compact: true)
            }

            if workoutManager.showLowCadenceWarning {
                cadenceWarningBanner
            }

            if let tip = viewModel.activeRideTip {
                rideTipBanner(tip)
            }

            goalProgressSection(fit: fit)

            if guidedSession.isActive
                && (workoutManager.state == .recording || workoutManager.state == .paused
                    || workoutManager.state == .autoPaused)
            {
                guidedSessionCard(condensed: fit)
            }

            if viewModel.ftmsControlIsAvailable {
                trainerControlCard(condensed: fit)
            }

            if viewModel.hasRoute {
                RouteMiniMapView(
                    routeService: viewModel.routeService,
                    distance: workoutManager.activeDistance,
                    mapHeight: mapH
                )
                ElevationProfileView(
                    routeService: viewModel.routeService,
                    currentDistance: workoutManager.activeDistance,
                    height: elevH
                )

                indoorLivePerformanceBar(compact: true, layoutMode: liveLayout, collapsible: true)

                PowerGraphView(
                    powerHistory: workoutManager.powerHistory,
                    powerHistoryMax: workoutManager.powerHistoryMax,
                    compact: true,
                    chartHeightCompact: chartHeight,
                    flatStrip: true
                )
            }

            if prefs.showLaps {
                LapCardView(
                    lapNumber: workoutManager.currentLapNumber,
                    currentAvgPower: workoutManager.currentLapAvgPower,
                    currentDuration: workoutManager.currentLapDuration,
                    previousAvgPower: workoutManager.previousLapAvgPower,
                    previousDuration: workoutManager.previousLapDuration,
                    compact: fit
                )
            }
        }
    }

    /// Two-column layout on landscape iPhone: hero + metrics left; arc, live performance, chart (or map) right.
    private var compactLandscapeLayout: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 10) {
                        phonePowerDisplay

                        if showRideModeBanner, viewModel.hasRoute {
                            IndoorRideModeContext(
                                hasRoute: true,
                                routeName: viewModel.routeName
                            )
                        }

                        phoneMetricsGrid
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    VStack(spacing: 10) {
                        if !viewModel.hasRoute {
                            PowerArcView(
                                watts: smoothedWatts,
                                compact: true,
                                showCenterText: false,
                                micro: false
                            )
                            .frame(maxWidth: .infinity)

                            indoorLivePerformanceBar(
                                compact: true, layoutMode: .stacked, collapsible: true)

                            PowerGraphView(
                                powerHistory: workoutManager.powerHistory,
                                powerHistoryMax: workoutManager.powerHistoryMax,
                                compact: true,
                                chartHeightCompact: 40,
                                flatStrip: true
                            )
                        } else {
                            RouteMiniMapView(
                                routeService: viewModel.routeService,
                                distance: workoutManager.activeDistance,
                                mapHeight: 120
                            )
                            ElevationProfileView(
                                routeService: viewModel.routeService,
                                currentDistance: workoutManager.activeDistance,
                                height: 48
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .layoutPriority(0)
                }

                // GPX rides: map + elevation stay in the right column; stats + strip span full width below (matches portrait order).
                if viewModel.hasRoute {
                    indoorLivePerformanceBar(compact: true, layoutMode: .stacked, collapsible: true)

                    PowerGraphView(
                        powerHistory: workoutManager.powerHistory,
                        powerHistoryMax: workoutManager.powerHistoryMax,
                        compact: true,
                        chartHeightCompact: 40,
                        flatStrip: true
                    )
                }

                if metrics.heartRate > 0 {
                    HeartRateBarView(heartRate: metrics.heartRate, compact: true)
                }

                if workoutManager.showLowCadenceWarning {
                    cadenceWarningBanner
                }

                if let tip = viewModel.activeRideTip {
                    rideTipBanner(tip)
                }

                goalProgressSection(fit: false)

                if guidedSession.isActive
                    && (workoutManager.state == .recording || workoutManager.state == .paused
                        || workoutManager.state == .autoPaused)
                {
                    guidedSessionCard(condensed: false)
                }

                if viewModel.ftmsControlIsAvailable {
                    trainerControlCard(condensed: false)
                }

                if prefs.showLaps {
                    LapCardView(
                        lapNumber: workoutManager.currentLapNumber,
                        currentAvgPower: workoutManager.currentLapAvgPower,
                        currentDuration: workoutManager.currentLapDuration,
                        previousAvgPower: workoutManager.previousLapAvgPower,
                        previousDuration: workoutManager.previousLapDuration,
                        compact: false
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Phone Compact Helpers

    private var pctFTP: Int {
        Int((Double(smoothedWatts) / Double(max(PowerZone.ftp, 1)) * 100).rounded())
    }

    private var powerZoneRangeText: String {
        let low = zone.wattRange.lowerBound
        let high = zone.wattRange.upperBound
        return zone.id == PowerZone.zones.last?.id ? "\(low)+ W" : "\(low)–\(high) W"
    }

    /// Hide the free-ride / route banner when a guided workout supplies context in the header.
    private var showRideModeBanner: Bool {
        !guidedSession.isActive
    }

    private var guidedStepIsHardIntensity: Bool {
        guard let z = guidedSession.currentStep?.zone else { return false }
        switch z {
        case .z4, .z5, .z4z5, .z3z5: return true
        default: return false
        }
    }

    @ViewBuilder
    private func indoorLivePerformanceBar(
        compact: Bool,
        layoutMode: LivePerformanceBar.LayoutMode,
        collapsible: Bool = false
    ) -> some View {
        if collapsible {
            CollapsibleLivePerformanceBar(
                formattedNP: workoutManager.formattedLiveNP,
                formattedIF: workoutManager.formattedLiveIF,
                formattedTSS: workoutManager.formattedLiveTSS,
                formattedVI: workoutManager.formattedVI,
                formattedAvgPower: workoutManager.formattedAvgPower,
                formattedEfficiency: workoutManager.formattedEfficiency,
                formattedKJ: workoutManager.formattedKJ,
                showEfficiency: metrics.heartRate > 0,
                ftpIsSet: PowerZone.hasSetFTP,
                compact: compact
            )
        } else {
            LivePerformanceBar(
                formattedNP: workoutManager.formattedLiveNP,
                formattedIF: workoutManager.formattedLiveIF,
                formattedTSS: workoutManager.formattedLiveTSS,
                formattedVI: workoutManager.formattedVI,
                formattedAvgPower: workoutManager.formattedAvgPower,
                formattedEfficiency: workoutManager.formattedEfficiency,
                formattedKJ: workoutManager.formattedKJ,
                showEfficiency: metrics.heartRate > 0,
                ftpIsSet: PowerZone.hasSetFTP,
                compact: compact,
                layoutMode: layoutMode
            )
        }
    }

    private var phonePowerDisplay: some View {
        PhonePowerDisplay(
            smoothedWatts: smoothedWatts,
            zone: zone,
            pctFTP: pctFTP,
            powerZoneRangeText: powerZoneRangeText,
            avg3s: workoutManager.avg3s
        )
    }

    private var phoneMetricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0) {
            phoneMetricCell(
                label: "SPEED",
                value: workoutManager.formattedSpeed,
                unit: speedUnitLabel
            )
            phoneMetricCell(
                label: "CADENCE",
                value: workoutManager.formattedCadence,
                unit: "rpm",
                color: AppColor.blue
            )
            phoneMetricCell(
                label: "DISTANCE",
                value: workoutManager.formattedDistanceKm,
                unit: "km"
            )
            phoneMetricCell(
                label: "ENERGY",
                value: workoutManager.formattedEnergyKJ,
                unit: "kJ",
                color: AppColor.yellow
            )
        }
        .cardStyle()
    }

    private func phoneMetricCell(label: String, value: String, unit: String, color: Color = .white)
        -> some View
    {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(1.0)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 22 : 26, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 22 : 26, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value) \(unit)")
    }

    // MARK: - Wide Layout (iPad / landscape)

    private var wideLayout: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    if showRideModeBanner, viewModel.hasRoute {
                        IndoorRideModeContext(
                            hasRoute: true,
                            routeName: viewModel.routeName
                        )
                    }

                    PowerArcView(
                        watts: smoothedWatts,
                        compact: viewModel.hasRoute,
                        showCenterText: true
                    )

                    SmoothedPowerView(
                        avg3s: workoutManager.avg3s,
                        avg5s: workoutManager.avg5s,
                        avg30s: workoutManager.avg30s,
                        compact: viewModel.hasRoute
                    )

                    if viewModel.hasRoute {
                        RouteMiniMapView(
                            routeService: viewModel.routeService,
                            distance: workoutManager.activeDistance,
                            mapHeight: 220
                        )
                        ElevationProfileView(
                            routeService: viewModel.routeService,
                            currentDistance: workoutManager.activeDistance,
                            height: 72
                        )
                    }

                    PowerGraphView(
                        powerHistory: workoutManager.powerHistory,
                        powerHistoryMax: workoutManager.powerHistoryMax,
                        compact: false
                    )

                    indoorLivePerformanceBar(
                        compact: false, layoutMode: .stacked, collapsible: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .frame(width: 380)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)
            }

            ScrollView {
                VStack(spacing: 16) {
                    if guidedSession.isActive,
                        workoutManager.state == .recording || workoutManager.state == .paused
                            || workoutManager.state == .autoPaused
                    {
                        guidedSessionCard(condensed: false)
                    }

                    metricsGrid

                    if workoutManager.showLowCadenceWarning {
                        cadenceWarningBanner
                    }

                    if let tip = viewModel.activeRideTip {
                        rideTipBanner(tip)
                    }

                    goalProgressSection(fit: false)

                    if metrics.heartRate > 0 {
                        HeartRateBarView(
                            heartRate: metrics.heartRate
                        )
                    }

                    if viewModel.ftmsControlIsAvailable, !guidedSession.isActive {
                        trainerControlCard(condensed: false)
                    }

                    if prefs.showLaps {
                        LapCardView(
                            lapNumber: workoutManager.currentLapNumber,
                            currentAvgPower: workoutManager.currentLapAvgPower,
                            currentDuration: workoutManager.currentLapDuration,
                            previousAvgPower: workoutManager.previousLapAvgPower,
                            previousDuration: workoutManager.previousLapDuration,
                            compact: false
                        )
                    }
                }
                .padding(22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Shared Pieces

    private var speedUnitLabel: String {
        RidePreferences.shared.indoorSpeedSource == .computed ? "km/h · calc" : "km/h"
    }

    // MARK: - Goal Progress

    @ViewBuilder
    private func goalProgressSection(fit: Bool) -> some View {
        let activeGoals = prefs.activeGoals
        if activeGoals.isEmpty {
            EmptyView()
        } else {
            let indices = fit ? Array(activeGoals.indices.prefix(2)) : Array(activeGoals.indices)
            VStack(spacing: 8) {
                ForEach(indices, id: \.self) { index in
                    let goal = activeGoals[index]
                    let progress = goalProgress(for: goal)
                    GoalProgressPill(
                        goal: goal,
                        progress: progress,
                        currentValue: goalCurrentValue(for: goal),
                        targetValue: goalTargetValue(for: goal),
                        elapsedSeconds: workoutManager.elapsedSeconds
                    )
                }
            }
        }
    }

    private func goalProgress(for goal: RideGoal) -> Double {
        let elapsedMinutes = Double(workoutManager.elapsedSeconds) / 60.0
        let distanceKm = workoutManager.activeDistance / 1000.0
        return goal.progress(
            distance: distanceKm,
            elapsedMinutes: elapsedMinutes,
            kj: workoutManager.kilojoules,
            tss: workoutManager.liveTSS
        )
    }

    private func goalCurrentValue(for goal: RideGoal) -> String {
        switch goal.kind {
        case .distance:
            return String(format: "%.2f", workoutManager.activeDistance / 1000.0)
        case .duration:
            return String(format: "%.0f", Double(workoutManager.elapsedSeconds) / 60.0)
        case .kilojoules:
            return String(format: "%.0f", workoutManager.kilojoules)
        case .tss:
            return String(format: "%.0f", workoutManager.liveTSS)
        }
    }

    private func goalTargetValue(for goal: RideGoal) -> String {
        switch goal.kind {
        case .distance:
            return String(format: "%.2f", goal.target)
        case .duration:
            return String(format: "%.0f", goal.target)
        case .kilojoules:
            return String(format: "%.0f", goal.target)
        case .tss:
            return String(format: "%.0f", goal.target)
        }
    }

    // MARK: - Cadence Warning

    private var cadenceWarningBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text("Cadence below \(prefs.lowCadenceThreshold) rpm")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(AppColor.orange)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(AppColor.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func rideTipBanner(_ tip: RideNudgeDisplay) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.mango)
                .frame(width: 20, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(tip.headline.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColor.mango.opacity(0.9))
                    .tracking(0.6)
                Text(tip.body)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                viewModel.clearRideTip()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss tip")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppColor.blue.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var metricsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                MetricCardView(
                    label: "SPEED",
                    value: workoutManager.formattedSpeed,
                    unit: speedUnitLabel
                )
                MetricCardView(
                    label: "CADENCE",
                    value: workoutManager.formattedCadence,
                    unit: "rpm",
                    valueColor: AppColor.blue
                )
            }

            HStack(spacing: 12) {
                MetricCardView(
                    label: "DISTANCE",
                    value: workoutManager.formattedDistanceKm1dp,
                    unit: "km"
                )
                MetricCardView(
                    label: "ENERGY",
                    value: workoutManager.formattedEnergyKJ,
                    unit: "kJ",
                    valueColor: AppColor.yellow
                )
            }
        }
    }

    // MARK: - Trainer Control Card

    private func trainerControlCard(condensed: Bool) -> some View {
        let isActive = workoutManager.state == .recording || workoutManager.state == .paused
        return TrainerControlCard(
            trainerMode: workoutManager.trainerMode,
            supportsSimulation: viewModel.ftmsControlSupportsSimulation,
            supportsERG: viewModel.ftmsControlSupportsERG,
            supportsResistance: viewModel.ftmsControlSupportsResistance,
            hasRoute: viewModel.hasRoute,
            isWorkoutActive: isActive,
            showRouteSimulationFooterHint: guidedSession.isActive,
            condensed: condensed,
            intensityMultiplier: workoutManager.intensityMultiplier,
            onIntensityChange: { newScale in
                workoutManager.intensityMultiplier = newScale
            },
            routeDifficultyScale: workoutManager.routeDifficultyScale,
            onDifficultyChange: { newScale in
                workoutManager.routeDifficultyScale = newScale
            },
            onRouteSim: {
                if case .simulation = workoutManager.trainerMode {
                    workoutManager.stopRouteSimulation()
                } else {
                    workoutManager.startRouteSimulation()
                }
            },
            onERG: {
                if case .erg = workoutManager.trainerMode {
                    workoutManager.releaseTrainerControl()
                } else {
                    workoutManager.setERGMode(watts: PowerZone.ftp)
                }
            },
            onResistance: {
                if case .resistance = workoutManager.trainerMode {
                    workoutManager.releaseTrainerControl()
                } else {
                    workoutManager.setResistanceMode(level: 0.5)
                }
            },
            onFreeRide: {
                workoutManager.releaseTrainerControl()
            }
        )
    }

    // MARK: - Guided Session Card

    private func guidedSessionCard(condensed: Bool) -> some View {
        GuidedSessionCard(session: guidedSession, condensed: condensed)
    }

    // MARK: - Actions

    // MARK: - Delight Helpers

    private func flashMilestone(_ text: String) {
        viewModel.showMilestone(text)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            viewModel.isMilestoneVisible = true
        }
        milestoneHideTask?.cancel()
        milestoneHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                viewModel.hideMilestone()
            }
        }
    }

    private func tickRideTipsIfNeeded() {
        let distanceGoalKm = prefs.activeGoals.first(where: { $0.kind == .distance && $0.target > 0 })?.target

        let guidedStepIndex: Int = {
            guard guidedSession.isActive, guidedSession.currentStep != nil else { return -1 }
            return guidedSession.currentStepIndex
        }()

        let guidedInto: Int? = {
            guard guidedSession.isActive, let step = guidedSession.currentStep else { return nil }
            return max(0, guidedSession.elapsedSeconds - step.startOffset)
        }()

        if let tip = viewModel.nextRideTip(
            rideTipsEnabled: prefs.rideTipsEnabled,
            isRecording: workoutManager.state == .recording,
            elapsedSeconds: workoutManager.elapsedSeconds,
            activeDistanceMeters: workoutManager.activeDistance,
            activeDistanceGoalKm: distanceGoalKm,
            displayPower: workoutManager.displayPower,
            displayCadenceRpm: workoutManager.displayCadenceRpm,
            zoneId: zone.id,
            lowCadenceThreshold: prefs.lowCadenceThreshold,
            lowCadenceStreakSeconds: workoutManager.lowCadenceStreakSeconds,
            showLowCadenceHardWarning: workoutManager.showLowCadenceWarning,
            guidedIsActive: guidedSession.isActive,
            guidedStepIsRecovery: guidedSession.currentStep?.isRecovery ?? false,
            guidedSecondsIntoStep: guidedInto,
            guidedStepIsHardIntensity: guidedStepIsHardIntensity,
            prefs: prefs,
            guidedStepIndex: guidedStepIndex
        ) {
            presentRideTip(tip)
        }
    }

    private func presentRideTip(_ tip: RideNudgeDisplay) {
        viewModel.presentRideTip(tip)
        hapticManager.rideTipNudge()
        AudioCueManager.shared.announceRideTip(script: tip.audioScript)
        let tipID = tip.id
        tipDismissTask?.cancel()
        tipDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(11))
            guard !Task.isCancelled else { return }
            viewModel.clearRideTip(ifMatching: tipID)
        }
    }

    /// Progress toward an enabled distance goal (25 / 50 / 75%); otherwise fixed 5 km markers.
    private func processIndoorDistanceMilestones(distanceMeters dist: Double) {
        let distanceGoalKm = prefs.activeGoals.first(where: { $0.kind == .distance && $0.target > 0 })?.target
        let triggers = viewModel.milestoneTriggers(
            distanceMeters: dist,
            isRecording: workoutManager.state == .recording,
            activeDistanceGoalKm: distanceGoalKm
        )
        for (index, trigger) in triggers.enumerated() {
            let delay = Double(index) * 3.5
            let taskID = UUID()
            let task = Task { @MainActor in
                defer { milestoneTasks[taskID] = nil }
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                guard workoutManager.state == .recording else { return }
                switch trigger {
                case .distanceInterval(let km):
                    flashMilestone("\(km) km")
                case .distanceGoalProgress(let percent, _, let targetKm):
                    let curKm = workoutManager.activeDistance / 1000.0
                    flashDistanceGoalFractionToast(percent: percent, currentKm: curKm, targetKm: targetKm)
                case .distanceGoalCompleted(let targetKm):
                    flashDistanceGoalCompleteToast(targetKm: targetKm)
                }
                hapticManager.milestone()
            }
            milestoneTasks[taskID] = task
        }
    }

    private func cancelTransientTasks() {
        zonePulseResetTask?.cancel()
        zonePulseResetTask = nil
        rideBriefingTask?.cancel()
        rideBriefingTask = nil
        liveActivitySyncTask?.cancel()
        liveActivitySyncTask = nil
        tipDismissTask?.cancel()
        tipDismissTask = nil
        milestoneHideTask?.cancel()
        milestoneHideTask = nil
        for (id, task) in milestoneTasks {
            task.cancel()
            milestoneTasks[id] = nil
        }
    }

    private func flashDistanceGoalFractionToast(percent: Int, currentKm: Double, targetKm: Double) {
        let imperial = prefs.isImperial
        let curStr = AppFormat.distanceString(currentKm * 1000.0, imperial: imperial, decimals: 1)
        let tgtStr = AppFormat.distanceString(targetKm * 1000.0, imperial: imperial, decimals: 1)
        let unit = AppFormat.distanceUnit(imperial: imperial)
        let headline: String
        switch percent {
        case 25: headline = "25%"
        case 50: headline = "Halfway"
        case 75: headline = "75%"
        default: headline = "\(percent)%"
        }
        flashMilestone("\(headline) · \(curStr) / \(tgtStr) \(unit)")
    }

    private func flashDistanceGoalCompleteToast(targetKm: Double) {
        switch viewModel.distanceGoalCompletedTrigger(targetKm: targetKm) {
        case .distanceGoalCompleted(let completedTargetKm):
            let imperial = prefs.isImperial
            let tgtStr = AppFormat.distanceString(completedTargetKm * 1000.0, imperial: imperial, decimals: 1)
            let unit = AppFormat.distanceUnit(imperial: imperial)
            flashMilestone("Goal reached · \(tgtStr) \(unit)")
        default:
            break
        }
    }

    private func milestoneToast(_ text: String) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(AppColor.mango)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .mangoxSurface(.frosted, shape: .capsule)
    }

    private func exitPreRide() {
        guard workoutManager.state == .idle else { return }
        applyNavigationAction(
            viewModel.exitPreRideAction(pathIsEmpty: navigationPath.isEmpty)
        )
    }

    private func discardRide() {
        applyNavigationAction(
            viewModel.discardRide(
            )
        )
    }

    private func endRide() {
        let completionAction = viewModel.endRide(
            customWorkoutTemplateID: customWorkoutTemplateID,
            planID: planID,
            planDayID: planDayID,
            linkedPlanDay: planDayID.flatMap { dayID in
                plan?.day(id: dayID)
            },
            allProgress: allProgress
        )

        if let completionAction {
            applyNavigationAction(completionAction)
        }
    }

    private func applyNavigationAction(_ action: IndoorNavigationAction) {
        switch action {
        case .pop:
            navigationPath.removeLast()
        case .resetRoot:
            navigationPath = NavigationPath()
        case .route(let route):
            navigationPath = NavigationPath()
            navigationPath.append(route)
        }
    }

    /// Reverses plan day completion when a workout linked to a plan day is deleted.
    /// Called from SummaryView via a notification or directly when the workout
    /// is deleted from the summary screen.
    static func unmarkPlanDay(_ dayID: String, planID: String, in context: ModelContext) {
        let descriptor = FetchDescriptor<TrainingPlanProgress>(
            predicate: #Predicate { $0.planID == planID }
        )
        if let progress = try? context.fetch(descriptor).first {
            progress.completedDayIDs.removeAll { $0 == dayID }
            try? context.save()
        }
    }
}
