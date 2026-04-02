import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(BLEManager.self) private var bleManager
    @Environment(DataSourceCoordinator.self) private var dataSource
    @Environment(RouteManager.self) private var routeManager
    @Environment(HealthKitManager.self) private var healthKitManager
    @Binding var navigationPath: NavigationPath
    var planID: String? = nil
    var planDayID: String? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @State private var workoutManager = WorkoutManager()
    @State private var hapticManager = HapticManager()
    @State private var guidedSession = GuidedSessionManager()
    /// Full-screen end/discard sheet (matches outdoor dashboard chrome).
    @State private var showIndoorEndConfirmation = false

    // Delight state
    @State private var zonePulse = false
    @State private var lastMilestoneKm = 0
    @State private var milestoneText: String? = nil
    @State private var milestoneVisible = false

    private let prefs = RidePreferences.shared

    private var plan: TrainingPlan {
        PlanLibrary.resolvePlan(planID: planID ?? CachedPlan.shared.id) ?? CachedPlan.shared
    }

    /// Unified BLE / WiFi metrics (WiFi takes priority when connected).
    private var metrics: CyclingMetrics {
        var m = CyclingMetrics(lastUpdate: Date())
        m.power = dataSource.power
        m.cadence = dataSource.cadence
        m.speed = dataSource.speed
        m.heartRate = dataSource.heartRate
        m.totalDistance = dataSource.totalDistance
        m.hrSource = bleManager.metrics.hrSource
        return m
    }

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
                if routeManager.hasRoute || accessibilityReduceTransparency {
                    Color(red: 0.03, green: 0.04, blue: 0.06)
                } else {
                    LinearGradient(
                        colors: [
                            Color(red: 0.035, green: 0.05, blue: 0.09),
                            Color(red: 0.03, green: 0.04, blue: 0.06),
                            Color(red: 0.045, green: 0.045, blue: 0.075)
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
                    onStart: { workoutManager.startWorkout() },
                    onPause: { workoutManager.pause() },
                    onResume: { workoutManager.resume() },
                    onLap: { workoutManager.lap() },
                    showEndConfirmation: $showIndoorEndConfirmation,
                    showLap: prefs.showLaps
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            if showIndoorEndConfirmation {
                indoorEndWorkoutOverlay
                    .zIndex(200)
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
            .animation(.easeOut(duration: accessibilityReduceMotion ? 0 : 0.25), value: zonePulse)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            dataSource.updateActiveSource()
            workoutManager.configure(bleManager: bleManager, modelContext: modelContext, dataSource: dataSource)
            workoutManager.configureRoute(routeManager)
            configureGuidedSession()
            // Tell WorkoutManager which plan day this session belongs to
            // so the Workout model gets tagged for deletion-aware un-marking.
            workoutManager.activePlanDayID = planDayID
            workoutManager.activePlanID = planID

            // Auto-start: the rider already committed by tapping "Ride" on
            // the connection screen, so skip the redundant START tap.
            // The 5-second trainer engage delay gives them time to clip in.
            if workoutManager.state == .idle {
                workoutManager.startWorkout()
            }
        }
        .onDisappear {
            // Clean up BLE subscriptions and timer without relying on deinit
            // actor isolation (which is inconsistent across Swift toolchain versions).
            workoutManager.tearDown()
        }
        .onChange(of: zone.id) { _, newZone in
            if workoutManager.state == .recording {
                hapticManager.zoneChanged(to: newZone)
                if accessibilityReduceMotion {
                    zonePulse = false
                } else {
                    zonePulse = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        zonePulse = false
                    }
                }
            }
        }
        .onChange(of: workoutManager.state) { oldState, newState in
            switch (oldState, newState) {
            case (.idle, .recording):
                hapticManager.workoutStarted()
            case (.recording, .autoPaused):
                hapticManager.autoPaused()
            case (.autoPaused, .recording):
                hapticManager.autoResumed()
            case (_, .finished):
                hapticManager.workoutEnded()
            default:
                break
            }
        }
        .onChange(of: workoutManager.currentLapNumber) { old, new in
            if new > old { hapticManager.lapCompleted() }
        }
        .onChange(of: workoutManager.justCompletedGoals) { _, completed in
            if !completed.isEmpty { hapticManager.goalCompleted() }
        }
        .onChange(of: workoutManager.activeDistance) { _, dist in
            guard workoutManager.state == .recording else { return }
            let km = Int(dist / 1000)
            let milestone = (km / 10) * 10
            if milestone >= 10 && milestone > lastMilestoneKm {
                lastMilestoneKm = milestone
                flashMilestone("\(milestone) km")
                hapticManager.milestone()
            }
        }
        .onChange(of: workoutManager.displayPower) { _, newPower in
            // Auto-resume when the last completed second shows power again (works for BLE + Wi‑Fi).
            if workoutManager.state == .autoPaused && newPower > 0 {
                workoutManager.resume()
            }
        }
        .onChange(of: workoutManager.elapsedSeconds) { _, _ in
            Task {
                await RideLiveActivityManager.shared.syncIndoorRecording(
                    isRecording: workoutManager.state == .recording,
                    prefs: prefs,
                    workoutManager: workoutManager,
                    bleManager: bleManager
                )
            }
        }
        .overlay(alignment: .top) {
            if milestoneVisible, let text = milestoneText {
                milestoneToast(text)
                    .padding(.top, 56)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.easeOut(duration: accessibilityReduceMotion ? 0 : 0.35), value: milestoneVisible)
        }
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
                            .modifier(IndoorGlassOrOpaqueCircle(
                                useOpaque: accessibilityReduceTransparency
                            ))
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
                            .lineLimit(1)
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
                        state: dataSource.trainerLinkDisplayState,
                        fallbackName: "Trainer",
                        isDataStale: dataSource.isTrainerLinkDataStale
                    )
                    DeviceStatusBadge(
                        icon: "heart.fill",
                        state: bleManager.hrConnectionState,
                        fallbackName: "HR"
                    )
                }
                .frame(minHeight: 28)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, guidedSession.isActive ? 6 : 14)

            // Mini overall progress bar when guided session is active
            if guidedSession.isActive && (workoutManager.state == .recording || workoutManager.state == .paused || workoutManager.state == .autoPaused) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                        Rectangle()
                            .fill(AppColor.mango)
                            .frame(width: max(0, geo.size.width * guidedSession.overallProgress))
                            .animation(.easeInOut(duration: 0.5), value: guidedSession.overallProgress)
                    }
                }
                .frame(height: 3)
            }
        }
        .modifier(IndoorHeaderBarChrome(reduceTransparency: accessibilityReduceTransparency))
    }

    // MARK: - End / discard (matches outdoor `endDiscardOverlays` chrome)

    private var indoorEndWorkoutOverlay: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture { showIndoorEndConfirmation = false }

            VStack(alignment: .leading, spacing: 16) {
                Text("End workout?")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text("We’ll open the summary next so you can review power, heart rate, and time — or discard this session with no save.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button {
                        showIndoorEndConfirmation = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        showIndoorEndConfirmation = false
                        endRide()
                    } label: {
                        Text("End & Save")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppColor.bg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(AppColor.mango)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button {
                    showIndoorEndConfirmation = false
                    discardRide()
                } label: {
                    Text("Discard without saving")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .background(AppColor.red.opacity(0.95))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppColor.bg)
                    .shadow(color: .black.opacity(0.45), radius: 30, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
        .allowsHitTesting(true)
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
            guard routeManager.hasRoute else { return 0 }
            if !isActiveRide { return 160 }
            return fit ? 100 : 140
        }()
        let elevH: CGFloat = {
            guard routeManager.hasRoute else { return 0 }
            if !isActiveRide { return 60 }
            return fit ? 44 : 52
        }()

        VStack(spacing: stackSpacing) {
            phonePowerDisplay

            if showRideModeBanner, routeManager.hasRoute {
                IndoorRideModeContext(
                    hasRoute: true,
                    routeName: routeManager.routeName,
                    compact: fit
                )
            }

            // Free ride: stats + strip up front (after banner). GPX: same controls after map + elevation so the route stays high in the stack.
            if !routeManager.hasRoute {
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

            goalProgressSection(fit: fit)

            if guidedSession.isActive && (workoutManager.state == .recording || workoutManager.state == .paused || workoutManager.state == .autoPaused) {
                guidedSessionCard(condensed: fit)
            }

            if bleManager.ftmsControl.isAvailable {
                trainerControlCard(condensed: fit)
            }

            if routeManager.hasRoute {
                RouteMiniMapView(
                    distance: workoutManager.activeDistance,
                    mapHeight: mapH
                )
                ElevationProfileView(
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

                        if showRideModeBanner, routeManager.hasRoute {
                            IndoorRideModeContext(
                                hasRoute: true,
                                routeName: routeManager.routeName
                            )
                        }

                        phoneMetricsGrid
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    VStack(spacing: 10) {
                        if !routeManager.hasRoute {
                            PowerArcView(
                                watts: smoothedWatts,
                                compact: true,
                                showCenterText: false,
                                micro: false
                            )
                            .frame(maxWidth: .infinity)

                            indoorLivePerformanceBar(compact: true, layoutMode: .stacked, collapsible: true)

                            PowerGraphView(
                                powerHistory: workoutManager.powerHistory,
                                powerHistoryMax: workoutManager.powerHistoryMax,
                                compact: true,
                                chartHeightCompact: 40,
                                flatStrip: true
                            )
                        } else {
                            RouteMiniMapView(
                                distance: workoutManager.activeDistance,
                                mapHeight: 120
                            )
                            ElevationProfileView(
                                currentDistance: workoutManager.activeDistance,
                                height: 48
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .layoutPriority(0)
                }

                // GPX rides: map + elevation stay in the right column; stats + strip span full width below (matches portrait order).
                if routeManager.hasRoute {
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

                goalProgressSection(fit: false)

                if guidedSession.isActive && (workoutManager.state == .recording || workoutManager.state == .paused || workoutManager.state == .autoPaused) {
                    guidedSessionCard(condensed: false)
                }

                if bleManager.ftmsControl.isAvailable {
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
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                phoneMetricCell(
                    label: "SPEED",
                    value: workoutManager.formattedSpeed,
                    unit: speedUnitLabel
                )
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)
                phoneMetricCell(
                    label: "CADENCE",
                    value: workoutManager.formattedCadence,
                    unit: "rpm",
                    color: AppColor.blue
                )
            }
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
            HStack(spacing: 0) {
                phoneMetricCell(
                    label: "DISTANCE",
                    value: workoutManager.formattedDistanceKm,
                    unit: "km"
                )
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)
                phoneMetricCell(
                    label: "ENERGY",
                    value: workoutManager.formattedEnergyKJ,
                    unit: "kJ",
                    color: AppColor.yellow
                )
            }
        }
        .cardStyle()
    }

    private func phoneMetricCell(label: String, value: String, unit: String, color: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(1.0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text(unit)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
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
                    if showRideModeBanner, routeManager.hasRoute {
                        IndoorRideModeContext(
                            hasRoute: true,
                            routeName: routeManager.routeName
                        )
                    }

                    PowerArcView(
                        watts: smoothedWatts,
                        compact: routeManager.hasRoute,
                        showCenterText: true
                    )

                    SmoothedPowerView(
                        avg3s: workoutManager.avg3s,
                        avg5s: workoutManager.avg5s,
                        avg30s: workoutManager.avg30s,
                        compact: routeManager.hasRoute
                    )

                    if routeManager.hasRoute {
                        RouteMiniMapView(
                            distance: workoutManager.activeDistance,
                            mapHeight: 220
                        )
                        ElevationProfileView(
                            currentDistance: workoutManager.activeDistance,
                            height: 72
                        )
                    }

                    PowerGraphView(
                        powerHistory: workoutManager.powerHistory,
                        powerHistoryMax: workoutManager.powerHistoryMax,
                        compact: false
                    )

                    indoorLivePerformanceBar(compact: false, layoutMode: .stacked, collapsible: true)
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
                       workoutManager.state == .recording || workoutManager.state == .paused || workoutManager.state == .autoPaused {
                        guidedSessionCard(condensed: false)
                    }

                    metricsGrid

                    if workoutManager.showLowCadenceWarning {
                        cadenceWarningBanner
                    }

                    goalProgressSection(fit: false)

                    if metrics.heartRate > 0 {
                        HeartRateBarView(
                            heartRate: metrics.heartRate
                        )
                    }

                    if bleManager.ftmsControl.isAvailable, !guidedSession.isActive {
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
            supportsSimulation: bleManager.ftmsControl.supportsSimulation,
            supportsERG: bleManager.ftmsControl.supportsERG,
            supportsResistance: bleManager.ftmsControl.supportsResistance,
            hasRoute: routeManager.hasRoute,
            isWorkoutActive: isActive,
            showRouteSimulationFooterHint: guidedSession.isActive,
            condensed: condensed,
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

    // MARK: - Guided Session Setup

    private func configureGuidedSession() {
        guard let dayID = planDayID, let day = plan.day(id: dayID) else { return }

        guidedSession.configure(planDay: day)

        // Wire trainer mode changes: when the guided session advances to a new step,
        // automatically update the trainer control mode.
        //
        // Engage delay: skip all trainer commands for the first 5 seconds so the
        // rider has time to clip in and start pedalling before ERG/SIM locks in.
        // On freeRide steps we drop to the lowest resistance level (0 %) instead
        // of issuing a full FTMS reset — a reset forces a re-negotiate cycle that
        // causes a brief hard lock before the trainer releases, which feels jarring.
        guidedSession.onTrainerModeChange = { [weak workoutManager] mode, ergWatts, grade in
            guard let wm = workoutManager else { return }
            guard wm.elapsedSeconds >= wm.trainerEngageDelay else { return }

            switch mode {
            case .erg:
                if let watts = ergWatts {
                    wm.setERGMode(watts: watts)
                }
            case .simulation:
                if let grade {
                    wm.setSimulationMode(grade: grade)
                }
            case .freeRide:
                // Drop resistance to zero rather than a full FTMS reset.
                // This lets the trainer coast immediately without the
                // re-negotiate stutter that releaseTrainerControl() causes.
                if wm.bleManager?.ftmsControl.supportsResistance == true {
                    wm.setResistanceMode(level: 0)
                } else {
                    wm.releaseTrainerControl()
                }
            }
        }

        // Wire the WorkoutManager's per-second tick to drive the guided session.
        workoutManager.onTick = { [weak guidedSession] elapsed, power in
            guidedSession?.tick(elapsed: elapsed, currentPower: power)
        }
    }

    // MARK: - Actions

    // MARK: - Delight Helpers

    private func flashMilestone(_ text: String) {
        milestoneText = text
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            milestoneVisible = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.4)) {
                milestoneVisible = false
            }
        }
    }

    private func milestoneToast(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(AppColor.mango)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .modifier(IndoorMilestoneToastChrome(reduceTransparency: accessibilityReduceTransparency))
    }

    private func exitPreRide() {
        guard workoutManager.state == .idle else { return }
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        } else {
            navigationPath = NavigationPath()
        }
    }

    private func discardRide() {
        workoutManager.discardWorkout()
        guidedSession.tearDown()
        bleManager.disconnectAll()

        // Navigate back to the root (home screen).
        navigationPath = NavigationPath()
    }

    private func endRide() {
        workoutManager.endWorkout()

        let workoutIsValid = workoutManager.workout?.isValid ?? false

        // Only mark plan day complete if the workout meets minimum duration.
        // This prevents accidental 3-second starts from counting as "done".
        if let dayID = planDayID, workoutIsValid {
            markPlanDayCompleted(dayID: dayID)
        }

        // Tear down guided session
        guidedSession.tearDown()

        if let workoutID = workoutManager.workout?.id {
            // Replace entire navigation stack with summary
            navigationPath = NavigationPath()
            navigationPath.append(AppRoute.summary(workoutID: workoutID))
        }
    }

    @Query private var allProgress: [TrainingPlanProgress]

    private func markPlanDayCompleted(dayID: String) {
        let resolvedPlanID = planID ?? CachedPlan.shared.id
        if let progress = allProgress.first(where: { $0.planID == resolvedPlanID }) {
            progress.markCompleted(dayID)
            try? modelContext.save()
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

// MARK: - Reduce Transparency (header chrome)

private struct IndoorHeaderBarChrome: ViewModifier {
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(red: 0.04, green: 0.05, blue: 0.08))
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: 0))
        }
    }
}

private struct IndoorGlassOrOpaqueCircle: ViewModifier {
    let useOpaque: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if useOpaque {
            content.background(Circle().fill(Color.white.opacity(0.12)))
        } else {
            content.glassEffect(.regular.interactive(), in: .circle)
        }
    }
}

private struct IndoorMilestoneToastChrome: ViewModifier {
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Capsule().fill(Color(red: 0.08, green: 0.09, blue: 0.12)))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        } else {
            content.glassEffect(.regular, in: .capsule)
        }
    }
}

#Preview("Free Ride") {
    let ble = BLEManager()
    let wifi = WiFiTrainerService()
    let ds = DataSourceCoordinator(bleManager: ble, wifiService: wifi)
    return DashboardView(
        navigationPath: .constant(NavigationPath())
    )
        .modelContainer(for: [Workout.self, WorkoutSample.self, LapSplit.self, TrainingPlanProgress.self], inMemory: true)
        .environment(ble)
        .environment(ds)
        .environment(RouteManager())
        .environment(HealthKitManager())
        .environment(FTPRefreshTrigger.shared)
}

#Preview("Guided Session") {
    let ble = BLEManager()
    let wifi = WiFiTrainerService()
    let ds = DataSourceCoordinator(bleManager: ble, wifiService: wifi)
    return DashboardView(
        navigationPath: .constant(NavigationPath()),
        planDayID: "w2d2"
    )
        .modelContainer(for: [Workout.self, WorkoutSample.self, LapSplit.self, TrainingPlanProgress.self], inMemory: true)
        .environment(ble)
        .environment(ds)
        .environment(RouteManager())
        .environment(HealthKitManager())
        .environment(FTPRefreshTrigger.shared)
}
