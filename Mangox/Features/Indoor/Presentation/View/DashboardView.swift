import SwiftData
import SwiftUI

#if canImport(UIKit)
    import UIKit
    import AudioToolbox
#endif

private enum DashboardViewFontToken {
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let fontName: String
        switch weight {
        case .light:
            fontName = "GeistMono-Light"
        case .medium, .semibold, .bold, .heavy, .black:
            fontName = "GeistMono-Medium"
        default:
            fontName = "GeistMono-Regular"
        }

        #if canImport(UIKit)
            if UIFont(name: fontName, size: size) != nil {
                return .custom(fontName, size: size)
            }
        #endif
        return .system(size: size, weight: weight, design: .monospaced)
    }
}

private enum CompactDashboardPage: String, CaseIterable, Identifiable {
    /// Primary in-ride readout: power, HR mini, zones, goals, secondary metrics.
    case ride
    /// Charts, NP/IF/TSS grid, laps, trainer, and session tools.
    case details

    var id: String { rawValue }

    /// Short segment label — uppercase mono, matches design system wayfinding.
    var segmentLabel: String {
        switch self {
        case .ride: return String(localized: "indoor.dashboard.segment.ride")
        case .details: return String(localized: "indoor.dashboard.segment.details")
        }
    }

    var accessibilitySummary: String {
        switch self {
        case .ride:
            return String(localized: "indoor.dashboard.a11y.page_ride")
        case .details:
            return String(localized: "indoor.dashboard.a11y.page_details")
        }
    }

    var icon: String {
        switch self {
        case .ride: return "figure.outdoor.cycle"
        case .details: return "chart.xyaxis.line"
        }
    }
}

struct DashboardView: View {
    @State private var viewModel: IndoorViewModel
    @State private var compactPage: CompactDashboardPage = .ride
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
    @State private var milestoneTasks: [UUID: Task<Void, Never>] = [:]
    @State private var tipDismissTask: Task<Void, Never>?
    @State private var milestoneHideTask: Task<Void, Never>?
    @State private var persistenceErrorMessage: String?
    private let prefs = RidePreferences.shared
    @AppStorage("indoorMilestoneSoundEnabled") private var indoorMilestoneSoundEnabled = false
    @State private var isScreenLocked = false

    /// Distance goal is surfaced in ``goalProgressSection`` — omit the duplicate distance tile from the grid.
    private var hasActiveDistanceGoal: Bool {
        prefs.activeGoals.contains { $0.kind == .distance }
    }

    /// Hides NP/kJ row + zone strip until effort registers — keeps the first minute glance-first.
    private var showExtendedRideSecondaryUI: Bool {
        if workoutManager.state != .recording { return true }
        return workoutManager.elapsedSeconds >= 45
            || workoutManager.liveNP > 0.5
            || workoutManager.kilojoules > 0.5
            || workoutManager.zoneSecondsByZoneID.values.reduce(0, +) > 3
    }

    private var guidedPowerHeroExtras: (target: String?, status: String?, statusColor: Color) {
        guard guidedSession.isActive,
            workoutManager.state.isLiveSessionActive,
            let step = guidedSession.currentStep,
            let range = guidedSession.scaledTargetWattRange(for: step)
        else { return (nil, nil, AppColor.fg2) }

        let target = String(
            format: String(localized: "indoor.guided.hero.target_format"),
            locale: .current,
            range.lowerBound,
            range.upperBound
        )

        let status: String
        let color: Color
        switch guidedSession.compliance {
        case .inZone:
            status = String(localized: "indoor.guided.status.on_target")
            color = AppColor.success
        case .belowZone:
            let gap = max(0, range.lowerBound - smoothedWatts)
            status = String(format: String(localized: "indoor.guided.status.below_w"), gap)
            color = AppColor.orange
        case .aboveZone:
            let over = max(0, smoothedWatts - range.upperBound)
            status = String(format: String(localized: "indoor.guided.status.above_w"), over)
            color = AppColor.orange
        }
        return (target, status, color)
    }

    /// Route context only — free-ride copy is omitted; mode is obvious from the dashboard.
    private var indoorSessionIntentSubtitle: String? {
        guard isActiveRide else { return nil }
        if guidedSession.isActive { return nil }
        guard viewModel.hasRoute else { return nil }
        if let n = viewModel.routeName, !n.isEmpty {
            return String(format: String(localized: "indoor.intent.route_named"), n)
        }
        return String(localized: "indoor.intent.route")
    }

    /// Compact goal line under the clock — skip distance (already on the Distance card).
    private var headerPinnedGoalLine: String? {
        guard isActiveRide, let g = prefs.activeGoals.first else { return nil }
        if g.kind == .distance { return nil }
        let cur = goalCurrentValue(for: g)
        let tgt = goalTargetValue(for: g)
        return String(
            format: String(localized: "indoor.header.goal_line"),
            g.kind.label,
            cur,
            tgt,
            g.kind.unit
        )
    }

    /// Symmetric side rails so elapsed + status read visually centered between controls and badges.
    private var headerBarSideSlotWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 96 : 82
    }

    /// Whole-km toast + haptic when crossing each multiple (e.g. 5 → 5 km, 10 km, …).
    private static let indoorDistanceMilestoneIntervalKm = 5
    private static let goalValue0Formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.numberStyle = .decimal
        return formatter
    }()
    private static let goalValue2Formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        return formatter
    }()

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

    /// Play/pause lane beside the elapsed clock — links session status to the hero time.
    private var headerSessionVisual: (icon: String, tint: Color, subtitle: String?)? {
        switch workoutManager.state {
        case .recording:
            return ("play.circle.fill", AppColor.mango, nil)
        case .paused:
            return ("pause.circle.fill", AppColor.yellow, String(localized: "indoor.header.status.paused"))
        case .autoPaused:
            return ("pause.circle.fill", AppColor.yellow, String(localized: "indoor.header.status.auto_paused"))
        default:
            return nil
        }
    }

    @ViewBuilder
    private var headerLeadingControl: some View {
        if workoutManager.state == .idle {
            Button {
                exitPreRide()
            } label: {
                Image(systemName: "xmark")
                    .mangoxFont(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.fg1)
                    .frame(width: 30, height: 30)
                    .background(AppColor.hair)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(AppColor.hair2, lineWidth: 0.5))
            }
            .accessibilityLabel(String(localized: "indoor.header.a11y.close_preride"))
        } else if let session = headerSessionVisual {
            Image(systemName: session.icon)
                .font(.title3)
                .foregroundStyle(session.tint)
                .frame(width: 30, height: 30)
                .accessibilityLabel(String(localized: "indoor.header.a11y.session_state"))
                .accessibilityValue(
                    session.subtitle
                        ?? String(localized: "indoor.header.a11y.session_recording"))
        } else {
            Color.clear.frame(width: 30, height: 30)
        }
    }

    var body: some View {
        FTPRefreshScope {
            ZStack {
                Group {
                    if viewModel.hasRoute || accessibilityReduceTransparency {
                        AppColor.bg0
                    } else {
                        LinearGradient(
                            colors: [
                                AppColor.bg2,
                                AppColor.bg0,
                                AppColor.bg1,
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
                        isScreenLocked: $isScreenLocked,
                        onStart: { viewModel.startWorkout() },
                        onPause: { viewModel.pauseWorkout() },
                        onResume: { viewModel.resumeWorkout() },
                        onLap: { viewModel.lapWorkout() },
                        showEndConfirmation: binding(\.showEndConfirmation),
                        showLap: prefs.showLaps
                    )
                    .padding(.horizontal, MangoxSpacing.page)
                    .padding(.vertical, 12)
                }

                if isScreenLocked {
                    screenLockOverlay
                        .zIndex(300)
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
                        colors: [zone.color.opacity(zonePulse ? 0.10 : 0.03), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 120)
                    Spacer()
                    LinearGradient(
                        colors: [.clear, zone.color.opacity(zonePulse ? 0.10 : 0.03)],
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
                    viewModel.resumeWorkout(fromUserControls: false)
                }
            }
            .onChange(of: workoutManager.elapsedSeconds) { _, _ in
                tickRideTipsIfNeeded()
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
        let guidedDuringRide = guidedSession.isActive
            && (workoutManager.state == .recording || workoutManager.state == .paused
                || workoutManager.state == .autoPaused)

        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                headerLeadingControl
                    .frame(width: headerBarSideSlotWidth, alignment: .leading)

                VStack(alignment: .center, spacing: 2) {
                    Text(workoutManager.formattedElapsed)
                        .font(
                            DashboardViewFontToken.mono(
                                size: dynamicTypeSize.isAccessibilitySize
                                    ? 22
                                    : (isActiveRide ? 32 : 26),
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            isActiveRide
                                ? AppColor.fg0
                                : AppColor.fg2
                        )
                        .monospacedDigit()
                        .tracking(0.4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.center)
                        .accessibilityLabel(String(localized: "indoor.header.a11y.elapsed"))
                        .accessibilityValue(workoutManager.formattedElapsed)

                    if let sub = headerSessionVisual?.subtitle {
                        Text(sub)
                            .mangoxFont(.micro)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.yellow.opacity(0.95))
                            .tracking(0.8)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(AppColor.success)
                            .frame(width: 5, height: 5)
                        Text("INDOOR")
                            .mangoxFont(.micro)
                            .fontWeight(.bold)
                            .foregroundStyle(AppColor.fg3)
                            .tracking(1.0)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 12) {
                    DeviceStatusBadge(
                        icon: "bicycle",
                        state: viewModel.trainerLinkDisplayState,
                        fallbackName: "Trainer",
                        isDataStale: viewModel.isTrainerLinkDataStale,
                        iconOnly: true,
                        bare: true
                    )
                    DeviceStatusBadge(
                        icon: "heart.fill",
                        state: viewModel.hrConnectionState,
                        fallbackName: "HR",
                        iconOnly: true,
                        bare: true
                    )
                }
                .frame(width: headerBarSideSlotWidth, alignment: .trailing)
            }
            .padding(.horizontal, MangoxSpacing.page)
            .padding(.top, guidedDuringRide ? 8 : 10)
            .padding(.bottom, 6)

            if isActiveRide,
                indoorSessionIntentSubtitle != nil || headerPinnedGoalLine != nil
                    || viewModel.isTrainerLinkDataStale
            {
                VStack(spacing: 3) {
                    if let intent = indoorSessionIntentSubtitle {
                        Text(intent)
                            .mangoxFont(.micro)
                            .foregroundStyle(AppColor.fg2)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                    }
                    if let goalLine = headerPinnedGoalLine {
                        Text(goalLine)
                            .mangoxFont(.micro)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.fg1.opacity(0.92))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.88)
                            .frame(maxWidth: .infinity)
                    }
                    if viewModel.isTrainerLinkDataStale {
                        Text(String(localized: "indoor.sensor.trainer_stale"))
                            .mangoxFont(.micro)
                            .foregroundStyle(AppColor.yellow.opacity(0.95))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, MangoxSpacing.page)
                .padding(.bottom, 4)
            }

            if guidedSession.isActive {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("GUIDED")
                            .mangoxFont(.micro)
                            .fontWeight(.bold)
                            .foregroundStyle(AppColor.mango)
                            .tracking(1.2)
                        Text(guidedSession.dayTitle)
                            .mangoxFont(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.fg0)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, MangoxSpacing.page)
                }
                .padding(.top, 2)
                .padding(.bottom, guidedDuringRide ? 4 : 8)
            }

            if guidedDuringRide {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(AppColor.hair)
                        Rectangle()
                            .fill(AppColor.mango)
                            .frame(width: max(0, geo.size.width * guidedSession.overallProgress))
                            .animation(
                                .easeInOut(duration: 0.5), value: guidedSession.overallProgress)
                    }
                }
                .frame(height: 3)
            }

            Rectangle()
                .fill(AppColor.hair)
                .frame(height: 1)
        }
        .background(AppColor.bg1.opacity(0.96))
    }

    // MARK: - End / discard (matches outdoor `endDiscardOverlays` chrome)

    private var indoorEndWorkoutOverlay: some View {
        MangoxConfirmOverlay(
            title: "End workout?",
            message:
                "We’ll open the summary next so you can review power, heart rate, and time — or discard this session with no save.",
            onDismiss: { viewModel.dismissEndConfirmation() }
        ) {
            MangoxConfirmDualButtonRow(
                cancelTitle: "Cancel",
                confirmTitle: "End & Save",
                trailingStyle: .hero,
                onCancel: { viewModel.dismissEndConfirmation() },
                onConfirm: { endRide() }
            )

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
            MangoxConfirmDualButtonRow(
                cancelTitle: "Not now",
                confirmTitle: "Enable Essentials",
                trailingStyle: .hero,
                onCancel: { viewModel.applyRideTipsOnboardingDecline(prefs: prefs) },
                onConfirm: { viewModel.applyRideTipsOnboardingEnable(prefs: prefs) }
            )
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

    private var screenLockOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(AppColor.fg2)

                Text("Screen Locked")
                    .mangoxFont(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColor.fg0)

                Text("Tap and hold to unlock")
                    .mangoxFont(.callout)
                    .foregroundStyle(AppColor.fg3)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            withAnimation(.easeOut(duration: 0.2)) {
                                isScreenLocked = false
                            }
                        }
                )
        )
        .allowsHitTesting(true)
    }

    // MARK: - Compact Layout (iPhone)

    /// Apple Workout-inspired compact layout: split live riding data into focused pages
    /// so the rider can swipe instead of scanning one overloaded vertical stack.
    private var compactLayout: some View {
        compactPagedLayout(isLandscape: false)
    }

    private var compactLandscapeLayout: some View {
        compactPagedLayout(isLandscape: true)
    }

    private func compactPagedLayout(isLandscape: Bool) -> some View {
        VStack(spacing: 0) {
            compactDashboardPageStrip(isLandscape: isLandscape)

            TabView(selection: $compactPage) {
                compactRidePage(isLandscape: isLandscape)
                    .tag(CompactDashboardPage.ride)
                compactDetailsPage(isLandscape: isLandscape)
                    .tag(CompactDashboardPage.details)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .onChange(of: compactPage) { _, new in
            IndoorDashboardAnalytics.compactTabChanged(new.rawValue)
        }
    }

    /// Single wayfinding control: thin segmented strip + swipe. Hides system page dots (no duplicate chrome).
    private func compactDashboardPageStrip(isLandscape: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(CompactDashboardPage.allCases) { page in
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        compactPage = page
                    }
                } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 4) {
                            Image(systemName: page.icon)
                                .mangoxFont(.micro)
                                .foregroundStyle(compactPage == page ? AppColor.mango : AppColor.fg3)
                            Text(page.segmentLabel)
                                .font(DashboardViewFontToken.mono(size: isLandscape ? 10 : 11, weight: .semibold))
                                .foregroundStyle(compactPage == page ? AppColor.fg0 : AppColor.fg3)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, isLandscape ? 6 : 8)

                        Rectangle()
                            .fill(compactPage == page ? AppColor.mango : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(page.accessibilitySummary)
                .accessibilityAddTraits(compactPage == page ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, MangoxSpacing.page)
        .background(AppColor.bg1.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColor.hair)
                .frame(height: 1)
        }
        .padding(.top, isLandscape ? 2 : 4)
    }

    private func compactRidePage(isLandscape: Bool) -> some View {
        GeometryReader { _ in
            ViewThatFits(in: .vertical) {
                compactRideLayout(isLandscape: isLandscape, dense: false)
                compactRideLayout(isLandscape: isLandscape, dense: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, MangoxSpacing.page)
            .padding(.vertical, isLandscape ? 6 : 8)
        }
    }

    /// Optional NP / work line once effort registers — keeps the ride page focused on the hero readout.
    @ViewBuilder
    private func compactRideEffortHintRow() -> some View {
        if workoutManager.liveNP > 0.5 || workoutManager.kilojoules > 0.5 {
            HStack(spacing: 10) {
                if workoutManager.liveNP > 0.5 {
                    HStack(spacing: 4) {
                        Text("NP")
                            .mangoxFont(.micro)
                            .fontWeight(.bold)
                            .foregroundStyle(AppColor.fg3)
                        Text(workoutManager.formattedLiveNP)
                            .font(DashboardViewFontToken.mono(size: 13, weight: .bold))
                            .foregroundStyle(AppColor.mango)
                        Text("W")
                            .mangoxFont(.micro)
                            .foregroundStyle(AppColor.fg3)
                    }
                }
                if workoutManager.kilojoules > 0.5 {
                    HStack(spacing: 4) {
                        Text(String(localized: "indoor.dashboard.snapshot.kj"))
                            .mangoxFont(.micro)
                            .fontWeight(.bold)
                            .foregroundStyle(AppColor.fg3)
                        Text(workoutManager.formattedEnergyKJ)
                            .font(DashboardViewFontToken.mono(size: 13, weight: .bold))
                            .foregroundStyle(AppColor.yellow.opacity(0.95))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppColor.hair.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue))
            .overlay(
                RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue)
                    .strokeBorder(AppColor.hair2, lineWidth: 1)
            )
        }
    }

    private func rideBlockSpacing(dense: Bool) -> CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return dense ? 10 : 12
        }
        return dense ? 7 : 9
    }

    private func compactRideLayout(isLandscape: Bool, dense: Bool) -> some View {
        let blockSpacing = rideBlockSpacing(dense: dense)
        return VStack(spacing: blockSpacing) {
            if isLandscape {
                HStack(alignment: .top, spacing: dense ? 8 : 10) {
                    VStack(spacing: blockSpacing) {
                        if guidedSession.isActive {
                            compactGuidedStatusCard(dense: dense)
                        }
                        compactPowerStageCard()
                        if showExtendedRideSecondaryUI {
                            compactRideEffortHintRow()
                            IndoorZoneDistributionStrip(
                                zoneSecondsByZoneID: workoutManager.zoneSecondsByZoneID,
                                compact: dense
                            )
                        }
                        if !prefs.activeGoals.isEmpty {
                            goalProgressSection(fit: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    VStack(spacing: blockSpacing) {
                        compactPrimaryMetricsGrid(dense: dense)
                        compactLiveNoticeBlock(dense: dense)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            } else {
                if guidedSession.isActive {
                    compactGuidedStatusCard(dense: dense)
                }
                compactPowerStageCard()
                compactPrimaryMetricsGrid(dense: dense)
                if showExtendedRideSecondaryUI {
                    compactRideEffortHintRow()
                    IndoorZoneDistributionStrip(
                        zoneSecondsByZoneID: workoutManager.zoneSecondsByZoneID,
                        compact: dense
                    )
                }
                if !prefs.activeGoals.isEmpty {
                    goalProgressSection(fit: true)
                }
                compactLiveNoticeBlock(dense: dense)
            }
        }
    }

    private func compactDetailsPage(isLandscape: Bool) -> some View {
        let chartH = compactDetailsPowerChartHeight(isLandscape: isLandscape)
        return ZStack(alignment: .bottom) {
            ScrollView {
                compactDetailsLayout(
                    isLandscape: isLandscape,
                    dense: true,
                    chartHeight: chartH
                )
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppColor.bg1.opacity(0.28))

            LinearGradient(
                colors: [
                    .clear,
                    AppColor.bg0.opacity(0.5),
                    AppColor.bg0.opacity(0.85),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 36)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, MangoxSpacing.page)
        .padding(.vertical, isLandscape ? 6 : 8)
    }

    /// Short fixed height so Details scrolls comfortably above the ride control bar.
    private func compactDetailsPowerChartHeight(isLandscape: Bool) -> CGFloat {
        isLandscape ? 88 : 100
    }

    /// Linear “hero” snapshot for Details — avoids the large arc gauge while keeping live power readable.
    private func compactDetailsPowerSnapshotCard() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(smoothedWatts)")
                    .font(DashboardViewFontToken.mono(size: 34, weight: .black))
                    .foregroundStyle(zone.color)
                    .contentTransition(.numericText())
                Text("W")
                    .font(.title3)
                    .foregroundStyle(AppColor.fg3)
                Spacer(minLength: 0)
                Text(zone.name.uppercased())
                    .mangoxFont(.micro)
                    .fontWeight(.bold)
                    .foregroundStyle(zone.color)
                    .tracking(0.9)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColor.hair2)
                    Capsule()
                        .fill(zone.color)
                        .frame(
                            width: max(
                                4,
                                geo.size.width * min(Double(smoothedWatts) / 500.0, 1.0)
                            )
                        )
                        .animation(.easeOut(duration: 0.3), value: smoothedWatts)
                }
            }
            .frame(height: 5)
            Text(powerZoneRangeText)
                .font(DashboardViewFontToken.mono(size: 11, weight: .medium))
                .foregroundStyle(AppColor.fg3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppColor.bg2)
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue)
                .strokeBorder(AppColor.hair2, lineWidth: 1)
        )
    }

    private func compactDetailsLayout(isLandscape: Bool, dense: Bool, chartHeight: CGFloat) -> some View {
        let mapHeight: CGFloat = isLandscape ? (dense ? 92 : 100) : (dense ? 112 : 120)
        let elevationHeight: CGFloat = isLandscape ? (dense ? 32 : 36) : (dense ? 36 : 40)

        let sessionStats: some View = SessionStatsMetricGrid(
            formattedNP: workoutManager.formattedLiveNP,
            formattedIF: workoutManager.formattedLiveIF,
            formattedTSS: workoutManager.formattedLiveTSS,
            formattedVI: workoutManager.formattedVI,
            formattedAvgPower: workoutManager.formattedAvgPower,
            formattedEfficiency: workoutManager.formattedEfficiency,
            formattedKJ: workoutManager.formattedKJ,
            showEfficiency: viewModel.liveHeartRateBpm > 0,
            ftpIsSet: PowerZone.hasSetFTP,
            compact: dense
        )

        return VStack(spacing: dense ? 7 : 9) {
            if isLandscape {
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 8) {
                        if viewModel.hasRoute {
                            RouteMiniMapView(
                                routeService: viewModel.routeService,
                                distance: workoutManager.activeDistance,
                                mapHeight: mapHeight
                            )
                            ElevationProfileView(
                                routeService: viewModel.routeService,
                                currentDistance: workoutManager.activeDistance,
                                height: elevationHeight
                            )
                        } else {
                            compactDetailsPowerSnapshotCard()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    VStack(spacing: 8) {
                        sessionStats
                        PowerGraphView(
                            powerHistory: workoutManager.powerHistory,
                            powerHistoryMax: workoutManager.powerHistoryMax,
                            compact: true,
                            chartHeightCompact: chartHeight,
                            flatStrip: true,
                            showTimeframeHint: true
                        )
                        IndoorPeakEffortsRow(peakPowers: workoutManager.peakPowers)
                        if prefs.showLaps {
                            currentLapSummaryCard(dense: dense)
                        }
                        IndoorZoneDistributionStrip(
                            zoneSecondsByZoneID: workoutManager.zoneSecondsByZoneID,
                            compact: dense
                        )
                        compactDetailsSessionControlsBlock(isLandscape: isLandscape, dense: dense, minimal: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            } else if viewModel.hasRoute {
                if showRideModeBanner, !dense {
                    IndoorRideModeContext(
                        hasRoute: true,
                        routeName: viewModel.routeName,
                        compact: true
                    )
                }

                RouteMiniMapView(
                    routeService: viewModel.routeService,
                    distance: workoutManager.activeDistance,
                    mapHeight: mapHeight
                )
                ElevationProfileView(
                    routeService: viewModel.routeService,
                    currentDistance: workoutManager.activeDistance,
                    height: elevationHeight
                )
                PowerGraphView(
                    powerHistory: workoutManager.powerHistory,
                    powerHistoryMax: workoutManager.powerHistoryMax,
                    compact: true,
                    chartHeightCompact: chartHeight,
                    flatStrip: true,
                    showTimeframeHint: true
                )
                IndoorPeakEffortsRow(peakPowers: workoutManager.peakPowers)
                sessionStats
                if prefs.showLaps {
                    currentLapSummaryCard(dense: dense)
                }
                IndoorZoneDistributionStrip(
                    zoneSecondsByZoneID: workoutManager.zoneSecondsByZoneID,
                    compact: dense
                )
                compactDetailsSessionControlsBlock(isLandscape: isLandscape, dense: dense, minimal: dense)
            } else {
                sessionStats
                PowerGraphView(
                    powerHistory: workoutManager.powerHistory,
                    powerHistoryMax: workoutManager.powerHistoryMax,
                    compact: true,
                    chartHeightCompact: chartHeight,
                    flatStrip: true,
                    showTimeframeHint: true
                )
                IndoorPeakEffortsRow(peakPowers: workoutManager.peakPowers)
                compactDetailsPowerSnapshotCard()
                if prefs.showLaps {
                    currentLapSummaryCard(dense: dense)
                }
                IndoorZoneDistributionStrip(
                    zoneSecondsByZoneID: workoutManager.zoneSecondsByZoneID,
                    compact: dense
                )
                compactDetailsSessionControlsBlock(isLandscape: isLandscape, dense: dense, minimal: dense)
            }
        }
    }

    /// Hardware, guided intervals, laps — lives on **Details** so Ride stays glance-first.
    private func compactDetailsSessionControlsBlock(isLandscape: Bool, dense: Bool, minimal: Bool) -> some View {
        let showGuidedSession = guidedSession.isActive
            && (workoutManager.state == .recording || workoutManager.state == .paused
                || workoutManager.state == .autoPaused)
        let showLaps = prefs.showLaps
        let showTrainerControls = viewModel.ftmsControlIsAvailable
        let hasControls = showGuidedSession || showLaps || showTrainerControls

        return VStack(spacing: dense ? 8 : 10) {
            if !minimal, showRideModeBanner, !viewModel.hasRoute {
                HStack(alignment: .center, spacing: 8) {
                    IndoorRideModeContext(
                        hasRoute: false,
                        routeName: nil,
                        compact: true
                    )
                    Spacer(minLength: 0)
                    indoorSessionConfigMenu(
                        showGuidedSession: showGuidedSession,
                        showLaps: showLaps,
                        showTrainerControls: showTrainerControls
                    )
                }
            } else if !minimal {
                HStack {
                    Spacer(minLength: 0)
                    indoorSessionConfigMenu(
                        showGuidedSession: showGuidedSession,
                        showLaps: showLaps,
                        showTrainerControls: showTrainerControls
                    )
                }
            }

            if isLandscape && !minimal {
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 8) {
                        if showTrainerControls {
                            trainerControlCard(condensed: true)
                        }
                        if showLaps {
                            LapCardView(
                                lapNumber: workoutManager.currentLapNumber,
                                currentAvgPower: workoutManager.currentLapAvgPower,
                                currentDuration: workoutManager.currentLapDuration,
                                previousAvgPower: workoutManager.previousLapAvgPower,
                                previousDuration: workoutManager.previousLapDuration,
                                compact: true
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    VStack(spacing: 8) {
                        if showGuidedSession {
                            compactGuidedStatusCard(dense: dense)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            } else {
                if showGuidedSession {
                    compactGuidedStatusCard(dense: dense)
                }

                if showTrainerControls {
                    trainerControlCard(condensed: true)
                }

                if showLaps {
                    LapCardView(
                        lapNumber: workoutManager.currentLapNumber,
                        currentAvgPower: workoutManager.currentLapAvgPower,
                        currentDuration: workoutManager.currentLapDuration,
                        previousAvgPower: workoutManager.previousLapAvgPower,
                        previousDuration: workoutManager.previousLapDuration,
                        compact: true
                    )
                }
            }

            if !hasControls, !minimal {
                compactSessionPagePlaceholder(hasTrainerFTMS: showTrainerControls)
            }
        }
    }

    private func indoorSessionConfigMenu(
        showGuidedSession: Bool,
        showLaps: Bool,
        showTrainerControls: Bool
    ) -> some View {
        Menu {
            Section(String(localized: "indoor.dashboard.session.menu.status_section")) {
                Label(
                    showGuidedSession
                        ? String(localized: "indoor.dashboard.session.menu.guided_on")
                        : String(localized: "indoor.dashboard.session.menu.guided_off"),
                    systemImage: "figure.indoor.cycle"
                )
                Label(
                    showLaps
                        ? String(localized: "indoor.dashboard.session.menu.laps_on")
                        : String(localized: "indoor.dashboard.session.menu.laps_off"),
                    systemImage: "flag.fill"
                )
                Label(
                    showTrainerControls
                        ? String(localized: "indoor.dashboard.session.menu.ftms_ready")
                        : String(localized: "indoor.dashboard.session.menu.ftms_unavailable"),
                    systemImage: "gearshape.2"
                )
            }
            Section(String(localized: "indoor.dashboard.session.menu.hint_section")) {
                Text(String(localized: "indoor.dashboard.session.menu.hint_body"))
            }
            Section {
                Toggle(String(localized: "indoor.dashboard.milestone_sound"), isOn: $indoorMilestoneSoundEnabled)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(AppColor.fg2)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(String(localized: "indoor.dashboard.session.menu.a11y"))
    }

    /// Elapsed · work done · intensity — always-visible on the Session page while the clock is running.
    /// Complements the header clock — load, intensity, and average power for the Session tab.
    private func compactSessionSnapshotRow() -> some View {
        HStack(spacing: 8) {
            compactHeroChip(
                label: String(localized: "indoor.dashboard.snapshot.kj"),
                value: workoutManager.formattedEnergyKJ,
                tint: AppColor.yellow
            )
            compactHeroChip(
                label: String(localized: "indoor.dashboard.snapshot.np"),
                value: workoutManager.formattedLiveNP,
                tint: AppColor.mango
            )
            compactHeroChip(
                label: String(localized: "indoor.dashboard.snapshot.avg"),
                value: workoutManager.formattedAvgPower,
                tint: AppColor.fg0
            )
        }
    }

    private func compactSessionPagePlaceholder(hasTrainerFTMS: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "indoor.dashboard.session.placeholder_title"))
                .mangoxFont(.label)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.fg2)
                .tracking(0.8)
            Text(String(localized: "indoor.dashboard.session.placeholder_body"))
                .mangoxFont(.caption)
                .foregroundStyle(AppColor.fg3)
                .fixedSize(horizontal: false, vertical: true)
            if !hasTrainerFTMS {
                Text(String(localized: "indoor.dashboard.session.placeholder_ftms"))
                    .mangoxFont(.micro)
                    .foregroundStyle(AppColor.fg4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(AppColor.hair)
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue)
                .strokeBorder(AppColor.hair2, lineWidth: 1)
        )
    }

    // MARK: - Phone Compact Helpers

    @ViewBuilder
    private func compactLiveNoticeBlock(dense: Bool) -> some View {
        if workoutManager.showLowCadenceWarning {
            cadenceWarningBanner
        }

        if let tip = viewModel.activeRideTip {
            compactRideTipInline(tip, dense: dense)
        } else if showRideModeBanner, viewModel.hasRoute, !dense {
            IndoorRideModeContext(
                hasRoute: true,
                routeName: viewModel.routeName,
                compact: true
            )
        }
    }

    private func compactPowerStageCard() -> some View {
        phonePowerDisplay
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [
                        AppColor.mango.opacity(0.08),
                        AppColor.bg2,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue))
            .overlay(
                RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue)
                    .strokeBorder(AppColor.hair2, lineWidth: 1)
            )
    }

    @ViewBuilder
    private func compactPrimaryMetricsGrid(dense: Bool) -> some View {
        let gridSpacing: CGFloat = dynamicTypeSize.isAccessibilitySize ? 10 : 8
        let hrZone = viewModel.liveHeartRateBpm > 0 ? HeartRateZone.zone(for: viewModel.liveHeartRateBpm) : nil

        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: gridSpacing) {
                compactPrimaryMetricTile(
                    icon: "heart.fill",
                    label: "HEART RATE",
                    value: viewModel.liveHeartRateBpm > 0 ? "\(viewModel.liveHeartRateBpm)" : "—",
                    unit: "bpm",
                    tint: hrZone?.color ?? AppColor.fg0,
                    dense: dense,
                    edgeColor: hrZone?.color,
                    isSearching: viewModel.liveHeartRateBpm == 0 && workoutManager.state == .recording
                )
                compactPrimaryMetricTile(
                    icon: "figure.outdoor.cycle",
                    label: "CADENCE",
                    value: workoutManager.formattedCadence,
                    unit: "rpm",
                    tint: AppColor.blue,
                    dense: dense
                )
                compactPrimaryMetricTile(
                    icon: "speedometer",
                    label: "SPEED",
                    value: workoutManager.formattedSpeed,
                    unit: speedUnitLabel,
                    tint: AppColor.fg3,
                    dense: dense
                )
                compactPrimaryMetricTile(
                    icon: "bolt.fill",
                    label: String(localized: "indoor.dashboard.tile.work"),
                    value: workoutManager.formattedEnergyKJ,
                    unit: "kJ",
                    tint: AppColor.yellow,
                    dense: dense
                )
                compactPrimaryMetricTile(
                    icon: "chart.xyaxis.line",
                    label: "AVG POWER",
                    value: workoutManager.formattedAvgPower,
                    unit: "W",
                    tint: AppColor.fg0,
                    dense: dense
                )
                compactPrimaryMetricTile(
                    icon: "bolt.horizontal.fill",
                    label: "NP",
                    value: workoutManager.formattedLiveNP,
                    unit: "W",
                    tint: AppColor.mango,
                    dense: dense
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: gridSpacing
            ) {
                compactPrimaryMetricTile(
                    icon: "heart.fill",
                    label: "HEART RATE",
                    value: viewModel.liveHeartRateBpm > 0 ? "\(viewModel.liveHeartRateBpm)" : "—",
                    unit: "bpm",
                    tint: hrZone?.color ?? AppColor.fg0,
                    dense: dense,
                    edgeColor: hrZone?.color,
                    isSearching: viewModel.liveHeartRateBpm == 0 && workoutManager.state == .recording
                )
                compactPrimaryMetricTile(
                    icon: "figure.outdoor.cycle",
                    label: "CADENCE",
                    value: workoutManager.formattedCadence,
                    unit: "rpm",
                    tint: AppColor.blue,
                    dense: dense
                )
                compactPrimaryMetricTile(
                    icon: "speedometer",
                    label: "SPEED",
                    value: workoutManager.formattedSpeed,
                    unit: speedUnitLabel,
                    tint: AppColor.fg3,
                    dense: dense
                )
                compactPrimaryMetricTile(
                    icon: "bolt.fill",
                    label: String(localized: "indoor.dashboard.tile.work"),
                    value: workoutManager.formattedEnergyKJ,
                    unit: "kJ",
                    tint: AppColor.yellow,
                    dense: dense
                )
                compactPrimaryMetricTile(
                    icon: "chart.xyaxis.line",
                    label: "AVG POWER",
                    value: workoutManager.formattedAvgPower,
                    unit: "W",
                    tint: AppColor.fg0,
                    dense: dense
                )
                compactPrimaryMetricTile(
                    icon: "bolt.horizontal.fill",
                    label: "NP",
                    value: workoutManager.formattedLiveNP,
                    unit: "W",
                    tint: AppColor.mango,
                    dense: dense
                )
            }
        }
    }

    private func metricTileVerticalPadding(dense: Bool) -> CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return dense ? 10 : 12
        }
        return dense ? 8 : 10
    }

    private func metricTileMinHeight(dense: Bool) -> CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return dense ? 76 : 88
        }
        return dense ? 70 : 82
    }

    private func compactPrimaryMetricTile(
        icon: String,
        label: String,
        value: String,
        unit: String,
        tint: Color,
        dense: Bool,
        valueSize: CGFloat? = nil,
        edgeColor: Color? = nil,
        isSearching: Bool = false
    ) -> some View {
        let defaultValueSize: CGFloat = dense ? 20 : 24
        let resolvedValueSize = valueSize ?? defaultValueSize

        return HStack(spacing: 0) {
            if let edgeColor {
                Rectangle()
                    .fill(edgeColor.opacity(0.7))
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue))
            }

            VStack(alignment: .leading, spacing: dense ? 4 : 6) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: dense ? 10 : 11, weight: .semibold))
                        .foregroundStyle(AppColor.fg3)
                    Text(label)
                        .mangoxFont(.micro)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColor.fg3)
                        .tracking(1.0)
                }

                if isSearching {
                    HStack(spacing: 4) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: resolvedValueSize * 0.5, weight: .semibold))
                            .foregroundStyle(AppColor.fg3)
                            .symbolEffect(.pulse, options: .repeating)
                        Text("Searching…")
                            .font(DashboardViewFontToken.mono(size: resolvedValueSize * 0.65, weight: .semibold))
                            .foregroundStyle(AppColor.fg3)
                    }
                } else {
                    Text(value)
                        .font(DashboardViewFontToken.mono(size: resolvedValueSize, weight: .bold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }

                Text(unit)
                    .mangoxFont(.micro)
                    .foregroundStyle(AppColor.fg3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, metricTileVerticalPadding(dense: dense))
        }
        .frame(minHeight: metricTileMinHeight(dense: dense))
        .background(AppColor.bg2)
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue)
                .strokeBorder(AppColor.hair2, lineWidth: 1)
        )
    }

    private func compactRideTipInline(_ tip: RideNudgeDisplay, dense: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .mangoxFont(.micro)
                .foregroundStyle(AppColor.mango)

            VStack(alignment: .leading, spacing: 2) {
                Text(tip.headline.uppercased())
                    .mangoxFont(.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.mango.opacity(0.9))
                    .tracking(0.6)
                Text(tip.body)
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg2)
                    .lineLimit(dense ? 1 : 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                viewModel.clearRideTip()
            } label: {
                Image(systemName: "xmark")
                    .mangoxFont(.micro)
                    .foregroundStyle(AppColor.fg3)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss tip")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppColor.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue)
                .strokeBorder(AppColor.hair2, lineWidth: 1)
        )
    }

    private func compactHeroChip(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .mangoxFont(.micro)
                .fontWeight(.bold)
                .foregroundStyle(AppColor.fg3)
                .tracking(1.1)
            Text(value)
                .font(DashboardViewFontToken.mono(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppColor.hair)
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue)
                .strokeBorder(AppColor.hair2, lineWidth: 1)
        )
    }

    // MARK: - Current Lap Summary Card

    /// Compact lap summary for the Details page — shows current lap avg power, HR, and elapsed time.
    private func currentLapSummaryCard(dense: Bool) -> some View {
        let lapPower = workoutManager.currentLapAvgPower
        let lapDuration = workoutManager.currentLapDuration
        let hasData = lapDuration > 0

        return VStack(alignment: .leading, spacing: dense ? 6 : 8) {
            HStack(spacing: 6) {
                Image(systemName: "flag.fill")
                    .mangoxFont(.micro)
                    .foregroundStyle(AppColor.blue)
                Text("LAP \(workoutManager.currentLapNumber)")
                    .mangoxFont(.micro)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColor.fg3)
                    .tracking(1.2)
                Spacer(minLength: 0)
                Text(GuidedSessionManager.formatCountdown(Int(lapDuration)))
                    .font(DashboardViewFontToken.mono(size: dense ? 12 : 13, weight: .semibold))
                    .foregroundStyle(AppColor.fg1)
            }

            if hasData {
                HStack(spacing: 12) {
                    compactHeroChip(
                        label: "AVG POWER",
                        value: "\(Int(lapPower.rounded()))W",
                        tint: lapPower > 0 ? PowerZone.zone(for: Int(lapPower.rounded())).color : AppColor.fg3
                    )
                    compactHeroChip(
                        label: "AVG HR",
                        value: workoutManager.currentLapAvgHR > 0 ? "\(Int(workoutManager.currentLapAvgHR.rounded()))bpm" : "—",
                        tint: workoutManager.currentLapAvgHR > 0 ? HeartRateZone.zone(for: Int(workoutManager.currentLapAvgHR.rounded())).color : AppColor.fg3
                    )
                }
            } else {
                Text("Start pedaling to see lap data")
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, dense ? 8 : 10)
        .background(AppColor.bg2)
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue)
                .strokeBorder(AppColor.hair2, lineWidth: 1)
        )
    }

    private func compactGuidedStatusCard(dense: Bool) -> some View {
        let step = guidedSession.currentStep
        let zoneColor = step?.zone.color ?? AppColor.mango
        let nextStep = guidedSession.nextStep

        return VStack(alignment: .leading, spacing: dense ? 6 : 8) {
            HStack(spacing: 6) {
                Image(systemName: "figure.indoor.cycle")
                    .mangoxFont(.micro)
                    .foregroundStyle(zoneColor)
                Text("GUIDED")
                    .mangoxFont(.micro)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColor.fg3)
                    .tracking(1.2)
                Spacer(minLength: 0)
                let isUrgent = guidedSession.stepSecondsRemaining <= 10 && guidedSession.stepSecondsRemaining > 0
                Text(GuidedSessionManager.formatCountdown(guidedSession.stepSecondsRemaining))
                    .font(DashboardViewFontToken.mono(size: isUrgent ? (dense ? 16 : 18) : (dense ? 12 : 13), weight: isUrgent ? .bold : .semibold))
                    .foregroundStyle(isUrgent ? AppColor.red : zoneColor)
                    .animation(.easeInOut(duration: 0.3), value: isUrgent)
            }

            Text(step?.label ?? guidedSession.dayTitle)
                .mangoxFont(.label)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.fg1)
                .lineLimit(dense ? 1 : 2)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if let watts = step?.ergTargetWatts {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(GuidedSessionManager.formatCountdown(step?.durationSeconds ?? 0))")
                                .font(DashboardViewFontToken.mono(size: dense ? 12 : 13, weight: .semibold))
                                .foregroundStyle(AppColor.fg0)
                            Text("@ \(watts)W")
                                .mangoxFont(.caption)
                                .foregroundStyle(AppColor.fg2)
                        }
                    }
                }
                Spacer(minLength: 0)
                if let next = nextStep {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Next")
                            .mangoxFont(.micro)
                            .fontWeight(.bold)
                            .foregroundStyle(AppColor.fg3)
                            .tracking(0.8)
                        Text("\(GuidedSessionManager.formatCountdown(next.durationSeconds)) \(next.label)")
                            .mangoxFont(.caption)
                            .foregroundStyle(AppColor.fg2)
                            .lineLimit(1)
                    }
                }
            }

            HStack(spacing: 6) {
                compactHeroChip(
                    label: "ZONE",
                    value: step?.zone.label ?? "Steady",
                    tint: zoneColor
                )
                compactHeroChip(
                    label: "IN ZONE",
                    value: "\(Int(guidedSession.stepInZonePercent.rounded()))%",
                    tint: guidedSession.compliance == .inZone ? AppColor.success : AppColor.orange
                )
            }

            GeometryReader { geo in
                let stepCount = max(1, guidedSession.timeline.count)
                let segmentWidth = geo.size.width / CGFloat(stepCount)
                let currentStepIndex = guidedSession.currentStepIndex

                HStack(spacing: 2) {
                    ForEach(0..<stepCount, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(segmentColor(for: index, currentStepIndex: currentStepIndex, zoneColor: zoneColor))
                            .frame(width: max(1, segmentWidth - 2))
                            .animation(.easeInOut(duration: 0.3), value: currentStepIndex)
                    }
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, dense ? 8 : 10)
        .background(AppColor.bg2)
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue)
                .strokeBorder(zoneColor.opacity(0.2), lineWidth: 1)
        )
    }

    private func segmentColor(for index: Int, currentStepIndex: Int, zoneColor: Color) -> Color {
        if index < currentStepIndex {
            return zoneColor.opacity(0.6)
        } else if index == currentStepIndex {
            return zoneColor
        } else {
            return AppColor.hair
        }
    }

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
                showEfficiency: viewModel.liveHeartRateBpm > 0,
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
                showEfficiency: viewModel.liveHeartRateBpm > 0,
                ftpIsSet: PowerZone.hasSetFTP,
                compact: compact,
                layoutMode: layoutMode
            )
        }
    }

    private var phonePowerDisplay: some View {
        let guided = guidedPowerHeroExtras
        return PhonePowerDisplay(
            smoothedWatts: smoothedWatts,
            zone: zone,
            pctFTP: pctFTP,
            powerZoneRangeText: powerZoneRangeText,
            avg3s: workoutManager.avg3s,
            guidedTargetText: guided.target,
            guidedStatusText: guided.status,
            guidedStatusColor: guided.statusColor
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
        .cardStyle(cornerRadius: MangoxRadius.sharp.rawValue)
    }

    private func phoneMetricCell(label: String, value: String, unit: String, color: Color = .white)
        -> some View
    {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .mangoxFont(.label)
                .fontWeight(.medium)
                .foregroundStyle(AppColor.fg3)
                .tracking(1.0)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(
                            DashboardViewFontToken.mono(
                                size: dynamicTypeSize.isAccessibilitySize ? 22 : 26,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(unit)
                        .mangoxFont(.caption)
                        .foregroundStyle(AppColor.fg3)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(
                            DashboardViewFontToken.mono(
                                size: dynamicTypeSize.isAccessibilitySize ? 22 : 26,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(unit)
                        .mangoxFont(.caption)
                        .foregroundStyle(AppColor.fg3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MangoxSpacing.page)
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
                .padding(.horizontal, MangoxSpacing.page)
                .padding(.vertical, 16)
            }
            .frame(width: 380)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(AppColor.hair)
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

                    if viewModel.liveHeartRateBpm > 0 {
                        HeartRateBarView(
                            heartRate: viewModel.liveHeartRateBpm
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
                .padding(MangoxSpacing.page)
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
            return Self.formatGoalNumber(workoutManager.activeDistance / 1000.0, decimals: 2)
        case .duration:
            return String(Int((Double(workoutManager.elapsedSeconds) / 60.0).rounded()))
        case .kilojoules:
            return Self.formatGoalNumber(workoutManager.kilojoules, decimals: 0)
        case .tss:
            return Self.formatGoalNumber(workoutManager.liveTSS, decimals: 0)
        }
    }

    private func goalTargetValue(for goal: RideGoal) -> String {
        switch goal.kind {
        case .distance:
            return Self.formatGoalNumber(goal.target, decimals: 2)
        case .duration:
            return Self.formatGoalNumber(goal.target, decimals: 0)
        case .kilojoules:
            return Self.formatGoalNumber(goal.target, decimals: 0)
        case .tss:
            return Self.formatGoalNumber(goal.target, decimals: 0)
        }
    }

    private static func formatGoalNumber(_ value: Double, decimals: Int) -> String {
        let formatter = (decimals == 0) ? goalValue0Formatter : goalValue2Formatter
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    // MARK: - Cadence Warning

    private var cadenceWarningBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .mangoxFont(.caption)
            Text("Cadence below \(prefs.lowCadenceThreshold) rpm")
                .mangoxFont(.callout)
                .fontWeight(.semibold)
        }
        .foregroundStyle(AppColor.orange)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(AppColor.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue))
    }

    private func rideTipBanner(_ tip: RideNudgeDisplay) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .mangoxFont(.callout)
                .foregroundStyle(AppColor.mango)
                .frame(width: 20, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(tip.headline.uppercased())
                    .mangoxFont(.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.mango.opacity(0.9))
                    .tracking(0.6)
                Text(tip.body)
                    .mangoxFont(.callout)
                    .foregroundStyle(AppColor.fg1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                viewModel.clearRideTip()
            } label: {
                Image(systemName: "xmark")
                    .mangoxFont(.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.fg3)
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
            RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue)
                .strokeBorder(AppColor.hair2, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue))
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
        IndoorDashboardAnalytics.milestoneToastShown()
        #if canImport(UIKit)
        if indoorMilestoneSoundEnabled {
            AudioServicesPlaySystemSound(1057)
        }
        #endif
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
                .mangoxFont(.caption)
                .fontWeight(.semibold)
            Text(text)
                .font(DashboardViewFontToken.mono(size: 13, weight: .semibold))
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
