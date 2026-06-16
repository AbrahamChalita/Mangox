// Features/ActivityLog/Presentation/View/LoggedActivitiesView.swift
import SwiftUI

struct LoggedActivitiesView: View {
    @State private var viewModel: LoggedActivitiesViewModel
    @Binding var navigationPath: NavigationPath

    init(viewModel: LoggedActivitiesViewModel, navigationPath: Binding<NavigationPath>) {
        _viewModel = State(initialValue: viewModel)
        _navigationPath = navigationPath
    }

    private var isDayLocked: Bool { viewModel.lockedDate != nil }

    var body: some View {
        ZStack {
            AppColor.bg.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 16, pinnedViews: []) {
                    if isDayLocked {
                        dayHeaderCard
                        dayActions
                    } else {
                        scopeFilterBar
                    }

                    contentSection
                }
                .padding(.horizontal, 16)
                .padding(.top, isDayLocked ? 8 : 4)
                .padding(.bottom, 40)
            }
            .refreshable {
                if isDayLocked {
                    await viewModel.runImportLockedDay()
                } else if viewModel.dateScope == .today {
                    await viewModel.runImportToday()
                } else {
                    await viewModel.runImportAll()
                }
            }
        }
        .navigationTitle(isDayLocked ? "Day Activities" : "Other Activities")
        .navigationBarTitleDisplayMode(isDayLocked ? .inline : .large)
        .toolbar { toolbarContent }
        .task {
            viewModel.load()
            if !isDayLocked { await viewModel.refreshIfStale() }
        }
        .overlay(alignment: .bottom) {
            if let summary = viewModel.importSummary {
                importToast(summary)
            }
        }
    }

    // MARK: - Day header (locked mode)

    private var dayHeaderCard: some View {
        let summary = viewModel.lockedDaySummary
        let date = viewModel.lockedDate ?? Date()
        return VStack(alignment: .leading, spacing: 14) {
            // Eyebrow + relative chip
            HStack(spacing: 8) {
                Text(eyebrowDay(for: date).uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColor.mango)
                    .tracking(1.6)
                if Calendar.current.isDateInToday(date) {
                    Text("TODAY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColor.bg)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(AppColor.mango, in: Capsule())
                }
                Spacer()
            }

            // Big day label
            Text(date, format: .dateTime.weekday(.wide).day().month(.wide).year())
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppColor.fg0)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Stat row
            if summary.count > 0 {
                HStack(spacing: 0) {
                    statTile(label: "ACTIVITIES", value: "\(summary.count)")
                    Divider().frame(width: 1, height: 30).background(AppColor.hair2)
                    statTile(label: "TIME", value: formatDuration(summary.durationSeconds))
                    if summary.distanceMeters > 0 {
                        Divider().frame(width: 1, height: 30).background(AppColor.hair2)
                        statTile(label: "DISTANCE", value: formatDistance(summary.distanceMeters))
                    }
                }
            } else {
                Text("No activities logged for this day.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.fg3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(AppOpacity.cardBg))
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.card.rawValue, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.card.rawValue, style: .continuous)
                .strokeBorder(Color.white.opacity(AppOpacity.cardBorder), lineWidth: 1)
        )
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColor.fg0)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColor.fg3)
                .tracking(1.2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private var dayActions: some View {
        HStack(spacing: 10) {
            if viewModel.stravaConnected || viewModel.whoopConnected {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await viewModel.runImportLockedDay() }
                } label: {
                    Label(viewModel.isImporting ? "Syncing…" : "Sync This Day",
                          systemImage: viewModel.isImporting ? "arrow.trianglehead.2.clockwise" : "arrow.down.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColor.mango)
                        .clipShape(Capsule())
                }
                .buttonStyle(MangoxPressStyle())
                .disabled(viewModel.isImporting)
            }

            Button {
                navigationPath.append(AppRoute.loggedActivityForm(editing: nil))
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.fg0)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(AppOpacity.cardBg))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(AppColor.hair2, lineWidth: 1))
            }
            .buttonStyle(MangoxPressStyle())
        }
    }

    // MARK: - Scope filter (browse mode)

    private var scopeFilterBar: some View {
        HStack(spacing: 8) {
            ForEach(LoggedActivityDateScope.allCases) { scope in
                let selected = viewModel.dateScope == scope
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.dateScope = scope
                } label: {
                    Text(scope.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected ? AppColor.bg : AppColor.fg1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selected ? AppColor.mango : Color.white.opacity(AppOpacity.cardBg))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().strokeBorder(
                                selected ? Color.clear : AppColor.hair2,
                                lineWidth: 1
                            )
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if viewModel.whoopConnected || viewModel.stravaConnected {
                compactSyncButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactSyncButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await runVisibleScopeImport() }
        } label: {
            Label(viewModel.isImporting ? "Syncing" : "Sync", systemImage: viewModel.isImporting ? "arrow.trianglehead.2.clockwise" : "arrow.down.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.fg1)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(AppOpacity.cardBg))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(AppColor.hair2, lineWidth: 1))
                .symbolEffect(.rotate, isActive: viewModel.isImporting)
        }
        .buttonStyle(MangoxPressStyle())
        .disabled(viewModel.isImporting)
        .accessibilityLabel("Sync activities")
    }

    private func runVisibleScopeImport() async {
        switch viewModel.dateScope {
        case .today:
            await viewModel.runImportToday()
        case .week, .all:
            await viewModel.runImportAll()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentSection: some View {
        if viewModel.activities.isEmpty && !viewModel.isImporting {
            emptyState
                .padding(.top, 32)
        } else if viewModel.filteredActivities.isEmpty {
            scopeEmptyState
                .padding(.top, 24)
        } else if isDayLocked {
            dayActivityList
        } else {
            groupedActivityList
        }
    }

    private var dayActivityList: some View {
        VStack(spacing: 0) {
            MangoxSectionLabel(title: "Activities", horizontalPadding: 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)

            VStack(spacing: 8) {
                ForEach(viewModel.filteredActivities) { activity in
                    Button {
                        navigationPath.append(AppRoute.loggedActivityDetail(id: activity.id))
                    } label: {
                        LoggedActivityRow(activity: activity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var groupedActivityList: some View {
        LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
            ForEach(viewModel.activitiesGroupedByWeek, id: \.weekLabel) { group in
                Section {
                    VStack(spacing: 8) {
                        ForEach(group.activities) { activity in
                            Button {
                                navigationPath.append(AppRoute.loggedActivityDetail(id: activity.id))
                            } label: {
                                LoggedActivityRow(activity: activity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 10)
                } header: {
                    weekHeader(group.weekLabel)
                }
            }
        }
    }

    private func weekHeader(_ label: String) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColor.fg3)
                .tracking(1.4)
            Spacer()
        }
        .padding(.vertical, 10)
        .background(AppColor.bg)
    }

    private var scopeEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 32))
                .foregroundStyle(AppColor.fg3)
            Text(scopeEmptyTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColor.fg1)
            Text(isDayLocked
                 ? "Pull to sync this day or tap + to log manually."
                 : "Pull down to refresh, or switch scope.")
                .font(.system(size: 12))
                .foregroundStyle(AppColor.fg3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var scopeEmptyTitle: String {
        if isDayLocked { return "No activities for this day" }
        switch viewModel.dateScope {
        case .today: return "No activities yet today"
        case .week: return "No activities this week"
        case .all: return "No activities found"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.mixed.cardio")
                .font(.system(size: 48))
                .foregroundStyle(AppColor.fg3)

            Text("No activities yet")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColor.fg1)

            Text("Log a workout manually or import from WHOOP and Strava.")
                .font(.system(size: 15))
                .foregroundStyle(AppColor.fg3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            HStack(spacing: 12) {
                Button {
                    navigationPath.append(AppRoute.loggedActivityForm(editing: nil))
                } label: {
                    Label("Add Manually", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColor.bg)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(AppColor.mango)
                        .clipShape(Capsule())
                }

                if viewModel.whoopConnected || viewModel.stravaConnected {
                    Button {
                        Task {
                            if isDayLocked {
                                await viewModel.runImportLockedDay()
                            } else {
                                await viewModel.runImportAll()
                            }
                        }
                    } label: {
                        Label("Import", systemImage: "arrow.down.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColor.fg1)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(AppColor.bg2)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(AppColor.hair2))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 4) {
                if !isDayLocked {
                    importMenu
                }
                Button {
                    navigationPath.append(AppRoute.loggedActivityForm(editing: nil))
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(AppColor.mango)
                }
            }
        }
    }

    private var importMenu: some View {
        Menu {
            if viewModel.stravaConnected {
                Button {
                    Task { await viewModel.runImportToday() }
                } label: {
                    Label("Sync Today", systemImage: "calendar.badge.clock")
                }
            }
            if viewModel.whoopConnected || viewModel.stravaConnected {
                Button {
                    Task { await viewModel.runImportAll() }
                } label: {
                    Label("Sync All Recent", systemImage: "arrow.down.circle")
                }
            }
            if !viewModel.whoopConnected && !viewModel.stravaConnected {
                Text("Connect WHOOP or Strava in Settings to import.")
            }
        } label: {
            Image(systemName: viewModel.isImporting ? "arrow.trianglehead.2.clockwise" : "arrow.down.circle")
                .foregroundStyle(AppColor.fg2)
                .symbolEffect(.rotate, isActive: viewModel.isImporting)
        }
    }

    // MARK: - Toast

    private func importToast(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(AppColor.bg)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppColor.mango)
            .clipShape(Capsule())
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { viewModel.dismissImportSummary() }
                }
            }
    }

    // MARK: - Helpers

    private func eyebrowDay(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today's Log" }
        if cal.isDateInYesterday(date) { return "Yesterday's Log" }
        return "Day Log"
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters.rounded())) m"
    }
}
