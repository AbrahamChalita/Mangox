import SwiftUI
import SwiftData

// MARK: - Layout mode (persisted, like Apple Calendar)

private enum CalendarScreenMode: String, CaseIterable, Identifiable {
    case monthGrid
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthGrid: return "Calendar"
        case .list: return "List"
        }
    }
}

// MARK: - Calendar workout query (bounded, documented)

/// Keeps calendar responsive: time window + hard row cap. Limits are summarized under the layout picker.
private enum CalendarWorkoutQuery {
    /// How far back the calendar includes rides (anchor is fixed when the descriptor is first created for the process).
    static let includedHistoryYears = 5
    static let maxRows = 12_000

    static let descriptor: FetchDescriptor<Workout> = {
        let cutoff =
            Calendar.current.date(byAdding: .year, value: -includedHistoryYears, to: Date())
            ?? .distantPast
        var d = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.startDate >= cutoff
            },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        d.fetchLimit = maxRows
        return d
    }()
}

/// Calendar month view showing ride history, with an optional list layout.
/// Each day shows a colored dot for rides, with tap-to-inspect.
struct CalendarView: View {
    @Environment(DIContainer.self) private var di
    @Environment(\.modelContext) private var modelContext
    @Binding var navigationPath: NavigationPath

    @Query(CalendarWorkoutQuery.descriptor) private var allWorkouts: [Workout]

    @AppStorage("calendarScreenMode") private var screenModeRaw = CalendarScreenMode.monthGrid.rawValue

    @State private var currentMonth: Date = Date()
    @State private var selectedDay: Date? = Date()
    /// Sorted sections for list mode (kept in sync with `workoutsByDayStart`).
    @State private var workoutsGroupedByDay: [(day: Date, workouts: [Workout])] = []
    /// O(1) day lookup for month cells (avoids scanning all workouts per cell).
    @State private var workoutsByDayStart: [Date: [Workout]] = [:]
    @State private var calendarRegroupTask: Task<Void, Never>?

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var screenMode: CalendarScreenMode {
        CalendarScreenMode(rawValue: screenModeRaw) ?? .monthGrid
    }

    /// Always derived from `allWorkouts` so deletes (e.g. from Summary) remove rows immediately.
    /// Storing this in `@State` left stale `Workout` references after deletion.
    private var selectedDayWorkouts: [Workout] {
        guard let day = selectedDay else { return [] }
        return workouts(for: day)
    }

    var body: some View {
        ZStack {
            AppColor.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                Picker("View layout", selection: $screenModeRaw) {
                    ForEach(CalendarScreenMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                calendarQueryScopeFootnote
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                if screenMode == .monthGrid {
                    monthCalendarContent
                } else {
                    listContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onChange(of: screenModeRaw) { _, _ in
            if screenMode == .list {
                selectedDay = nil
            }
        }
        .onChange(of: allWorkouts, initial: true) { _, workouts in
            applyCalendarWorkoutChanges(workouts)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mangoxWorkoutAggregatesMayHaveChanged)) {
            _ in
            applyCalendarWorkoutChanges(allWorkouts)
        }
    }

    /// One full scan to refresh indexes; debounced after the first population to coalesce SwiftData bursts.
    private func applyCalendarWorkoutChanges(_ workouts: [Workout]) {
        if workouts.isEmpty {
            calendarRegroupTask?.cancel()
            rebuildCalendarIndexes(from: workouts)
            return
        }
        if workoutsByDayStart.isEmpty {
            calendarRegroupTask?.cancel()
            rebuildCalendarIndexes(from: workouts)
        } else {
            calendarRegroupTask?.cancel()
            calendarRegroupTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(56))
                guard !Task.isCancelled else { return }
                rebuildCalendarIndexes(from: workouts)
            }
        }
    }

    private func rebuildCalendarIndexes(from workouts: [Workout]) {
        let grouped = Dictionary(grouping: workouts) { calendar.startOfDay(for: $0.startDate) }
        var byDay: [Date: [Workout]] = [:]
        byDay.reserveCapacity(grouped.count)
        for (day, items) in grouped {
            byDay[day] = items.sorted { $0.startDate > $1.startDate }
        }
        workoutsByDayStart = byDay
        workoutsGroupedByDay = byDay.keys.sorted(by: >).map { day in (day, byDay[day]!) }
    }

    /// Surfaces the same bounds as `CalendarWorkoutQuery` so the calendar tradeoffs aren’t hidden.
    private var calendarQueryScopeFootnote: some View {
        VStack(spacing: 6) {
            Text(
                "Shows rides from about the last \(CalendarWorkoutQuery.includedHistoryYears) years, up to \(CalendarWorkoutQuery.maxRows.formatted()) entries."
            )
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.3))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            if allWorkouts.count >= CalendarWorkoutQuery.maxRows {
                Text("You’re at that entry cap—some rides in this window may not appear.")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColor.mango.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Month grid

    private var monthCalendarContent: some View {
        VStack(spacing: 0) {
            // Month navigation
            HStack {
                Button { changeMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Text(currentMonth, format: .dateTime.month(.wide).year())
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button { changeMonth(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            // Weekday headers
            HStack(spacing: 0) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.25))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 0) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, date in
                            if let date {
                                dayCell(date: date)
                            } else {
                                Color.clear.frame(height: 40)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // Selected day detail
                    if let day = selectedDay {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(day, format: .dateTime.weekday(.wide).month(.wide).day())
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.horizontal, 20)

                            if selectedDayWorkouts.isEmpty {
                                selectedDayEmptyState(date: day)
                            } else {
                                ForEach(selectedDayWorkouts) { workout in
                                    Button {
                                        navigationPath.append(AppRoute.summary(workoutID: workout.id))
                                    } label: {
                                        WorkoutRowView(
                                            workout: workout,
                                            trainingPlanLookupService: di.trainingPlanLookupService
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 16)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - List (all rides, grouped by day)

    private var listContent: some View {
        Group {
            if allWorkouts.isEmpty {
                emptyRidesPlaceholder
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(workoutsGroupedByDay, id: \.day) { group in
                            Section {
                                ForEach(group.workouts) { workout in
                                    Button {
                                        navigationPath.append(AppRoute.summary(workoutID: workout.id))
                                    } label: {
                                        WorkoutRowView(
                                            workout: workout,
                                            trainingPlanLookupService: di.trainingPlanLookupService
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.bottom, 8)
                                }
                            } header: {
                                listSectionHeader(day: group.day, workouts: group.workouts)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func listSectionHeader(day: Date, workouts: [Workout]) -> some View {
        let dayTSS = workouts.reduce(0.0) { $0 + $1.tss }
        return HStack {
            Text(day, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            if dayTSS > 0 {
                Text(String(format: "%.0f TSS", dayTSS))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .padding(.vertical, 10)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.bg)
    }

    private var emptyRidesPlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.outdoor.cycle")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.18))
            Text("No rides yet")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.45))
            Text("Complete a ride to see it here.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.28))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Calendar")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white.opacity(AppOpacity.textPrimary))

            Spacer()

            // Weekly TSS badge
            let weekTSS = tssThisWeek()
            if weekTSS > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 10))
                    Text("\(Int(weekTSS)) TSS")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(AppOpacity.cardBg))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(AppOpacity.cardBorder), lineWidth: 1)
                )
            }

        }
    }

    // MARK: - Selected day empty

    private func selectedDayEmptyState(date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: "calendar.badge.minus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))

            Text(isToday ? "No workouts today" : "No workouts on this day")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Day Cell

    @ViewBuilder
    private func dayCell(date: Date) -> some View {
        let dayWorkouts = workouts(for: date)
        let hasRide = !dayWorkouts.isEmpty
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDay ?? .distantPast)
        let isToday = calendar.isDateInToday(date)
        let dayTSS = dayWorkouts.reduce(0.0) { $0 + $1.tss }

        Button {
            selectedDay = isSelected ? nil : date
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 14, weight: isToday ? .bold : .medium))
                    .foregroundStyle(isToday ? AppColor.mango : .white.opacity(hasRide ? 0.8 : 0.3))

                if hasRide {
                    Circle()
                        .fill(tssColor(dayTSS))
                        .frame(width: 6, height: 6)
                } else {
                    Spacer().frame(height: 6)
                }
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.white.opacity(0.10) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var daysInMonth: [Date?] {
        guard let monthRange = calendar.range(of: .day, in: .month, for: currentMonth),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) else {
            return []
        }
        let weekday = calendar.component(.weekday, from: firstOfMonth) - 1
        let blanks = Array(repeating: nil as Date?, count: weekday)
        let days = monthRange.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)
        }
        return blanks + days
    }

    private func hasRide(on date: Date) -> Bool {
        workouts(for: date).count > 0
    }

    private func workouts(for date: Date) -> [Workout] {
        let startOfDay = calendar.startOfDay(for: date)
        return workoutsByDayStart[startOfDay] ?? []
    }

    private func changeMonth(by offset: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: offset, to: currentMonth) {
            currentMonth = newMonth
            selectedDay = nil
        }
    }

    private func tssColor(_ tss: Double) -> Color {
        if tss < 50 { return AppColor.success }
        if tss < 150 { return AppColor.yellow }
        if tss < 300 { return AppColor.orange }
        return AppColor.red
    }

    private func tssThisWeek() -> Double {
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) else {
            return 0
        }
        if workoutsByDayStart.isEmpty {
            return allWorkouts
                .filter { $0.startDate >= weekStart }
                .reduce(0.0) { $0 + $1.tss }
        }
        var total = 0.0
        for i in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: i, to: weekStart) else { continue }
            let sod = calendar.startOfDay(for: day)
            total += workoutsByDayStart[sod]?.reduce(0.0) { $0 + $1.tss } ?? 0
        }
        return total
    }
}
