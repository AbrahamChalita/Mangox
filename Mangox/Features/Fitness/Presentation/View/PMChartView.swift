import Charts
import SwiftData
import SwiftUI

/// Performance Management Chart (PMC) showing CTL, ATL, and TSB over time.
/// The industry-standard training load visualization.
struct PMChartView: View {
    @Binding var navigationPath: NavigationPath
    @State private var viewModel: FitnessViewModel

    /// Hard cap keeps the stats tab responsive; matches footnote when the store returns a full page.
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

    @MainActor
    private var workoutSnapshots: [WorkoutMetricsSnapshot] {
        allWorkouts.map { WorkoutMetricsSnapshot(from: $0) }
    }

    init(navigationPath: Binding<NavigationPath>, viewModel: FitnessViewModel) {
        _navigationPath = navigationPath
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            AppColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 16)

                    if let compliance = viewModel.planCompliance {
                        planComplianceCard(compliance)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                    }

                    // Training load hero card — overlaps chart
                    if let latest = viewModel.pmcData.last {
                        trainingLoadHero(latest)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                    }

                    // Range selector
                    HStack(spacing: 0) {
                        ForEach(viewModel.rangeOptions, id: \.self) { days in
                            let isSelected = days == viewModel.rangeDays
                            let dayLabel = "\(days)d"
                            Button(action: {
                                withAnimation {
                                    viewModel.setRange(days)
                                    viewModel.schedulePMCRebuild(with: workoutSnapshots)
                                }
                            }) {
                                Text(dayLabel)
                                    .font(
                                        .system(
                                            size: 13,
                                            weight: isSelected ? .semibold : .medium)
                                    )
                                    .foregroundStyle(
                                        isSelected ? .black : .white.opacity(0.6)
                                    )
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? AppColor.mango : Color.clear)
                                    )
                            }
                        }
                    }
                    .padding(4)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    // Legend
                    HStack(spacing: 16) {
                        legendItem(label: "Fitness", color: AppColor.blue, isOn: $viewModel.showCTL)
                        legendItem(label: "Fatigue", color: AppColor.red, isOn: $viewModel.showATL)
                        legendItem(label: "Form", color: AppColor.success, isOn: $viewModel.showTSB)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                    pmcQueryScopeFootnote
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                    // Chart
                    if viewModel.pmcData.isEmpty {
                        emptyState
                    } else {
                        pmcChart
                            .padding(.horizontal, 16)
                    }

                    // CTL / ATL / TSB breakdown
                    if let latest = viewModel.pmcData.last {
                        metricStrip(latest)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                    }

                    if !viewModel.powerCurve.isEmpty {
                        powerCurveSection
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                    }

                    Spacer(minLength: 40)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarBackButtonHidden()
        .onChange(of: allWorkouts, initial: true) { _, _ in
            viewModel.schedulePMCRebuild(with: workoutSnapshots)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mangoxWorkoutAggregatesMayHaveChanged)) {
            _ in
            viewModel.schedulePMCRebuild(with: workoutSnapshots)
        }
        .onChange(of: recentPlanProgress, initial: true) { _, _ in
            viewModel.updatePlanCompliance(progress: recentPlanProgress, workouts: workoutSnapshots)
        }
    }

    private var pmcAtFetchCap: Bool {
        allWorkouts.count >= Self.pmcFetchLimit
    }

    private var pmcQueryScopeFootnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                "Chart uses up to the \(Self.pmcFetchLimit.formatted()) most recent rides in the training load query."
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.38))
            .fixedSize(horizontal: false, vertical: true)
            if pmcAtFetchCap {
                Text(
                    "You're at that cap — oldest rides in this query are omitted; fitness trend still warms up from the included history."
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Training Load")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            Spacer()
        }
    }

    private func planComplianceCard(_ snap: PlanWeekCompliance.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plan adherence")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(0.6)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snap.planName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                    Text("Scheduled workouts this week (Mon–Sun)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.38))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(snap.completedWorkouts)/\(snap.scheduledWorkouts)")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColor.mango)
                    Text(snap.percentLabel + " complete")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            if snap.plannedWeekTSS > 0 {
                HStack {
                    Text("Week load (TSS)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Text("\(snap.actualWeekTSS) / \(snap.plannedWeekTSS)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.82))
                    Text("(\(snap.tssPercentLabel) of plan)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.top, 4)
            }

            if snap.keySessionsPlanned > 0 {
                HStack {
                    Text("Key sessions")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Text("\(snap.keySessionsCompleted)/\(snap.keySessionsPlanned) done")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var powerCurveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Power curve")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
            Text(
                "Best average power for each duration — rides with a power meter in the last \(viewModel.rangeDays) days (up to 80 sessions)."
            )
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.38))
            .fixedSize(horizontal: false, vertical: true)

            Chart(viewModel.powerCurve) { pt in
                BarMark(
                    x: .value("Duration", powerDurationLabel(pt.durationSeconds)),
                    y: .value("Watts", pt.watts)
                )
                .foregroundStyle(AppColor.mango.opacity(0.85))
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { val in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel()
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .frame(height: 200)
            .padding(12)
            .background(Color.white.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func powerDurationLabel(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds % 60 == 0 { return "\(seconds / 60)m" }
        return "\(seconds / 60)m\(seconds % 60)s"
    }

    // MARK: - Training Load Hero Card

    private func trainingLoadHero(_ latest: PMCPoint) -> some View {
        let tsb = latest.tsb
        let status: String
        let statusColor: Color
        let statusIcon: String
        let advice: String

        if tsb > 25 {
            status = "Very Fresh"
            statusColor = AppColor.blue
            statusIcon = "bolt.fill"
            advice = "High form — ready for a hard session or race."
        } else if tsb > 5 {
            status = "Fresh"
            statusColor = AppColor.success
            statusIcon = "checkmark.seal.fill"
            advice = "Good form — ideal for intensity work."
        } else if tsb > -10 {
            status = "Neutral"
            statusColor = AppColor.yellow
            statusIcon = "equal.circle.fill"
            advice = "Balanced fitness and fatigue."
        } else if tsb > -30 {
            status = "Fatigued"
            statusColor = AppColor.orange
            statusIcon = "flame.fill"
            advice = "Consider an easy day or rest."
        } else {
            status = "Overreached"
            statusColor = AppColor.red
            statusIcon = "exclamationmark.triangle.fill"
            advice = "Recovery needed to avoid overtraining."
        }

        return VStack(spacing: 0) {
            // Top section: big TSB number + status
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 15))
                            .foregroundStyle(statusColor)
                        Text(status.uppercased())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(statusColor)
                            .tracking(1.2)
                    }

                    Text(advice)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }

                Spacer()

                // Big TSB number
                VStack(alignment: .trailing, spacing: 2) {
                    Text("FORM")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.3))
                        .tracking(1.0)
                    Text(String(format: "%.0f", tsb))
                        .font(.system(size: 52, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Mini sparkline showing recent TSB trend
            if viewModel.pmcData.count > 7 {
                let recentTSB = Array(viewModel.pmcData.suffix(min(30, viewModel.pmcData.count)).map(\.tsb))
                miniSparkline(values: recentTSB, color: statusColor)
                    .frame(height: 40)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(statusColor.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Mini Sparkline

    private func miniSparkline(values: [Double], color: Color) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let range = max(maxV - minV, 1)

            // Zero line
            let zeroY = h * (1 - CGFloat((0 - minV) / range))

            Path { p in
                p.move(to: CGPoint(x: 0, y: zeroY))
                p.addLine(to: CGPoint(x: w, y: zeroY))
            }
            .stroke(Color.white.opacity(0.06), lineWidth: 1)

            // Sparkline
            Path { p in
                for (i, val) in values.enumerated() {
                    let x = w * CGFloat(i) / CGFloat(max(values.count - 1, 1))
                    let y = h * (1 - CGFloat((val - minV) / range))
                    if i == 0 {
                        p.move(to: CGPoint(x: x, y: y))
                    } else {
                        p.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color.opacity(0.6), lineWidth: 1.5)

            // Gradient fill under sparkline
            Path { p in
                for (i, val) in values.enumerated() {
                    let x = w * CGFloat(i) / CGFloat(max(values.count - 1, 1))
                    let y = h * (1 - CGFloat((val - minV) / range))
                    if i == 0 {
                        p.move(to: CGPoint(x: x, y: y))
                    } else {
                        p.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                p.addLine(to: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: 0, y: h))
                p.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.15), color.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    // MARK: - Metric Strip

    private func metricStrip(_ latest: PMCPoint) -> some View {
        let tsb = latest.tsb
        let statusColor: Color =
            if tsb > 25 {
                AppColor.blue
            } else if tsb > 5 {
                AppColor.success
            } else if tsb > -10 {
                AppColor.yellow
            } else if tsb > -30 {
                AppColor.orange
            } else {
                AppColor.red
            }

        return HStack(spacing: 12) {
            pmcStat(
                label: "CTL", subtitle: "Fitness", value: String(format: "%.0f", latest.ctl),
                color: AppColor.blue
            )
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            pmcStat(
                label: "ATL", subtitle: "Fatigue", value: String(format: "%.0f", latest.atl),
                color: AppColor.red
            )
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            pmcStat(
                label: "TSB", subtitle: "Form", value: String(format: "%.0f", latest.tsb),
                color: statusColor
            )
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Legend

    private func legendItem(label: String, color: Color, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(isOn.wrappedValue ? color : Color.white.opacity(0.15))
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isOn.wrappedValue ? .white.opacity(0.5) : .white.opacity(0.2))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.15))
            Text("Not enough data yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            Text("Complete a few rides to see your training load trends.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.25))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Chart

    private var pmcChart: some View {
        Chart {
            if viewModel.showTSB {
                ForEach(viewModel.pmcData) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("TSB Zero", 0),
                        yEnd: .value("TSB", point.tsb)
                    )
                    .foregroundStyle(
                        point.tsb >= 0 ? AppColor.success.opacity(0.1) : AppColor.red.opacity(0.1)
                    )
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("TSB", point.tsb)
                    )
                    .foregroundStyle(AppColor.success)
                    .interpolationMethod(.monotone)
                }
            }

            if viewModel.showCTL {
                ForEach(viewModel.pmcData) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("CTL", point.ctl)
                    )
                    .foregroundStyle(AppColor.blue)
                    .interpolationMethod(.monotone)
                }
            }

            if viewModel.showATL {
                ForEach(viewModel.pmcData) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("ATL", point.atl)
                    )
                    .foregroundStyle(AppColor.red)
                    .interpolationMethod(.monotone)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.04))
                AxisTick().foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel(format: .dateTime.month().day(), anchor: .top)
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.04))
                AxisTick().foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel()
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
        .frame(height: 240)
        .padding()
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .drawingGroup()
    }

    // MARK: - PMC Stat

    private func pmcStat(label: String, subtitle: String, value: String, color: Color) -> some View
    {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.25))
                .tracking(0.8)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }
}
