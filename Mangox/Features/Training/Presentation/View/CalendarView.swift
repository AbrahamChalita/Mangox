import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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

private enum WorkoutHistoryFilter: String, CaseIterable, Identifiable {
    case all
    case outdoor
    case indoor
    case planned
    case imported

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .outdoor: return "Outdoor"
        case .indoor: return "Indoor"
        case .planned: return "Planned"
        case .imported: return "Imported"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "line.3.horizontal.decrease.circle"
        case .outdoor: return "mountain.2"
        case .indoor: return "bolt.heart"
        case .planned: return "calendar.badge.checkmark"
        case .imported: return "square.and.arrow.down"
        }
    }

    func includes(_ workout: Workout) -> Bool {
        switch self {
        case .all:
            return true
        case .outdoor:
            return workout.savedRouteKind != nil
        case .indoor:
            return workout.savedRouteKind == nil && workout.planDayID == nil && !workout.isImported
        case .planned:
            return workout.planDayID != nil
        case .imported:
            return workout.isImported
        }
    }
}

private enum WorkoutImportPickerError: LocalizedError {
    case unsupportedFileType

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "Select a .tcx or .fit workout file."
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
    let di: DIContainer
    @Binding var navigationPath: NavigationPath

    @Query(CalendarWorkoutQuery.descriptor) private var allWorkouts: [Workout]

    @AppStorage("calendarScreenMode") private var screenModeRaw = CalendarScreenMode.monthGrid.rawValue
    @AppStorage("workoutHistoryFilter") private var historyFilterRaw = WorkoutHistoryFilter.all.rawValue

    @State private var currentMonth: Date = Date()
    @State private var selectedDay: Date? = Date()
    /// Sorted sections for list mode (kept in sync with `workoutsByDayStart`).
    @State private var workoutsGroupedByDay: [(day: Date, workouts: [Workout])] = []
    /// O(1) day lookup for month cells (avoids scanning all workouts per cell).
    @State private var workoutsByDayStart: [Date: [Workout]] = [:]
    @State private var calendarRegroupTask: Task<Void, Never>?
    @State private var showWorkoutImporter = false
    @State private var workoutImportError: String?
    @State private var showWorkoutImportErrorOverlay = false
    @State private var isImportingWorkout = false
    @State private var filteredWorkoutGroups: [(day: Date, workouts: [Workout])] = []
    @State private var filteredWorkoutTotal = 0
    @Namespace private var layoutModeSelectionNamespace

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var screenMode: CalendarScreenMode {
        CalendarScreenMode(rawValue: screenModeRaw) ?? .monthGrid
    }

    private var historyFilter: WorkoutHistoryFilter {
        WorkoutHistoryFilter(rawValue: historyFilterRaw) ?? .all
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

                layoutModeGlassSwitcher
                    .padding(.horizontal, 20)

                subviewStatusRow
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                if allWorkouts.count >= CalendarWorkoutQuery.maxRows {
                    calendarQueryScopeFootnote
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                } else {
                    Color.clear
                        .frame(height: 12)
                }

                if screenMode == .monthGrid {
                    monthCalendarContent
                } else {
                    listContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if showWorkoutImportErrorOverlay {
                MangoxConfirmOverlay(
                    title: "Workout Import Failed",
                    message: workoutImportError ?? "",
                    onDismiss: clearWorkoutImportError
                ) {
                    Button {
                        clearWorkoutImportError()
                    } label: {
                        Text("OK")
                            .mangoxButtonChrome(.hero)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }
        }
        .onChange(of: screenModeRaw) { _, _ in
            if screenMode == .list {
                selectedDay = nil
            } else if selectedDay == nil {
                selectedDay = Date()
                currentMonth = Date()
            }
        }
        .onAppear {
            if screenMode == .monthGrid, selectedDay == nil {
                selectedDay = Date()
                currentMonth = Date()
            }
        }
        .onChange(of: allWorkouts, initial: true) { _, workouts in
            applyCalendarWorkoutChanges(workouts)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mangoxWorkoutAggregatesMayHaveChanged)) {
            _ in
            applyCalendarWorkoutChanges(allWorkouts)
        }
        .fileImporter(
            isPresented: $showWorkoutImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    await importWorkout(from: url)
                }
            case .failure(let error):
                workoutImportError = error.localizedDescription
            }
        }
        .onChange(of: workoutImportError) { _, value in
            showWorkoutImportErrorOverlay = value != nil
        }
        .onChange(of: historyFilterRaw, initial: true) { _, _ in
            recomputeFilteredWorkoutGroups()
        }
        .sensoryFeedback(.selection, trigger: screenModeRaw)
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
        recomputeFilteredWorkoutGroups()
    }

    /// Shows a warning only when the query cap is reached.
    private var calendarQueryScopeFootnote: some View {
        VStack(spacing: 6) {
            Text("You’re at that entry cap—some rides in this window may not appear.")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColor.mango.opacity(0.85))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
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
            if filteredWorkoutGroups.isEmpty {
                emptyRidesPlaceholder
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(filteredWorkoutGroups, id: \.day) { group in
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
            Image(systemName: historyFilter == .imported ? "square.and.arrow.down" : "figure.outdoor.cycle")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.18))
            Text(emptyStateTitle)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.45))
            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.28))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    // MARK: - Header

    private var layoutModeGlassSwitcher: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(CalendarScreenMode.allCases) { mode in
                    layoutModeSegment(mode)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View layout")
        .accessibilityValue(screenMode.title)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                setScreenMode(.list)
            case .decrement:
                setScreenMode(.monthGrid)
            @unknown default:
                break
            }
        }
    }

    private func layoutModeSegment(_ mode: CalendarScreenMode) -> some View {
        let isSelected = screenMode == mode

        return Button {
            setScreenMode(mode)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(0.001))

                if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(AppColor.mango.opacity(0.18))
                        .matchedGeometryEffect(id: "layout-mode-selected", in: layoutModeSelectionNamespace)
                }

                Text(mode.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        isSelected
                            ? .white.opacity(AppOpacity.textPrimary)
                            : .white.opacity(AppOpacity.textSecondary)
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.title)
        .accessibilityHint("Switch workout view")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Workouts")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white.opacity(AppOpacity.textPrimary))

            Spacer()

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    importWorkoutButton
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
    }

    private var subviewStatusRow: some View {
        Group {
            if screenMode == .list {
                listFilterChips
            } else {
                Color.clear.frame(height: 0)
            }
        }
    }

    /// Horizontal filter chips — replaces the previous "count left / menu right"
    /// imbalance. Each filter is directly tappable; the active chip is mango-
    /// tinted and carries its own count inline as a tight trailing badge.
    /// Scrolls horizontally so the row never breaks on narrow devices.
    private var listFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WorkoutHistoryFilter.allCases) { filter in
                    historyFilterChip(filter)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: historyFilterRaw)
    }

    @ViewBuilder
    private func historyFilterChip(_ filter: WorkoutHistoryFilter) -> some View {
        let isSelected = historyFilter == filter
        let count = filteredCount(for: filter)

        Button {
            if historyFilterRaw != filter.rawValue {
                withAnimation(.snappy(duration: 0.18)) {
                    historyFilterRaw = filter.rawValue
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: filter.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(filter.title)
                    .font(.system(size: 12, weight: .semibold))
                if isSelected {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.white.opacity(0.18), in: Capsule())
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .foregroundStyle(
                isSelected
                    ? AppColor.bg
                    : .white.opacity(AppOpacity.textSecondary)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? AppColor.mango : Color.clear,
                in: Capsule()
            )
            .overlay {
                if !isSelected {
                    Capsule()
                        .strokeBorder(Color.white.opacity(AppOpacity.cardBorder), lineWidth: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.title) — \(count) workouts")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Count of workouts matching a filter using the already-loaded grouped
    /// workouts. Cheap — same data source as the list itself.
    private func filteredCount(for filter: WorkoutHistoryFilter) -> Int {
        workoutsGroupedByDay.reduce(0) { acc, group in
            acc + group.workouts.reduce(0) { $0 + (filter.includes($1) ? 1 : 0) }
        }
    }

    private var importWorkoutButton: some View {
        Button {
            showWorkoutImporter = true
        } label: {
            Image(systemName: isImportingWorkout ? "hourglass" : "square.and.arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(AppOpacity.textSecondary))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .mangoxSurface(.frostedInteractive, shape: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(isImportingWorkout)
        .accessibilityLabel("Import workout file")
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

    private func recomputeFilteredWorkoutGroups() {
        let filter = historyFilter
        let groups = workoutsGroupedByDay.compactMap { group -> (day: Date, workouts: [Workout])? in
            let filtered = group.workouts.filter { filter.includes($0) }
            guard !filtered.isEmpty else { return nil }
            return (group.day, filtered)
        }
        filteredWorkoutGroups = groups
        filteredWorkoutTotal = groups.reduce(0) { $0 + $1.workouts.count }
    }

    private func setScreenMode(_ mode: CalendarScreenMode) {
        guard screenModeRaw != mode.rawValue else { return }
        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
            screenModeRaw = mode.rawValue
        }
    }

    private var emptyStateTitle: String {
        switch historyFilter {
        case .all:
            return "No workouts yet"
        case .outdoor:
            return "No outdoor rides yet"
        case .indoor:
            return "No indoor workouts yet"
        case .planned:
            return "No planned workouts yet"
        case .imported:
            return "No imported workouts yet"
        }
    }

    private var emptyStateMessage: String {
        switch historyFilter {
        case .all:
            return "Complete or import a workout to see it here."
        case .outdoor:
            return "Outdoor rides with a saved route will appear here."
        case .indoor:
            return "Unplanned indoor trainer sessions will appear here."
        case .planned:
            return "Workouts started from a training plan will appear here."
        case .imported:
            return "Import a TCX or FIT file to add older sessions to your history."
        }
    }

    private func clearWorkoutImportError() {
        showWorkoutImportErrorOverlay = false
        workoutImportError = nil
    }

    @MainActor
    private func importWorkout(from url: URL) async {
        isImportingWorkout = true
        defer { isImportingWorkout = false }

        do {
            let payload = try loadImportedWorkoutPayload(from: url)
            _ = try di.workoutPersistenceRepository.saveImportedWorkout(payload)
            screenModeRaw = CalendarScreenMode.list.rawValue
            historyFilterRaw = WorkoutHistoryFilter.all.rawValue
        } catch {
            workoutImportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadImportedWorkoutPayload(from url: URL) throws -> ImportedWorkoutPayload {
        let data = try readFileData(from: url)
        let ext = url.pathExtension.lowercased()
        let importResult: FITWorkoutCodec.ImportResult
        let format: WorkoutImportFormat

        switch ext {
        case "fit":
            importResult = try FITWorkoutCodec.decodeActivity(data: data)
            format = .fit
        case "tcx":
            importResult = try TCXWorkoutImportService.parse(data: data)
            format = .tcx
        default:
            throw WorkoutImportPickerError.unsupportedFileType
        }

        return ImportedWorkoutPayload(
            fileName: url.lastPathComponent,
            format: format,
            startDate: importResult.startDate,
            durationSeconds: importResult.durationSeconds,
            distanceMeters: importResult.distanceMeters,
            avgPower: importResult.avgPower,
            maxPower: importResult.maxPower,
            avgHR: importResult.avgHR,
            maxHR: importResult.maxHR,
            samples: importResult.samples.map {
                ImportedWorkoutSamplePayload(
                    timestamp: importResult.startDate.addingTimeInterval(TimeInterval($0.elapsed)),
                    elapsedSeconds: $0.elapsed,
                    power: $0.power,
                    cadence: $0.cadence,
                    speed: $0.speed,
                    heartRate: $0.hr
                )
            }
        )
    }

    private func readFileData(from url: URL) throws -> Data {
        if url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }
            return try Data(contentsOf: url)
        }
        return try Data(contentsOf: url)
    }
}
