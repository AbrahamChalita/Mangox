import SwiftUI
import SwiftData
import os.log

private let planLogger = Logger(subsystem: "com.abchalita.Mangox", category: "TrainingPlan")

struct TrainingPlanView: View {
    @State private var viewModel: TrainingViewModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Binding var navigationPath: NavigationPath

    private static let planProgressDescriptor: FetchDescriptor<TrainingPlanProgress> = {
        var d = FetchDescriptor<TrainingPlanProgress>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        d.fetchLimit = 256
        return d
    }()

    private static let aiPlansDescriptor: FetchDescriptor<AIGeneratedPlan> = {
        var d = FetchDescriptor<AIGeneratedPlan>(
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)])
        d.fetchLimit = 256
        return d
    }()

    @Query(Self.planProgressDescriptor) private var allProgress: [TrainingPlanProgress]

    @Query(Self.aiPlansDescriptor) private var aiPlans: [AIGeneratedPlan]

    private static let recentWorkoutsForPlanDescriptor: FetchDescriptor<Workout> = {
        var d = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        d.fetchLimit = 400
        return d
    }()

    @Query(Self.recentWorkoutsForPlanDescriptor) private var recentWorkoutsForPlan: [Workout]

    private let plan: TrainingPlan

    init(
        navigationPath: Binding<NavigationPath>,
        plan: TrainingPlan,
        viewModel: TrainingViewModel
    ) {
        _navigationPath = navigationPath
        self.plan = plan
        self._viewModel = State(initialValue: viewModel)
    }

    private let accentGreen = AppColor.success
    private let accentYellow = AppColor.yellow
    private let accentOrange = AppColor.orange
    private let accentRed = AppColor.red
    private let accentBlue = AppColor.blue
    private let bg = AppColor.bg

    /// True when this plan was AI-generated (not the built-in Classicissima).
    private var isAIPlan: Bool {
        true
    }

    private var progress: TrainingPlanProgress? {
        allProgress.first { $0.planID == plan.id }
    }

    private var currentWeek: PlanWeek? {
        plan.weeks.first { $0.weekNumber == viewModel.selectedWeek }
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<TrainingViewModel, Value>)
        -> Binding<Value>
    {
        Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }

    private var overallProgress: Double {
        guard let progress else { return 0 }
        let totalWorkoutDays = plan.allDays.filter {
            $0.dayType == .workout || $0.dayType == .ftpTest || $0.dayType == .optionalWorkout
                || $0.dayType == .commute
        }.count
        guard totalWorkoutDays > 0 else { return 0 }
        return Double(progress.completedCount) / Double(totalWorkoutDays)
    }

    private var todayDayID: String? {
        guard let progress else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for day in plan.allDays {
            let dayDate = calendar.startOfDay(for: progress.calendarDate(for: day))
            if dayDate == today {
                return day.id
            }
        }
        return nil
    }

    private func matchingCompletedWorkout(dayID: String) -> Workout? {
        recentWorkoutsForPlan
            .filter {
                $0.planID == plan.id && $0.planDayID == dayID && $0.status == .completed && $0.isValid
            }
            .max(by: { $0.startDate < $1.startDate })
    }

    var body: some View {
        FTPRefreshScope {
            ZStack {
                bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                        .padding(.bottom, viewModel.showsWhoopBanner ? 2 : 4)

                    if viewModel.showsWhoopBanner {
                        whoopPlanBanner
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                    }

                    if progress == nil {
                        noPlanActiveView
                    } else {
                        planContent
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: binding(\.showStartPlanSheet)) {
            startPlanSheet
        }
        .alert("Reset Progress?", isPresented: binding(\.showResetConfirmation)) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetPlan()
            }
        } message: {
            Text("This will erase all progress for \(plan.name). This cannot be undone.")
        }
        .alert("Delete Plan?", isPresented: binding(\.showDeleteConfirmation)) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteAIPlan()
            }
        } message: {
            Text("The plan and all progress will be permanently deleted.")
        }
        .sheet(isPresented: binding(\.showICSExportShare)) {
            if let icsExportURL = viewModel.icsExportURL {
                ShareSheet(activityItems: [icsExportURL])
            }
        }
        .onAppear {
            viewModel.autoSelectCurrentWeek(progress: progress, totalWeeks: plan.totalWeeks)
        }
        .task {
            await viewModel.refreshWhoopIfNeeded()
        }
        .onChange(of: viewModel.pendingNavigation) { _, action in
            guard let action else { return }
            switch action {
            case .paywall:
                navigationPath.append(AppRoute.paywall)
            case .connectionForPlan(let planID, let dayID):
                navigationPath.append(AppRoute.connectionForPlan(planID: planID, dayID: dayID))
            case .ftpSetup:
                navigationPath.append(AppRoute.ftpSetup)
            }
            viewModel.clearPendingNavigation()
        }
    }

    // MARK: - WHOOP

    private var whoopPlanBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(AppColor.whoop)
                if let pct = viewModel.whoopRecoveryScore {
                    Text(String(format: "Recovery %.0f%%", pct))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(viewModel.whoopReadinessAccentColor)
                } else {
                    Text("WHOOP linked")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
            }
            Text(viewModel.whoopReadinessHint)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.42))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(AppColor.whoop.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(AppColor.whoop.opacity(0.28), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                navigationPath.removeLast()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(AppOpacity.textSecondary))
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Training")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white.opacity(AppOpacity.textPrimary))
                Text(plan.eventName)
                    .font(.caption)
                    .foregroundStyle(accentYellow.opacity(0.9))
            }

            Spacer()

            if progress != nil || isAIPlan {
                Menu {
                    if let progress {
                        Button("Export calendar (.ics, timed)") {
                            exportPlanICS(progress: progress)
                        }
                    }
                    if progress != nil {
                        Button("Reset Progress", role: .destructive) {
                            viewModel.showResetConfirmation = true
                        }
                    }
                    if isAIPlan {
                        Button("Delete Plan", role: .destructive) {
                            viewModel.showDeleteConfirmation = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: - No Plan Active

    private var noPlanActiveView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 30)

                // Event card
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 16))
                            .foregroundStyle(accentYellow)
                        Text(plan.eventName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 16) {
                        eventStat(icon: "map", label: "Distance", value: plan.distance)
                        eventStat(icon: "mountain.2", label: "Elevation", value: plan.elevation)
                        eventStat(icon: "calendar", label: "Date", value: plan.eventDate)
                    }

                    HStack(spacing: 16) {
                        eventStat(icon: "mappin.and.ellipse", label: "Location", value: plan.location)
                        eventStat(icon: "clock", label: "Weeks", value: "\(plan.totalWeeks)")
                    }
                }
                .padding(18)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(accentYellow.opacity(0.2), lineWidth: 1)
                )

                // Description
                Text(plan.description)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                // Requirements
                VStack(alignment: .leading, spacing: 10) {
                    requirementRow(icon: "bicycle", text: "Smart trainer (ThinkRider Pro XX)", met: true)
                    requirementRow(icon: "laptopcomputer", text: "MyWhoosh or similar app", met: true)
                    requirementRow(
                        icon: "bolt.heart",
                        text: "FTP Test (Week 1, Day 2)",
                        met: PowerZone.ftp != 265,
                        note: PowerZone.ftp == 265 ? "Using default FTP — test recommended" : "FTP: \(PowerZone.ftp)W"
                    )
                    requirementRow(icon: "heart.fill", text: "Heart rate monitor (optional)", met: true)
                }
                .padding(16)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )

                // Start button
                Button {
                    viewModel.showStartPlanSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Start Training Plan")
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(accentGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if viewModel.shouldShowUpgradeCTA {
                    Button {
                        viewModel.requestPaywall()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "crown.fill")
                            Text("Upgrade to Pro")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Plan Content

    private var planContent: some View {
        VStack(spacing: 0) {
            // Overall progress bar
            overallProgressCard
                .padding(.horizontal, 20)
                .padding(.top, 12)

            // Week selector
            weekSelector
                .padding(.top, 12)

            // Week info header
            if let week = currentWeek {
                weekInfoHeader(week: week)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }

            // Day cards
            ScrollView {
                if let week = currentWeek {
                    LazyVStack(spacing: 10) {
                        ForEach(week.days, id: \.id) { day in
                            dayCard(day: day, week: week)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - Overall Progress Card

    private var overallProgressCard: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PLAN PROGRESS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                        .tracking(1.5)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(overallProgress * 100))")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        Text("%")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                Spacer()

                if let progress {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 12) {
                            miniStat(value: "\(progress.completedCount)", label: "Done", color: accentGreen)
                            miniStat(value: "\(progress.skippedCount)", label: "Skip", color: accentOrange)
                        }

                        Text("FTP: \(progress.currentFTP)W")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))

                        Text(
                            "Adaptive ERG: \(Int((progress.adaptiveLoadMultiplier * 100).rounded()))% of plan targets"
                        )
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.28))

                        if abs(progress.adaptiveLoadMultiplier - 1.0) > 0.009 {
                            Button {
                                viewModel.resetAdaptiveLoadMultiplier(progress: progress)
                            } label: {
                                Text("Reset adaptive to 100%")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(AppColor.blue.opacity(0.9))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }
                    }
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 6)

                    Capsule()
                        .fill(accentGreen)
                        .frame(width: max(0, geo.size.width * overallProgress), height: 6)
                        .animation(.easeInOut(duration: accessibilityReduceMotion ? 0 : 0.4), value: overallProgress)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(AppOpacity.cardBorder), lineWidth: 1)
        )
    }

    // MARK: - Week Selector

    private var weekSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(plan.weeks) { week in
                        let isSelected = viewModel.selectedWeek == week.weekNumber
                        let weekProgress = weekCompletionFraction(week: week)

                        Button {
                            if accessibilityReduceMotion {
                                viewModel.selectedWeek = week.weekNumber
                            } else {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.selectedWeek = week.weekNumber
                                }
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Text("W\(week.weekNumber)")
                                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? .white : .white.opacity(0.5))

                                Text(week.phase.prefix(4).uppercased())
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(phaseColor(week.phase).opacity(isSelected ? 0.9 : 0.5))
                                    .tracking(0.5)

                                // Mini progress bar
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.white.opacity(0.08))
                                        Capsule()
                                            .fill(phaseColor(week.phase))
                                            .frame(width: max(0, geo.size.width * weekProgress))
                                    }
                                }
                                .frame(height: 3)
                                .clipShape(Capsule())
                            }
                            .frame(width: 50)
                            .padding(.vertical, 8)
                            .background(isSelected ? phaseColor(week.phase).opacity(0.12) : Color.white.opacity(0.02))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(
                                        isSelected ? phaseColor(week.phase).opacity(0.4) : Color.white.opacity(0.06),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .id(week.weekNumber)
                    }
                }
                .padding(.horizontal, 20)
            }
            .onChange(of: viewModel.selectedWeek) { _, newValue in
                if accessibilityReduceMotion {
                    proxy.scrollTo(newValue, anchor: .center)
                } else {
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Week Info Header

    private func weekInfoHeader(week: PlanWeek) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WEEK \(week.weekNumber) · \(week.phase.uppercased())")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(phaseColor(week.phase).opacity(0.8))
                        .tracking(1.5)

                    Text(week.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(week.formattedHours)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))

                    if week.tssTarget.lowerBound > 0 {
                        Text("TSS \(week.tssTarget.lowerBound)–\(week.tssTarget.upperBound)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            }

            Text(week.focus)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
        }
    }


    private func dynamicDayLabel(for day: PlanDay, calendarDate: Date?) -> String {
        guard let calendarDate else { return day.dayLabel }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE" // Short weekday, e.g. Mon, Tue, Wed
        return formatter.string(from: calendarDate)
    }

    // MARK: - Day Card


    private func dayCard(day: PlanDay, week: PlanWeek) -> some View {
        let status = progress?.status(for: day.id) ?? .upcoming
        let isToday = todayDayID == day.id
        let calendarDate = progress?.calendarDate(for: day)

        return VStack(alignment: .leading, spacing: 0) {
            // Top row: day label, date, status
            HStack(spacing: 8) {
                // Day of week (computed from real start date if active)
                Text(dynamicDayLabel(for: day, calendarDate: calendarDate).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(1)
                    .frame(width: 32, alignment: .leading)

                if let calendarDate {
                    Text(calendarDate, format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }

                if isToday {
                    Text("TODAY")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentYellow)
                        .clipShape(Capsule())
                }

                if day.isKeyWorkout {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(accentYellow)
                }

                if day.requiresFTPTest {
                    Image(systemName: "bolt.heart.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(accentOrange)
                }

                Spacer()

                statusBadge(status: status)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            // Main content
            HStack(alignment: .top, spacing: 12) {
                // Left: zone color indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(day.zone.color)
                    .frame(width: 3, height: 40)
                    .opacity(day.dayType == .rest ? 0.3 : 0.8)

                // Center: workout info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        dayTypeIcon(day.dayType)

                        Text(day.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(status == .completed ? .white.opacity(0.5) : .white)
                            .strikethrough(status == .skipped, color: .white.opacity(0.3))
                    }

                    HStack(spacing: 8) {
                        if day.durationMinutes > 0 {
                            Label(day.formattedDuration, systemImage: "clock")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.45))
                        }

                        if day.zone != .rest && day.zone != .none {
                            Text(day.zone.label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(day.zone.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(day.zone.color.opacity(0.12))
                                .clipShape(Capsule())
                        }

                        if day.hasStructuredIntervals {
                            Label("\(day.intervals.count) segments", systemImage: "chart.bar.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }

                    Text(day.notes)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(2)
                        .padding(.top, 1)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)

            if status == .completed, let w = matchingCompletedWorkout(dayID: day.id) {
                planDayPlannedVsActualMini(day: day, workout: w)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
            }

            // Interval preview (collapsed)
            if day.hasStructuredIntervals && status != .completed {
                intervalPreview(day: day)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }

            // Action buttons
            dayActions(day: day, status: status)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isToday ? phaseColor(week.phase).opacity(0.04) : Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isToday ? phaseColor(week.phase).opacity(0.25) : Color.white.opacity(0.06),
                    lineWidth: isToday ? 1.5 : 1
                )
        )
    }

    private func planDayPlannedVsActualMini(day: PlanDay, workout: Workout) -> some View {
        let ftp = PowerZone.ftp
        let plannedTSS = day.estimatedPlannedTSS(ftp: ftp)
        let plannedMin = day.durationMinutes
        let actualTSS = workout.tss
        let actualMin = max(1, Int(workout.duration / 60))

        return VStack(alignment: .leading, spacing: 6) {
            Text("LOGGED VS PLAN")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.3))
                .tracking(1)
            HStack {
                Text(
                    plannedMin > 0
                        ? "Plan \(plannedMin) min · est. TSS \(Int(plannedTSS))"
                        : "Plan est. TSS \(Int(plannedTSS))"
                )
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text("\(actualMin) min · TSS \(Int(actualTSS))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accentYellow.opacity(0.9))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Interval Preview

    private func intervalPreview(day: PlanDay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(day.intervals) { segment in
                HStack(spacing: 6) {
                    Circle()
                        .fill(segment.zone.color)
                        .frame(width: 6, height: 6)

                    Text(segment.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))

                    if segment.repeats > 1 {
                        Text("\(segment.repeats)x")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(accentYellow.opacity(0.7))
                    }

                    Text(formatSeconds(segment.durationSeconds))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))

                    Text(segment.zone.label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(segment.zone.color.opacity(0.7))

                    if let low = segment.cadenceLow, let high = segment.cadenceHigh {
                        Text("\(low)–\(high) RPM")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.25))
                    }

                    Spacer()
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Day Actions

    @ViewBuilder
    private func dayActions(day: PlanDay, status: PlanDayStatus) -> some View {
        HStack(spacing: 8) {
            switch day.dayType {
            case .workout, .optionalWorkout, .commute:
                if status == .completed {
                    Button {
                        viewModel.unmark(day.id, progress: progress)
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.04))
                            .clipShape(Capsule())
                    }
                } else if status == .skipped {
                    Button {
                        viewModel.unmark(day.id, progress: progress)
                    } label: {
                        Label("Undo Skip", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.04))
                            .clipShape(Capsule())
                    }
                } else {
                    Button {
                        viewModel.requestPlanWorkout(planID: plan.id, dayID: day.id)
                    } label: {
                        Label("Start Ride", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(accentGreen)
                            .clipShape(Capsule())
                    }

                    Button {
                        viewModel.markCompleted(day.id, progress: progress)
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(accentGreen.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(accentGreen.opacity(0.08))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(accentGreen.opacity(0.2), lineWidth: 1)
                            )
                    }

                    Button {
                        viewModel.markSkipped(day.id, progress: progress)
                    } label: {
                        Label("Skip", systemImage: "forward.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(accentOrange.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.03))
                            .clipShape(Capsule())
                    }
                }

            case .ftpTest:
                if status == .completed {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(accentGreen)
                        Text("FTP Test Complete")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Button {
                        viewModel.unmark(day.id, progress: progress)
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.04))
                            .clipShape(Capsule())
                    }
                } else {
                    Button {
                        viewModel.requestFTPSetup()
                    } label: {
                        Label("Take FTP Test", systemImage: "bolt.heart.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(accentYellow)
                            .clipShape(Capsule())
                    }

                    Button {
                        viewModel.markCompleted(day.id, progress: progress)
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(accentGreen.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(accentGreen.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }

            case .rest:
                if status != .completed {
                    Button {
                        viewModel.markCompleted(day.id, progress: progress)
                    } label: {
                        Label("Rest Day Complete", systemImage: "checkmark.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(accentBlue.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(accentBlue.opacity(0.06))
                            .clipShape(Capsule())
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.fill")
                            .foregroundStyle(accentBlue.opacity(0.6))
                        Text("Rested")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

            case .race:
                if status != .completed {
                    Button {
                        viewModel.markCompleted(day.id, progress: progress)
                    } label: {
                        Label("I Finished the Race!", systemImage: "flag.checkered")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(accentYellow)
                            .clipShape(Capsule())
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(accentYellow)
                        Text("Race Complete! 🏆")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(accentYellow)
                    }
                }

            case .event:
                if status != .completed {
                    Button {
                        viewModel.markCompleted(day.id, progress: progress)
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.04))
                            .clipShape(Capsule())
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(accentGreen)
                        Text("Done")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - Start Plan Sheet

    private var startPlanSheet: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 8) {
                            Image(systemName: "figure.outdoor.cycle")
                                .font(.system(size: 40))
                                .foregroundStyle(accentGreen)

                            Text("Start Your Training Plan")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)

                            Text("Pick the Monday you want Week 1 to start. Your \(plan.totalWeeks)-week plan maps from this date through each day on the calendar.")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                        }

                        DatePicker(
                            "Start Date (Monday)",
                            selection: binding(\.planStartDate),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .tint(accentGreen)
                        .colorScheme(.dark)

                        VStack(spacing: 6) {
                            HStack {
                                Text("Current FTP")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.6))
                                Spacer()
                                Text("\(PowerZone.ftp) W")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                            }

                            if PowerZone.ftp == 265 {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(accentOrange)
                                    Text("Using default FTP. Take the FTP test in Week 1 to set accurate zones.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(accentOrange.opacity(0.8))
                                }
                            }
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            startPlan()
                            viewModel.showStartPlanSheet = false
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                Text("Begin Plan")
                            }
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(accentGreen)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.showStartPlanSheet = false
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helper Views

    private func eventStat(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }

    private func requirementRow(icon: String, text: String, met: Bool, note: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(met ? accentGreen : accentOrange)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                if let note {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(met ? .white.opacity(0.3) : accentOrange.opacity(0.7))
                }
            }

            Spacer()

            Image(systemName: met ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(met ? accentGreen : accentOrange)
        }
    }

    private func statusBadge(status: PlanDayStatus) -> some View {
        Group {
            switch status {
            case .completed:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                    Text("DONE")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1)
                }
                .foregroundStyle(accentGreen)

            case .skipped:
                HStack(spacing: 4) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 9))
                    Text("SKIPPED")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1)
                }
                .foregroundStyle(accentOrange.opacity(0.7))

            case .inProgress:
                HStack(spacing: 4) {
                    Image(systemName: "figure.indoor.cycle")
                        .font(.system(size: 10))
                    Text("IN PROGRESS")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1)
                }
                .foregroundStyle(accentYellow)

            case .upcoming:
                EmptyView()
            }
        }
    }

    private func dayTypeIcon(_ type: PlanDayType) -> some View {
        Group {
            switch type {
            case .workout:
                Image(systemName: "figure.indoor.cycle")
                    .font(.system(size: 12))
                    .foregroundStyle(accentGreen)
            case .rest:
                Image(systemName: "moon.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(accentBlue.opacity(0.6))
            case .race:
                Image(systemName: "flag.checkered")
                    .font(.system(size: 12))
                    .foregroundStyle(accentYellow)
            case .event:
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            case .ftpTest:
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(accentOrange)
            case .optionalWorkout:
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
            case .commute:
                Image(systemName: "bicycle.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(accentBlue.opacity(0.85))
            }
        }
    }

    private func miniStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    // MARK: - Helper Functions

    private func phaseColor(_ phase: String) -> Color {
        switch phase.lowercased() {
        case "foundation": return accentBlue
        case "build": return accentOrange
        case "taper": return accentGreen
        case "race": return accentYellow
        default: return accentGreen
        }
    }



    private func formatSeconds(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if s == 0 {
            return "\(m)m"
        }
        return "\(m)m\(s)s"
    }

    private func weekCompletionFraction(week: PlanWeek) -> Double {
        guard let progress else { return 0 }
        let dayIDs = week.days.map(\.id)
        let completed = dayIDs.filter { progress.isCompleted($0) }.count
        guard !dayIDs.isEmpty else { return 0 }
        return Double(completed) / Double(dayIDs.count)
    }

    // MARK: - Actions

    private func startPlan() {
        viewModel.startPlan(plan: plan)
    }

    private func resetPlan() {
        viewModel.resetPlan(progress: progress)
    }

    private func exportPlanICS(progress: TrainingPlanProgress) {
        viewModel.exportPlanICS(plan: plan, progress: progress)
    }

    private func deleteAIPlan() {
        viewModel.deleteAIPlan(
            progress: progress,
            aiPlan: aiPlans.first(where: { $0.id == plan.id })
        )
        navigationPath.removeLast()
    }
}

// MARK: - Preview

#Preview {
    TrainingPlanView(
        navigationPath: .constant(NavigationPath()),
        viewModel: TrainingViewModel(
            whoopService: WhoopService(),
            purchasesService: PurchasesManager.shared,
            persistenceRepository: TrainingPlanPersistenceRepository(
                modelContainer: try! PersistenceContainer.makeContainer(inMemory: true)
            )
        )
    )
    .modelContainer(for: [
        Workout.self, WorkoutSample.self, LapSplit.self,
        TrainingPlanProgress.self, WorkoutRAGChunk.self,
    ], inMemory: true)
    .environment(BLEManager())
    .environment(HealthKitManager())
    .environment(WhoopService())
    .environment(PurchasesManager.shared)
}
