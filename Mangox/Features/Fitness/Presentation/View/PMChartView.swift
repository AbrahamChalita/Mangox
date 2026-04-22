import Charts
import SwiftData
import SwiftUI

/// Performance Management Chart (PMC) + power curve for the Stats tab.
/// Form (TSB), fitness (CTL), and fatigue (ATL) live in one panel above an
/// interactive chart that supports scrubbing. Compaction notes:
/// - The old hero + metric strip are merged into a single `formPanel`.
/// - The range selector + series toggle + footnote all collapse into the
///   chart card's title bar so the chart itself is the center of the screen.
/// - Power curve is a log-scaled LineMark with tap-to-inspect instead of bars.
/// - A slim sticky pill appears above the chart once the form panel scrolls
///   off so the current TSB is always in view.
struct PMChartView: View {
    @Binding var navigationPath: NavigationPath
    @State private var viewModel: FitnessViewModel
    @State private var pmcWorkoutSnapshotCache: [WorkoutMetricsSnapshot] = []
    @State private var powerCurveSnapshotCache: [WorkoutMetricsSnapshot] = []

    @State private var selectedPMCDate: Date?
    @State private var selectedPowerDuration: Int?
    @State private var showScopeInfo = false
    @State private var stickyVisible = false
    @State private var formPanelBottomY: CGFloat = .infinity

    /// Hard cap keeps the stats tab responsive; surfaced via an info popover.
    private static let pmcFetchLimit = 600

    private static let pmcWorkoutsDescriptor: FetchDescriptor<Workout> = {
        var d = FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        d.fetchLimit = Self.pmcFetchLimit
        return d
    }()

    @Query(PMChartView.pmcWorkoutsDescriptor) private var allWorkouts: [Workout]

    private static let recentPlanProgressDescriptor: FetchDescriptor<TrainingPlanProgress> = {
        var d = FetchDescriptor<TrainingPlanProgress>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        d.fetchLimit = 8
        return d
    }()

    @Query(Self.recentPlanProgressDescriptor) private var recentPlanProgress: [TrainingPlanProgress]

    init(navigationPath: Binding<NavigationPath>, viewModel: FitnessViewModel) {
        _navigationPath = navigationPath
        _viewModel = State(initialValue: viewModel)
    }

    @MainActor
    private func rebuildWorkoutSnapshotCaches() {
        pmcWorkoutSnapshotCache = allWorkouts.map { WorkoutMetricsSnapshot(pmcFieldsFrom: $0) }
        rebuildPowerCurveSnapshotCache()
    }

    @MainActor
    private func rebuildPowerCurveSnapshotCache() {
        powerCurveSnapshotCache = WorkoutMetricsSnapshot.powerCurveCandidates(
            from: allWorkouts,
            rangeDays: viewModel.rangeDays
        )
    }

    @MainActor
    private func schedulePMCAndPowerCurveRebuild() {
        viewModel.schedulePMCRebuild(
            pmcWorkouts: pmcWorkoutSnapshotCache,
            powerCurveWorkouts: powerCurveSnapshotCache
        )
    }

    @MainActor
    private func setRange(_ days: Int) {
        guard days != viewModel.rangeDays else { return }
        withAnimation(.snappy) {
            viewModel.setRange(days)
            rebuildPowerCurveSnapshotCache()
            schedulePMCAndPowerCurveRebuild()
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AppColor.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FITNESS · \(viewModel.rangeDays) DAYS")
                        .mangoxFont(.caption)
                        .foregroundStyle(AppColor.mango)

                    Text("Stats")
                        .font(MangoxFont.title.value)
                        .foregroundStyle(.white.opacity(AppOpacity.textPrimary))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, MangoxSpacing.page)
                .padding(.top, 12)
                .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 16) {
                    if let latest = viewModel.pmcData.last {
                        formPanel(latest)
                            .onGeometryChange(
                                for: CGFloat.self,
                                of: { $0.frame(in: .named("stats.scroll")).maxY }
                            ) { newValue in
                                if abs(newValue - formPanelBottomY) > 0.5 {
                                    formPanelBottomY = newValue
                                }
                            }
                    }

                    if let compliance = viewModel.planCompliance {
                        planComplianceRow(compliance)
                    }

                    pmcChartCard

                    if !viewModel.powerCurve.isEmpty {
                        powerCurveCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .coordinateSpace(name: "stats.scroll")
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { _, offset in
                // Show the sticky pill once the form panel has scrolled past
                // the top safe area. Slight hysteresis avoids flicker.
                let threshold: CGFloat = 8
                let shouldShow = offset > (formPanelBottomY - offset) + threshold
                    && offset > 60
                if shouldShow != stickyVisible {
                    withAnimation(.snappy(duration: 0.22)) { stickyVisible = shouldShow }
                }
            }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            if stickyVisible, let latest = viewModel.pmcData.last {
                stickyFormPill(latest)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: allWorkouts, initial: true) { _, _ in
            rebuildWorkoutSnapshotCaches()
            schedulePMCAndPowerCurveRebuild()
            viewModel.updatePlanCompliance(
                progress: recentPlanProgress,
                workouts: pmcWorkoutSnapshotCache
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .mangoxWorkoutAggregatesMayHaveChanged)) {
            _ in
            schedulePMCAndPowerCurveRebuild()
        }
        .onChange(of: recentPlanProgress, initial: true) { _, _ in
            viewModel.updatePlanCompliance(
                progress: recentPlanProgress,
                workouts: pmcWorkoutSnapshotCache
            )
        }
    }

    // MARK: - Form Panel (hero + metric strip, merged)

    private func formStatus(for tsb: Double) -> (label: String, color: Color, icon: String, advice: String) {
        if tsb > 25 {
            return ("Very fresh", AppColor.blue, "bolt.fill", "Ready to push")
        } else if tsb > 5 {
            return ("Fresh", AppColor.success, "checkmark.seal.fill", "Good for intensity")
        } else if tsb > -10 {
            return ("Neutral", AppColor.yellow, "equal.circle.fill", "Balanced")
        } else if tsb > -30 {
            return ("Fatigued", AppColor.orange, "flame.fill", "Take it easy")
        } else {
            return ("Overreached", AppColor.red, "exclamationmark.triangle.fill", "Recover")
        }
    }

    private func formWoWDelta(_ latest: PMCPoint) -> Int? {
        let cal = Calendar.current
        let latestDay = cal.startOfDay(for: latest.date)
        guard let weekAgoDay = cal.date(byAdding: .day, value: -7, to: latestDay) else { return nil }
        let target = cal.startOfDay(for: weekAgoDay)
        guard let prior = viewModel.pmcData.first(where: { cal.startOfDay(for: $0.date) == target })
        else { return nil }
        let delta = latest.tsb - prior.tsb
        guard abs(delta) >= 1 else { return 0 }
        return Int(delta.rounded())
    }

    private func formPanel(_ latest: PMCPoint) -> some View {
        let status = formStatus(for: latest.tsb)
        let delta = formWoWDelta(latest)
        // Shared scale so the two bars are visually comparable.
        let scaleMax = max(latest.ctl, latest.atl, 1)

        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text("FORM")
                    .mangoxFont(.label)
                    .foregroundStyle(AppColor.mango)
                    .tracking(1.4)
                Text(String(format: "%.0f", latest.tsb))
                    .font(MangoxFont.heroValue.value)
                    .foregroundStyle(status.color)
                    .contentTransition(.numericText(value: latest.tsb))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(minWidth: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: status.icon)
                        .font(.system(size: 10, weight: .bold))
                        .symbolEffect(.bounce, value: status.label)
                    Text(status.label)
                        .font(.system(size: 12, weight: .semibold))
                    if let delta {
                        Text("·").foregroundStyle(.white.opacity(0.25))
                        HStack(spacing: 2) {
                            Image(systemName:
                                delta > 0 ? "arrow.up" : (delta < 0 ? "arrow.down" : "equal")
                            )
                            .font(.system(size: 8, weight: .bold))
                            Text(delta == 0 ? "flat" : "\(abs(delta)) wk")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        }
                        .foregroundStyle(.white.opacity(0.48))
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(status.color)

                Text(status.advice)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(AppOpacity.textSecondary))

                balanceBar(
                    label: "Fit", value: latest.ctl, max: scaleMax, color: AppColor.blue
                )
                balanceBar(
                    label: "Fat", value: latest.atl, max: scaleMax, color: AppColor.red
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppColor.bg2)
        .overlay(
            Rectangle()
                .stroke(status.color.opacity(0.28), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .animation(.snappy, value: latest.tsb)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Form \(Int(latest.tsb.rounded())), \(status.label). Fitness \(Int(latest.ctl.rounded())), fatigue \(Int(latest.atl.rounded()))."
        )
    }

    /// Thin horizontal bar — fitness vs fatigue at a glance. Shared scale
    /// means "fit bar longer than fat bar" reads directly as positive form.
    private func balanceBar(label: String, value: Double, max: Double, color: Color) -> some View {
        let pct = max > 0 ? min(1, value / max) : 0
        return HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
                .tracking(0.6)
                .frame(width: 22, alignment: .leading)

            Rectangle()
                .fill(AppColor.bg4)
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(color)
                            .frame(width: geo.size.width * pct)
                            .animation(.smooth(duration: 0.4), value: pct)
                    }
                }

            Text(String(format: "%.0f", value))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(AppOpacity.textPrimary))
                .contentTransition(.numericText(value: value))
                .frame(width: 24, alignment: .trailing)
        }
    }

    // MARK: - Sticky Form Pill

    private func stickyFormPill(_ latest: PMCPoint) -> some View {
        let status = formStatus(for: latest.tsb)
        return HStack(spacing: 8) {
            Circle().fill(status.color).frame(width: 6, height: 6)
            Text("Form")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
            Text(String(format: "%.0f", latest.tsb))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(status.color)
                .contentTransition(.numericText(value: latest.tsb))
            Text("·")
                .foregroundStyle(.white.opacity(0.3))
            Text(status.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(AppOpacity.textSecondary))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(AppColor.bg1, in: Capsule())
        .overlay(Capsule().strokeBorder(AppColor.hair2, lineWidth: 1))
        .padding(.top, 4)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Plan Adherence (ring + one line)

    private func planComplianceRow(_ snap: PlanWeekCompliance.Snapshot) -> some View {
        let fraction = max(0, min(1, snap.fraction))
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        AppColor.success,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(snap.percentLabel)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(AppOpacity.textPrimary))
                    .contentTransition(.numericText())
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text("PLAN ADHERENCE")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
                    .tracking(1.1)
                Text(snap.planName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(AppOpacity.textPrimary))
                    .lineLimit(1)
                Text(adherenceSubline(snap))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AppColor.bg2)
        .overlay(Rectangle().stroke(AppColor.hair2, lineWidth: 1))
        .animation(.snappy, value: snap.fraction)
    }

    private func adherenceSubline(_ snap: PlanWeekCompliance.Snapshot) -> String {
        var parts: [String] = ["\(snap.completedWorkouts)/\(snap.scheduledWorkouts) sessions"]
        if snap.plannedWeekTSS > 0 {
            parts.append("\(snap.actualWeekTSS)/\(snap.plannedWeekTSS) TSS")
        }
        if snap.keySessionsPlanned > 0 {
            parts.append("\(snap.keySessionsCompleted)/\(snap.keySessionsPlanned) key")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - PMC Chart Card

    private var pmcAtFetchCap: Bool { allWorkouts.count >= Self.pmcFetchLimit }

    private var pmcChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("TRAINING LOAD")
                    .mangoxFont(.label)
                    .foregroundStyle(AppColor.mango)
                    .tracking(1.4)

                Spacer(minLength: 8)

                rangeSegmented

                Menu {
                    // Buttons (not Toggles) — the menu dismisses on tap, so state
                    // changes never race the dismissal animation. This avoids the
                    // "updateVisibleMenuWithBlock while no context menu is visible"
                    // UIKit warning that Toggle-in-Menu triggers on iOS 26.
                    Button {
                        viewModel.showCTL.toggle()
                    } label: {
                        Label(
                            "Fitness (CTL)",
                            systemImage: viewModel.showCTL ? "checkmark.circle.fill" : "circle"
                        )
                    }
                    Button {
                        viewModel.showATL.toggle()
                    } label: {
                        Label(
                            "Fatigue (ATL)",
                            systemImage: viewModel.showATL ? "checkmark.circle.fill" : "circle"
                        )
                    }
                    Button {
                        viewModel.showTSB.toggle()
                    } label: {
                        Label(
                            "Form (TSB)",
                            systemImage: viewModel.showTSB ? "checkmark.circle.fill" : "circle"
                        )
                    }
                    Divider()
                    Button { showScopeInfo = true } label: {
                        Label("About this chart", systemImage: "info.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuOrder(.fixed)
                .accessibilityLabel("Chart options")
                .popover(isPresented: $showScopeInfo, arrowEdge: .top) {
                    scopeInfoPopover
                }
            }

            if viewModel.pmcData.isEmpty {
                emptyState.padding(.vertical, 20)
            } else {
                pmcChart
                    .frame(height: 220)
            }
        }
        .padding(14)
        .background(AppColor.bg2)
        .overlay(Rectangle().stroke(AppColor.hair2, lineWidth: 1))
    }

    private var scopeInfoPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Chart scope")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(
                "Uses up to the \(Self.pmcFetchLimit.formatted()) most recent rides for the training load query."
            )
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.7))
            if pmcAtFetchCap {
                Text("You're at the cap — oldest rides are omitted; fitness trend still warms up from the included history.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(14)
        .frame(maxWidth: 280, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }

    private var rangeSegmented: some View {
        HStack(spacing: 6) {
            ForEach(viewModel.rangeOptions, id: \.self) { days in
                let isSelected = days == viewModel.rangeDays
                Button {
                    setRange(days)
                } label: {
                    Text("\(days)D")
                        .mangoxFont(.caption)
                        .foregroundStyle(isSelected ? AppColor.fg0 : AppColor.fg2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                        .background(isSelected ? AppColor.bg2 : AppColor.bg1)
                        .overlay(
                            Rectangle()
                                .stroke(isSelected ? AppColor.blue.opacity(0.4) : AppColor.hair, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(days)-day range")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: viewModel.rangeDays)
    }

    // MARK: - PMC Chart

    private var pmcChart: some View {
        Chart {
            // TSB zero reference line.
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color.white.opacity(0.12))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))

            if viewModel.showTSB {
                ForEach(viewModel.pmcData) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Zero", 0),
                        yEnd: .value("Form", point.tsb)
                    )
                    .foregroundStyle(
                        point.tsb >= 0 ? AppColor.success.opacity(0.12) : AppColor.red.opacity(0.12)
                    )
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Form", point.tsb),
                        series: .value("Series", "TSB")
                    )
                    .foregroundStyle(AppColor.success)
                    .interpolationMethod(.monotone)
                }
            }

            if viewModel.showCTL {
                ForEach(viewModel.pmcData) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Fitness", point.ctl),
                        series: .value("Series", "CTL")
                    )
                    .foregroundStyle(AppColor.blue)
                    .interpolationMethod(.monotone)
                }
            }

            if viewModel.showATL {
                ForEach(viewModel.pmcData) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Fatigue", point.atl),
                        series: .value("Series", "ATL")
                    )
                    .foregroundStyle(AppColor.red)
                    .interpolationMethod(.monotone)
                }
            }

            if let selectedPMCDate,
                let hit = selectedPMCPoint(for: selectedPMCDate)
            {
                RuleMark(x: .value("Selected", hit.date))
                    .foregroundStyle(Color.white.opacity(0.28))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(
                        position: .top,
                        alignment: .center,
                        spacing: 6,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        pmcCallout(for: hit)
                    }
            }
        }
        .chartXSelection(value: $selectedPMCDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.04))
                AxisValueLabel(format: .dateTime.month().day(), anchor: .top)
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.04))
                AxisValueLabel()
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
        .animation(.smooth(duration: 0.35), value: viewModel.pmcData.count)
    }

    private func selectedPMCPoint(for date: Date) -> PMCPoint? {
        let cal = Calendar.current
        let targetDay = cal.startOfDay(for: date)
        return viewModel.pmcData.min(by: { lhs, rhs in
            abs(cal.startOfDay(for: lhs.date).timeIntervalSince(targetDay))
                < abs(cal.startOfDay(for: rhs.date).timeIntervalSince(targetDay))
        })
    }

    private func pmcCallout(for point: PMCPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(point.date.formatted(.dateTime.month().day().weekday(.abbreviated)))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 10) {
                calloutRow(label: "Fit", value: point.ctl, color: AppColor.blue)
                calloutRow(label: "Fat", value: point.atl, color: AppColor.red)
                calloutRow(label: "Form", value: point.tsb, color: AppColor.success)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .mangoxSurface(.frosted, shape: .rounded(10))
        .allowsHitTesting(false)
    }

    private func calloutRow(label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Text(String(format: "%.0f", value))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(AppOpacity.textPrimary))
        }
    }

    // MARK: - Power Curve (log-scaled LineMark)

    private var powerCurveCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("POWER CURVE")
                    .mangoxFont(.label)
                    .foregroundStyle(AppColor.mango)
                    .tracking(1.4)
                Spacer()
                Text("\(viewModel.rangeDays)D")
                    .mangoxFont(.caption)
                    .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
            }

            Chart {
                ForEach(viewModel.powerCurve) { pt in
                    LineMark(
                        x: .value("Duration", Double(pt.durationSeconds)),
                        y: .value("Watts", pt.watts)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppColor.orange, AppColor.mango],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))

                    AreaMark(
                        x: .value("Duration", Double(pt.durationSeconds)),
                        y: .value("Watts", pt.watts)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppColor.mango.opacity(0.18), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                if let selectedPowerDuration,
                    let hit = powerCurvePoint(nearest: selectedPowerDuration)
                {
                    RuleMark(x: .value("Duration", Double(hit.durationSeconds)))
                        .foregroundStyle(Color.white.opacity(0.28))
                        .lineStyle(StrokeStyle(lineWidth: 1))

                    PointMark(
                        x: .value("Duration", Double(hit.durationSeconds)),
                        y: .value("Watts", hit.watts)
                    )
                    .foregroundStyle(AppColor.mango)
                    .symbolSize(80)
                    .annotation(
                        position: .top,
                        alignment: .center,
                        spacing: 6,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        powerCallout(for: hit)
                    }
                }
            }
            .chartXScale(type: .log)
            .chartXSelection(value: $selectedPowerDuration)
            .chartXAxis {
                AxisMarks(values: powerCurveAxisValues) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.04))
                    AxisValueLabel {
                        if let raw = value.as(Double.self) {
                            Text(powerDurationLabel(Int(raw.rounded())))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.04))
                    AxisValueLabel()
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .frame(height: 180)
        }
        .padding(14)
        .background(AppColor.bg2)
        .overlay(Rectangle().stroke(AppColor.hair2, lineWidth: 1))
    }

    /// Axis tick positions at conventional duration breakpoints that intersect
    /// the available data. Using a fixed set keeps labels legible on a log axis.
    private var powerCurveAxisValues: [Double] {
        let candidates: [Double] = [5, 15, 30, 60, 120, 300, 600, 1200, 1800, 3600]
        guard let minD = viewModel.powerCurve.map(\.durationSeconds).min(),
            let maxD = viewModel.powerCurve.map(\.durationSeconds).max()
        else { return candidates }
        return candidates.filter { $0 >= Double(minD) && $0 <= Double(maxD) }
    }

    private func powerCurvePoint(nearest seconds: Int) -> PowerCurveAnalytics.Point? {
        viewModel.powerCurve.min(by: { abs($0.durationSeconds - seconds) < abs($1.durationSeconds - seconds) })
    }

    private func powerCallout(for pt: PowerCurveAnalytics.Point) -> some View {
        HStack(spacing: 6) {
            Text(powerDurationLabel(pt.durationSeconds))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            Text("\(pt.watts)W")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColor.mango)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .mangoxSurface(.frosted, shape: .rounded(10))
        .allowsHitTesting(false)
    }

    private func powerDurationLabel(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds % 60 == 0 { return "\(seconds / 60)m" }
        return "\(seconds / 60)m\(seconds % 60)s"
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.15))
            Text("Not enough data yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            Text("Complete a few rides to see your training load trends.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.25))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
