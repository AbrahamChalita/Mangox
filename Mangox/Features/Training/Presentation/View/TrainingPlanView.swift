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

    private static let dayLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    @Query(Self.recentWorkoutsForPlanDescriptor) private var recentWorkoutsForPlan: [Workout]

    @State private var expandedDayIDs: Set<String> = []

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

    private let bg = AppColor.bg

    private let isAIPlan = true

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
                        .padding(.bottom, 4)

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

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                navigationPath.removeLast()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(AppOpacity.textSecondary))
                    .frame(width: 32, height: 32)
            }
            .background(AppColor.bg1)
            .overlay(Rectangle().stroke(AppColor.hair2, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text("PLAN · W\(viewModel.selectedWeek) / W\(plan.totalWeeks)")
                    .mangoxFont(.label)
                    .foregroundStyle(AppColor.fg3)
                    .tracking(1.4)

                Text(plan.eventName)
                    .font(MangoxFont.title.value)
                    .foregroundStyle(AppColor.fg0)
                    .lineLimit(1)
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
                VStack(alignment: .leading, spacing: MangoxSpacing.md.rawValue) {
                    HStack(spacing: MangoxSpacing.sm.rawValue) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColor.yellow)
                        Text("EVENT")
                            .mangoxFont(.label)
                            .tracking(1.4)
                            .foregroundStyle(AppColor.yellow)
                    }
                    Text(plan.eventName)
                        .mangoxFont(.title)
                        .foregroundStyle(AppColor.fg0)

                    Rectangle().fill(AppColor.hair).frame(height: 1)

                    HStack(spacing: MangoxSpacing.md.rawValue) {
                        eventStat(icon: "map", label: "Distance", value: plan.distance)
                        eventStat(icon: "mountain.2", label: "Elevation", value: plan.elevation)
                        eventStat(icon: "calendar", label: "Date", value: plan.eventDate)
                    }

                    HStack(spacing: MangoxSpacing.md.rawValue) {
                        eventStat(icon: "mappin.and.ellipse", label: "Location", value: plan.location)
                        eventStat(icon: "clock", label: "Weeks", value: "\(plan.totalWeeks)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(MangoxSpacing.lg.rawValue)
                .background(AppColor.bg2)
                .overlay(Rectangle().stroke(AppColor.yellow.opacity(0.2), lineWidth: 1))

                // Description
                Text(plan.description)
                    .mangoxFont(.body)
                    .foregroundStyle(AppColor.fg2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Requirements
                VStack(alignment: .leading, spacing: MangoxSpacing.sm.rawValue) {
                    Text("REQUIREMENTS")
                        .mangoxFont(.label)
                        .tracking(1.4)
                        .foregroundStyle(AppColor.fg3)
                        .padding(.bottom, MangoxSpacing.xs.rawValue)

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
                .padding(MangoxSpacing.lg.rawValue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColor.bg2)
                .overlay(Rectangle().stroke(AppColor.hair2, lineWidth: 1))

                // Start button
                Button {
                    viewModel.showStartPlanSheet = true
                } label: {
                    HStack(spacing: MangoxSpacing.sm.rawValue) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("START TRAINING PLAN")
                            .mangoxFont(.label)
                            .tracking(1.6)
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MangoxSpacing.lg.rawValue)
                    .background(AppColor.mango)
                    .overlay(Rectangle().stroke(AppColor.mango, lineWidth: 1))
                }

                if viewModel.shouldShowUpgradeCTA {
                    Button {
                        viewModel.requestPaywall()
                    } label: {
                        HStack(spacing: MangoxSpacing.sm.rawValue) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 11))
                            Text("UPGRADE TO PRO")
                                .mangoxFont(.label)
                                .tracking(1.4)
                        }
                        .foregroundStyle(AppColor.fg2)
                    }
                }

                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Plan Content

    private var planContent: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                if let week = currentWeek {
                    mergedBlockHeader(week: week)
                        .padding(.horizontal, MangoxSpacing.xl.rawValue)
                        .padding(.top, MangoxSpacing.md.rawValue)
                        .padding(.bottom, MangoxSpacing.md.rawValue)
                }

                Section {
                    if let week = currentWeek {
                        VStack(spacing: MangoxSpacing.sm.rawValue) {
                            ForEach(week.days, id: \.id) { day in
                                dayCard(day: day, week: week)
                            }
                        }
                        .padding(.horizontal, MangoxSpacing.xl.rawValue)
                        .padding(.top, MangoxSpacing.md.rawValue)
                        .padding(.bottom, MangoxSpacing.xl.rawValue)
                    }
                } header: {
                    weekSelector
                        .padding(.vertical, MangoxSpacing.sm.rawValue)
                        .background(AppColor.bg0)
                        .overlay(
                            Rectangle()
                                .fill(AppColor.hair)
                                .frame(height: 1),
                            alignment: .bottom
                        )
                        .overlay(
                            Rectangle()
                                .fill(AppColor.hair)
                                .frame(height: 1),
                            alignment: .top
                        )
                }
            }
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                if stickyCTAVisible, let today = todayDay {
                    stickyTodayCTA(day: today)
                        .padding(.horizontal, MangoxSpacing.xl.rawValue)
                        .padding(.bottom, MangoxSpacing.md.rawValue)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: stickyCTAVisible)
        }
        .onAppear { seedExpansion() }
        .onChange(of: viewModel.selectedWeek) { _, _ in seedExpansion() }
    }

    // MARK: - Merged Block Header

    @ViewBuilder
    private func mergedBlockHeader(week: PlanWeek) -> some View {
        let phase = phaseColor(week.phase)
        VStack(alignment: .leading, spacing: MangoxSpacing.md.rawValue) {
            HStack(alignment: .firstTextBaseline, spacing: MangoxSpacing.sm.rawValue) {
                Text("\(week.phase.uppercased()) · W\(week.weekNumber) / W\(plan.totalWeeks)")
                    .mangoxFont(.label)
                    .tracking(1.4)
                    .foregroundStyle(phase)
                Spacer()
                Text(week.formattedHours.uppercased())
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg1)
                if week.tssTarget.lowerBound > 0 {
                    Text("·")
                        .mangoxFont(.caption)
                        .foregroundStyle(AppColor.fg3)
                    Text("TSS \(week.tssTarget.lowerBound)–\(week.tssTarget.upperBound)")
                        .mangoxFont(.caption)
                        .foregroundStyle(AppColor.fg2)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: MangoxSpacing.md.rawValue) {
                Text(week.title)
                    .font(MangoxFont.title.value)
                    .foregroundStyle(AppColor.fg0)
                    .lineLimit(2)
                Spacer()
                Text("\(Int(overallProgress * 100))%")
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg1)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(AppColor.hair2).frame(height: 2)
                    Rectangle()
                        .fill(AppColor.mango)
                        .frame(width: max(0, geo.size.width * overallProgress), height: 2)
                        .animation(.easeInOut(duration: accessibilityReduceMotion ? 0 : 0.4), value: overallProgress)
                }
            }
            .frame(height: 2)

            if let progress {
                HStack(spacing: MangoxSpacing.lg.rawValue) {
                    inlineStat(label: "DONE", value: "\(progress.completedCount)", color: AppColor.success)
                    inlineStat(label: "SKIP", value: "\(progress.skippedCount)", color: AppColor.orange)
                    inlineStat(label: "FTP", value: "\(progress.currentFTP)W", color: AppColor.mango)
                    if viewModel.showsWhoopBanner, let pct = viewModel.whoopRecoveryScore {
                        Spacer()
                        whoopChip(pct: pct)
                    } else {
                        Spacer()
                    }
                }
            }

            if !week.focus.isEmpty {
                Text(week.focus)
                    .mangoxFont(.body)
                    .foregroundStyle(AppColor.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let metaParts = [plan.distance, plan.elevation, plan.eventDate]
                .filter { !$0.isEmpty }
                .map { $0.uppercased() }
            if !metaParts.isEmpty {
                Text(metaParts.joined(separator: " · "))
                    .mangoxFont(.micro)
                    .tracking(1.0)
                    .foregroundStyle(AppColor.fg3)
                    .lineLimit(1)
            }
        }
        .padding(MangoxSpacing.lg.rawValue)
        .background(AppColor.bg2)
        .overlay(Rectangle().stroke(AppColor.hair2, lineWidth: 1))
    }

    private func inlineStat(label: String, value: String, color: Color) -> some View {
        HStack(spacing: MangoxSpacing.xs.rawValue) {
            Text(label)
                .mangoxFont(.micro)
                .tracking(1.0)
                .foregroundStyle(color.opacity(0.85))
            Text(value)
                .mangoxFont(.caption)
                .foregroundStyle(AppColor.fg1)
                .lineLimit(1)
        }
    }

    private func whoopChip(pct: Double) -> some View {
        HStack(spacing: MangoxSpacing.xs.rawValue) {
            Image(systemName: "waveform.path.ecg")
                .font(MangoxFont.micro.value)
                .foregroundStyle(AppColor.whoop)
            Text(String(format: "WHOOP %.0f%%", pct))
                .mangoxFont(.micro)
                .tracking(1.0)
                .foregroundStyle(viewModel.whoopReadinessAccentColor)
        }
        .padding(.horizontal, MangoxSpacing.sm.rawValue)
        .padding(.vertical, 4)
        .overlay(Rectangle().stroke(AppColor.whoop.opacity(0.32), lineWidth: 1))
    }

    // MARK: - Expansion state

    private var todayDay: PlanDay? {
        guard let todayID = todayDayID else { return nil }
        return currentWeek?.days.first { $0.id == todayID }
    }

    private func seedExpansion() {
        if let id = todayDayID, !expandedDayIDs.contains(id) {
            expandedDayIDs.insert(id)
        }
    }

    private func statusGlyph(for status: PlanDayStatus) -> (symbol: String, color: Color)? {
        switch status {
        case .completed: return ("checkmark", AppColor.success)
        case .skipped: return ("minus", AppColor.fg3)
        case .inProgress: return ("circle.fill", AppColor.mango)
        case .upcoming: return nil
        }
    }

    private func toggleExpanded(_ id: String) {
        if expandedDayIDs.contains(id) {
            expandedDayIDs.remove(id)
        } else {
            expandedDayIDs.insert(id)
        }
    }

    // MARK: - Sticky CTA

    private var stickyCTAVisible: Bool {
        guard let today = todayDay else { return false }
        let status = progress?.status(for: today.id) ?? .upcoming
        guard status != .completed && status != .skipped else { return false }
        switch today.dayType {
        case .workout, .optionalWorkout, .commute, .ftpTest, .race:
            return true
        case .rest, .event:
            return false
        }
    }

    @ViewBuilder
    private func stickyTodayCTA(day: PlanDay) -> some View {
        HStack(spacing: MangoxSpacing.md.rawValue) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TODAY")
                    .mangoxFont(.micro)
                    .tracking(1.2)
                    .foregroundStyle(AppColor.mango)
                Text(day.title)
                    .mangoxFont(.bodyBold)
                    .foregroundStyle(AppColor.fg0)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                switch day.dayType {
                case .ftpTest: viewModel.requestFTPSetup()
                default: viewModel.requestPlanWorkout(planID: plan.id, dayID: day.id)
                }
            } label: {
                HStack(spacing: MangoxSpacing.xs.rawValue) {
                    Image(systemName: day.dayType == .ftpTest ? "bolt.heart.fill" : "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(day.dayType == .ftpTest ? "FTP TEST" : "START RIDE")
                        .mangoxFont(.label)
                        .tracking(1.4)
                }
                .foregroundStyle(.black)
                .padding(.horizontal, MangoxSpacing.lg.rawValue)
                .padding(.vertical, MangoxSpacing.md.rawValue)
                .background(AppColor.mango)
                .overlay(Rectangle().stroke(AppColor.mango, lineWidth: 1))
            }
        }
        .padding(.horizontal, MangoxSpacing.lg.rawValue)
        .padding(.vertical, MangoxSpacing.md.rawValue)
        .background(AppColor.bg1)
        .overlay(Rectangle().stroke(AppColor.hair2, lineWidth: 1))
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
                            VStack(spacing: 6) {
                                Text("W\(week.weekNumber)")
                                    .mangoxFont(.caption)
                                    .foregroundStyle(isSelected ? AppColor.fg0 : AppColor.fg2)

                                Text(week.phase.prefix(4).uppercased())
                                    .mangoxFont(.micro)
                                    .foregroundStyle(phaseColor(week.phase).opacity(isSelected ? 0.9 : 0.5))
                                    .tracking(0.8)

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Rectangle()
                                            .fill(AppColor.bg4)
                                        Rectangle()
                                            .fill(phaseColor(week.phase))
                                            .frame(width: max(0, geo.size.width * weekProgress))
                                    }
                                }
                                .frame(height: 2)
                            }
                            .frame(width: 54)
                            .padding(.vertical, 8)
                            .background(isSelected ? AppColor.bg2 : AppColor.bg1)
                            .overlay(
                                Rectangle()
                                    .stroke(
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

    private func dynamicDayLabel(for day: PlanDay, calendarDate: Date?) -> String {
        guard let calendarDate else { return day.dayLabel }
        return Self.dayLabelFormatter.string(from: calendarDate)
    }

    // MARK: - Day Card


    private func dayCard(day: PlanDay, week: PlanWeek) -> some View {
        let status = progress?.status(for: day.id) ?? .upcoming
        let isToday = todayDayID == day.id
        let calendarDate = progress?.calendarDate(for: day)
        let isExpanded = isToday || expandedDayIDs.contains(day.id)

        return Group {
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        if !isToday { toggleExpanded(day.id) }
                    } label: {
                        dayHeaderRow(day: day, status: status, isToday: isToday, calendarDate: calendarDate)
                            .padding(.horizontal, MangoxSpacing.lg.rawValue)
                            .padding(.top, MangoxSpacing.md.rawValue)
                    }
                    .buttonStyle(.plain)

                    daySummaryRow(day: day, status: status)
                        .padding(.horizontal, MangoxSpacing.lg.rawValue)
                        .padding(.top, MangoxSpacing.sm.rawValue)

                    if day.hasStructuredIntervals {
                        dayWorkoutProfile(day: day)
                            .padding(.horizontal, MangoxSpacing.lg.rawValue)
                            .padding(.top, MangoxSpacing.md.rawValue)
                    }

                    if status == .completed, let w = matchingCompletedWorkout(dayID: day.id) {
                        planDayPlannedVsActualMini(day: day, workout: w)
                            .padding(.horizontal, MangoxSpacing.lg.rawValue)
                            .padding(.top, MangoxSpacing.sm.rawValue)
                    }

                    if day.hasStructuredIntervals && status != .completed {
                        intervalPreview(day: day)
                            .padding(.horizontal, MangoxSpacing.lg.rawValue)
                            .padding(.top, MangoxSpacing.sm.rawValue)
                    }

                    dayActions(day: day, status: status)
                        .padding(.horizontal, MangoxSpacing.lg.rawValue)
                        .padding(.top, MangoxSpacing.md.rawValue)
                        .padding(.bottom, MangoxSpacing.md.rawValue)
                }
            } else {
                Button {
                    toggleExpanded(day.id)
                } label: {
                    dayCompactRow(day: day, status: status, calendarDate: calendarDate)
                }
                .buttonStyle(.plain)
            }
        }
        .background(isToday ? AppColor.mango.opacity(0.04) : AppColor.bg2)
        .overlay(
            Rectangle()
                .stroke(
                    isToday ? AppColor.mango.opacity(0.35) : AppColor.hair,
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.18), value: expandedDayIDs)
    }

    private func dayCompactRow(day: PlanDay, status: PlanDayStatus, calendarDate: Date?) -> some View {
        let plannedTSS = day.estimatedPlannedTSS(ftp: PowerZone.ftp)
        let glyph = statusGlyph(for: status)

        return HStack(spacing: MangoxSpacing.sm.rawValue) {
            ZStack {
                if let glyph {
                    Image(systemName: glyph.symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(glyph.color)
                }
            }
            .frame(width: 10)

            Text(dynamicDayLabel(for: day, calendarDate: calendarDate).uppercased())
                .mangoxFont(.label)
                .tracking(1.2)
                .foregroundStyle(AppColor.fg2)
                .frame(width: 32, alignment: .leading)

            if let calendarDate {
                Text(calendarDate, format: .dateTime.month(.abbreviated).day())
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg3)
                    .frame(width: 48, alignment: .leading)
            }

            Rectangle()
                .fill(day.zone.color)
                .frame(width: 2, height: 16)
                .opacity(day.dayType == .rest ? 0.3 : 0.8)

            Text(day.title)
                .mangoxFont(.body)
                .foregroundStyle(status == .completed ? AppColor.fg2 : AppColor.fg1)
                .strikethrough(status == .skipped, color: AppColor.fg3)
                .lineLimit(1)

            Spacer(minLength: MangoxSpacing.sm.rawValue)

            if plannedTSS > 0 {
                Text("\(Int(plannedTSS)) TSS")
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg2)
            }

            if day.dayType != .rest {
                Text(day.zone.label)
                    .mangoxFont(.micro)
                    .tracking(0.8)
                    .foregroundStyle(AppColor.fg3)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppColor.fg3)
        }
        .padding(.horizontal, MangoxSpacing.lg.rawValue)
        .padding(.vertical, MangoxSpacing.md.rawValue)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(compactRowAccessibilityLabel(day: day, status: status, calendarDate: calendarDate, plannedTSS: plannedTSS))
        .accessibilityHint("Double tap to expand")
    }

    private func compactRowAccessibilityLabel(day: PlanDay, status: PlanDayStatus, calendarDate: Date?, plannedTSS: Double) -> String {
        var parts: [String] = []
        if let calendarDate {
            parts.append(calendarDate.formatted(date: .complete, time: .omitted))
        } else {
            parts.append(day.dayLabel)
        }
        parts.append(day.title)
        if plannedTSS > 0 { parts.append("\(Int(plannedTSS)) TSS") }
        if day.dayType != .rest { parts.append("zone \(day.zone.label)") }
        switch status {
        case .completed: parts.append("completed")
        case .skipped: parts.append("skipped")
        case .inProgress: parts.append("in progress")
        case .upcoming: parts.append("upcoming")
        }
        return parts.joined(separator: ", ")
    }

    private func dayHeaderRow(day: PlanDay, status: PlanDayStatus, isToday: Bool, calendarDate: Date?) -> some View {
        HStack(spacing: MangoxSpacing.sm.rawValue) {
            Text(dynamicDayLabel(for: day, calendarDate: calendarDate).uppercased())
                .mangoxFont(.label)
                .tracking(1.2)
                .foregroundStyle(AppColor.fg2)
                .frame(width: 32, alignment: .leading)

            if let calendarDate {
                Text(calendarDate, format: .dateTime.month(.abbreviated).day())
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg3)
            }

            if isToday {
                Text("TODAY")
                    .mangoxFont(.micro)
                    .tracking(1.0)
                    .foregroundStyle(.black)
                    .padding(.horizontal, MangoxSpacing.sm.rawValue)
                    .padding(.vertical, 2)
                    .background(AppColor.mango)
            }

            if day.isKeyWorkout {
                Image(systemName: "star.fill")
                    .font(MangoxFont.micro.value)
                    .foregroundStyle(AppColor.yellow)
            }

            if day.requiresFTPTest {
                Image(systemName: "bolt.heart.fill")
                    .font(MangoxFont.micro.value)
                    .foregroundStyle(AppColor.orange)
            }

            Spacer()

            statusBadge(status: status)

            if !isToday {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppColor.fg3)
                    .rotationEffect(.degrees(expandedDayIDs.contains(day.id) ? 180 : 0))
                    .animation(.easeInOut(duration: 0.18), value: expandedDayIDs)
            }
        }
    }

    private func daySummaryRow(day: PlanDay, status: PlanDayStatus) -> some View {
        HStack(alignment: .top, spacing: MangoxSpacing.md.rawValue) {
            Rectangle()
                .fill(day.zone.color)
                .frame(width: 2, height: 40)
                .opacity(day.dayType == .rest ? 0.3 : 0.8)

            VStack(alignment: .leading, spacing: MangoxSpacing.xs.rawValue) {
                HStack(spacing: MangoxSpacing.sm.rawValue) {
                    dayTypeIcon(day.dayType)
                    Text(day.title)
                        .mangoxFont(.bodyBold)
                        .foregroundStyle(status == .completed ? AppColor.fg2 : AppColor.fg0)
                        .strikethrough(status == .skipped, color: AppColor.fg3)
                }

                HStack(spacing: MangoxSpacing.sm.rawValue) {
                    if day.durationMinutes > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundStyle(AppColor.fg3)
                            Text(day.formattedDuration)
                                .mangoxFont(.caption)
                                .foregroundStyle(AppColor.fg2)
                        }
                    }

                    if day.zone != .rest && day.zone != .none {
                        Text(day.zone.label)
                            .mangoxFont(.caption)
                            .foregroundStyle(day.zone.color)
                            .padding(.horizontal, MangoxSpacing.sm.rawValue)
                            .padding(.vertical, 2)
                            .background(AppColor.bg1)
                            .overlay(Rectangle().stroke(day.zone.color.opacity(0.35), lineWidth: 1))
                    }

                    if day.hasStructuredIntervals {
                        HStack(spacing: 4) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(AppColor.fg3)
                            Text("\(day.intervals.count) segments")
                                .mangoxFont(.caption)
                                .foregroundStyle(AppColor.fg3)
                        }
                    }
                }

                if !day.notes.isEmpty {
                    Text(day.notes)
                        .mangoxFont(.body)
                        .foregroundStyle(AppColor.fg3)
                        .lineLimit(2)
                        .padding(.top, 1)
                }
            }

            Spacer()
        }
    }

    private func planDayPlannedVsActualMini(day: PlanDay, workout: Workout) -> some View {
        let ftp = PowerZone.ftp
        let plannedTSS = day.estimatedPlannedTSS(ftp: ftp)
        let plannedMin = day.durationMinutes
        let actualTSS = workout.tss
        let actualMin = max(1, Int(workout.duration / 60))

        return VStack(alignment: .leading, spacing: MangoxSpacing.sm.rawValue) {
            Text("LOGGED VS PLAN")
                .mangoxFont(.micro)
                .tracking(1.0)
                .foregroundStyle(AppColor.fg3)
            HStack {
                Text(
                    plannedMin > 0
                        ? "Plan \(plannedMin) min · est. TSS \(Int(plannedTSS))"
                        : "Plan est. TSS \(Int(plannedTSS))"
                )
                .mangoxFont(.caption)
                .foregroundStyle(AppColor.fg2)
                Spacer()
                Text("\(actualMin) min · TSS \(Int(actualTSS))")
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.yellow)
            }
        }
        .padding(MangoxSpacing.md.rawValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.bg1)
        .overlay(Rectangle().stroke(AppColor.hair, lineWidth: 1))
    }

    private func dayWorkoutProfile(day: PlanDay) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(day.intervals.prefix(7).enumerated()), id: \.offset) { _, segment in
                Rectangle()
                    .fill(segment.zone.color)
                    .frame(maxWidth: .infinity)
                    .frame(height: intervalBarHeight(for: segment.zone))
            }
        }
        .frame(height: 38, alignment: .bottom)
    }

    private func intervalBarHeight(for zone: TrainingZoneTarget) -> CGFloat {
        switch zone {
        case .rest, .none:
            return 10
        case .z1, .z1z2:
            return 14
        case .z2, .z2z3:
            return 20
        case .z3, .z3z4, .mixed:
            return 28
        case .z4, .z4z5, .all:
            return 32
        case .z5, .z3z5:
            return 36
        }
    }

    // MARK: - Interval Preview

    private func intervalPreview(day: PlanDay) -> some View {
        VStack(alignment: .leading, spacing: MangoxSpacing.xs.rawValue) {
            ForEach(day.intervals) { segment in
                HStack(spacing: MangoxSpacing.sm.rawValue) {
                    Rectangle()
                        .fill(segment.zone.color)
                        .frame(width: 6, height: 6)

                    Text(segment.name)
                        .mangoxFont(.caption)
                        .foregroundStyle(AppColor.fg2)

                    if segment.repeats > 1 {
                        Text("\(segment.repeats)x")
                            .mangoxFont(.micro)
                            .foregroundStyle(AppColor.yellow)
                    }

                    Text(formatSeconds(segment.durationSeconds))
                        .mangoxFont(.micro)
                        .foregroundStyle(AppColor.fg3)

                    Text(segment.zone.label)
                        .mangoxFont(.micro)
                        .foregroundStyle(segment.zone.color)

                    if let low = segment.cadenceLow, let high = segment.cadenceHigh {
                        Text("\(low)–\(high) RPM")
                            .mangoxFont(.micro)
                            .foregroundStyle(AppColor.fg3)
                    }

                    Spacer()
                }
            }
        }
        .padding(MangoxSpacing.md.rawValue)
        .background(AppColor.bg1)
        .overlay(Rectangle().stroke(AppColor.hair, lineWidth: 1))
    }

    // MARK: - Day Actions

    private enum ActionStyle {
        case primary(Color)   // filled block, black text
        case secondary(Color) // hairline block, accent text
        case ghost            // subtle block, muted text
    }

    @ViewBuilder
    private func actionButton(_ title: String, icon: String, style: ActionStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: MangoxSpacing.xs.rawValue) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .mangoxFont(.caption)
            }
            .padding(.horizontal, MangoxSpacing.md.rawValue)
            .padding(.vertical, MangoxSpacing.sm.rawValue)
            .foregroundStyle(actionFg(style))
            .background(actionBg(style))
            .overlay(Rectangle().stroke(actionBorder(style), lineWidth: 1))
        }
    }

    private func actionFg(_ style: ActionStyle) -> Color {
        switch style {
        case .primary: return .black
        case .secondary(let c): return c
        case .ghost: return AppColor.fg2
        }
    }

    private func actionBg(_ style: ActionStyle) -> Color {
        switch style {
        case .primary(let c): return c
        case .secondary(let c): return c.opacity(0.08)
        case .ghost: return AppColor.bg1
        }
    }

    private func actionBorder(_ style: ActionStyle) -> Color {
        switch style {
        case .primary(let c): return c
        case .secondary(let c): return c.opacity(0.3)
        case .ghost: return AppColor.hair
        }
    }

    private func statusReadout(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: MangoxSpacing.sm.rawValue) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text(text.uppercased())
                .mangoxFont(.label)
                .tracking(1.2)
                .foregroundStyle(AppColor.fg2)
        }
    }

    @ViewBuilder
    private func dayActions(day: PlanDay, status: PlanDayStatus) -> some View {
        HStack(spacing: MangoxSpacing.sm.rawValue) {
            switch day.dayType {
            case .workout, .optionalWorkout, .commute:
                if status == .completed {
                    actionButton("Undo", icon: "arrow.uturn.backward", style: .ghost) {
                        viewModel.unmark(day.id, progress: progress)
                    }
                } else if status == .skipped {
                    actionButton("Undo Skip", icon: "arrow.uturn.backward", style: .ghost) {
                        viewModel.unmark(day.id, progress: progress)
                    }
                } else {
                    actionButton("Start Ride", icon: "play.fill", style: .primary(AppColor.mango)) {
                        viewModel.requestPlanWorkout(planID: plan.id, dayID: day.id)
                    }
                    actionButton("Done", icon: "checkmark", style: .secondary(AppColor.success)) {
                        viewModel.markCompleted(day.id, progress: progress)
                    }
                    actionButton("Skip", icon: "forward.fill", style: .ghost) {
                        viewModel.markSkipped(day.id, progress: progress)
                    }
                }

            case .ftpTest:
                if status == .completed {
                    statusReadout(icon: "checkmark.circle.fill", text: "FTP Test Complete", color: AppColor.success)
                    actionButton("Undo", icon: "arrow.uturn.backward", style: .ghost) {
                        viewModel.unmark(day.id, progress: progress)
                    }
                } else {
                    actionButton("Take FTP Test", icon: "bolt.heart.fill", style: .primary(AppColor.yellow)) {
                        viewModel.requestFTPSetup()
                    }
                    actionButton("Done", icon: "checkmark", style: .secondary(AppColor.success)) {
                        viewModel.markCompleted(day.id, progress: progress)
                    }
                }

            case .rest:
                if status != .completed {
                    actionButton("Rest Day Complete", icon: "checkmark.circle", style: .secondary(AppColor.blue)) {
                        viewModel.markCompleted(day.id, progress: progress)
                    }
                } else {
                    statusReadout(icon: "moon.fill", text: "Rested", color: AppColor.blue)
                }

            case .race:
                if status != .completed {
                    actionButton("I Finished the Race", icon: "flag.checkered", style: .primary(AppColor.yellow)) {
                        viewModel.markCompleted(day.id, progress: progress)
                    }
                } else {
                    statusReadout(icon: "trophy.fill", text: "Race Complete", color: AppColor.yellow)
                }

            case .event:
                if status != .completed {
                    actionButton("Done", icon: "checkmark", style: .ghost) {
                        viewModel.markCompleted(day.id, progress: progress)
                    }
                } else {
                    statusReadout(icon: "checkmark.circle.fill", text: "Done", color: AppColor.success)
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
                                .font(.system(size: 32))
                                .foregroundStyle(AppColor.mango)

                            Text("START TRAINING PLAN")
                                .mangoxFont(.label)
                                .tracking(1.6)
                                .foregroundStyle(AppColor.mango)

                            Text(plan.eventName)
                                .mangoxFont(.title)
                                .foregroundStyle(AppColor.fg0)

                            Text("Pick the Monday you want Week 1 to start. Your \(plan.totalWeeks)-week plan maps from this date through each day on the calendar.")
                                .mangoxFont(.body)
                                .foregroundStyle(AppColor.fg2)
                                .multilineTextAlignment(.center)
                        }

                        DatePicker(
                            "Start Date (Monday)",
                            selection: binding(\.planStartDate),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .tint(AppColor.mango)
                        .colorScheme(.dark)

                        VStack(alignment: .leading, spacing: MangoxSpacing.sm.rawValue) {
                            HStack {
                                Text("CURRENT FTP")
                                    .mangoxFont(.label)
                                    .tracking(1.4)
                                    .foregroundStyle(AppColor.fg3)
                                Spacer()
                                Text("\(PowerZone.ftp)W")
                                    .mangoxFont(.caption)
                                    .foregroundStyle(AppColor.fg0)
                            }

                            if PowerZone.ftp == 265 {
                                HStack(spacing: MangoxSpacing.sm.rawValue) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(AppColor.orange)
                                    Text("Using default FTP. Take the FTP test in Week 1 for accurate zones.")
                                        .mangoxFont(.body)
                                        .foregroundStyle(AppColor.orange)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(MangoxSpacing.lg.rawValue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColor.bg2)
                        .overlay(Rectangle().stroke(AppColor.hair2, lineWidth: 1))

                        Button {
                            startPlan()
                            viewModel.showStartPlanSheet = false
                        } label: {
                            HStack(spacing: MangoxSpacing.sm.rawValue) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("BEGIN PLAN")
                                    .mangoxFont(.label)
                                    .tracking(1.6)
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, MangoxSpacing.lg.rawValue)
                            .background(AppColor.mango)
                            .overlay(Rectangle().stroke(AppColor.mango, lineWidth: 1))
                        }
                    }
                    .padding(MangoxSpacing.xl.rawValue)
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
                    .foregroundStyle(AppColor.fg2)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helper Views

    private func eventStat(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: MangoxSpacing.xs.rawValue) {
            Text(label.uppercased())
                .mangoxFont(.micro)
                .tracking(1.2)
                .foregroundStyle(AppColor.fg3)
            HStack(spacing: MangoxSpacing.xs.rawValue) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(AppColor.fg2)
                Text(value)
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg1)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func requirementRow(icon: String, text: String, met: Bool, note: String? = nil) -> some View {
        HStack(spacing: MangoxSpacing.md.rawValue) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(met ? AppColor.success : AppColor.orange)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                    .mangoxFont(.body)
                    .foregroundStyle(AppColor.fg1)
                if let note {
                    Text(note)
                        .mangoxFont(.micro)
                        .foregroundStyle(met ? AppColor.fg3 : AppColor.orange)
                }
            }

            Spacer()

            Image(systemName: met ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(met ? AppColor.success : AppColor.orange)
        }
    }

    private func statusBadge(status: PlanDayStatus) -> some View {
        Group {
            switch status {
            case .completed:
                HStack(spacing: MangoxSpacing.xs.rawValue) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                    Text("DONE")
                        .mangoxFont(.micro)
                        .tracking(1.0)
                }
                .foregroundStyle(AppColor.success)

            case .skipped:
                HStack(spacing: MangoxSpacing.xs.rawValue) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 10))
                    Text("SKIPPED")
                        .mangoxFont(.micro)
                        .tracking(1.0)
                }
                .foregroundStyle(AppColor.orange)

            case .inProgress:
                HStack(spacing: MangoxSpacing.xs.rawValue) {
                    Image(systemName: "figure.indoor.cycle")
                        .font(.system(size: 10))
                    Text("IN PROGRESS")
                        .mangoxFont(.micro)
                        .tracking(1.0)
                }
                .foregroundStyle(AppColor.mango)

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
                    .foregroundStyle(AppColor.success)
            case .rest:
                Image(systemName: "moon.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.blue.opacity(0.6))
            case .race:
                Image(systemName: "flag.checkered")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.yellow)
            case .event:
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            case .ftpTest:
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.orange)
            case .optionalWorkout:
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
            case .commute:
                Image(systemName: "bicycle.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.blue.opacity(0.85))
            }
        }
    }

    // MARK: - Helper Functions

    private func phaseColor(_ phase: String) -> Color {
        switch phase.lowercased() {
        case "foundation": return AppColor.blue
        case "build": return AppColor.orange
        case "taper": return AppColor.success
        case "race": return AppColor.yellow
        default: return AppColor.success
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
    let previewPlan = TrainingPlan(
        id: "preview-plan",
        name: "Preview Plan",
        eventName: "Sample Event",
        eventDate: "",
        distance: "",
        elevation: "",
        location: "",
        description: "",
        weeks: []
    )
    TrainingPlanView(
        navigationPath: .constant(NavigationPath()),
        plan: previewPlan,
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
